-- mvp_221 · 경영 지표 화면 (2026-10-16)
-- 관리자 메뉴 [경영 지표] — 기간을 고르면 매출·주문·구매 고객·신규/재구매·재구매율·객단가(전기·전년 대비),
-- 문의 → 견적 → 구매 흐름(fn_inquiry_flow 와 같이 씀), GA 유입(core.web_traffic), 링크 클릭·발송, 고객 자산을 한 화면에.
-- 조각 함수 4개(core.f_exec_*) + 입구 public.fn_exec_kpi (10분 캐시 core.rpc_cache 'exec:…').

-- ① 매출·고객 (한 기간)
create or replace function core.f_exec_sales(p_f date, p_t date) returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $$
with o as (
  select source, order_no, buyer_key, channel_type ct, net_amount net, gross_amount gross, refund_amount refund
    from core.orders_live
   where order_at >= (p_f::timestamp at time zone 'Asia/Seoul') and order_at < ((p_t+1)::timestamp at time zone 'Asia/Seoul')),
tot as (select coalesce(sum(net),0) net, coalesce(sum(gross),0) gross, coalesce(sum(refund),0) refund,
               count(distinct (source, order_no)) filter (where net > 0) orders from o),
bb as (
  /* 식별 고객 = 고객키가 있고 오픈마켓이 아닌 주문 · 신규 = 고객 롤의 첫 구매일이 이 기간 안 (롤에 없으면 신규) */
  select o.buyer_key bk, sum(o.net) net, bool_or(coalesce(o.ct,'') = '오픈마켓') om,
         coalesce((r.first_at at time zone 'Asia/Seoul')::date >= p_f, true) is_new
    from o left join crm.customer_roll r on r.buyer_key = o.buyer_key
   where o.buyer_key is not null group by o.buyer_key, r.first_at),
ident as (select * from bb where not om and net > 0),
cust as (select count(*) buyers, count(*) filter (where is_new) new_buyers, count(*) filter (where not is_new) repeat_buyers,
                coalesce(sum(net),0) ident_net, coalesce(sum(net) filter (where not is_new),0) repeat_net from ident),
grp as (select coalesce(ct,'기타') ct, sum(net) net, count(distinct (source, order_no)) filter (where net > 0) orders,
               count(distinct buyer_key) filter (where buyer_key is not null and coalesce(ct,'') <> '오픈마켓') buyers
          from o group by 1)
select jsonb_build_object('from', p_f, 'to', p_t, 'net', tot.net, 'gross', tot.gross, 'refund', tot.refund, 'orders', tot.orders,
  'avg_order', case when tot.orders > 0 then round(tot.net / tot.orders) end,
  'buyers', cust.buyers, 'new_buyers', cust.new_buyers, 'repeat_buyers', cust.repeat_buyers,
  'repeat_rate', case when cust.buyers > 0 then round(100.0 * cust.repeat_buyers / cust.buyers, 1) end,
  'repeat_net_share', case when cust.ident_net > 0 then round(100.0 * cust.repeat_net / cust.ident_net, 1) end,
  'ident_net', cust.ident_net,
  'groups', (select coalesce(jsonb_agg(jsonb_build_object('ct', ct, 'net', net, 'orders', orders, 'buyers', buyers) order by net desc), '[]'::jsonb) from grp))
from tot, cust
$$;

-- ② 추이 (일 또는 월 단위)
create or replace function core.f_exec_series(p_f date, p_t date, p_daily boolean) returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $$
with o as (
  select to_char(order_at at time zone 'Asia/Seoul', case when p_daily then 'YYYY-MM-DD' else 'YYYY-MM' end) p,
         source, order_no, buyer_key, channel_type ct, net_amount net
    from core.orders_live
   where order_at >= (p_f::timestamp at time zone 'Asia/Seoul') and order_at < ((p_t+1)::timestamp at time zone 'Asia/Seoul')),
per as (select p, sum(net) net, count(distinct (source, order_no)) filter (where net > 0) orders from o group by p),
bb as (select p, buyer_key bk, bool_or(coalesce(ct,'') = '오픈마켓') om, sum(net) net from o where buyer_key is not null group by p, buyer_key),
bbn as (select b.p, b.bk,
               coalesce(to_char(r.first_at at time zone 'Asia/Seoul', case when p_daily then 'YYYY-MM-DD' else 'YYYY-MM' end) = b.p, true) is_new
          from bb b left join crm.customer_roll r on r.buyer_key = b.bk where not b.om and b.net > 0),
