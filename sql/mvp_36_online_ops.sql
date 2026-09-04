-- mvp_36: 온라인 담당자 시트 → Datacenter
--   1) core.channel_daily   채널별 일별 매출/환불 (담당자 수기 · '온라인 매출_YYYY년' / '_raw' 시트)
--   2) core.settlement      오픈마켓 정산내역 (SSG/쿠팡/롯데온/자사몰)
--   3) core.listing_request 상품 등록/가격 요청 (시흥·가전시장·B2B 시트)

-- ───────── 1) 채널 일별 ─────────
create table if not exists core.channel_daily (
  biz_date date not null, channel text not null,
  sales numeric not null default 0, refund numeric not null default 0,
  source text not null default 'manual', file_name text, note text,
  updated_by uuid, updated_at timestamptz default now(),
  primary key (biz_date, channel));
alter table core.channel_daily enable row level security;

-- 채널 표준명 (GAS 대시보드와 동일)
create or replace function core.f_channel_norm(t text) returns text
language sql immutable set search_path = pg_catalog, public as $$
  select case regexp_replace(coalesce(t,''), '\s', '', 'g')
    when '프라자몰' then 'P몰' when 'P몰' then 'P몰' when '피몰' then 'P몰'
    when '에스몰' then 'S몰' when 'S몰' then 'S몰'
    when 'AT몰' then 'AT몰' when '에이티몰' then 'AT몰' when '삼성AT스토어' then 'AT몰'
    when '시흥' then '시흥' when '시흥몰' then '시흥' when '시흥스토어' then '시흥'
    when 'E스토어' then 'E스토어' when '이스토어' then 'E스토어' when '스마트스토어' then 'E스토어'
    when 'B2B' then 'B2B' when 'B2B스토어' then 'B2B' when '가전시장' then '가전시장' when '쿠팡' then '쿠팡' when '11번가' then '11번가'
    when '지마켓' then '지마켓' when 'G마켓' then '지마켓' when '옥션' then '옥션' when 'SSG' then 'SSG' when 'SSG닷컴' then 'SSG'
    when '현대홈쇼핑' then '현대홈쇼핑' when '현대몰' then '현대홈쇼핑' when '쿠팡이츠' then '쿠팡이츠'
    when 'SK스토아' then 'SK스토아' when 'SK스토어' then 'SK스토아' when '토스쇼핑' then '토스쇼핑' when '토스' then '토스쇼핑'
    when '롯데온' then '롯데온' when '카카오-관악' then '카카오-관악' when '카카오-시흥' then '카카오-시흥' when '한퓨어' then '한퓨어'
    else nullif(btrim(t),'') end;
$$;

create or replace function public.fn_channel_daily_upsert(p_rows jsonb, p_source text default 'manual', p_file text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_n int := 0; v_skip int := 0; r jsonb; v_ch text; v_d date;
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_ch := core.f_channel_norm(r->>'channel');
    v_d := core.f_dt(r->>'date');
    if v_ch is null or v_d is null then v_skip := v_skip + 1; continue; end if;
    insert into core.channel_daily (biz_date, channel, sales, refund, source, file_name, note, updated_by, updated_at)
    values (v_d, v_ch, coalesce((r->>'sales')::numeric,0), coalesce((r->>'refund')::numeric,0), coalesce(p_source,'manual'), p_file,
            nullif(r->>'note',''), auth.uid(), now())
    on conflict (biz_date, channel) do update set sales = excluded.sales, refund = excluded.refund,
      source = excluded.source, file_name = excluded.file_name, note = coalesce(excluded.note, core.channel_daily.note),
      updated_by = excluded.updated_by, updated_at = now();
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'upserted', v_n, 'skipped', v_skip);
end $$;
revoke all on function public.fn_channel_daily_upsert(jsonb, text, text) from public;
grant execute on function public.fn_channel_daily_upsert(jsonb, text, text) to authenticated;

