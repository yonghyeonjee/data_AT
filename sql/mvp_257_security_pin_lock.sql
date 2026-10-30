-- mvp_257 · 2026-10-30 · 보안 점검 뒤 바로 고친 것 (적용 기록용 — DB 에는 이미 반영돼 있다)
--
-- ① 담당자 4자리 코드 무작위 대입
--    잠금(5회 · 15분)이 x-dc-device 헤더 기준이었다 — 이 값은 보내는 쪽이 바꿀 수 있어 요청마다 바꾸면 잠기지 않았다.
--    활성 코드 13개 / 10,000 → 평균 770번이면 하나가 맞고, 맞으면 그 직원의 내 고객(실번호)·고객 찾기가 열린다.
--    게다가 fn_quote_share · fn_quote_share_revoke · fn_store_handler_load 는 core.f_staff 를 안 거치고 코드를 직접 확인해
--    잠금 자체가 없었다(오답과 정답의 오류 문구가 달라 맞혀 보는 데 쓸 수 있었다).
--
--    고친 것 (core.f_staff · 서버 원본을 부분 치환):
--      · 기기별 5회 / 15분 — 그대로
--      · 같은 IP 15회 / 15분 — 새로
--      · 전체 보안 잠금 — 매장 전체 실패가 1시간에 15회 이상이면 로그인한 적 있는 기기(core.pin_device · 180일)만 통과.
--        막힌 시도도 실패로 남겨 공격이 계속되는 동안 잠금이 이어진다. 걸리는 순간 잔디 'store.pin_lock' 카드(전체 보안 잠금).
--      · 성공하면 core.pin_device 에 기기 기록(하루 한 번 갱신 · 읽기 전용 트랜잭션이면 조용히 건너뜀)
--      · 세 함수의 직접 확인 → v_me := core.f_staff(p_code)
--    기기 표시값은 브라우저가 처음 한 번 만드는 96비트 무작위 값(localStorage dc_device)이라 짐작할 수 없다.
--
--    시험(롤백 블록): 정상 로그인 통과·기기 기록 / 전체 잠금 중 새 기기 막힘 · 쓰던 기기 통과 / 같은 IP 15분 안 15회 막힘.

create table if not exists core.pin_device (key text primary key, staff text, first_ok timestamptz not null default now(), last_ok timestamptz not null default now());
alter table core.pin_device enable row level security;
revoke all on core.pin_device from public, anon, authenticated;
create index if not exists ix_pin_attempt_at on core.pin_attempt (at desc);
create index if not exists ix_pin_attempt_ip_at on core.pin_attempt (ip, at desc);
-- core.f_staff · core.f_pin_fail_record · fn_quote_share · fn_quote_share_revoke · fn_store_handler_load 본문은
-- 서버 pg_get_functiondef 를 replace 해 다시 만들었다(지점 개수 검증). 현재 본문은 서버에서 볼 것.

-- ② 공개 화면 파일의 실제 고객 정보
--    admin.html(·admin/test) 의 업로드 양식 예시 줄에 실제 고객 휴대폰 12개 · 이름 · 이메일 · 거래처명이 있었다
--    (로그인 전에도 받을 수 있는 파일 · 공개 저장소). 전부 가짜 값(홍길동 · 010-0000-00NN · example.com)으로 바꿨다.
--    저장소 기록(git history)에는 남아 있다 — 기록 정리는 따로 결정.
