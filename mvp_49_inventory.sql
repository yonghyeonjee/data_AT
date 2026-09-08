-- mvp_49: 재고 (inv) — 별도 영역. 지금은 자체 입출고 기록으로 현재고를 계산하고,
--         이카운트 연동이 붙으면 창고별재고현황 API 결과를 같은 구조(movement kind='sync')로 흘려 넣는다.
create schema if not exists inv;

-- 품목 마스터 (이카운트 품목 내보내기 컬럼과 1:1 — 품목코드/상품명/규격/단위/재고관리여부/안전재고/매입가/분류)
create table if not exists inv.item (
  code        text primary key,                 -- 이카운트 품목코드 (예: AT-00079, CLT-00350)
  name        text not null,
  spec        text,
  unit        text default 'EA',
  category    text,                             -- 분류코드1 또는 사람이 읽는 분류
  item_type   text,                             -- 1 상품 · 2 제품 · 3 원재료 · 7 기타
  track       boolean not null default true,    -- 재고관리여부
  safety_qty  numeric not null default 0,       -- 안전재고
  cost        numeric,                          -- 매입가
  cost_vat    boolean,
  barcode     text,
  model       text,                             -- 모델명(상품명에서 추출 또는 별도)
  active      boolean not null default true,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists inv_item_name on inv.item (lower(name));
create index if not exists inv_item_model on inv.item (upper(model));

-- 입출고 원장. 재고 = 품목×창고별 sum(qty_signed)
create table if not exists inv.movement (
  id          bigserial primary key,
  moved_at    timestamptz not null default now(),
  kind        text not null check (kind in ('in','out','move','adjust','sync')),  -- 입고/출고/창고이동/재고조정/이카운트동기화
  item_code   text not null references inv.item(code),
  warehouse   text not null references ec.warehouse(code),
  to_warehouse text references ec.warehouse(code),       -- move 일 때
  qty         numeric not null,                          -- 양수. 방향은 kind 가 정함
  unit_cost   numeric,
  ref_type    text,                                      -- order / purchase / ecount / manual …
  ref_no      text,
  note        text,
  created_by  text,                                      -- 담당자 이름 (PIN) 또는 로그인 이메일
  created_at  timestamptz not null default now()
);
create index if not exists inv_mv_item on inv.movement (item_code, moved_at desc);
create index if not exists inv_mv_wh on inv.movement (warehouse, moved_at desc);
create index if not exists inv_mv_at on inv.movement (moved_at desc);

-- 부호 있는 수량으로 펼친 뷰 (move 는 두 줄)
create or replace view inv.v_ledger as
  select id, moved_at, kind, item_code, warehouse, qty as qty_signed, unit_cost, ref_type, ref_no, note, created_by
    from inv.movement where kind in ('in','adjust','sync')
  union all
  select id, moved_at, kind, item_code, warehouse, -qty, unit_cost, ref_type, ref_no, note, created_by
    from inv.movement where kind = 'out'
  union all
  select id, moved_at, kind, item_code, warehouse, -qty, unit_cost, ref_type, ref_no, note, created_by
    from inv.movement where kind = 'move'
  union all
  select id, moved_at, kind, item_code, to_warehouse, qty, unit_cost, ref_type, ref_no, note, created_by
    from inv.movement where kind = 'move' and to_warehouse is not null;

-- 현재고 (품목×창고)
create or replace view inv.v_stock as
  select item_code, warehouse, sum(qty_signed) qty, max(moved_at) last_moved
    from inv.v_ledger group by 1, 2;

-- 캐시 무효화와 무관 (매출 아님)

/* ─────────────── 관리자 RPC ─────────────── */
create or replace function public.fn_inv_summary()
returns jsonb language sql security definer set search_path = pg_catalog, public as $$
  select case when core.f_role() = 'anon' then null else jsonb_build_object(
    'items', (select count(*) from inv.item where active),
    'tracked', (select count(*) from inv.item where active and track),
    'warehouses', (select count(*) from ec.warehouse where active),
    'on_hand_lines', (select count(*) from inv.v_stock where qty <> 0),
    'on_hand_qty', (select coalesce(sum(qty),0) from inv.v_stock),
    'low', (select count(*) from (select i.code, coalesce(sum(s.qty),0) q from inv.item i left join inv.v_stock s on s.item_code = i.code
                                    where i.active and i.track and i.safety_qty > 0 group by 1, i.safety_qty having coalesce(sum(s.qty),0) < i.safety_qty) t),
    'neg', (select count(*) from inv.v_stock where qty < 0),
    'moves_today', (select count(*) from inv.movement where moved_at >= (current_date::timestamp at time zone 'Asia/Seoul')),
    'moves_month', (select count(*) from inv.movement where moved_at >= (date_trunc('month', current_date)::timestamp at time zone 'Asia/Seoul')),
    'last_moved', (select to_char(max(moved_at) at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI') from inv.movement),
    'last_sync', (select to_char(max(moved_at) at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI') from inv.movement where kind='sync'),
    'by_warehouse', (select coalesce(jsonb_agg(jsonb_build_object('code', w.code, 'name', w.name, 'lines', coalesce(t.lines,0), 'qty', coalesce(t.qty,0)) order by w.code), '[]'::jsonb)
                       from ec.warehouse w left join (select warehouse, count(*) filter (where qty<>0) lines, sum(qty) qty from inv.v_stock group by 1) t on t.warehouse = w.code
                      where w.active)
  ) end;
$$;
revoke all on function public.fn_inv_summary() from public;
grant execute on function public.fn_inv_summary() to authenticated;

-- 현재고 목록 (품목별 합계 + 창고별 분해)
create or replace function public.fn_inv_stock(p_q text default null, p_warehouse text default null, p_low_only boolean default false,
                                               p_category text default null, p_limit int default 200, p_offset int default 0)
returns jsonb language sql security definer set search_path = pg_catalog, public as $$
  with base as (
    select i.code, i.name, i.model, i.spec, i.unit, i.category, i.track, i.safety_qty, i.cost,
           coalesce(sum(s.qty) filter (where p_warehouse is null or s.warehouse = p_warehouse), 0) qty,
           max(s.last_moved) last_moved,
           coalesce(jsonb_object_agg(s.warehouse, s.qty) filter (where s.warehouse is not null and s.qty <> 0), '{}'::jsonb) by_wh
      from inv.item i left join inv.v_stock s on s.item_code = i.code
     where i.active
       and (p_category is null or i.category = p_category)
       and (p_q is null or p_q = '' or i.code ilike '%'||p_q||'%' or i.name ilike '%'||p_q||'%' or i.model ilike '%'||p_q||'%' or i.spec ilike '%'||p_q||'%')
     group by i.code, i.name, i.model, i.spec, i.unit, i.category, i.track, i.safety_qty, i.cost
  ), f as (
    select * from base where (not p_low_only) or (track and safety_qty > 0 and qty < safety_qty)
  )
  select case when core.f_role() = 'anon' then null else jsonb_build_object(
    'total', (select count(*) from f),
    'rows', (select coalesce(jsonb_agg(to_jsonb(x) order by (x.track and x.safety_qty > 0 and x.qty < x.safety_qty) desc, x.qty desc, x.name), '[]'::jsonb)
               from (select * from f order by (track and safety_qty > 0 and qty < safety_qty) desc, qty desc, name limit least(greatest(p_limit,1),500) offset greatest(p_offset,0)) x),
    'categories', (select coalesce(jsonb_agg(distinct category) filter (where category is not null), '[]'::jsonb) from inv.item where active)
  ) end;
$$;
revoke all on function public.fn_inv_stock(text,text,boolean,text,int,int) from public;
grant execute on function public.fn_inv_stock(text,text,boolean,text,int,int) to authenticated;

-- 입출고 내역
create or replace function public.fn_inv_movements(p_from date default (current_date - 30), p_to date default current_date,
    p_kind text default null, p_warehouse text default null, p_item text default null, p_q text default null,
    p_limit int default 100, p_offset int default 0)
returns jsonb language sql security definer set search_path = pg_catalog, public as $$
  with f as (
    select m.*, i.name item_name, i.model, w.name wh_name, w2.name to_wh_name
      from inv.movement m join inv.item i on i.code = m.item_code
      join ec.warehouse w on w.code = m.warehouse left join ec.warehouse w2 on w2.code = m.to_warehouse
     where m.moved_at >= (p_from::timestamp at time zone 'Asia/Seoul') and m.moved_at < ((p_to+1)::timestamp at time zone 'Asia/Seoul')
       and (p_kind is null or p_kind = '' or m.kind = p_kind)
       and (p_warehouse is null or p_warehouse = '' or m.warehouse = p_warehouse or m.to_warehouse = p_warehouse)
       and (p_item is null or p_item = '' or m.item_code = p_item)
       and (p_q is null or p_q = '' or i.name ilike '%'||p_q||'%' or i.code ilike '%'||p_q||'%' or i.model ilike '%'||p_q||'%'
            or m.ref_no ilike '%'||p_q||'%' or m.note ilike '%'||p_q||'%' or m.created_by ilike '%'||p_q||'%'))
  select case when core.f_role() = 'anon' then null else jsonb_build_object(
    'total', (select count(*) from f),
    'sum_in',  (select coalesce(sum(qty),0) from f where kind in ('in','sync')),
    'sum_out', (select coalesce(sum(qty),0) from f where kind = 'out'),
    'sum_move', (select coalesce(sum(qty),0) from f where kind = 'move'),
    'sum_adjust', (select coalesce(sum(qty),0) from f where kind = 'adjust'),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'at', to_char(moved_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'kind', kind,
                'item_code', item_code, 'item_name', item_name, 'model', model, 'wh', warehouse, 'wh_name', wh_name, 'to_wh', to_warehouse, 'to_wh_name', to_wh_name,
                'qty', qty, 'unit_cost', unit_cost, 'ref_type', ref_type, 'ref_no', ref_no, 'note', note, 'by', created_by) order by moved_at desc, id desc), '[]'::jsonb)
               from (select * from f order by moved_at desc, id desc limit least(greatest(p_limit,1),500) offset greatest(p_offset,0)) x)
  ) end;
$$;
revoke all on function public.fn_inv_movements(date,date,text,text,text,text,int,int) from public;
grant execute on function public.fn_inv_movements(date,date,text,text,text,text,int,int) to authenticated;

-- 입출고 등록 (관리자). rows: [{kind,item_code,warehouse,to_warehouse,qty,unit_cost,ref_type,ref_no,note,moved_at}]
create or replace function core.f_inv_move(p_rows jsonb, p_by text)
returns jsonb language plpgsql set search_path = pg_catalog, public as $$
declare r jsonb; n int := 0; v_kind text; v_qty numeric; v_id bigint; ids bigint[] := '{}';
begin
  if jsonb_typeof(p_rows) <> 'array' then p_rows := jsonb_build_array(p_rows); end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_kind := lower(coalesce(r->>'kind',''));
    v_qty := (r->>'qty')::numeric;
    if v_kind not in ('in','out','move','adjust') then raise exception '구분이 올바르지 않습니다: %', v_kind; end if;
    if v_qty is null or (v_kind <> 'adjust' and v_qty <= 0) then raise exception '수량은 0보다 커야 합니다'; end if;
    if not exists (select 1 from inv.item where code = r->>'item_code' and active) then raise exception '품목이 없습니다: %', r->>'item_code'; end if;
    if not exists (select 1 from ec.warehouse where code = r->>'warehouse' and active) then raise exception '창고가 없습니다: %', r->>'warehouse'; end if;
    if v_kind = 'move' and (nullif(r->>'to_warehouse','') is null or r->>'to_warehouse' = r->>'warehouse') then raise exception '이동은 다른 창고를 지정해야 합니다'; end if;
    insert into inv.movement (moved_at, kind, item_code, warehouse, to_warehouse, qty, unit_cost, ref_type, ref_no, note, created_by)
    values (coalesce(core.f_kst_ts(r->>'moved_at'), now()), v_kind, r->>'item_code', r->>'warehouse',
            case when v_kind='move' then r->>'to_warehouse' end,
            v_qty, nullif(r->>'unit_cost','')::numeric, coalesce(nullif(r->>'ref_type',''), 'manual'), nullif(r->>'ref_no',''), nullif(r->>'note',''), p_by)
    returning id into v_id;
    ids := ids || v_id; n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'saved', n, 'ids', to_jsonb(ids));
end $$;

create or replace function public.fn_inv_move(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_inv_move(p_rows, coalesce((select handler_name from public.profiles where id = auth.uid()), (select email from public.profiles where id = auth.uid()), 'admin'));
end $$;
revoke all on function public.fn_inv_move(jsonb) from public;
grant execute on function public.fn_inv_move(jsonb) to authenticated;

-- 입출고 삭제 (관리자만)
create or replace function public.fn_inv_move_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() <> 'admin' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  delete from inv.movement where id = p_id;
  return jsonb_build_object('ok', found);
end $$;
revoke all on function public.fn_inv_move_delete(bigint) from public;
grant execute on function public.fn_inv_move_delete(bigint) to authenticated;

-- 품목 목록 / 저장 / 업로드
create or replace function public.fn_inv_items(p_q text default null, p_active boolean default true, p_limit int default 300, p_offset int default 0)
returns jsonb language sql security definer set search_path = pg_catalog, public as $$
  with f as (select * from inv.item i where (p_active is null or i.active = p_active)
               and (p_q is null or p_q = '' or i.code ilike '%'||p_q||'%' or i.name ilike '%'||p_q||'%' or i.model ilike '%'||p_q||'%' or i.category ilike '%'||p_q||'%'))
  select case when core.f_role() = 'anon' then null else jsonb_build_object(
    'total', (select count(*) from f),
    'rows', (select coalesce(jsonb_agg(to_jsonb(x) order by x.name), '[]'::jsonb) from (select * from f order by name limit least(greatest(p_limit,1),1000) offset greatest(p_offset,0)) x)
  ) end;
$$;
revoke all on function public.fn_inv_items(text,boolean,int,int) from public;
grant execute on function public.fn_inv_items(text,boolean,int,int) to authenticated;

create or replace function public.fn_inv_item_save(p_data jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_code text := upper(btrim(coalesce(p_data->>'code','')));
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_code = '' or nullif(btrim(p_data->>'name'),'') is null then raise exception '품목코드와 상품명은 필수입니다'; end if;
  insert into inv.item (code, name, spec, unit, category, item_type, track, safety_qty, cost, cost_vat, barcode, model, active, note, updated_at)
  values (v_code, btrim(p_data->>'name'), nullif(p_data->>'spec',''), coalesce(nullif(p_data->>'unit',''),'EA'), nullif(p_data->>'category',''),
          nullif(p_data->>'item_type',''), coalesce((p_data->>'track')::boolean, true), coalesce((p_data->>'safety_qty')::numeric, 0),
          nullif(p_data->>'cost','')::numeric, (p_data->>'cost_vat')::boolean, nullif(p_data->>'barcode',''), nullif(p_data->>'model',''),
          coalesce((p_data->>'active')::boolean, true), nullif(p_data->>'note',''), now())
  on conflict (code) do update set name = excluded.name, spec = excluded.spec, unit = excluded.unit, category = excluded.category,
     item_type = excluded.item_type, track = excluded.track, safety_qty = excluded.safety_qty, cost = excluded.cost, cost_vat = excluded.cost_vat,
     barcode = excluded.barcode, model = excluded.model, active = excluded.active, note = excluded.note, updated_at = now();
  return jsonb_build_object('ok', true, 'code', v_code);
end $$;
revoke all on function public.fn_inv_item_save(jsonb) from public;
grant execute on function public.fn_inv_item_save(jsonb) to authenticated;

-- 이카운트 품목 내보내기 업로드 (콘솔 데이터 가져오기)
create or replace function public.fn_inv_items_upsert(p_rows jsonb, p_source text default 'ecount_items', p_file text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare r jsonb; n int := 0; skip int := 0; v_code text;
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_code := upper(btrim(coalesce(r->>'code','')));
    if v_code = '' or nullif(btrim(coalesce(r->>'name','')),'') is null then skip := skip + 1; continue; end if;
    insert into inv.item (code, name, spec, unit, category, item_type, track, safety_qty, cost, cost_vat, barcode, model, updated_at)
    values (v_code, btrim(r->>'name'), nullif(r->>'spec',''), coalesce(nullif(r->>'unit',''),'EA'), nullif(r->>'category',''),
            nullif(r->>'item_type',''), coalesce((r->>'track') in ('1','true','Y','y'), true), coalesce(nullif(r->>'safety_qty','')::numeric, 0),
            nullif(r->>'cost','')::numeric, (r->>'cost_vat') in ('1','true','Y','y'), nullif(r->>'barcode',''), nullif(r->>'model',''), now())
    on conflict (code) do update set name = excluded.name, spec = excluded.spec, unit = excluded.unit, category = coalesce(excluded.category, inv.item.category),
      item_type = excluded.item_type, track = excluded.track, safety_qty = excluded.safety_qty, cost = excluded.cost, cost_vat = excluded.cost_vat,
      barcode = coalesce(excluded.barcode, inv.item.barcode), model = coalesce(excluded.model, inv.item.model), updated_at = now();
    n := n + 1;
  end loop;
  insert into raw.upload (source, file_name, row_count, error_count, uploaded_by)
  values (p_source, p_file, n, skip, (select email from public.profiles where id = auth.uid()));
  return jsonb_build_object('ok', true, 'upserted', n, 'skipped', skip);
end $$;
revoke all on function public.fn_inv_items_upsert(jsonb,text,text) from public;
grant execute on function public.fn_inv_items_upsert(jsonb,text,text) to authenticated;

-- 창고 목록 (관리자·담당자 공용)
create or replace function public.fn_inv_warehouses()
returns jsonb language sql security definer set search_path = pg_catalog, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]'::jsonb) from ec.warehouse where active;
$$;
revoke all on function public.fn_inv_warehouses() from public;
grant execute on function public.fn_inv_warehouses() to anon, authenticated;

/* ─────────────── 담당자(PIN) RPC — stock.html ─────────────── */
create or replace function public.fn_stock_search(p_code text, p_q text, p_warehouse text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_me text := core.f_staff(p_code);
begin
  return jsonb_build_object('me', v_me, 'rows', (
    select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name, 'model', i.model, 'spec', i.spec, 'unit', i.unit,
             'safety', i.safety_qty, 'track', i.track, 'qty', coalesce(t.qty,0), 'by_wh', coalesce(t.by_wh,'{}'::jsonb)) order by (coalesce(t.qty,0) < i.safety_qty and i.safety_qty>0) desc, i.name), '[]'::jsonb)
      from inv.item i
      left join lateral (select sum(s.qty) filter (where p_warehouse is null or s.warehouse = p_warehouse) qty,
                                jsonb_object_agg(s.warehouse, s.qty) filter (where s.qty <> 0) by_wh
                           from inv.v_stock s where s.item_code = i.code) t on true
     where i.active and (nullif(btrim(coalesce(p_q,'')),'') is null or i.code ilike '%'||p_q||'%' or i.name ilike '%'||p_q||'%' or i.model ilike '%'||p_q||'%')
     limit 60));
end $$;
revoke all on function public.fn_stock_search(text,text,text) from public;
grant execute on function public.fn_stock_search(text,text,text) to anon, authenticated;

create or replace function public.fn_stock_move(p_code text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_me text := core.f_staff(p_code);
begin
  return core.f_inv_move(p_rows, v_me);
end $$;
revoke all on function public.fn_stock_move(text,jsonb) from public;
grant execute on function public.fn_stock_move(text,jsonb) to anon, authenticated;

create or replace function public.fn_stock_my(p_code text, p_days int default 14)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_me text := core.f_staff(p_code);
begin
  return jsonb_build_object('me', v_me,
    'low', (select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name, 'model', i.model, 'qty', q, 'safety', i.safety_qty) order by (i.safety_qty - q) desc), '[]'::jsonb)
              from (select i.code, coalesce(sum(s.qty),0) q from inv.item i left join inv.v_stock s on s.item_code=i.code
                     where i.active and i.track and i.safety_qty > 0 group by i.code) t join inv.item i on i.code = t.code where t.q < i.safety_qty limit 30),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'at', to_char(m.moved_at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'kind', m.kind,
                'item_code', m.item_code, 'item_name', i.name, 'wh', w.name, 'to_wh', w2.name, 'qty', m.qty, 'note', m.note, 'by', m.created_by, 'mine', m.created_by = v_me) order by m.moved_at desc), '[]'::jsonb)
              from inv.movement m join inv.item i on i.code=m.item_code join ec.warehouse w on w.code=m.warehouse left join ec.warehouse w2 on w2.code=m.to_warehouse
             where m.moved_at >= now() - make_interval(days => greatest(1, least(coalesce(p_days,14), 90))) limit 100),
    'summary', jsonb_build_object(
      'today_in',  (select coalesce(sum(qty),0) from inv.movement where kind='in'  and moved_at >= (current_date::timestamp at time zone 'Asia/Seoul')),
      'today_out', (select coalesce(sum(qty),0) from inv.movement where kind='out' and moved_at >= (current_date::timestamp at time zone 'Asia/Seoul')),
      'low_count', (select count(*) from (select i.code, coalesce(sum(s.qty),0) q from inv.item i left join inv.v_stock s on s.item_code=i.code
                                            where i.active and i.track and i.safety_qty > 0 group by i.code, i.safety_qty having coalesce(sum(s.qty),0) < i.safety_qty) t),
      'last', (select to_char(max(moved_at) at time zone 'Asia/Seoul','MM-DD HH24:MI') from inv.movement)));
end $$;
revoke all on function public.fn_stock_my(text,int) from public;
grant execute on function public.fn_stock_my(text,int) to anon, authenticated;
