-- mvp_279 · 2026-11-06 · 사이니지 LED 문구 관리 · 담당자 로그인 1시간 · 연장 · 휴대폰 뒷번호 4자리 (DB 에 적용됨 · 기록용)

-- 1) LED 문구 — 담당자 화면 [디스플레이 관리] › LED 문구. [ ] = 강조
create table if not exists core.signage_setting (id int primary key default 1 check (id=1), led jsonb not null default '[]'::jsonb, updated_by text, updated_at timestamptz not null default now());
alter table core.signage_setting enable row level security;
-- core.f_signage_led() · public.fn_store_signage_led_save(p_code, p_msgs jsonb)  (1~6줄 · 줄마다 80자 · core.f_staff · VOLATILE)
-- fn_store_signage 응답에 led·led_at·led_by · fn_signage_guests 응답에 led (부분 치환)

-- 2) 담당자 세션
alter table core.staff_session add column if not exists unlock_fail int not null default 0;
-- core.app_setting 'store_session_min' (분) — fn_store_login 이 store_session_hours 대신 이 값으로 만료를 잡는다 (부분 치환)
--   지금 720(12시간). 새 담당자 화면(v283)을 배포한 뒤 60 으로 바꿀 것:
--   update core.app_setting set value='60' where key='store_session_min';
-- public.fn_store_session()  — {me, expires_at, has_mobile} (새로고침 때 남은 시간 맞춤)
-- public.fn_store_extend()   — expires_at = now() + store_session_min
-- public.fn_store_unlock(p_last4) — core.staff.mobile 뒤 4자리 · 틀리면 unlock_fail+1 (예외 없이 jsonb 로 돌려 기록이 남음) · 5번이면 세션 끊음(relogin) · 휴대폰 없으면 no_mobile
-- 셋 다 core.f_staff('') 로 세션 확인 · anon 실행 (revoke public → grant anon, authenticated, service_role)