-- 월 그리드: 수기값 + 원장(샵링커 등) 같은 날·채널 합계 (대사용)
create or replace function public.fn_channel_daily_month(p_month date)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $$
declare v_from date := date_trunc('month', p_month)::date; v_to date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return jsonb_build_object(
    'from', v_from, 'to', v_to,
    'channels', (select coalesce(jsonb_agg(c order by o), '[]'::jsonb) from (
        select c, o from unnest(array['P몰','S몰','AT몰','시흥','E스토어','B2B','가전시장','쿠팡','11번가','지마켓','옥션','SSG','현대홈쇼핑','쿠팡이츠','SK스토아','토스쇼핑','롯데온','카카오-관악','카카오-시흥','한퓨어']) with ordinality as t(c, o)
        union select channel, 100 from core.channel_daily where biz_date between v_from and v_to
          and channel not in ('P몰','S몰','AT몰','시흥','E스토어','B2B','가전시장','쿠팡','11번가','지마켓','옥션','SSG','현대홈쇼핑','쿠팡이츠','SK스토아','토스쇼핑','롯데온','카카오-관악','카카오-시흥','한퓨어')) x),
    'manual', (select coalesce(jsonb_agg(jsonb_build_object('d', biz_date, 'c', channel, 's', sales, 'r', refund, 'src', source)), '[]'::jsonb)
        from core.channel_daily where biz_date between v_from and v_to),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'c', c, 's', s, 'r', r, 'n', n)), '[]'::jsonb) from (
        select (o.order_at at time zone 'Asia/Seoul')::date d, core.f_channel_norm(o.channel_name) c,
               sum(o.gross_amount) s, sum(o.refund_amount) r, count(*) n
        from core.orders o
        where o.source in ('shoplinker','godo','smartstore') and (o.order_at at time zone 'Asia/Seoul')::date between v_from and v_to
        group by 1, 2) t),
    'closed_days', (select count(distinct biz_date) from core.channel_daily where biz_date between v_from and v_to));
end $$;
revoke all on function public.fn_channel_daily_month(date) from public;
grant execute on function public.fn_channel_daily_month(date) to authenticated;

-- ───────── 2) 정산내역 ─────────
create table if not exists core.settlement (
  id bigserial primary key,
  channel text not null, sales_month date not null,           -- 결제완료 월 (YYYY-MM-01)
  sales_amount numeric, net_amount numeric,                   -- 판매금액 · 수수료제외 금액
  delivered_amount numeric,                                   -- 배송완료금액(수수료제외)
  settle_date date, expected_amount numeric, pay_ratio numeric, paid_date date,
  period_text text, status text, note text,
  source text default 'manual', file_name text, updated_by uuid, updated_at timestamptz default now());
create unique index if not exists settlement_uq on core.settlement (channel, sales_month, coalesce(settle_date, '1900-01-01'::date), coalesce(period_text,''), coalesce(pay_ratio, 0));
alter table core.settlement enable row level security;

