-- mvp_97 (2026-09-07) 세트 품목 구성품 차감 · 직배송 미차감 · 이카운트 주문서 현황 업로드(등록 여부) · 발송/미발송 · 영업담당 코드 · 담당자 코드 추가 · 샵링커 단가=주문금액
-- ── 1. 영업담당 코드 (사용자 제공) ─────────────────────────
insert into ec.code (kind, code, label, sort) values
 ('emp','00053','강남(안성대)',10),('emp','00079','강민정',20),('emp','00052','강북(최기영)',30),('emp','00073','고병재',40),('emp','00090','고창재',50),
 ('emp','00082','권혁찬',60),('emp','00080','김미란',70),('emp','00078','김민정',80),('emp','00004','김성욱',90),('emp','00081','나승준',100),
 ('emp','00091','박연희',110),('emp','00072','박은지',120),('emp','00057','오영환',130),('emp','00031','오토바이(퀵)',140),('emp','00022','오픈마켓',150),
 ('emp','00086','유미주',160),('emp','00077','윤소영',170),('emp','00070','이장훈',180),('emp','00083','이혜진',190),('emp','00089','이효진',200),
 ('emp','00058','장성원',210),('emp','00067','정주용',220),('emp','00061','지점',230),('emp','00065','진정매',240),('emp','00085','차세빈',250),
 ('emp','00011','차효범',260),('emp','00088','최종득',270),('emp','00013','택배',280),('emp','00023','포스트퀵',290),('emp','00063','황은경',300)
on conflict (kind, code) do update set label = excluded.label, sort = excluded.sort, active = true;
-- 거래유형은 이 회사에서 채널명(스마트스토어 B2B · SSG · 자체VMS …)으로 쓰는 관리항목이라 표준 세율 코드가 맞지 않는다 → 표준 seed 는 끈다
update ec.code set active = false where kind = 'io_type' and code in ('11','12','13','14');
-- 거래유형이 이카운트의 어느 필드로 가는지도 매핑에서 정한다 (기본 IO_TYPE)
update core.app_setting set value = (value::jsonb || '{"deal_type":"IO_TYPE"}'::jsonb)::text where key = 'ec_field_map' and not (value::jsonb ? 'deal_type');

-- 담당자도 코드 추가 가능 (이카운트에 없는 코드면 전송 때 실패 → "이카운트에 별도 코드 등록 필요" 안내)
create or replace function core.f_ec_codes_add(p_kind text, p_rows jsonb)
returns jsonb language plpgsql set search_path = pg_catalog, public as $$
declare r jsonb; i int := 0; v_max int;
begin
  if p_kind not in ('emp','io_type','kind') then raise exception '알 수 없는 코드표: %', p_kind; end if;
  select coalesce(max(sort),0) into v_max from ec.code where kind = p_kind;
  for r in select value from jsonb_array_elements(p_rows) loop
    continue when nullif(btrim(r->>'code'),'') is null;
    i := i + 1;
    insert into ec.code (kind, code, label, sort, active)
    values (p_kind, btrim(r->>'code'), coalesce(nullif(btrim(r->>'label'),''), btrim(r->>'code')), v_max + i*10, true)
    on conflict (kind, code) do update set label = excluded.label, active = true;
  end loop;
  return jsonb_build_object('kind', p_kind, 'n', i);