cu as (select p, count(*) buyers, count(*) filter (where is_new) new_buyers from bbn group by p)
select coalesce(jsonb_agg(jsonb_build_object('p', per.p, 'net', per.net, 'orders', per.orders, 'buyers', coalesce(cu.buyers,0), 'new_buyers', coalesce(cu.new_buyers,0)) order by per.p), '[]'::jsonb)
  from per left join cu on cu.p = per.p
$$;

-- ③ 문의·견적 (한 기간)
create or replace function core.f_exec_inquiry(p_f date, p_t date) returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $$
with c as (select * from crm.consult_live
            where consult_at >= (p_f::timestamp at time zone 'Asia/Seoul') and consult_at < ((p_t+1)::timestamp at time zone 'Asia/Seoul')),
q as (select distinct on (quote_no) quote_no, customer_name, counselor from crm.quote
       where issued_at >= (p_f::timestamp at time zone 'Asia/Seoul') and issued_at < ((p_t+1)::timestamp at time zone 'Asia/Seoul')
       order by quote_no, version desc)
select jsonb_build_object(
  'consults', (select count(*) from c),
  'people', (select count(distinct coalesce(buyer_key::text, nullif(right(regexp_replace(coalesce(phone,''),'\D','','g'),8),''), 'c'||id::text)) from c),
  'bought_marked', (select count(*) from c where result = '구매완료' or linked_order_id is not null),
  'open', (select count(*) from c where result in ('진행전','진행중','보류')),
  'from_links', (select count(*) from c where core.f_consult_campaign(raw_payload) is not null),
  'quotes', (select count(*) from q where not core.f_quote_is_test(quote_no, customer_name, counselor)),
  'quotes_sent', (select count(distinct s.quote_no) from crm.quote_share s join q on q.quote_no = s.quote_no
                   where not coalesce(s.revoked,false) and not core.f_quote_is_test(q.quote_no, q.customer_name, q.counselor)))
$$;

-- ④ GA 유입 (core.web_traffic · page = all / subscribe_inquiry / quote / src:<출처> / camp:<utm_campaign>)
create or replace function core.f_exec_traffic(p_f date, p_t date, p_cf date, p_ct date, p_daily boolean) returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $$
with cur as (select coalesce(sum(sessions),0) s, coalesce(sum(users),0) u, coalesce(sum(views),0) v, count(*) days from core.web_traffic where page = 'all' and day between p_f and p_t),
prv as (select coalesce(sum(sessions),0) s, coalesce(sum(users),0) u from core.web_traffic where page = 'all' and day between p_cf and p_ct),
ser as (select to_char(day, case when p_daily then 'YYYY-MM-DD' else 'YYYY-MM' end) p, sum(sessions) s, sum(users) u
          from core.web_traffic where page = 'all' and day between p_f and p_t group by 1),
src as (select substr(page, 5) src, sum(sessions) s from core.web_traffic where page like 'src:%' and day between p_f and p_t group by 1 order by 2 desc limit 10),
cmp as (select substr(page, 6) camp, sum(sessions) s from core.web_traffic where page like 'camp:%' and day between p_f and p_t group by 1 order by 2 desc limit 10),
pg as (select page, sum(sessions) s from core.web_traffic where page in ('subscribe_inquiry','quote') and day between p_f and p_t group by 1)
select jsonb_build_object('has', exists (select 1 from core.web_traffic), 'last_day', (select max(day) from core.web_traffic),
  'sessions', cur.s, 'users', cur.u, 'views', cur.v, 'days', cur.days, 'prev_sessions', prv.s, 'prev_users', prv.u,
  'series', (select coalesce(jsonb_agg(jsonb_build_object('p', p, 's', s, 'u', u) order by p), '[]'::jsonb) from ser),
  'sources', (select coalesce(jsonb_agg(jsonb_build_object('src', src, 's', s) order by s desc), '[]'::jsonb) from src),
  'campaigns', (select coalesce(jsonb_agg(jsonb_build_object('camp', camp, 's', s) order by s desc), '[]'::jsonb) from cmp),
  'pages', (select coalesce(jsonb_object_agg(page, s), '{}'::jsonb) from pg))
from cur, prv
$$;

