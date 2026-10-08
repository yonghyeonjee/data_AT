-- mvp_196 · 발송 링크 관리 [문의] — 캠페인 링크로 문의한 사람 (2026-10-08 · v183)
-- "그것도 발송관리에서 볼수 있음 좋겠는데" (오늘 자급제 문의 3건이 어느 채널·언제 가입·구매 이력인지)
-- 적용 기록용 — DB 에는 이미 반영돼 있다.

-- 문의 → 캠페인: 폼이 남긴 pageUrl 의 utm_campaign (구독 페이지 등). 소문자로 맞춘다
create or replace function core.f_consult_campaign(p_raw jsonb) returns text
language sql immutable as $$
  select nullif(lower(substring(coalesce(p_raw->>'pageUrl','') from '[?&]utm_campaign=([^&#]+)')), '')
$$;

-- fn_utm_campaigns: 캠페인마다 'inquiries' (삭제·테스트 숨김 제외) — 'clicks' 바로 뒤에 서버 본문 replace 로 넣었다
--   'inquiries', (select count(*) from crm.consult q where core.f_consult_campaign(q.raw_payload) = lower(c.code)
--                  and q.deleted_at is null and coalesce(q.hidden_reason,'') not like '테스트%'),

-- fn_utm_responses(p_code, p_unmask) — admin·user. 실명은 admin 만 · 실명 보기는 crm.access_log 'utm_responses:unmask'
--   고객 = 휴대폰 뒤 8자리가 같은 crm.customer 중 문의 1분 전보다 먼저 있던 것 (문의가 만든 고객 줄은 뺀다)
--   chans = 그 고객들의 source_channels (web_subscription·web·gas 같은 폼 출처는 뺀다 = 처음 들어온 경로)
--   first_seen = min(first_seen_at) — 고도몰 회원이면 가입일
--   buy_n·buy_amt·buy_last = 문의 전 순매출 > 0 인 주문 (테스트 제외) · after_n = 문의 뒤
--   sent_this = 이 캠페인 send_log(실패 제외) 가 있나 · sent_other = 다른 캠페인 수
--   summary: known · new_person · never_bought · bought_before · bought_after · sent_this · by_chan · by_year
--   (본문 전체는 pg_get_functiondef('public.fn_utm_responses(text,boolean)'::regprocedure) 로)
-- revoke all … from public, anon · grant execute … to authenticated, service_role

-- 확인(롤백 블록, 관리자 로그인): tabs12 inquiries 3 · 응답 3줄 · known 3 · never_bought 3 · S몰 2 · P몰 1 · 가입 연도 2020/2024/2025 각 1 · sent_this 0(센드온 결과 미적재)
