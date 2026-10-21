-- mvp_231 · 2026-10-21 · 자동 발송 엔진 시작 — 토너 교체 안내 화~금 10:00 · 문구·080 인증번호 안내 정리
-- 사용자 결정: "토,일,월을 제외한 화~금 오전 10시 발송으로 익일부터" · 16:30 실제 고객 정보로 테스트 번호에 한 통.

-- ① 문구 · 꼬리말
update crm.sms_template set body = replace(body, '소모품(토너·잉크) {모델} 교체 시기가 되었습니다.', '사용하시는 프린터/복합기 소모품 교체 시기가 되었습니다.')
 where code = 'auto_toner';
update core.sms_config set ad_footer = E'무료거부 0808811293\n인증번호(수신거부시 입력해주시면 됩니다.) : 5016' where id = 1;

-- ② core.f_sms_send — kind 'auto' + p_opt.auto_live 이고 cron(session_user postgres)에서 부를 때만 설정 모드와 무관하게 실제 발송
--    (pg_get_functiondef 의 v_live 한 줄을 지점 1개 확인 뒤 치환)
--    v_live := (c.mode = 'live' or (v_kind = 'test' and jsonb_array_length(p_rows) <= 3)
--               or (v_kind = 'auto' and coalesce((p_opt->>'auto_live')::boolean, false) and session_user not in ('authenticator','anon','authenticated'))) and not v_force_test;

-- ③ core.f_auto_rule_rows(p_code, p_limit 5000) — fn_auto_rule_preview 본문(prosrc)에서 권한 줄 제거 · 상한 50 → 5000 ·
--    product_cycle 줄의 phone 을 실번호로 + 'key'(고객키). public 권한 없음.

-- ④ 대기열 · 실행 기록
create table if not exists crm.auto_send_queue (
  id bigserial primary key, rule_code text not null, run_date date not null, campaign text not null,
  buyer_key text, phone text not null, name text, vars jsonb not null default '{}'::jsonb,
  not_before timestamptz not null default now(), is_test boolean not null default false,
  status text not null default 'pending' check (status in ('pending','sent','failed','blocked','error','skipped')),
  result jsonb, error text, created_at timestamptz not null default now(), sent_at timestamptz);
create unique index if not exists ux_auto_send_q on crm.auto_send_queue (rule_code, run_date, phone) where not is_test;
create index if not exists ix_auto_send_q_pending on crm.auto_send_queue (not_before) where status = 'pending';
create table if not exists crm.auto_run (rule_code text not null, run_date date not null, planned_at timestamptz not null default now(),
  n int not null default 0, note text, primary key (rule_code, run_date));
-- 시작한 날(10-21)은 고객 발송을 막아 둔다
insert into crm.auto_run (rule_code, run_date, n, note)
select code, (now() at time zone 'Asia/Seoul')::date, 0, '시작 전날 — 고객 발송은 다음 발송일부터 (16:30 테스트 한 통만)' from crm.auto_rule on conflict do nothing;

-- ⑤ core.f_auto_plan()      켜진 규칙 · 요일(daily | weekdays | 'tue,wed,thu,fri') · send_time ≤ 지금 < 18:00 · 그날 한 번 → 대기열(같은 번호 하나) + {링크}=고정 단축 링크
--    core.f_auto_send_tick(20) 09~20시 · pending 20통 · 한 사람씩 f_sms_send(kind auto · auto_live) · 줄마다 예외를 잡아 error 로 남기고 다시 안 보냄
--    core.f_auto_engine()      plan + tick  (본문은 DB 에 저장된 판이 원본)
select cron.schedule('auto-send', '* * * * *', $$select core.f_auto_engine()$$);

-- ⑥ 규칙 켜기
update crm.auto_rule set enabled = true, weekday = 'tue,wed,thu,fri', send_time = '10:00' where code = 'toner_cycle';

-- ⑦ 16:30 테스트 한 통 — 1순위 실제 고객의 이름·제품·고객키(추적 링크) + 받는 번호만 테스트 번호 · 캠페인 auto_toner_cycle_test (그 고객 내일 발송에서 안 빠지게)
--    (crm.auto_send_queue is_test=true · not_before 2026-10-21 16:30+09)

-- 확인(롤백 실험): 명단 357명(358 중 같은 번호 1 합침) · 링크 357 · 두 번째 plan 0
-- 멈추기: 관리자 › 자동 발송 설정 스위치 끄기 (대기 줄은 '규칙이 꺼짐' 으로 skipped) · 엔진 자체는 select cron.unschedule('auto-send');
