-- mvp_96 (2026-09-07) 주문서 직접 입력 폼 — 이카운트 주문서 입력 화면과 같은 항목
--   상단 : 일자 · 거래처(ec.customer 검색) · 영업담당(코드표) · 출하창고 · 판매담당자(텍스트) · 거래유형(코드표) · 구분(코드표) · 특이사항
--   하단 : 품목코드(품목명으로 자동) · 품목명 · 수량 · 단가(VAT포함) · 공급가 · 부가세(자동) · 적요
--   영업담당·거래유형·구분은 이카운트에 조회 API 가 없어 코드표(ec.code)를 관리자 화면에서 한 번 입력해 둔다.
--   거래처는 이카운트 거래처 엑셀 업로드(ec.customer)로 채운다. 쇼핑몰 거래처 15곳은 channel_cust 에서 미리 넣음.

create table if not exists ec.code (
  kind text not null,             -- emp(영업담당) · io_type(거래유형) · kind(구분)
  code text not null,
  label text not null,
  sort int not null default 100,
  active boolean not null default true,
  primary key (kind, code)
);
-- 거래유형은 이카운트 표준 코드. 라벨은 이카운트 기초등록 화면과 다르면 관리자 화면에서 고친다.
insert into ec.code (kind, code, label, sort) values
  ('io_type','11','과세 (부가세 별도)',10), ('io_type','12','영세',20), ('io_type','13','면세',30), ('io_type','14','과세 (부가세 포함)',40)
on conflict do nothing;

insert into ec.customer (code, name, note)
  select c.cust_code, c.channel || case when c.sub is not null then ' ('||c.sub||')' else '' end, '쇼핑몰 거래처 (channel_cust)'
  from ec.channel_cust c where c.cust_code is not null
on conflict (code) do nothing;

alter table ec.order_queue add column if not exists handler text;      -- 판매담당자 (텍스트)
alter table ec.order_queue add column if not exists kind_code text;    -- 구분
alter table ec.order_queue_line add column if not exists supply_amt numeric;  -- 공급가액 (줄 합계)
alter table ec.order_queue_line add column if not exists vat_amt numeric;     -- 부가세 (줄 합계)

-- 전송 필드 매핑 : 우리 항목 → 이카운트 SaleOrder 필드. 필드 확인 전표 결과를 보고 관리자 화면에서 고친다.
insert into core.app_setting (key, value) values ('ec_field_map',
  '{"phone":"U_MEMO1","addr":"U_TXT1","remark":"ADD_TXT_01_T","handler":"U_MEMO2","kind":"ADD_CD_01","order_no":"U_MEMO3"}')
on conflict (key) do nothing;

-- ── 메타(코드표·창고·담당자) ──────────────────────────────
create or replace function core.f_order_meta()
returns jsonb language sql stable set search_path = pg_catalog, public as $$
  select jsonb_build_object(
    'warehouses', (select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name) order by code),'[]') from ec.warehouse where active),
    'emp',     (select coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label) order by sort, code),'[]') from ec.code where kind='emp' and active),
    'io_type', (select coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label) order by sort, code),'[]') from ec.code where kind='io_type' and active),
    'kind',    (select coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label) order by sort, code),'[]') from ec.code where kind='kind' and active),
    'staff',   (select coalesce(jsonb_agg(name order by name),'[]') from core.staff where active),
    'channels',(select coalesce(jsonb_agg(distinct channel),'[]') from ec.channel_cust),
    'customers_n', (select count(*) from ec.customer));
