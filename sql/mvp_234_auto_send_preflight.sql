-- mvp_234 · 2026-10-21 · 자동 발송 첫 실제 발송(10-22 10:00) 전 점검 — 시간 예산 · 080 수신거부 자동 받아오기 · 하루치 한 묶음 · 실행 기록 조회
-- 본문은 서버에서 pg_get_functiondef 를 읽어 지점 개수(1개)를 확인한 뒤 replace → execute 했다. 아래는 바뀐 조각.

-- ① core.f_auto_send_tick — 30초 시간 예산. 한 문장이 시간 제한에 끊겨 롤백되면 이미 나간 문자가 다시 pending 이 되어
--    다음 분에 또 나가므로(9/17 이카운트 사고와 같은 구조) 30초가 지나면 새 줄은 다음 분으로 넘긴다.
--      v_t0 timestamptz := clock_timestamp();
--      if clock_timestamp() - v_t0 > interval '30 seconds' then exit; end if;
--    (cron postgres 역할은 statement_timeout 이 따로 없다 · 한 통 0.2초 · HTTP 상한 4초)

-- ② 하루치 = 한 발송 요청 — crm.auto_run.batch_id 를 tick 이 f_sms_send p_opt.batch_id 로 넘긴다 (테스트 줄은 따로)
alter table crm.auto_run add column if not exists batch_id uuid not null default gen_random_uuid();
--    core.f_sms_send : v_batch uuid := coalesce(nullif(p_opt->>'batch_id','')::uuid, gen_random_uuid());
--    → 발송 결과 [발송 요청별] 에 그날 357통이 한 줄 · 발송결과 보기에서 클릭률까지

-- ③ core.f_auto_plan — 그날 첫 계획 직전에 센드온 080 수신거부를 받아온다(fn_sms_blocklist_pull · 잠깐 service_role 클레임 · 끝나면 되돌림).
--    실패해도 발송은 진행(f_sms_send 가 보낼 때 crm.sms_optout 을 다시 본다) · 결과는 crm.auto_run.note '수신거부 받아오기: …'

-- ④ public.fn_auto_runs(p_days 14) — admin·staff · 엔진 상태(cron · 마지막 실행 · 24시간 오류) · 다음 발송 규칙 · 규칙·날짜마다
--    대상 · 대기 · 보냄 · 차단 · 실패 · 오류 · 처음/마지막 발송 · 사유 · batch_id · 테스트 발송. 화면 = 자동 발송 대상 › 자동 발송 설정 › [실행 기록].
revoke all on function public.fn_auto_runs(int) from public, anon;
grant execute on function public.fn_auto_runs(int) to authenticated, service_role;

-- 리허설(롤백 · 시각만 2026-10-22 10:00:30 · tick 은 p_opt.test=true 로 강제 테스트): 계획 357 · 두 번째 계획 0 ·
--   수신거부 받아오기 8건(새 0) · tick 19번 · 357줄 한 묶음 · test 347 + blocked 10(전부 유선 번호 '번호 형식') · 1.7초.
-- 그 밖 점검: cron auto-send 켜짐(6시간 136회 실패 0) · 토너 규칙 화~금 10:00 · 10-22 기록·대기열 없음 · 센드온 잔액 135,280 ·
--   발신번호 0221093500 ACTIVE · 하루 상한 2000 · 본문 564~600B LMS · 남은 자리 글자 0 · 수신거부 겹침 0. 예상 347 × 26.95 ≈ 9,350원.
