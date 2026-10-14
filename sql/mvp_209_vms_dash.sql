-- mvp_209 (2026-10-14) VMS(통신판매) 대시보드 — /dash/vms/
-- 자료 = core.orders_live source='ecount' (이카운트 판매현황 · 영업담당 오픈마켓 전표는 적재 때 이미 제외).
-- 주문 = 고객×날짜 합산, 주기 = 간격 중앙값, 교체 예정일 = 마지막 구매 + 주기(최소 30일) — 콜랩 CRM_analytics 와 같은 규칙.
-- 캐시 core.rpc_cache 'vms_dash' (cron vms-warm 7,37분 · 빌드 약 7초 · 10KB)
-- 처음 판은 cu 가 고객마다 d 를 다시 훑는 상관 서브쿼리라 60초를 넘겼다 → a12·crm.customer·sms_optout 을 조인으로 (지금 7초) → 읽기는 fn_vms_payload(관리자) · fn_vms_payload_pub(공유 비밀번호 dash_share).

create or replace function core.f_vms_payload_build() returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $f$
with o as (
  select buyer_key, (order_at at time zone 'Asia/Seoul')::date dt, net_amount amt, qty, model_key, product_name_raw, category, handler
  from core.orders_live where source='ecount' and buyer_key is not null),
d as (select buyer_key, dt, sum(amt) amt from o where amt<>0 group by 1,2),
c as (
  select buyer_key, count(*) days, min(dt) first_dt, max(dt) last_dt, sum(amt) amt,
         percentile_cont(0.5) within group (order by dt-prev) cyc
  from (select *, lag(dt) over (partition by buyer_key order by dt) prev from d) z group by 1),
a12 as (select buyer_key, sum(amt) amt12 from d where dt >= current_date-365 group by 1),
cu as (select c.*, (current_date - c.last_dt) since, coalesce(a12.amt12,0) amt12,
         regexp_replace(coalesce(x.phone,''),'\D','','g') ph, coalesce(x.consent_marketing,false) consent
       from c left join a12 using(buyer_key) left join crm.customer x on x.buyer_key=c.buyer_key),
cu2 as (select cu.*, (ph ~ '^01[016789]\d{7,8}$') mobile, (op.d8 is not null) optout,
         case when days>=2 then last_dt + greatest(cyc,30)::int end due_dt,
         case when days>=2 and cyc>0 then round(amt/days * 365.0/greatest(cyc,30)) end annual
         from cu left join (select distinct d8 from crm.sms_optout where released_at is null) op on op.d8 = right(cu.ph,8) and length(cu.ph)>=8),
m0 as (select generate_series(date_trunc('month',current_date)-interval '23 months', date_trunc('month',current_date), interval '1 month')::date m),
months as (
  select to_char(m0.m,'YYYY-MM') m,
    coalesce(sum(d.amt) filter (where d.dt<>c.first_dt),0)::bigint rev_rep,
    coalesce(sum(d.amt) filter (where d.dt=c.first_dt),0)::bigint rev_new,
    count(distinct d.buyer_key) filter (where d.dt<>c.first_dt) buyers_rep,
    count(distinct d.buyer_key) filter (where d.dt=c.first_dt) buyers_new
  from m0 left join d on date_trunc('month',d.dt)=m0.m left join c on c.buyer_key=d.buyer_key
  group by m0.m order by m0.m),
seg as (
  select k, ord, count(*) n, sum(amt)::bigint amt, round(avg(amt))::bigint avg_amt from (
    select case when since<=90 then '최근 3개월 구매' when since<=180 then '3~6개월 전 구매' when since<=365 then '6~12개월 전 구매'
                when since<=730 then '1~2년 전 구매' else '2년 이상 미구매' end k,
           case when since<=90 then 1 when since<=180 then 2 when since<=365 then 3 when since<=730 then 4 else 5 end ord, amt from cu2) z
  group by 1,2 order by 2),
