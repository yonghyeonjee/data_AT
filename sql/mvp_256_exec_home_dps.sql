-- mvp_256 · 2026-10-30 · 경영 지표 · 홈을 DPS 기준으로 (원장은 함께 보거나 고른다)
-- 적용 기록용 — DB 에는 이미 반영돼 있다.
--
-- 요청: "경영지표도 DPS default로 하고 원장도 선택할 수 있게" · "홈도 dps, 원장 둘다 보이게 · 오늘이 아니라 어제 순매출 ·
--        DPS 기준 큰 글자 원장은 작은 글자로 아래에"
--
-- DPS 셈법은 대시보드 [DPS] 기준(f_dash_payload 'dps')과 같다:
--   dps.perf_line(실적일 · 사원 · 판매번호 · 금액) 을 (실적일, 판매번호) 로 묶어 합이 + 면 매출, − 면 환불(해약).
--   채널은 dps.sale.channel (없으면 'DPS 채널 미확인'). DPS 공용 고객 'DP'(crm.customer.is_placeholder) 는 고객 수에서 뺀다.
--   신규 고객 = 그 고객의 첫 + 실적일이 기간 안. 오픈마켓 주문은 안심번호라 고객을 세지 않는다(원장과 같은 규칙).
--
-- 대조 (2026-10-01 ~ 10-29 · 10-30 09:06 수집분):
--   대시보드 [DPS] 캐시 vs perf_line 직접 합 — 합계 815,279,770 · 채널 11개 · 매장 사원 6명 전부 원 단위까지 같다.
--   매장 사원 6명 합 2.85억 (이수혁 8,031만 · 김규완 6,590만 · 최태웅 5,446만 · 차효범 3,364만 · 권혁찬 3,150만 · 송희봉 1,935만).
--   DPS 화면과 다를 수 있는 건 수집 시점 뒤 실적뿐이다(수집은 아침 한 번, 전날까지).

-- ① 묶음 이름 (경영 지표 '채널 묶음별')
CREATE OR REPLACE FUNCTION core.f_dps_group(p_ch text)
 RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog', 'public'
AS $function$
  select case
    when p_ch in ('P몰','S몰','AT몰','시흥') then '자사몰'
    when p_ch in ('매장(시흥)','매장구독(시흥)') then '매장'
    when core.f_is_openmarket(p_ch) then '오픈마켓'
    when p_ch in ('DPS 소모품(대량)','B2B') then '대량·B2B'
    else '대표님·미확인' end
$function$;

-- ② core.f_exec_sales_dps(p_f, p_t) — core.f_exec_sales 와 같은 키(net·gross·refund·orders·avg_order·buyers·new_buyers·
--    repeat_buyers·repeat_rate·repeat_net_share·ident_net·groups) + basis 'dps' + channels[{ch,net,orders}]. 한 달 0.35초.
--    (본문은 서버 pg_get_functiondef 참고 — 위 셈법 그대로 CTE 로 짰다)

-- ③ core.f_exec_series_dps(p_f, p_t, p_daily) — f_exec_series 와 같은 모양 [{p, net, orders, buyers, new_buyers}]
CREATE OR REPLACE FUNCTION core.f_exec_series_dps(p_f date, p_t date, p_daily boolean)
 RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'pg_catalog', 'public'
AS $function$
with dl as (
  select l.perf_date d, l.sale_no, coalesce(max(s.channel),'DPS 채널 미확인') ch, max(s.buyer_key::text) bk, sum(l.amount) net
    from dps.perf_line l left join dps.sale s on s.sale_no = l.sale_no
   where l.perf_date between p_f and p_t group by 1, 2),
o as (select to_char(d, case when p_daily then 'YYYY-MM-DD' else 'YYYY-MM' end) p, sale_no, core.f_dps_group(ch) ct,
             case when bk in (select buyer_key::text from crm.customer where is_placeholder) then null else bk end bk, net from dl),
per as (select p, sum(net) net, count(distinct sale_no) filter (where net > 0) orders from o group by p),
fb as (select s.buyer_key::text bk, min(x.d) first_d
         from (select l.sale_no, l.perf_date d from dps.perf_line l where l.perf_date <= p_t group by 1, 2 having sum(l.amount) > 0) x
         join dps.sale s on s.sale_no = x.sale_no
        where s.buyer_key::text in (select bk from o where bk is not null) group by 1),
bb as (select p, bk, bool_or(ct = '오픈마켓') om, sum(net) net from o where bk is not null group by p, bk),
bbn as (select b.p, b.bk, coalesce(to_char(f.first_d, case when p_daily then 'YYYY-MM-DD' else 'YYYY-MM' end) = b.p, true) is_new
          from bb b left join fb f on f.bk = b.bk where not b.om and b.net > 0),
cu as (select p, count(*) buyers, count(*) filter (where is_new) new_buyers from bbn group by p)
select coalesce(jsonb_agg(jsonb_build_object('p', per.p, 'net', per.net, 'orders', per.orders, 'buyers', coalesce(cu.buyers,0), 'new_buyers', coalesce(cu.new_buyers,0)) order by per.p), '[]'::jsonb)
  from per left join cu on cu.p = per.p
$function$;
revoke all on function core.f_dps_group(text), core.f_exec_sales_dps(date,date), core.f_exec_series_dps(date,date,boolean) from public, anon, authenticated;

-- ④ public.fn_exec_kpi(p_from, p_to, p_cfrom, p_cto, p_basis) — 새 5인자 판 (p_basis 기본값 없음 → 옛 4인자 호출은 그대로 옛 판으로 간다)
--    'ledger' = 옛 4인자 판 결과 + basis 'ledger' · 그 밖(기본 'dps') = sales/sales_prev/sales_yoy/series 를 DPS 로,
--    나머지(문의·유입·링크·고객 자산)는 같고, orders_last = 마지막 실적일 · dps_fetched(수집 시각) · dps_first. 캐시 키 exec_dps:… 10분.
--    한 달 첫 빌드 0.8초.
revoke all on function public.fn_exec_kpi(date,date,date,date,text) from public, anon;
grant execute on function public.fn_exec_kpi(date,date,date,date,text) to authenticated, service_role;

-- ⑤ core.f_home_build() 부분 치환 (서버 원본에서 replace · 지점 1개씩 검증)
--    · current_date → (now() at time zone 'Asia/Seoul')::date — 자정~09시에 '오늘·이번 달' 이 하루 밀리던 것
--    · sales 에 yday_net · yday_orders (원장 · KST 어제)
--    · 새 키 sales_dps = {yday, yday_net, yday_orders, month_net, month_orders, pm_same_net(전월 1일 ~ 어제와 같은 날),
--                         last(마지막 실적일), fetched(수집 시각), top_channels(이번 달 채널 상위 6)}
--    화면: 홈 1·2번 타일 = 어제 · 이번 달 순매출 DPS 큰 글자 + 원장 작은 글자 · '이번 달 채널 상위' [DPS|원장] (기본 DPS)
--          할 일에서 '온라인 채널 미입력' · '매장 일마감 미입력' 뺌 (둘 다 이제 안 쓴다 — 아래 ⑥)

-- ⑥ 수집 미도착 알림 끔 (2026-10-30) — 매장 일마감 · 온라인 채널 일매출 은 이제 안 쓴다
update core.data_source set alert = false where key in ('channel_daily','store_manual');