create or replace function public.fn_settlement_upsert(p_rows jsonb, p_source text default 'manual', p_file text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_n int := 0; v_skip int := 0; r jsonb; v_ch text; v_m date;
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_ch := core.f_channel_norm(r->>'channel'); v_m := core.f_dt(r->>'sales_month');
    if v_ch is null or v_m is null then v_skip := v_skip + 1; continue; end if;
    v_m := date_trunc('month', v_m)::date;
    insert into core.settlement (channel, sales_month, sales_amount, net_amount, delivered_amount, settle_date, expected_amount,
      pay_ratio, paid_date, period_text, status, note, source, file_name, updated_by, updated_at)
    values (v_ch, v_m, nullif(r->>'sales_amount','')::numeric, nullif(r->>'net_amount','')::numeric, nullif(r->>'delivered_amount','')::numeric,
      core.f_dt(r->>'settle_date'), nullif(r->>'expected_amount','')::numeric, nullif(r->>'pay_ratio','')::numeric, core.f_dt(r->>'paid_date'),
      nullif(r->>'period_text',''), nullif(r->>'status',''), nullif(r->>'note',''), coalesce(p_source,'manual'), p_file, auth.uid(), now())
    on conflict (channel, sales_month, coalesce(settle_date, '1900-01-01'::date), coalesce(period_text,''), coalesce(pay_ratio, 0)) do update set
      sales_amount = coalesce(excluded.sales_amount, core.settlement.sales_amount), net_amount = coalesce(excluded.net_amount, core.settlement.net_amount),
      delivered_amount = coalesce(excluded.delivered_amount, core.settlement.delivered_amount),
      expected_amount = coalesce(excluded.expected_amount, core.settlement.expected_amount), paid_date = coalesce(excluded.paid_date, core.settlement.paid_date),
      status = coalesce(excluded.status, core.settlement.status), note = coalesce(excluded.note, core.settlement.note),
      source = excluded.source, file_name = excluded.file_name, updated_by = excluded.updated_by, updated_at = now();
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'upserted', v_n, 'skipped', v_skip);
end $$;
revoke all on function public.fn_settlement_upsert(jsonb, text, text) from public;
grant execute on function public.fn_settlement_upsert(jsonb, text, text) to authenticated;

create or replace function public.fn_settlement_list(p_from date, p_to date, p_channel text default null)
returns table (id bigint, channel text, sales_month date, sales_amount numeric, net_amount numeric, delivered_amount numeric,
  settle_date date, expected_amount numeric, pay_ratio numeric, paid_date date, period_text text, status text, note text, source text)
language sql stable security definer set search_path = pg_catalog, public as $$
  select s.id, s.channel, s.sales_month, s.sales_amount, s.net_amount, s.delivered_amount, s.settle_date, s.expected_amount,
         s.pay_ratio, s.paid_date, s.period_text, s.status, s.note, s.source
  from core.settlement s
  where core.f_role() <> 'anon' and s.sales_month between date_trunc('month', p_from)::date and p_to
    and (p_channel is null or p_channel = '' or s.channel = p_channel)
  order by s.sales_month desc, s.channel, s.settle_date nulls last, s.pay_ratio;
$$;
revoke all on function public.fn_settlement_list(date, date, text) from public;
grant execute on function public.fn_settlement_list(date, date, text) to authenticated;

create or replace function public.fn_settlement_set(p_id bigint, p_status text, p_paid_date date, p_note text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  update core.settlement set status = nullif(p_status,''), paid_date = p_paid_date, note = nullif(p_note,''), updated_by = auth.uid(), updated_at = now()
  where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.fn_settlement_set(bigint, text, date, text) from public;
grant execute on function public.fn_settlement_set(bigint, text, date, text) to authenticated;

-- ───────── 3) 상품 등록/가격 요청 ─────────
create table if not exists core.listing_request (
  id bigserial primary key,
  sheet text not null,                 -- 시흥 / 가전시장 / B2B / 기타
  category text, requester text, status text, model text, note text,
  list_price numeric, opt1 text, opt2 text, opt3 text, sub_price numeric, sub_warranty text, min_price numeric,
  requested_at date, source text default 'manual', file_name text, updated_by uuid, updated_at timestamptz default now());
create unique index if not exists listing_request_uq on core.listing_request (sheet, model, coalesce(category,''), coalesce(requester,''));
alter table core.listing_request enable row level security;