$$;
create or replace function public.fn_order_meta()
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_order_meta();
end $$;
create or replace function public.fn_store_order_meta(p_code text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_me text := core.f_staff(p_code);
begin
  if not core.f_has_perm(v_me, 'order') then raise exception '주문서 권한이 없습니다' using errcode='42501'; end if;
  return core.f_order_meta() || jsonb_build_object('me', v_me);
end $$;

-- 코드표 관리 (관리자)
create or replace function public.fn_ec_codes_set(p_kind text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare r jsonb; i int := 0;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 가능합니다' using errcode='42501'; end if;
  if p_kind not in ('emp','io_type','kind') then raise exception '알 수 없는 코드표: %', p_kind; end if;
  update ec.code set active = false where kind = p_kind;
  for r in select value from jsonb_array_elements(p_rows) loop
    continue when nullif(btrim(r->>'code'),'') is null;
    i := i + 1;
    insert into ec.code (kind, code, label, sort, active)
    values (p_kind, btrim(r->>'code'), coalesce(nullif(btrim(r->>'label'),''), btrim(r->>'code')), i*10, true)
    on conflict (kind, code) do update set label = excluded.label, sort = excluded.sort, active = true;
  end loop;
  return jsonb_build_object('kind', p_kind, 'n', i);
end $$;

-- ── 거래처 ────────────────────────────────────────────────
create or replace function core.f_ec_customer_search(p_q text, p_limit int default 20)
returns jsonb language sql stable set search_path = pg_catalog, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('code',c.code,'name',c.name,'ceo',c.ceo,'phone',coalesce(c.mobile,c.phone),'addr',c.addr,
                                               'handler',c.handler,'deal_type',c.deal_type,'kind',c.kind) order by
           case when c.name ilike p_q||'%' then 0 else 1 end, c.name), '[]'::jsonb)
  from (select * from ec.customer c
         where p_q is null or p_q = '' or c.name ilike '%'||p_q||'%' or c.code ilike '%'||p_q||'%'
            or regexp_replace(coalesce(c.mobile,c.phone,''),'\D','','g') like '%'||regexp_replace(p_q,'\D','','g')||'%' and length(regexp_replace(p_q,'\D','','g')) >= 4
         order by case when c.name ilike p_q||'%' then 0 else 1 end, c.name limit least(greatest(coalesce(p_limit,20),1),50)) c;
$$;
create or replace function public.fn_ec_customer_search(p_q text, p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_ec_customer_search(p_q, p_limit);
end $$;
create or replace function public.fn_store_ec_customers(p_code text, p_q text, p_limit int default 20)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_me text := core.f_staff(p_code);
begin
  if not core.f_has_perm(v_me, 'order') then raise exception '주문서 권한이 없습니다' using errcode='42501'; end if;
  return core.f_ec_customer_search(p_q, p_limit);
end $$;

-- 이카운트 거래처 엑셀 → ec.customer (관리자 데이터 가져오기)
create or replace function public.fn_ec_customers_upsert(p_rows jsonb, p_source text default 'sheet', p_file text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare r jsonb; i int := 0; v_up bigint;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 가능합니다' using errcode='42501'; end if;
  insert into raw.upload (source, file_name, uploaded_by, row_count) values ('ecount_customer', p_file, auth.uid(), jsonb_array_length(p_rows)) returning id into v_up;
  for r in select value from jsonb_array_elements(p_rows) loop
    continue when nullif(btrim(r->>'code'),'') is null;
    i := i + 1;
    insert into ec.customer (code, name, ceo, phone, mobile, addr, handler, deal_type, kind, note)
    values (btrim(r->>'code'), coalesce(nullif(btrim(r->>'name'),''), btrim(r->>'code')), nullif(btrim(r->>'ceo'),''), nullif(btrim(r->>'phone'),''),
            nullif(btrim(r->>'mobile'),''), nullif(btrim(r->>'addr'),''), nullif(btrim(r->>'handler'),''), nullif(btrim(r->>'deal_type'),''),
            nullif(btrim(r->>'kind'),''), '업로드 #'||v_up)
    on conflict (code) do update set name = excluded.name, ceo = coalesce(excluded.ceo, ec.customer.ceo), phone = coalesce(excluded.phone, ec.customer.phone),
      mobile = coalesce(excluded.mobile, ec.customer.mobile), addr = coalesce(excluded.addr, ec.customer.addr), handler = coalesce(excluded.handler, ec.customer.handler),
      deal_type = coalesce(excluded.deal_type, ec.customer.deal_type), kind = coalesce(excluded.kind, ec.customer.kind);
  end loop;
  return jsonb_build_object('upload_id', v_up, '거래처', i);
end $$;

-- ── 품목명 → 품목코드 (붙여넣은 줄마다) ───────────────────
create or replace function core.f_item_resolve(p_rows jsonb)
returns jsonb language plpgsql stable set search_path = pg_catalog, public as $$
declare r jsonb; out jsonb := '[]'::jsonb; v_code text; v_name text; v_model text; v_cands jsonb; v_q text;
begin
  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    v_code := nullif(upper(btrim(coalesce(r->>'code',''))),''); v_name := nullif(btrim(coalesce(r->>'name','')),''); v_model := nullif(btrim(coalesce(r->>'model','')),'');
    -- 1) 코드가 있으면 그대로 확인
    if v_code is not null and exists (select 1 from inv.item where code = v_code and active) then
      out := out || jsonb_build_object('code', v_code, 'name', (select name from inv.item where code = v_code), 'how', 'code'); continue;
    end if;
    -- 2) "코드"라고 넣은 것이 사실 품목명일 수도 있다
    v_q := coalesce(v_name, v_code);
    if v_q is null then out := out || jsonb_build_object('code', null, 'name', null, 'how', 'empty'); continue; end if;
    -- 3) 품목명이 마스터와 정확히 같음
    select i.code into v_code from inv.item i where i.active and upper(regexp_replace(i.name,'\s','','g')) = upper(regexp_replace(v_q,'\s','','g')) limit 1;
    if v_code is not null then out := out || jsonb_build_object('code', v_code, 'name', (select name from inv.item where code = v_code), 'how', 'exact'); continue; end if;
    -- 4) 별칭·모델 규칙 (샵링커 변환과 같은 규칙)
    v_code := core.f_ec_code_of(v_q, v_model);
    if v_code is not null then out := out || jsonb_build_object('code', v_code, 'name', (select name from inv.item where code = v_code), 'how', 'alias'); continue; end if;
    -- 5) 후보만 돌려준다 (사용자가 고른다)
    v_cands := coalesce(core.f_ec_cands(v_q, v_model, null), '[]'::jsonb);
    if jsonb_array_length(v_cands) = 0 then
      v_cands := (select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name) order by i.name), '[]'::jsonb)
                  from (select code, name from inv.item i where i.active and (i.name ilike '%'||v_q||'%' or i.model ilike '%'||v_q||'%' or i.code ilike '%'||v_q||'%') limit 8) i);
    end if;
    out := out || jsonb_build_object('code', null, 'name', v_q, 'how', 'cands', 'cands', v_cands);
  end loop;
  return out;
