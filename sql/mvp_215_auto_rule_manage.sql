-- mvp_215 · 2026-10-15 · 자동 발송 설정을 관리 화면으로 — 규칙 표 · 스위치 · 거르개 · [+ 규칙 추가] · 보관 (DB 는 이미 적용됨 · 기록용)
-- "자동 발송 on/off 하고 뭔가 관리하기 쉽게 · 향후에 조건을 추가하거나 시나리오를 추가할 수 있으면" (고도몰 CRM 자동 알림 발송 화면 캡처)

-- 1. 규칙 표에 분류·보관·만든 때
alter table crm.auto_rule add column if not exists category text, add column if not exists archived_at timestamptz, add column if not exists created_at timestamptz not null default now();
update crm.auto_rule set category = case kind when 'sub_expire' then '구독' when 'quote_follow' then '견적' when 'product_cycle' then '소모품' else '케어' end where category is null;

-- 2. fn_auto_rules() 응답에 category · archived · archived_at (정렬 sort, created_at, code). 보관된 규칙도 archived=true 로 함께 준다 — 화면 [보관함] 에서 복구.

-- 3. fn_auto_rule_save(p_code, p_data) — 관리자만. 코드는 ^[a-z0-9_]{2,40}$
--   · 없는 코드 → 새 규칙: kind(sub_expire·quote_follow·product_cycle·product_age)·label·body 필수, 템플릿 crm.sms_template 'auto_<code>'(scope admin) 생성, category 기본은 종류별, enabled 기본 false, sort = max+10
--   · {archive:true} → archived_at=now() + enabled=false / {restore:true} → archived_at=null (꺼진 채)
--   · 그 밖엔 enabled·label·category·send_time·weekday·note·params(얕은 병합)·sort·body/is_ad(템플릿) 갱신
--   · 감사로그 crm.access_log 'auto_rule:create|archive|restore|save'
--   본문은 sql 편집기나 pg_get_functiondef('public.fn_auto_rule_save'::regproc) 로 — mvp_214 판과 같은 골격에 위 가지가 더해진 것.
--   NULL 함정 하나: `if v_kind not in (...)` 는 kind 가 없으면 NULL → 거짓이라 not-null 제약 오류가 났다 → coalesce(v_kind,'') 로.

-- 4. 롤백 실험 (관리자 JWT): 새 규칙 만들기 → 소모품·tue·tpl auto_zz_test_rule · 미리보기 61명 → 이름·분류·주기 90·문구 바꿈 → 보관(archived=true·enabled=false) → 복구 → 'Bad Code!' 거절 · kind 없음 거절 · access_log 4줄 → raise 로 롤백
-- 5. 화면(admin.html · admin/test) #arCard — 거르개 바(상태 전체/켜짐/꺼짐 · 분류 · 보관함 · 대상 합계) + 규칙 줄(스위치=바로 저장 · 분류 · 이름+조건 · 요일 시각 · 지금 대상 · LMS/SMS 바이트 · [열기]) + 펼침 편집(이름·분류·요일·시각·종류 · 조건 칸(AR_KINDS 정의) · 자리 글자 칩 · 문구 · 광고 · 명단 보기 · 테스트 받기 · 저장 · 보관/복구) + [+ 규칙 추가] 창(종류 → 조건 칸·기본 문구 바뀜 · 코드 자동 · 꺼짐으로 시작)
--    새 종류(kind)를 더하려면: 화면 AR_KINDS 한 줄 + fn_auto_rule_preview 가지 하나 + fn_auto_rule_save 의 kind 목록. 테스트 ptest/autorule.mjs 37/37.
