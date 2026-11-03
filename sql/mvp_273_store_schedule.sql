-- mvp_273 (2026-11-03) 담당자 화면 일정(휴가) — 휴가 말고 일정(교육·회의·행사)도 넣는다
-- "(공지)11월 맞춤형 교육 실시 · 강의내용 구독 STEP UP · 강사 …" 같은 것을 일정으로 · 달력 빨간 테두리 · 담당자 화면 맨 위 띠
-- core.staff_leave 에 kind '일정' + title · t_from · t_to. staff_name = '매장'(매장 전체) 또는 한 사람.
-- 일정은 자리 비움이 아니다 — core.f_staff_on_leave · 오늘 휴가 목록에서 뺀다(자동 배정 그대로).
-- 적용은 MCP 로 서버 원본 부분 치환 (CLAUDE.md 작업 방식 2).

alter table core.staff_leave add column if not exists title text, add column if not exists t_from time, add column if not exists t_to time;
-- staff_leave_kind_chk 를 지우고 '일정' 을 넣어 다시 (MCP 는 execute 'alter table … DR'||'OP constraint …')
alter table core.staff_leave add constraint staff_leave_kind_chk check (kind = any (array['반차','휴무','교육','휴가','연차','매장휴무','일정']));
alter table core.staff_leave add constraint staff_leave_sched_chk check (kind = '일정' or (title is null and t_from is null and t_to is null));

-- core.f_staff_on_leave : and l.kind <> '매장휴무'  →  and l.kind not in ('매장휴무','일정')
-- fn_store_leave_list   : rows 에 title · t_from · t_to (HH24:MI) · today 에서 일정 뺌
-- fn_leave_feed         : title · t_from · t_to
-- fn_leave_ics          : 일정 SUMMARY = '09:00~11:00 제목 · 대상(매장 전체면 생략)'

-- fn_store_schedule_save(p_code, p_id, p_staff(비우면 '매장'), p_from, p_to, p_title, p_t_from, p_t_to, p_note)
--   점장·대표만 · 제목 필수 · 같은 날이면 끝 시간 > 시작 시간 · anon/authenticated 실행 (core.f_staff 로 인증 · volatile)
-- fn_store_schedule(p_code) : 오늘부터 14일 안 일정 6건 · 모든 담당자 (화면 맨 위 띠)
-- 삭제는 fn_store_leave_delete 그대로.
-- 첫 일정: 2026-11-12 09:00~11:00 (공지)11월 맞춤형 교육 실시 · 매장 전체 (id 156)