end $$;
create or replace function public.fn_item_resolve(p_rows jsonb)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_item_resolve(p_rows);
end $$;
create or replace function public.fn_store_item_resolve(p_code text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_me text := core.f_staff(p_code);
begin
  if not core.f_has_perm(v_me, 'order') then raise exception '주문서 권한이 없습니다' using errcode='42501'; end if;
  return core.f_item_resolve(p_rows);
end $$;

-- ── 주문서 저장 : 새 항목(영업담당·판매담당자·거래유형·구분·공급가·부가세) 반영 ──
create or replace function core.f_order_submit(p_data jsonb, p_by text)
returns jsonb language plpgsql set search_path = pg_catalog, public as $$
declare v_id bigint; r jsonb; i int := 0; v_code text; v_qty numeric; v_wh text; v_date date; v_lines jsonb;
        v_short jsonb := '[]'::jsonb; v_cur numeric; v_price numeric; v_tot numeric; v_sup numeric; v_vat numeric;
begin
  v_wh   := coalesce(nullif(btrim(p_data->>'wh_code'),''), '00001');
  v_date := coalesce(nullif(btrim(p_data->>'io_date'),'')::date, (now() at time zone 'Asia/Seoul')::date);
  v_lines := coalesce(p_data->'lines', '[]'::jsonb);
  if jsonb_array_length(v_lines) = 0 then raise exception '품목을 한 줄 이상 넣으세요'; end if;
  if not exists (select 1 from ec.warehouse where code = v_wh and active) then raise exception '창고가 없습니다: %', v_wh; end if;

  for r in select value from jsonb_array_elements(v_lines) loop
    v_code := upper(btrim(coalesce(r->>'item_code','')));
    v_qty  := nullif(btrim(coalesce(r->>'qty','')),'')::numeric;
    if v_code = '' then raise exception '품목코드가 빈 줄이 있습니다 (%)', coalesce(r->>'item_name','?'); end if;
    if v_qty is null or v_qty <= 0 then raise exception '% : 수량은 0보다 커야 합니다', v_code; end if;
    if not exists (select 1 from inv.item where code = v_code and active) then raise exception '없는 품목입니다: %', v_code; end if;
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
    v_price := nullif(regexp_replace(coalesce(r->>'unit_price',''),'[^0-9.-]','','g'),'')::numeric;
    v_tot := case when v_price is null then null else round(v_price * v_qty) end;
    v_sup := nullif(regexp_replace(coalesce(r->>'supply_amt',''),'[^0-9.-]','','g'),'')::numeric;
    v_vat := nullif(regexp_replace(coalesce(r->>'vat_amt',''),'[^0-9.-]','','g'),'')::numeric;
    if v_tot is not null and v_sup is null then v_sup := round(v_tot / 1.1); end if;   -- 이카운트 기본 계산과 같게 (합계/1.1 반올림)
    if v_tot is not null and v_vat is null then v_vat := v_tot - v_sup; end if;
    insert into ec.order_queue_line (queue_id, line_no, item_code, item_name, qty, unit_price, supply_amt, vat_amt, remark)
    values (v_id, i, v_code, coalesce(nullif(btrim(r->>'item_name'),''), (select name from inv.item where code = v_code)), v_qty,
            v_price, v_sup, v_vat, nullif(btrim(r->>'remark'),''));
    insert into inv.movement (moved_at, kind, item_code, warehouse, qty, unit_cost, ref_type, ref_no, note, created_by)
    values ((v_date::timestamp + interval '12 hours') at time zone 'Asia/Seoul', 'out', v_code, v_wh, v_qty,
            v_price, 'order', v_id::text,
            coalesce(nullif(btrim(p_data->>'channel'),'')||' ', '') || coalesce(nullif(btrim(p_data->>'order_no'),''),'주문 '||v_id), p_by);
  end loop;

  return jsonb_build_object('ok', true, 'id', v_id, 'lines', i, 'shortage', v_short);
end $$;

-- ── 전송 본문 : 필드 매핑(app_setting ec_field_map) 적용 + 공급가·부가세 ──
create or replace function core.f_order_body(p_id bigint)
returns jsonb language plpgsql stable set search_path = pg_catalog, public as $$
declare q record; l record; v_map jsonb; base jsonb; line jsonb; lines jsonb := '[]'::jsonb;
  clean text; k text;
begin
  select * into q from ec.order_queue where id = p_id; if not found then return null; end if;
  v_map := coalesce((select value::jsonb from core.app_setting where key = 'ec_field_map'), '{}'::jsonb);
  base := jsonb_build_object('IO_DATE', to_char(q.io_date,'YYYYMMDD'), 'UPLOAD_SER_NO', q.id::text,
            'CUST', q.cust_code, 'CUST_DES', q.cust_name, 'EMP_CD', q.emp_code, 'WH_CD', q.wh_code, 'IO_TYPE', q.deal_type,
            'TIME_DATE', case when q.due_date is null then null else to_char(q.due_date,'YYYYMMDD') end);
  -- 우리 항목 → 이카운트 필드 (특수문자는 이카운트가 거부하므로 정리)
  for k in select jsonb_object_keys(v_map) loop
    clean := case k when 'phone' then nullif(regexp_replace(coalesce(q.phone,''),'[^0-9-]','','g'),'')
                    when 'addr' then nullif(regexp_replace(coalesce(q.addr,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),'')
                    when 'remark' then nullif(regexp_replace(coalesce(q.remark,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),'')
                    when 'handler' then nullif(regexp_replace(coalesce(q.handler,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),'')
                    when 'kind' then q.kind_code
                    when 'order_no' then nullif(regexp_replace(coalesce(q.order_no,''),'[^0-9A-Za-z가-힣 ,.()/-]',' ','g'),'')
                    when 'channel' then q.channel
                    else null end;
    if clean is not null and nullif(v_map->>k,'') is not null then base := base || jsonb_build_object(v_map->>k, clean); end if;
  end loop;
  -- U_MEMO1 은 필수 : 비어 있으면 기본값
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

revoke all on function public.fn_order_meta(), public.fn_ec_codes_set(text,jsonb), public.fn_ec_customer_search(text,int), public.fn_ec_customers_upsert(jsonb,text,text), public.fn_item_resolve(jsonb) from public, anon;
grant execute on function public.fn_order_meta(), public.fn_ec_codes_set(text,jsonb), public.fn_ec_customer_search(text,int), public.fn_ec_customers_upsert(jsonb,text,text), public.fn_item_resolve(jsonb) to authenticated;
revoke all on function public.fn_store_order_meta(text), public.fn_store_ec_customers(text,text,int), public.fn_store_item_resolve(text,jsonb) from public;
grant execute on function public.fn_store_order_meta(text), public.fn_store_ec_customers(text,text,int), public.fn_store_item_resolve(text,jsonb) to anon, authenticated;