end $$;
create or replace function public.fn_ec_codes_add(p_kind text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_ec_codes_add(p_kind, p_rows);
end $$;
create or replace function public.fn_store_codes_add(p_code text, p_kind text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_me text := core.f_staff(p_code);
begin
  if not core.f_has_perm(v_me, 'order') then raise exception '주문서 권한이 없습니다' using errcode='42501'; end if;
  return core.f_ec_codes_add(p_kind, p_rows);
end $$;
revoke all on function public.fn_ec_codes_add(text,jsonb) from public, anon; grant execute on function public.fn_ec_codes_add(text,jsonb) to authenticated;
revoke all on function public.fn_store_codes_add(text,text,jsonb) from public; grant execute on function public.fn_store_codes_add(text,text,jsonb) to anon, authenticated;

-- ── 2. 원장 : 자사주문번호(샵링커) · 송장번호 ───────────────
alter table core.orders add column if not exists alt_order_no text;
alter table core.orders add column if not exists tracking_no text;
create index if not exists orders_alt_order_no_idx on core.orders (alt_order_no) where alt_order_no is not null;

-- ── 3. 이카운트 주문서 현황 업로드 → 이미 등록된 주문 ─────────
create table if not exists ec.slip_ref (
  order_no text primary key,            -- 이카운트 주문No. (= 샵링커 주문번호 또는 자사주문번호)
  slip_no text, io_date date, cust_name text, emp_name text, handler text, deal_type text, kind text,
  amount numeric, status text, items text, uploaded_at timestamptz not null default now(), upload_id bigint);
create or replace function public.fn_ec_slips_upsert(p_rows jsonb, p_source text default 'sheet', p_file text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare r jsonb; i int := 0; v_up bigint; v_no text; v_skip int := 0;
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  insert into raw.upload (source, file_name, uploaded_by, row_count) values ('ecount_slip', p_file, auth.uid(), jsonb_array_length(p_rows)) returning id into v_up;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_no := nullif(btrim(r->>'order_no'),'');
    if v_no is null then v_skip := v_skip + 1; continue; end if;
    i := i + 1;
    insert into ec.slip_ref (order_no, slip_no, io_date, cust_name, emp_name, handler, deal_type, kind, amount, status, items, upload_id)
    values (v_no, nullif(btrim(r->>'slip_no'),''), core.f_ts(left(r->>'slip_no',8))::date, nullif(btrim(r->>'cust_name'),''), nullif(btrim(r->>'emp_name'),''),
            nullif(btrim(r->>'handler'),''), nullif(btrim(r->>'deal_type'),''), nullif(btrim(r->>'kind'),''),
            nullif(regexp_replace(coalesce(r->>'amount',''),'[^0-9.-]','','g'),'')::numeric, nullif(btrim(r->>'status'),''), nullif(btrim(r->>'items'),''), v_up)
    on conflict (order_no) do update set slip_no = excluded.slip_no, io_date = excluded.io_date, cust_name = excluded.cust_name, emp_name = excluded.emp_name,
      handler = excluded.handler, deal_type = excluded.deal_type, kind = excluded.kind, amount = excluded.amount, status = excluded.status, items = excluded.items,
      uploaded_at = now(), upload_id = excluded.upload_id;
  end loop;
  update raw.upload set error_count = v_skip where id = v_up;
  return jsonb_build_object('upload_id', v_up, '주문서', i, '주문No없음', v_skip);
end $$;
revoke all on function public.fn_ec_slips_upsert(jsonb,text,text) from public, anon; grant execute on function public.fn_ec_slips_upsert(jsonb,text,text) to authenticated;

-- 이카운트에 이미 있는지 (우리 전송 전표 또는 업로드된 주문서 현황)
create or replace function core.f_ec_slip_of(p_order_no text, p_alt text)
returns text language sql stable set search_path = pg_catalog, public as $$
  select coalesce(
    (select q.ec_slip_no from ec.order_queue q where q.order_no = p_order_no and q.status = 'sent' and q.ec_slip_no is not null limit 1),
    (select s.slip_no from ec.slip_ref s where s.order_no = p_order_no or (p_alt is not null and s.order_no = p_alt) limit 1));
$$;

-- ── 4. 세트 품목 구성 · 직배송(재고 미차감) ───────────────────
alter table inv.item add column if not exists no_stock boolean not null default false;   -- 직배송 등 재고를 세지 않는 품목
create table if not exists inv.item_set (
  set_code text not null references inv.item(code) on delete cascade,
  comp_code text not null references inv.item(code),
  qty numeric not null default 1 check (qty > 0),
  note text, updated_at timestamptz not null default now(),
  primary key (set_code, comp_code));
-- 이름 규칙으로 자동 구성 : "X 1+1" → X/TND ×2 · "A/B/C 3색세트" → 각 /TND ×1 · "CLT-Kxxx 4색 패키지" → K·C·M·Y /TND ×1
insert into inv.item_set (set_code, comp_code, qty, note)
select s.code, x.c, x.q, '이름 규칙 자동 구성'
from (select code, name from inv.item where active and (name ~ '1\+1$' or name ~ '색세트$' or name ~ '4색 패키지$')) s
cross join lateral (
  select i.code c, 2::numeric q from inv.item i where s.name ~ '1\+1$' and i.active and (i.name = regexp_replace(s.name,'\s*1\+1$','')||'/TND' or i.name = regexp_replace(regexp_replace(s.name,'\s*1\+1$',''),'\s','','g')||'/TND')
  union all
  select i.code, 1 from inv.item i where s.name ~ '3색세트$' and i.active and i.name in (select split_part(s.name,'-',1)||'-'||t||'/TND' from unnest(string_to_array(regexp_replace(split_part(s.name,'-',2),' 3색세트$',''),'/')) t)
  union all
  select i.code, 1 from inv.item i where s.name ~ '4색 패키지$' and i.active and i.name in (select 'CLT-'||c||substr(split_part(regexp_replace(s.name,' 4색 패키지$',''),'-',2),2)||'/TND' from unnest(array['K','C','M','Y']) c)
) x
on conflict do nothing;

create or replace function core.f_item_sets(p_q text default null)
returns jsonb language sql stable set search_path = pg_catalog, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('set_code', s.code, 'set_name', s.name, 'no_stock', s.no_stock,
           'comps', (select coalesce(jsonb_agg(jsonb_build_object('code', c.comp_code, 'name', i.name, 'qty', c.qty) order by c.comp_code), '[]'::jsonb)
                     from inv.item_set c join inv.item i on i.code = c.comp_code where c.set_code = s.code)) order by s.name), '[]'::jsonb)
  from inv.item s
  where s.active and (exists (select 1 from inv.item_set c where c.set_code = s.code) or s.name ~ '1\+1$' or s.name ~ '세트$' or s.name ~ '패키지$' or s.name ~* '\(SET\)$')
    and (p_q is null or p_q = '' or s.name ilike '%'||p_q||'%' or s.code ilike '%'||p_q||'%');
$$;
create or replace function public.fn_inv_sets(p_q text default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_item_sets(p_q);
end $$;
create or replace function public.fn_inv_set_save(p_set_code text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare r jsonb; i int := 0; v_c text;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 가능합니다' using errcode='42501'; end if;
  if not exists (select 1 from inv.item where code = upper(btrim(p_set_code))) then raise exception '없는 품목입니다: %', p_set_code; end if;
  delete from inv.item_set where set_code = upper(btrim(p_set_code));
  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    v_c := upper(btrim(coalesce(r->>'code','')));
    continue when v_c = '';
    if not exists (select 1 from inv.item where code = v_c) then raise exception '없는 구성 품목입니다: %', v_c; end if;
    if v_c = upper(btrim(p_set_code)) then raise exception '세트 자신을 구성품으로 넣을 수 없습니다'; end if;
    insert into inv.item_set (set_code, comp_code, qty, note) values (upper(btrim(p_set_code)), v_c, greatest(coalesce(nullif(r->>'qty','')::numeric,1),0.01), '관리자 입력');
    i := i + 1;
  end loop;
  return jsonb_build_object('set_code', p_set_code, 'comps', i);
end $$;
create or replace function public.fn_inv_item_no_stock(p_codes text[], p_no_stock boolean)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 가능합니다' using errcode='42501'; end if;
  update inv.item set no_stock = p_no_stock, updated_at = now() where code = any(p_codes);
  return jsonb_build_object('n', (select count(*) from inv.item where code = any(p_codes)));
end $$;
revoke all on function public.fn_inv_sets(text), public.fn_inv_set_save(text,jsonb), public.fn_inv_item_no_stock(text[],boolean) from public, anon;
grant execute on function public.fn_inv_sets(text), public.fn_inv_set_save(text,jsonb), public.fn_inv_item_no_stock(text[],boolean) to authenticated;

-- ── 5. 주문서 저장 : 세트 → 구성품으로 풀어서 (재고 차감 · 이카운트 줄 모두) · 직배송/no_stock 은 재고 안 뺌 ──
create or replace function core.f_order_submit(p_data jsonb, p_by text)
returns jsonb language plpgsql set search_path = pg_catalog, public as $$
declare v_id bigint; r jsonb; i int := 0; v_code text; v_qty numeric; v_wh text; v_date date; v_lines jsonb; v_exp jsonb := '[]'::jsonb;
        v_short jsonb := '[]'::jsonb; v_cur numeric; v_price numeric; v_tot numeric; v_sup numeric; v_vat numeric; v_ns boolean;
        c record; v_ctot numeric; v_cqty numeric; v_rem numeric; v_comp jsonb; v_lt numeric;
begin
  v_wh   := coalesce(nullif(btrim(p_data->>'wh_code'),''), '00001');
  v_date := coalesce(nullif(btrim(p_data->>'io_date'),'')::date, (now() at time zone 'Asia/Seoul')::date);
  v_lines := coalesce(p_data->'lines', '[]'::jsonb);
  if jsonb_array_length(v_lines) = 0 then raise exception '품목을 한 줄 이상 넣으세요'; end if;
  if not exists (select 1 from ec.warehouse where code = v_wh and active) then raise exception '창고가 없습니다: %', v_wh; end if;

  -- 세트를 구성품으로 푼다. 세트 금액은 구성품 수량 비율로 나누고, 나머지는 첫 구성품에 붙여 합계가 같게 한다.
  for r in select value from jsonb_array_elements(v_lines) loop
    v_code := upper(btrim(coalesce(r->>'item_code','')));
    v_qty  := nullif(btrim(coalesce(r->>'qty','')),'')::numeric;
    if v_code = '' then raise exception '품목코드가 빈 줄이 있습니다 (%)', coalesce(r->>'item_name','?'); end if;
    if v_qty is null or v_qty <= 0 then raise exception '% : 수량은 0보다 커야 합니다', v_code; end if;
    if not exists (select 1 from inv.item where code = v_code and active) then raise exception '없는 품목입니다: %', v_code; end if;
    if exists (select 1 from inv.item_set s where s.set_code = v_code) then
      v_price := nullif(regexp_replace(coalesce(r->>'unit_price',''),'[^0-9.-]','','g'),'')::numeric;
      v_ctot := case when v_price is null then null else round(v_price * v_qty) end;      -- 세트 줄 합계
      select sum(qty) into v_cqty from inv.item_set where set_code = v_code;               -- 세트 1개당 구성품 수
      v_rem := v_ctot; v_comp := '[]'::jsonb;
      for c in select s.comp_code, s.qty from inv.item_set s where s.set_code = v_code order by s.comp_code loop
        v_lt := case when v_ctot is null then null else round(v_ctot * c.qty / v_cqty) end;   -- 이 구성품 줄 합계
        v_comp := v_comp || jsonb_build_object('item_code', c.comp_code, 'qty', c.qty * v_qty,
                    'line_total', v_lt, 'remark', left(coalesce(nullif(r->>'remark',''),'')||' [세트 '||v_code||']', 100),
                    'no_stock', coalesce((r->>'no_stock')::boolean,false), 'set_code', v_code);
        if v_ctot is not null then v_rem := v_rem - v_lt; end if;
      end loop;
      if v_ctot is not null and v_rem <> 0 then       -- 반올림 나머지를 첫 구성품에 붙여 세트 합계와 같게
        v_comp := jsonb_set(v_comp, '{0,line_total}', to_jsonb(((v_comp->0->>'line_total')::numeric) + v_rem));
      end if;
      v_exp := v_exp || v_comp;
    else
      v_exp := v_exp || r;
    end if;
  end loop;
  v_lines := v_exp;

  -- 먼저 전부 검증 (한 줄이라도 틀리면 아무것도 안 들어간다). 재고를 세지 않는 품목은 부족 검사도 하지 않는다.
  for r in select value from jsonb_array_elements(v_lines) loop
    v_code := upper(btrim(coalesce(r->>'item_code','')));
    v_qty  := nullif(btrim(coalesce(r->>'qty','')),'')::numeric;
    if not exists (select 1 from inv.item where code = v_code and active) then raise exception '없는 품목입니다: %', v_code; end if;
    select no_stock into v_ns from inv.item where code = v_code;
    if v_ns or coalesce((r->>'no_stock')::boolean,false) then continue; end if;
    select coalesce(sum(qty_signed),0) into v_cur from inv.v_ledger where item_code = v_code and warehouse = v_wh;
    if v_cur < v_qty then v_short := v_short || jsonb_build_object('item', v_code, 'have', v_cur, 'need', v_qty); end if;
  end loop;
  if jsonb_array_length(v_short) > 0 and not coalesce((p_data->>'allow_negative')::boolean, false) then
    return jsonb_build_object('ok', false, 'shortage', v_short);
  end if;

  insert into ec.order_queue (created_by, origin, io_date, channel, order_no, cust_code, cust_name, wh_code,
                              emp_code, deal_type, kind_code, handler, phone, addr, due_date, remark, status, stock_applied)
  values (p_by, coalesce(nullif(p_data->>'origin',''),'online'), v_date, nullif(btrim(p_data->>'channel'),''),
          nullif(btrim(p_data->>'order_no'),''), nullif(btrim(p_data->>'cust_code'),''), nullif(btrim(p_data->>'cust_name'),''),
          v_wh, nullif(btrim(p_data->>'emp_code'),''), nullif(btrim(p_data->>'deal_type'),''), nullif(btrim(p_data->>'kind_code'),''),
          nullif(btrim(p_data->>'handler'),''),
          nullif(btrim(p_data->>'phone'),''), nullif(btrim(p_data->>'addr'),''), nullif(btrim(p_data->>'due_date'),'')::date,
          nullif(btrim(p_data->>'remark'),''), 'ready', true)
  returning id into v_id;

  for r in select value from jsonb_array_elements(v_lines) loop
    i := i + 1;
    v_code := upper(btrim(r->>'item_code'));
    v_qty  := (r->>'qty')::numeric;
    -- 줄 합계가 정해져 있으면(세트 분할·샵링커 주문금액) 그것을 기준으로, 아니면 단가×수량
    v_tot := nullif(regexp_replace(coalesce(r->>'line_total',''),'[^0-9.-]','','g'),'')::numeric;
    v_price := nullif(regexp_replace(coalesce(r->>'unit_price',''),'[^0-9.-]','','g'),'')::numeric;
    if v_tot is not null then v_price := round(v_tot / v_qty); else v_tot := case when v_price is null then null else round(v_price * v_qty) end; end if;
    v_sup := nullif(regexp_replace(coalesce(r->>'supply_amt',''),'[^0-9.-]','','g'),'')::numeric;
    v_vat := nullif(regexp_replace(coalesce(r->>'vat_amt',''),'[^0-9.-]','','g'),'')::numeric;
    if v_tot is not null and v_sup is null then v_sup := round(v_tot / 1.1); end if;
    if v_tot is not null and v_vat is null then v_vat := v_tot - v_sup; end if;
    insert into ec.order_queue_line (queue_id, line_no, item_code, item_name, qty, unit_price, supply_amt, vat_amt, remark)
    values (v_id, i, v_code, coalesce(nullif(btrim(r->>'item_name'),''), (select name from inv.item where code = v_code)), v_qty,
            v_price, v_sup, v_vat, nullif(btrim(r->>'remark'),''));
    select no_stock into v_ns from inv.item where code = v_code;
    if not (v_ns or coalesce((r->>'no_stock')::boolean,false)) then
      insert into inv.movement (moved_at, kind, item_code, warehouse, qty, unit_cost, ref_type, ref_no, note, created_by)
      values ((v_date::timestamp + interval '12 hours') at time zone 'Asia/Seoul', 'out', v_code, v_wh, v_qty,
              v_price, 'order', v_id::text,
              coalesce(nullif(btrim(p_data->>'channel'),'')||' ', '') || coalesce(nullif(btrim(p_data->>'order_no'),''),'주문 '||v_id)
                || case when r ? 'set_code' then ' (세트 '||(r->>'set_code')||')' else '' end, p_by);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'id', v_id, 'lines', i, 'shortage', v_short);
end $$;

-- ── 6. 샵링커 → 주문서 : 이카운트 금액 = 샵링커 주문금액(실결제) · 대물(직배송)은 재고 안 뺌 ──
create or replace function core.f_sl_to_order(p_order_nos text[], p_wh text, p_by text, p_allow_neg boolean default false, p_picks jsonb default '{}'::jsonb)
returns jsonb language plpgsql set search_path = pg_catalog, public as $$
declare r record; v_res jsonb; ok int := 0; skip jsonb := '[]'::jsonb; made bigint[] := '{}';
        v_batch text := 'SL-' || to_char(now() at time zone 'Asia/Seoul','YYMMDD-HH24MISS') || '-' || left(coalesce(p_by,'?'),6);
begin
  for r in
    with l as (
      select o.order_no, o.line_no, o.qty, o.unit_price, o.gross_amount, o.option_text, o.channel_name, o.buyer_name_raw, o.order_at, o.goods_kind,
             coalesce(nullif(p_picks->>(o.order_no||'#'||o.line_no),''),
                      core.f_ec_cands_cached(o.product_name_raw, o.model_code, o.option_text)->0->>'code') code
        from core.orders o
       where o.source='shoplinker' and o.order_no = any(p_order_nos) and coalesce(o.refund_amount,0)=0
    )
    select l.order_no, max(l.channel_name) ch, max(l.buyer_name_raw) buyer,
           (max(l.order_at) at time zone 'Asia/Seoul')::date io_date,
           jsonb_agg(jsonb_build_object('item_code', l.code, 'qty', l.qty,
                                        'unit_price', case when coalesce(l.gross_amount,0) > 0 then round(l.gross_amount / greatest(l.qty,1)) else l.unit_price end,
                                        'line_total', case when coalesce(l.gross_amount,0) > 0 then l.gross_amount end,
                                        'no_stock', (l.goods_kind = '대물'),
                                        'remark', left(coalesce(l.option_text,''),100)) order by l.line_no) lines,
           count(*) filter (where l.code is null) miss
      from l group by l.order_no
  loop
    if r.miss > 0 then skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '품목을 못 정한 줄 '||r.miss||'개'); continue; end if;
    if exists (select 1 from ec.order_queue q where q.order_no = r.order_no and q.status <> 'void') then
      skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '이미 주문서로 만들었습니다'); continue; end if;
    if core.f_ec_slip_of(r.order_no, (select max(alt_order_no) from core.orders o where o.source='shoplinker' and o.order_no = r.order_no)) is not null then
      skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '이카운트에 이미 등록된 주문 (주문서 현황 업로드 기준)'); continue; end if;
    v_res := core.f_order_submit(jsonb_build_object(
      'origin','online', 'io_date', r.io_date, 'wh_code', p_wh, 'channel', r.ch, 'order_no', r.order_no, 'cust_name', r.buyer,
      'cust_code', (select cust_code from ec.channel_cust cc where cc.channel = r.ch limit 1),
      'remark', '샵링커 자동수집', 'allow_negative', p_allow_neg, 'lines', r.lines), p_by);
    if coalesce((v_res->>'ok')::boolean,false) then
      ok := ok + 1; made := made || (v_res->>'id')::bigint;
      update ec.order_queue set batch_id = v_batch where id = (v_res->>'id')::bigint;
    else skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '재고 부족', 'shortage', v_res->'shortage'); end if;
  end loop;
  return jsonb_build_object('ok', ok > 0, 'made', ok, 'ids', to_jsonb(made), 'skipped', skip, 'batch_id', case when ok > 0 then v_batch end);
