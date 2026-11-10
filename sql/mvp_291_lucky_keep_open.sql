-- mvp_291 · 2026-11-10 · 행운 이벤트 — 기간 12/1~12/31 · "기간 밖에도 계속 열어 두기"(ev.event.keep_open) (적용됨 · 기록용)
-- 사용자: "기간은 12월 1일~12월 31일인데, 일단 계속 열어놔" → 기간은 안내용, keep_open=true 면 시작 전·끝난 뒤에도 주기·룰렛·긁기가 된다.
-- 함수는 서버 원본에서 해당 줄만 치환(CLAUDE.md 2번 규칙): fn_store_lucky_issue · fn_lucky_spin 의 기간 끝 검사, fn_lucky_admin_save 의 keep_open 저장, ev.f_pub 의 open/keep_open.
-- 추첨일(draw_date)은 비워 둠 — 관리자 화면 › 행운 이벤트 › 회차 설정에서 정한다.
alter table ev.event add column if not exists keep_open boolean not null default false;
update ev.event set start_date=date '2026-12-01', end_date=date '2026-12-31', draw_date=null, keep_open=true, updated_at=now(), updated_by='mvp_291' where id=1;
-- 치환: 'if ev.f_today() > e.end_date then' → 'if ev.f_today() > e.end_date and not e.keep_open then' (fn_store_lucky_issue · fn_lucky_spin)
-- 치환: fn_lucky_admin_save update/insert 에 keep_open 칸 추가
-- 치환: ev.f_pub 'open' = e.keep_open or 기간 안 · 'keep_open' 추가