wk as (select generate_series(0,12) i),
due as (
  select jsonb_build_object(
    'overdue30', count(*) filter (where due_dt < current_date-30),
    'overdue',   count(*) filter (where due_dt >= current_date-30 and due_dt < current_date),
    'next30',    count(*) filter (where due_dt >= current_date and due_dt < current_date+30),
    'next90',    count(*) filter (where due_dt >= current_date+30 and due_dt < current_date+90),
    'later',     count(*) filter (where due_dt >= current_date+90),
    'weeks', (select jsonb_agg(jsonb_build_object('w', to_char(current_date + wk.i*7,'MM/DD'),
                'n', (select count(*) from cu2 x where x.since<=365 and x.due_dt >= current_date + wk.i*7 and x.due_dt < current_date + (wk.i+1)*7)) order by wk.i) from wk))
  from cu2 where since<=365),
mm as (select generate_series(date_trunc('month',current_date)-interval '11 months', date_trunc('month',current_date), interval '1 month')::date m),
models as (
  select coalesce(o.model_key, left(o.product_name_raw,30)) model, max(o.product_name_raw) name,
         sum(o.amt)::bigint amt12, count(distinct o.buyer_key) buyers12, sum(o.qty)::int qty12
  from o where o.dt >= current_date-365 and o.amt>0 group by 1 order by 3 desc limit 10),
model_trend as (
  select md.model, (select jsonb_agg(coalesce((select sum(o.amt) from o where coalesce(o.model_key,left(o.product_name_raw,30))=md.model and o.amt>0 and date_trunc('month',o.dt)=mm.m),0)::bigint order by mm.m) from mm) trend
  from models md),
handlers as (
  select coalesce(handler,'(미지정)') h, sum(amt)::bigint amt12, count(distinct buyer_key) buyers12
  from o where dt >= current_date-365 and amt>0 group by 1 order by 2 desc limit 8),
tiers as (
  select k, ord, count(*) n, sum(amt12)::bigint amt12 from (
    select case when amt12>=1000000 then '연 100만원 이상' when amt12>=300000 then '연 30~100만원' when amt12>=100000 then '연 10~30만원' else '연 10만원 미만' end k,
           case when amt12>=1000000 then 1 when amt12>=300000 then 2 when amt12>=100000 then 3 else 4 end ord, amt12 from cu2 where amt12>0) z group by 1,2 order by 2),
top20 as (
  select round(100.0 * sum(amt12) filter (where rn <= cnt*0.2) / nullif(sum(amt12),0)) share
  from (select amt12, row_number() over (order by amt12 desc) rn, count(*) over () cnt from cu2 where amt12>0) z),
byfreq as (
  select k, ord, count(*) n, round(avg(amt))::bigint avg_total, round(avg(annual))::bigint avg_annual, round(avg(cyc))::int avg_cyc from (
    select case when days=1 then '1회 구매' when days<=3 then '2~3회' when days<=9 then '4~9회' else '10회 이상' end k,
           case when days=1 then 1 when days<=3 then 2 when days<=9 then 3 else 4 end ord, amt, annual, cyc from cu2 where since<=365) z group by 1,2 order by 2),
crm as (
  select jsonb_build_object(
    'due30',      count(*) filter (where due_dt between current_date and current_date+30),
    'overdue',    count(*) filter (where due_dt < current_date and due_dt >= current_date-60),
    'risk',       count(*) filter (where since between 181 and 365 and days>=2),
    'high_risk',  count(*) filter (where since > 120 and days>=4 and amt12 >= 300000),
    'sms_ok',     count(*) filter (where mobile and not optout and since<=180 and days>=2),
    'sms_consent',count(*) filter (where mobile and not optout and consent),
    'no_mobile',  count(*) filter (where not mobile and since<=365),
    'optout',     count(*) filter (where optout))
  from cu2),
kpi as (
  select jsonb_build_object(
    'rev12',       (select sum(amt) from d where dt>=current_date-365)::bigint,
    'rev_prev12',  (select sum(amt) from d where dt>=current_date-730 and dt<current_date-365)::bigint,
    'buyers12',    (select count(distinct buyer_key) from d where dt>=current_date-365),
    'buyers_prev12',(select count(distinct buyer_key) from d where dt>=current_date-730 and dt<current_date-365),
    'orders12',    (select count(*) from d where dt>=current_date-365),
    'avg_order',   (select round(avg(amt)) from d where dt>=current_date-365)::bigint,
    'repeat_rate', (select round(100.0*count(*) filter (where days>=2)/nullif(count(*),0)) from cu2 where since<=365),
    'med_cycle',   (select round(percentile_cont(0.5) within group (order by cyc)) from cu2 where days>=2 and since<=365),
    'ltv_avg',     (select round(avg(amt)) from cu2 where since<=365)::bigint,
    'rev_rep_share',(select round(100.0*sum(rev_rep)/nullif(sum(rev_rep+rev_new),0)) from months where m >= to_char(current_date-365,'YYYY-MM')),
    'last_order',  (select max(dt) from d)))