-- ⑤ 링크 클릭 · 발송
create or replace function core.f_exec_links(p_f date, p_t date, p_cf date, p_ct date) returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $$
select jsonb_build_object(
  'clicks', (select count(*) from crm.link_hit where at >= (p_f::timestamp at time zone 'Asia/Seoul') and at < ((p_t+1)::timestamp at time zone 'Asia/Seoul')),
  'clicks_prev', (select count(*) from crm.link_hit where at >= (p_cf::timestamp at time zone 'Asia/Seoul') and at < ((p_ct+1)::timestamp at time zone 'Asia/Seoul')),
  'sends', (select count(*) from crm.send_log where coalesce(status,'') <> 'failed' and sent_at >= (p_f::timestamp at time zone 'Asia/Seoul') and sent_at < ((p_t+1)::timestamp at time zone 'Asia/Seoul')),
  'sends_prev', (select count(*) from crm.send_log where coalesce(status,'') <> 'failed' and sent_at >= (p_cf::timestamp at time zone 'Asia/Seoul') and sent_at < ((p_ct+1)::timestamp at time zone 'Asia/Seoul')),
  'sms_live', (select count(*) from crm.sms_message where mode = 'live' and status = 'sent' and created_at >= (p_f::timestamp at time zone 'Asia/Seoul') and created_at < ((p_t+1)::timestamp at time zone 'Asia/Seoul')))
$$;

-- ⑥ 입구 — 10분 캐시 (core.rpc_cache)
create or replace function public.fn_exec_kpi(p_from date, p_to date, p_cfrom date default null, p_cto date default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_key text; v jsonb; v_t timestamptz := clock_timestamp(); v_span int; v_cf date; v_ct date; v_yf date; v_yt date; v_daily boolean;
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception '기간이 잘못됐습니다' using errcode='22023'; end if;
  if p_to - p_from > 800 then raise exception '기간은 800일까지 볼 수 있습니다' using errcode='22023'; end if;
  v_span := p_to - p_from + 1;
  v_cf := coalesce(p_cfrom, p_from - v_span); v_ct := coalesce(p_cto, p_from - 1);
  v_yf := (p_from - interval '1 year')::date; v_yt := (p_to - interval '1 year')::date;
  v_daily := v_span <= 62;
  v_key := format('exec:%s:%s:%s:%s', p_from, p_to, v_cf, v_ct);
  select payload into v from core.rpc_cache where cache_key = v_key and built_at > now() - interval '10 minutes';
  if v is not null then return v || jsonb_build_object('cached', true); end if;
  v := jsonb_build_object(
    'from', p_from, 'to', p_to, 'prev', jsonb_build_object('from', v_cf, 'to', v_ct), 'yoy', jsonb_build_object('from', v_yf, 'to', v_yt),
    'grain', case when v_daily then 'day' else 'month' end, 'today', (now() at time zone 'Asia/Seoul')::date,
    'sales', core.f_exec_sales(p_from, p_to), 'sales_prev', core.f_exec_sales(v_cf, v_ct), 'sales_yoy', core.f_exec_sales(v_yf, v_yt),
    'series', core.f_exec_series(p_from, p_to, v_daily),
    'inquiry', core.f_exec_inquiry(p_from, p_to), 'inquiry_prev', core.f_exec_inquiry(v_cf, v_ct),
    'traffic', core.f_exec_traffic(p_from, p_to, v_cf, v_ct, v_daily),
    'links', core.f_exec_links(p_from, p_to, v_cf, v_ct),
    'customers', (select val - 'by_source' - 'new_by_month' - 'by_freq' from crm.customer_stats_cache where id = 1),
    'orders_last', (select max(order_at at time zone 'Asia/Seoul')::date from core.orders_live));
  v := v || jsonb_build_object('built_at', to_char(now() at time zone 'Asia/Seoul', 'MM-DD HH24:MI'), 'build_ms', extract(milliseconds from clock_timestamp() - v_t)::int);
  insert into core.rpc_cache (cache_key, payload, built_at, build_ms) values (v_key, v, now(), (v->>'build_ms')::int)
    on conflict (cache_key) do update set payload = excluded.payload, built_at = excluded.built_at, build_ms = excluded.build_ms;
  return v;
end $$;
revoke all on function public.fn_exec_kpi(date, date, date, date) from public, anon;
grant execute on function public.fn_exec_kpi(date, date, date, date) to authenticated, service_role;

-- ⑦ 메뉴 — 맨 위 묶음, 홈 다음
insert into core.menu_item (code, group_code, label, sort, state, note, envs)
values ('exec', '_top', '경영 지표', 5, 'on', '문의 → 견적 → 구매 · 재구매율 · GA 유입 · 캠페인', array['test','prod'])
on conflict (code) do update set label = excluded.label, group_code = excluded.group_code, sort = excluded.sort, note = excluded.note, updated_at = now();
