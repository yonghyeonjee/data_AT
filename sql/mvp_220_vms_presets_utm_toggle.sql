-- mvp_220 (2026-10-15 · v208) — ① VMS 대시보드 기간 프리셋 금일·금주·이전 주(+화면 금월·저번달 · 기본 금월)
--                               ② 발송 링크 관리 구매 기준 토글 [구매 · 링크 경유 | 수신자 30일]
-- 적용 방식: 서버 본문을 읽어 지점 1개를 확인한 뒤 replace → execute (CLAUDE.md 규칙). 전부 적용됨.
-- ※ ②는 처음에 패치와 raise 롤백 테스트를 한 호출에 넣어 패치까지 롤백됐었다(같은 날 두 번째 시도에서 들어감). 패치와 테스트는 반드시 두 호출로.

-- ① core.f_vms_payload_build — ranges CTE 의 'ly' 줄 뒤에 세 줄 (KST 오늘 기준 · 월요일 시작)
--    td 금일   : s=오늘, e=내일 · prev=어제 · yoy=364일 전 같은 요일
--    tw 금주   : s=이번 주 월요일, e=내일 · prev=지난주 같은 구간 · yoy=364일 전 같은 구간
--    lw 이전 주: s=지난주 월요일, e=이번 주 월요일 · prev=그 전 주 · yoy=364일 전 같은 주
--    (create or replace 로 다시 만들면서 search_path 가 빠져 alter function … set search_path 로 되돌렸다 — 원본 속성: language sql stable set search_path to 'pg_catalog','public')
/*
  union all select 'td','금일',7, kd.t, kd.t+1, kd.t-1, kd.t, kd.t-364, kd.t-363 from (select (now() at time zone 'Asia/Seoul')::date t) kd
  union all select 'tw','금주',8, kd.w, kd.t+1, kd.w-7, kd.t-6, kd.w-364, kd.t-363 from (select x.t, date_trunc('week',x.t)::date w from (select (now() at time zone 'Asia/Seoul')::date t) x) kd
  union all select 'lw','이전 주',9, kd.w-7, kd.w, kd.w-14, kd.w-7, kd.w-371, kd.w-364 from (select date_trunc('week',(now() at time zone 'Asia/Seoul')::date)::date w) kd),
*/
-- 화면 전용 키 tm(금월)·lm(저번달) 은 dash/vms/index.html 이 periods.month_keys 의 마지막·그 앞 달(m:YYYY-MM) 로 푼다 — 서버 키 없음.
-- 빌드 5.1초 · 95.9KB · ranges 32개. 캐시는 core.f_vms_warm() 으로 바로 다시 구웠다(cron vms-warm 7,37분).

-- ② public.fn_utm_campaigns — 캠페인마다 'bought_rcpt30_amt' (수신자(발송 실패 제외)가 발송 뒤 30일 안에 한 주문의 순매출 합 · 테스트 제외)
/*
        'bought_rcpt30_amt', (select coalesce(sum(o.net_amount),0) from core.orders o where not coalesce(o.is_test,false) and o.net_amount > 0
                    and exists (select 1 from crm.send_log l where l.campaign=c.code and coalesce(l.status,'')<>'failed' and l.buyer_key=o.buyer_key and o.order_at >= l.sent_at and o.order_at < l.sent_at + interval '30 days')),
*/
-- ② public.fn_order_list · fn_order_summary — p_campaign 이 '코드|rcpt' 면 수신자 30일 규칙, 아니면 링크 경유 규칙(mvp_218)
/*
      and (p_campaign is null or p_campaign = '' or (not coalesce(o.is_test,false) and case when p_campaign like '%|rcpt'
           then exists (select 1 from crm.send_log l where l.campaign = split_part(p_campaign,'|',1) and coalesce(l.status,'')<>'failed'
                        and l.buyer_key = o.buyer_key and o.order_at >= l.sent_at and o.order_at < l.sent_at + interval '30 days')
           else exists (select 1 from crm.link_hit h join crm.link k on k.slug = h.slug
           where k.campaign = p_campaign and h.buyer_key = o.buyer_key and o.order_at >= h.at and o.order_at < h.at + interval '30 days') end))
*/
-- pg_get_functiondef 통째 replace 라 ACL 그대로(fn_order_* 는 anon 포함, fn_utm_campaigns 는 authenticated·service_role).
-- 확인(관리자 claims): 2608_toner rcpt30 53명 · 1,191.6만 / fn_order_list('2608_toner|rcpt', 8/1~10/15) 133줄 · 순매출 1,144만 / '2608_toner'(링크 경유) 0줄.
--   2609_toner 47명 1,141.5만 · 2609_chuseok 8명 254만 · tabs12 7명 1,379.2만 · 2609_haf 0.
