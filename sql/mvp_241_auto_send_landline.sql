-- mvp_241 (2026-10-27) 자동 발송 — 유선번호는 명단에 '유선번호 · 발송 안 함' 으로 보이고 대기열에는 안 넣는다
-- 전: 토너 규칙이 유선번호 8명을 날마다 대기열에 넣고 core.f_sms_send 가 '번호 형식' 으로 차단(비용 없음 · 차단 숫자만 쌓임)
-- 적용은 서버 본문 부분 치환(pg_get_functiondef → replace · 지점 개수 1 검증 → execute). 아래는 무엇을 바꿨는지 기록.

-- ① 휴대폰 앞자리 판정 — 가린 번호(010-****-5678)에도 쓸 수 있게 앞자리만 본다. 빈 번호는 null
create or replace function core.f_is_mobile(p text) returns boolean language sql immutable as
$b$ select case when coalesce(p,'') = '' then null else regexp_replace(p, '\D', '', 'g') ~ '^01[016789]' end $b$;

-- ② core.f_auto_rule_rows · public.fn_auto_rule_preview (product_cycle 가지)
--    sel 에 mob = coalesce(core.f_is_mobile(cu.phone), false)
--    total = count(*) filter (where rec_ok and ad_ok and mob)  · backlog·own_cycle 도 mob 만
--    줄마다 'landline', not s.mob · extra 'landline' = rec_ok and ad_ok and not mob 인 사람 수
--    모든 종류 공통 끝 처리: 줄에 landline 이 없으면 not core.f_is_mobile(phone)
--    fn_auto_rule_preview 만: 명단 = 휴대폰 v_lim 줄 + 유선 20줄(맨 아래 · order by (not mob), due_d, name)

-- ③ core.f_auto_plan — 대기열 insert 에
--      and regexp_replace(x->>'phone', '\D', '', 'g') ~ '^01[016789][0-9]{7,8}$'   (f_sms_send 의 '번호 형식' 규칙과 같음)
--    auto_run.note 에 'N명은 유선번호·번호 형식이라 대기열에 안 넣음'

-- 확인(10-27 09:2x KST): toner_cycle total 49 · landline 8 · 대기열 후보 49 · 미리보기 휴대폰 8줄 + 유선 8줄(맨 아래)