select jsonb_build_object(
  'built_at', now(), 'today', current_date,
  'kpi', (select * from kpi),
  'months', (select jsonb_agg(to_jsonb(months)) from months),
  'seg', (select jsonb_agg(jsonb_build_object('k',k,'n',n,'amt',amt,'avg',avg_amt) order by ord) from seg),
  'due', (select * from due),
  'models', (select jsonb_agg(jsonb_build_object('model',md.model,'name',md.name,'amt12',md.amt12,'buyers12',md.buyers12,'qty12',md.qty12,'trend',mt.trend) order by md.amt12 desc) from models md join model_trend mt using(model)),
  'months12', (select jsonb_agg(to_char(m,'YY.MM') order by m) from mm),
  'handlers', (select jsonb_agg(to_jsonb(handlers) order by amt12 desc) from handlers),
  'ltv', jsonb_build_object(
     'tiers', (select jsonb_agg(jsonb_build_object('k',k,'n',n,'amt12',amt12) order by ord) from tiers),
     'top20_share', (select share from top20),
     'by_freq', (select jsonb_agg(jsonb_build_object('k',k,'n',n,'avg_total',avg_total,'avg_annual',avg_annual,'avg_cyc',avg_cyc) order by ord) from byfreq)),
  'crm', (select * from crm),
  'sms', (select jsonb_build_object(
     'sent30', count(*) filter (where sent_at >= now()-interval '30 days'),
     'sent90', count(*) filter (where sent_at >= now()-interval '90 days'),
     'failed90', count(*) filter (where sent_at >= now()-interval '90 days' and status='failed'))
     from crm.send_log where campaign ilike '%toner%' or campaign ilike '%vms%' or campaign ilike '%토너%'))
$f$;

create or replace function core.f_vms_payload_get() returns jsonb
language plpgsql volatile set search_path to 'pg_catalog','public' as $f$
declare v jsonb; v_at timestamptz; t0 timestamptz := clock_timestamp();
begin
  select payload, built_at into v, v_at from core.rpc_cache where cache_key = 'vms_dash';
  if v is not null and v_at >= now() - interval '2 hours' then
    return v || jsonb_build_object('cached', true);
  end if;
  v := core.f_vms_payload_build();
  insert into core.rpc_cache (cache_key, payload, built_at, build_ms)
  values ('vms_dash', v, now(), extract(milliseconds from clock_timestamp()-t0)::int)
  on conflict (cache_key) do update set payload = excluded.payload, built_at = excluded.built_at, build_ms = excluded.build_ms;
  return v || jsonb_build_object('cached', false);
end $f$;

create or replace function core.f_vms_warm() returns int
language plpgsql volatile set search_path to 'pg_catalog','public' as $f$
declare v jsonb; t0 timestamptz := clock_timestamp();
begin
  v := core.f_vms_payload_build();
  insert into core.rpc_cache (cache_key, payload, built_at, build_ms)
  values ('vms_dash', v, now(), extract(milliseconds from clock_timestamp()-t0)::int)
  on conflict (cache_key) do update set payload = excluded.payload, built_at = excluded.built_at, build_ms = excluded.build_ms;
  return pg_column_size(v);
end $f$;

create or replace function public.fn_vms_payload() returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_vms_payload_get();
end $f$;
revoke all on function public.fn_vms_payload() from public, anon;
grant execute on function public.fn_vms_payload() to authenticated, service_role;

create or replace function public.fn_vms_payload_pub(p_pw text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
begin
  if not core.f_api_ok('dash_share', p_pw) then raise exception 'unauthorized' using errcode='42501'; end if;
  return core.f_vms_payload_get();
end $f$;
grant execute on function public.fn_vms_payload_pub(text) to anon, authenticated, service_role;

select cron.schedule('vms-warm', '7,37 * * * *', 'select core.f_vms_warm();');