end $$;
drop function if exists core.f_sl_to_order(text[], text, text, boolean);

-- ── 7. 전송 본문 : 거래유형 필드도 매핑에서 · 주문No 는 order_no 매핑 ─────────
create or replace function core.f_order_body(p_id bigint)
returns jsonb language plpgsql stable set search_path = pg_catalog, public as $$
declare q record; l record; v_map jsonb; base jsonb; line jsonb; lines jsonb := '[]'::jsonb; clean text; k text;
begin
  select * into q from ec.order_queue where id = p_id; if not found then return null; end if;
  v_map := coalesce((select value::jsonb from core.app_setting where key = 'ec_field_map'), '{}'::jsonb);
  base := jsonb_build_object('IO_DATE', to_char(q.io_date,'YYYYMMDD'), 'UPLOAD_SER_NO', q.id::text,
            'CUST', q.cust_code, 'CUST_DES', q.cust_name, 'EMP_CD', q.emp_code, 'WH_CD', q.wh_code,
            'TIME_DATE', case when q.due_date is null then null else to_char(q.due_date,'YYYYMMDD') end);
  if not (v_map ? 'deal_type') then base := base || jsonb_build_object('IO_TYPE', q.deal_type); end if;
  for k in select jsonb_object_keys(v_map) loop
    clean := case k when 'phone' then nullif(regexp_replace(coalesce(q.phone,''),'[^0-9-]','','g'),'')
                    when 'addr' then nullif(regexp_replace(coalesce(q.addr,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),'')
                    when 'remark' then nullif(regexp_replace(coalesce(q.remark,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),'')
                    when 'handler' then nullif(regexp_replace(coalesce(q.handler,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),'')
                    when 'kind' then q.kind_code
                    when 'deal_type' then q.deal_type
                    when 'order_no' then nullif(regexp_replace(coalesce(q.order_no,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),'')
                    when 'channel' then q.channel
                    else null end;
    if clean is not null and nullif(v_map->>k,'') is not null then base := base || jsonb_build_object(v_map->>k, clean); end if;
  end loop;
  if nullif(base->>'U_MEMO1','') is null then base := base || jsonb_build_object('U_MEMO1', coalesce(nullif(regexp_replace(coalesce(q.phone,''),'[^0-9-]','','g'),''), '010-0000-0000')); end if;
  for l in select * from ec.order_queue_line where queue_id = p_id order by line_no loop
    line := base || jsonb_build_object('PROD_CD', l.item_code, 'PROD_DES', l.item_name, 'QTY', l.qty::text,
              'USER_PRICE_VAT', case when l.unit_price is null then null else trunc(l.unit_price)::text end,
              'SUPPLY_AMT', case when l.supply_amt is null then null else trunc(l.supply_amt)::text end,
              'VAT_AMT', case when l.vat_amt is null then null else trunc(l.vat_amt)::text end,
              'REMARKS', nullif(regexp_replace(coalesce(l.remark,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),''));
    lines := lines || jsonb_build_object('BulkDatas', jsonb_strip_nulls(line));
  end loop;
  return jsonb_build_object('SaleOrderList', lines);
end $$;

-- ── 8. 품목 찾기 응답에 세트 구성 · 직배송 표시 ─────────────
create or replace function core.f_item_resolve(p_rows jsonb)
returns jsonb language plpgsql stable set search_path = pg_catalog, public as $$
declare r jsonb; out jsonb := '[]'::jsonb; v_code text; v_name text; v_model text; v_cands jsonb; v_q text; x jsonb;
  info jsonb;
begin
  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    v_code := nullif(upper(btrim(coalesce(r->>'code',''))),''); v_name := nullif(btrim(coalesce(r->>'name','')),''); v_model := nullif(btrim(coalesce(r->>'model','')),'');
    x := null;
    if v_code is not null and exists (select 1 from inv.item where code = v_code and active) then
      x := jsonb_build_object('code', v_code, 'name', (select name from inv.item where code = v_code), 'how', 'code');
    else
      v_q := coalesce(v_name, v_code);
      if v_q is null then out := out || jsonb_build_object('code', null, 'name', null, 'how', 'empty'); continue; end if;
      select i.code into v_code from inv.item i where i.active and upper(regexp_replace(i.name,'\s','','g')) = upper(regexp_replace(v_q,'\s','','g')) limit 1;
      if v_code is not null then x := jsonb_build_object('code', v_code, 'name', (select name from inv.item where code = v_code), 'how', 'exact');
      else
        v_code := core.f_ec_code_of(v_q, v_model);
        if v_code is not null then x := jsonb_build_object('code', v_code, 'name', (select name from inv.item where code = v_code), 'how', 'alias');
        else
          v_cands := coalesce(core.f_ec_cands(v_q, v_model, null), '[]'::jsonb);
          if jsonb_array_length(v_cands) = 0 then
            v_cands := (select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name) order by i.name), '[]'::jsonb)
                        from (select code, name from inv.item i where i.active and (i.name ilike '%'||v_q||'%' or i.model ilike '%'||v_q||'%' or i.code ilike '%'||v_q||'%') limit 8) i);
          end if;
          out := out || jsonb_build_object('code', null, 'name', v_q, 'how', 'cands', 'cands', v_cands); continue;
        end if;
      end if;
    end if;
    -- 세트·직배송 표시
    info := jsonb_build_object('no_stock', (select no_stock from inv.item where code = x->>'code'),
              'set', (select jsonb_agg(jsonb_build_object('code', s.comp_code, 'name', i.name, 'qty', s.qty) order by s.comp_code)
                      from inv.item_set s join inv.item i on i.code = s.comp_code where s.set_code = x->>'code'));
    out := out || (x || jsonb_strip_nulls(info));
  end loop;
  return out;
end $$;

-- ── 9. 샵링커 목록 : 발송 여부 · 이카운트 등록 여부 ────────────
create or replace function core.f_sl_range(p_from date, p_to date, p_basis text default 'order', p_q text default null, p_channel text default null, p_limit integer default 500, p_include_done boolean default false)
returns jsonb language plpgsql set search_path = pg_catalog, public as $$
declare v_rows jsonb; v_total int; v_f timestamptz; v_t timestamptz;
begin
  v_f := (coalesce(p_from, (now() at time zone 'Asia/Seoul')::date - 7)::timestamp) at time zone 'Asia/Seoul';
  v_t := ((coalesce(p_to, (now() at time zone 'Asia/Seoul')::date) + 1)::timestamp) at time zone 'Asia/Seoul';
  drop table if exists pg_temp._sll; drop table if exists pg_temp._slc; drop table if exists pg_temp._slp;
  create temp table _sll on commit drop as
    select o.order_no, o.line_no, o.product_name_raw, o.model_code, o.option_text, o.qty, o.unit_price,
           o.channel_name, o.channel_account, o.buyer_name_raw, o.order_at, o.created_at, o.net_amount, o.gross_amount, o.status,
           o.tracking_no, o.alt_order_no,
           coalesce(o.category,'기타') category, coalesce(o.goods_kind,'기타') kind,
           (exists (select 1 from ec.order_queue q where q.order_no = o.order_no and q.status <> 'void')
              or core.f_ec_slip_of(o.order_no, o.alt_order_no) is not null) done,
           core.f_ec_slip_of(o.order_no, o.alt_order_no) ec_slip,
           (o.tracking_no is not null or o.shipped_at is not null
              or coalesce(o.status,'') in ('송장전송완료','배송중','배송완료','구매확정','구매결정','교환완료')) shipped
      from core.orders o
     where o.source = 'shoplinker'
       and (case when p_basis = 'collect' then o.created_at else o.order_at end) >= v_f
       and (case when p_basis = 'collect' then o.created_at else o.order_at end) <  v_t
       and coalesce(o.status,'') not in ('취소','반품','환불','주문취소')
       and coalesce(o.refund_amount,0) = 0
       and (p_include_done or not (exists (select 1 from ec.order_queue q where q.order_no = o.order_no and q.status <> 'void')
                                   or core.f_ec_slip_of(o.order_no, o.alt_order_no) is not null))
       and (p_channel is null or p_channel = '' or o.channel_name = p_channel)
       and (p_q is null or p_q = '' or o.order_no ilike '%'||p_q||'%' or o.alt_order_no ilike '%'||p_q||'%' or o.buyer_name_raw ilike '%'||p_q||'%'
            or o.product_name_raw ilike '%'||p_q||'%' or o.model_code ilike '%'||p_q||'%' or o.option_text ilike '%'||p_q||'%');
  create temp table _slc on commit drop as
    select d.product_name_raw, d.model_code, d.option_text,
           core.f_ec_cands_cached(d.product_name_raw, d.model_code, d.option_text) cands,
           core.f_sl_model(d.model_code, d.option_text) model_eff
      from (select distinct product_name_raw, model_code, option_text from _sll) d;
  create temp table _slp on commit drop as
    select l.order_no, max(l.channel_name) ch, max(l.channel_account) acct, max(l.buyer_name_raw) buyer,
           max(l.order_at) at, max(l.created_at) collected, bool_or(l.done) done, max(l.status) status,
           max(l.ec_slip) ec_slip, bool_or(l.shipped) shipped, max(l.tracking_no) tracking_no, max(l.alt_order_no) alt_order_no,
           (select cc.cust_code from ec.channel_cust cc where cc.channel = max(l.channel_name) limit 1) cust_code,
           mode() within group (order by l.category) category,
           case when bool_and(l.kind='소모품') then '소모품' when bool_and(l.kind='대물') then '대물' when bool_or(l.kind='대물') then '혼합' else '기타' end kind,
           jsonb_agg(jsonb_build_object(
              'line', l.line_no, 'product', l.product_name_raw, 'model', l.model_code,
              'model_eff', c.model_eff, 'option', l.option_text, 'qty', l.qty, 'price', l.unit_price,
              'category', l.category, 'kind', l.kind,
              'item_code', c.cands->0->>'code', 'item_name', c.cands->0->>'name',
              'cands', c.cands, 'n_cand', jsonb_array_length(c.cands)) order by l.line_no) lines,
           sum(coalesce(l.net_amount, l.gross_amount, 0)) amount, sum(l.qty) qty,
           count(*) filter (where jsonb_array_length(c.cands) > 0)::int mapped,
           count(*) filter (where jsonb_array_length(c.cands) > 1)::int ambig,
           count(*)::int total_lines
      from _sll l
      join _slc c on c.product_name_raw is not distinct from l.product_name_raw
                 and c.model_code is not distinct from l.model_code
                 and c.option_text is not distinct from l.option_text
     group by l.order_no;
  select count(*) into v_total from _slp;
  select coalesce(jsonb_agg(jsonb_build_object(
      'order_no', order_no, 'alt_order_no', alt_order_no, 'channel', ch, 'account', acct, 'buyer', buyer, 'cust_code', cust_code,
      'category', category, 'kind', kind,
      'at', to_char(at at time zone 'Asia/Seoul','MM-DD HH24:MI'),
      'collected', to_char(collected at time zone 'Asia/Seoul','MM-DD HH24:MI'),
      'io_date', (at at time zone 'Asia/Seoul')::date, 'done', done, 'status', status,
      'ec_slip', ec_slip, 'shipped', shipped, 'tracking_no', tracking_no,
      'qty', qty, 'amount', amount, 'lines', lines,
      'mapped', mapped, 'ambig', ambig, 'total_lines', total_lines,
      'ready', mapped = total_lines) order by at desc), '[]'::jsonb) into v_rows
  from (select * from _slp order by at desc limit greatest(p_limit,1)) t;
  return jsonb_build_object('rows', v_rows, 'total', v_total,
    'from', coalesce(p_from, (now() at time zone 'Asia/Seoul')::date - 7), 'to', coalesce(p_to, (now() at time zone 'Asia/Seoul')::date),
    'channels', (select coalesce(jsonb_agg(distinct ch),'[]'::jsonb) from _slp where ch is not null),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('c', category, 'n', n) order by n desc),'[]'::jsonb) from (select category, count(*) n from _slp where not done group by category) x),
    'kinds', (select coalesce(jsonb_agg(jsonb_build_object('k', kind, 'n', n) order by n desc),'[]'::jsonb) from (select kind, count(*) n from _slp where not done group by kind) x),
    'ready', (select count(*) from _slp where mapped = total_lines and not done),
    'ambig', (select count(*) from _slp where ambig > 0 and not done),
    'unmapped', (select count(*) from _slp where mapped < total_lines and not done),
    'done', (select count(*) from _slp where done),
    'shipped', (select count(*) from _slp where shipped and not done),
    'unshipped', (select count(*) from _slp where not shipped and not done),
    'lines', (select coalesce(sum(total_lines),0) from _slp));
