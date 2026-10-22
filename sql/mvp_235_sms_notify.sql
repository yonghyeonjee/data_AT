-- mvp_235 · 2026-10-22 · 문자 발송 잔디 알림 — 발송 완료 · 24시간 결과 · 충전 필요
-- "문자 발송 완료도 알림으로 보내줘" + "발송결과도" + "충전필요 알림도 주고"
-- 잔디 방 주소는 core.notify_channel 'jandi_sms' endpoint 에만 (저장소·문서에 적지 않는다).

create table if not exists crm.sms_batch_notice (
  batch_id uuid primary key, kind text, done_at timestamptz, done_info jsonb, result_at timestamptz, result_info jsonb,
  created_at timestamptz not null default now());
alter table crm.sms_batch_notice enable row level security;
alter table core.sms_config add column if not exists low_balance numeric not null default 30000;   -- 충전 필요 기준(원)
alter table core.sms_config add column if not exists low_alert_at timestamptz;

-- core.notify_channel 'jandi_sms' (잔디 · 문자 발송) + core.notify_rule:
--   sms_done   'sms.done'   📨 {kind} 발송 완료 · {label} · 성공 N  — 발송 결과(대상·성공·차단·실패·사유) · 시각 · 비용·남은 포인트 · 문구(이름 ○○○ · 사람별 토큰 뗌) · 발송 결과 보기
--   sms_result 'sms.result' 📈 발송 24시간 결과 — 링크 클릭(누른 사람/사람별 링크 문자 · 총 클릭 · 첫 클릭까지) · 누른 사람의 클릭 뒤 30일 안 주문 · 캠페인 링크로 온 문의
--   sms_low    'sms.low'    ⚠️ 문자 포인트 충전 필요 — 잔액 · LMS/SMS 남은 통수 · 최근 7일 사용·하루 평균·남은 날 · 다음 자동 발송

-- core.f_sms_notify_tick() (public 권한 없음) — core.f_auto_engine() 이 매분 plan · tick 다음에 부른다(예외는 잡아 엔진은 안 멈춤)
--   ① 완료: mode live · kind 가 test 아님 · 마지막 문자 3분 지남 · 자동 발송이면 그날 대기열 pending 0 · 자동 발송 테스트 줄 묶음 제외 → 한 장 · 다시 안 보냄
--   ② 결과: 완료 24시간 뒤 한 장 (숫자는 fn_sms_batch 를 service_role 클레임으로 그대로 — 발송결과 보기와 같은 값)
--   ③ 잔액: 완료 카드 직전, 또는 9~18시에 마지막 확인이 12시간 넘었으면 fn_sms_check · 기준 아래면 하루 한 번(low_alert_at)
--   HTTP 5초 제한 · 20~25초 시간 예산 · 끝나면 클레임 되돌림
-- 오늘(10-22) 전 발송 묶음은 skip 으로 미리 적어 옛 발송 카드가 한꺼번에 오지 않게 했다.

-- core.f_auto_engine: begin nt := core.f_sms_notify_tick(); exception when others then … end; → 반환에 'notify'
-- 화면(admin.html): 한 번의 [발송하기] · 발송 대상 [문자 보내기] = batch_id 하나(smsBatchId) → 조각이 한 묶음 = 발송 결과 한 줄 · 카드 한 장. 예약은 건마다 따로.

-- 확인: 롤백 실험(채널 주소를 트랜잭션 안에서 비움) — 10-22 토너 묶음 완료 카드 · 24시간 결과 카드(클릭 8명 2.3% · 구매 0) 0.13초 ·
--   기준 200,000 으로 올린 충전 필요 카드. 실제 첫 카드: 10-22 12:05 토너 발송 완료(HTTP 200).