create or replace function public.fn_listing_request_upsert(p_rows jsonb, p_source text default 'manual', p_file text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_n int := 0; v_skip int := 0; r jsonb;
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if nullif(r->>'model','') is null then v_skip := v_skip + 1; continue; end if;
    insert into core.listing_request (sheet, category, requester, status, model, note, list_price, opt1, opt2, opt3, sub_price, sub_warranty, min_price,
      requested_at, source, file_name, updated_by, updated_at)
    values (coalesce(nullif(r->>'sheet',''),'기타'), nullif(r->>'category',''), nullif(r->>'requester',''), nullif(r->>'status',''),
      upper(btrim(r->>'model')), nullif(r->>'note',''), nullif(regexp_replace(coalesce(r->>'list_price',''),'[^0-9.]','','g'),'')::numeric,
      nullif(r->>'opt1',''), nullif(r->>'opt2',''), nullif(r->>'opt3',''),
      nullif(regexp_replace(coalesce(r->>'sub_price',''),'[^0-9.]','','g'),'')::numeric, nullif(r->>'sub_warranty',''),
      nullif(regexp_replace(coalesce(r->>'min_price',''),'[^0-9.]','','g'),'')::numeric,
      core.f_dt(r->>'requested_at'), coalesce(p_source,'manual'), p_file, auth.uid(), now())
    on conflict (sheet, model, coalesce(category,''), coalesce(requester,'')) do update set
      status = coalesce(excluded.status, core.listing_request.status), note = coalesce(excluded.note, core.listing_request.note),
      list_price = coalesce(excluded.list_price, core.listing_request.list_price), opt1 = coalesce(excluded.opt1, core.listing_request.opt1),
      opt2 = coalesce(excluded.opt2, core.listing_request.opt2), opt3 = coalesce(excluded.opt3, core.listing_request.opt3),
      sub_price = coalesce(excluded.sub_price, core.listing_request.sub_price), sub_warranty = coalesce(excluded.sub_warranty, core.listing_request.sub_warranty),
      min_price = coalesce(excluded.min_price, core.listing_request.min_price), source = excluded.source, file_name = excluded.file_name,
      updated_by = excluded.updated_by, updated_at = now();
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'upserted', v_n, 'skipped', v_skip);
end $$;
revoke all on function public.fn_listing_request_upsert(jsonb, text, text) from public;
grant execute on function public.fn_listing_request_upsert(jsonb, text, text) to authenticated;

create or replace function public.fn_listing_request_list(p_sheet text default null, p_status text default null, p_q text default null)
returns table (id bigint, sheet text, category text, requester text, status text, model text, note text, list_price numeric,
  opt1 text, opt2 text, opt3 text, sub_price numeric, sub_warranty text, min_price numeric, requested_at date, updated_at timestamptz)
language sql stable security definer set search_path = pg_catalog, public as $$
  select l.id, l.sheet, l.category, l.requester, l.status, l.model, l.note, l.list_price, l.opt1, l.opt2, l.opt3, l.sub_price, l.sub_warranty, l.min_price, l.requested_at, l.updated_at
  from core.listing_request l
  where core.f_role() <> 'anon'
    and (p_sheet is null or p_sheet = '' or l.sheet = p_sheet)
    and (p_status is null or p_status = '' or l.status = p_status)
    and (p_q is null or p_q = '' or l.model ilike '%'||p_q||'%' or l.category ilike '%'||p_q||'%' or l.note ilike '%'||p_q||'%' or l.requester ilike '%'||p_q||'%')
  order by (l.status in ('작업완료','완료')) asc, l.updated_at desc limit 500;
$$;
revoke all on function public.fn_listing_request_list(text, text, text) from public;
grant execute on function public.fn_listing_request_list(text, text, text) to authenticated;

create or replace function public.fn_listing_request_set(p_id bigint, p_status text, p_note text, p_list_price numeric, p_sub_price numeric, p_min_price numeric)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  update core.listing_request set status = nullif(p_status,''), note = nullif(p_note,''), list_price = p_list_price, sub_price = p_sub_price,
    min_price = p_min_price, updated_by = auth.uid(), updated_at = now() where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.fn_listing_request_set(bigint, text, text, numeric, numeric, numeric) from public;
grant execute on function public.fn_listing_request_set(bigint, text, text, numeric, numeric, numeric) to authenticated;