end $$;

-- ── 10. 원장 적재 : 자사주문번호 · 송장번호 ─────────────────
create or replace function core.f_orders_bulk_upsert(p_source text, p_file_name text, p_rows jsonb, p_by uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_upload bigint; v_n int := 0; v_noKey int := 0; r jsonb; v_key char(16); v_alt text; v_name text; v_dig text;
begin
  insert into raw.upload (source, file_name, uploaded_by, row_count, note)
  values (p_source, p_file_name, p_by, jsonb_array_length(p_rows), p_note) returning id into v_upload;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_name := nullif(btrim(r->>'customer_name'), '');
    v_dig  := regexp_replace(coalesce(r->>'customer_phone',''), '\D', '', 'g');
    v_alt := coalesce(nullif(r->>'business_no',''), nullif(r->>'email',''),
                      case when p_source in ('rental','ecount') and v_name is not null
                            and (coalesce(r->>'account_type','')='business' or length(v_dig) < 8) then 'biz:'||v_name end);
    v_key := core.f_buyer_key(v_name, r->>'customer_phone', v_alt);
    if v_key is not null then
      insert into crm.customer (buyer_key, name, phone, email, address, account_type, business_no, first_seen_at, last_seen_at, source_channels)
      values (v_key, coalesce(v_name,'(미상)'), nullif(v_dig,''), nullif(r->>'email',''), nullif(r->>'address',''),
              coalesce(nullif(r->>'account_type',''), 'personal'), nullif(r->>'business_no',''),
              coalesce(core.f_ts(r->>'order_at'), now()), coalesce(core.f_ts(r->>'order_at'), now()), array[p_source])
      on conflict (buyer_key) do update set
        last_seen_at  = greatest(crm.customer.last_seen_at, excluded.last_seen_at),
        first_seen_at = least(crm.customer.first_seen_at, excluded.first_seen_at),
        name    = case when crm.customer.name = '(미상)' then excluded.name else crm.customer.name end,
        phone   = coalesce(crm.customer.phone, excluded.phone), email = coalesce(crm.customer.email, excluded.email),
        address = coalesce(crm.customer.address, excluded.address), business_no = coalesce(crm.customer.business_no, excluded.business_no),
        source_channels = (select array_agg(distinct x) from unnest(crm.customer.source_channels || excluded.source_channels) x);
    else v_noKey := v_noKey + 1; end if;
    insert into core.orders (source, channel_type, channel_name, order_no, line_no, source_ref, order_at, status,
      product_code, model_code, product_name_raw, option_text, qty, unit_price,
      gross_amount, supply_amount, vat_amount, discount_amount, refund_amount,
      payment_method, sale_kind, buyer_key, buyer_name_raw, handler, device_model, notes, upload_id, channel_account, alt_order_no, tracking_no)
    values (p_source, coalesce(r->>'channel_type', '매장'), coalesce(nullif(r->>'channel_name',''), r->>'channel_type', '매장'),
      coalesce(nullif(r->>'order_no',''), p_source||'-'||v_upload||'-'||v_n), coalesce((r->>'line_no')::int, 1),
      nullif(r->>'source_ref',''), coalesce(core.f_ts(r->>'order_at'), now()), coalesce(nullif(r->>'status',''), '결제완료'),
      nullif(r->>'product_code',''), nullif(r->>'model_code',''), r->>'product_name', nullif(r->>'option_text',''),
      coalesce((r->>'qty')::numeric, 1), (r->>'unit_price')::numeric,
      coalesce((r->>'gross_amount')::numeric, 0), (r->>'supply_amount')::numeric, (r->>'vat_amount')::numeric,
      coalesce((r->>'discount_amount')::numeric, 0), coalesce((r->>'refund_amount')::numeric, 0),
      nullif(r->>'payment_method',''), nullif(r->>'sale_kind',''), v_key, v_name, nullif(r->>'handler',''),
      nullif(r->>'device_model',''), nullif(r->>'notes',''), v_upload, nullif(r->>'channel_account',''), nullif(r->>'alt_order_no',''), nullif(r->>'tracking_no',''))
    on conflict (source, order_no, line_no) do update set
      status = excluded.status, gross_amount = excluded.gross_amount, refund_amount = excluded.refund_amount,
      qty = excluded.qty, model_code = coalesce(excluded.model_code, core.orders.model_code),
      source_ref = coalesce(excluded.source_ref, core.orders.source_ref),
      buyer_key = coalesce(excluded.buyer_key, core.orders.buyer_key),
      buyer_name_raw = coalesce(excluded.buyer_name_raw, core.orders.buyer_name_raw),
      alt_order_no = coalesce(excluded.alt_order_no, core.orders.alt_order_no),
      tracking_no = coalesce(excluded.tracking_no, core.orders.tracking_no), updated_at = now();
    v_n := v_n + 1;
  end loop;
  update raw.upload set error_count = v_noKey where id = v_upload;
  return jsonb_build_object('upload_id', v_upload, '적재', v_n, '고객키없음', v_noKey);
end $$;
