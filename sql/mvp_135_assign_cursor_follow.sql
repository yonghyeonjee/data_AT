-- mvp_135 · 2026-09-14 — 자동 배정이 잘못 갔을 때 담당자를 바꾸면 순번 커서도 따라간다
-- 어디서 바꾸든(담당자 화면 [담당 바꾸기]·[넘기기], 관리자 문의 관리, 시트 수정→onMgmtEdit) crm.consult.handler 가 바뀌는 순간 트리거가 본다:
--   이전 담당자가 순번표(default)가 마지막으로 준 사람이고, 새 담당자가 풀 인원이면 커서를 새 담당자로 옮긴다 → 다음 문의는 그 다음 사람.
--   풀 밖 사람(예: 박은지)에게 넘기거나, 마지막 배정 건이 아닌 옛 건을 옮기면 커서는 그대로.
create or replace function core.f_consult_assign_cursor() returns trigger
language plpgsql set search_path to 'pg_catalog','public' as $$
begin
  if new.handler is distinct from old.handler and old.handler is not null and new.handler is not null
     and old.handler = (select last_staff from core.assign_state where scope = 'default')
     and exists (select 1 from core.assign_pool p where p.scope = 'default' and p.staff_name = new.handler and p.active) then
    update core.assign_state set last_staff = new.handler, last_at = now() where scope = 'default';
  end if;
  return new;
end $$;
drop trigger if exists trg_consult_assign_cursor on crm.consult;
create trigger trg_consult_assign_cursor after update of handler on crm.consult
  for each row execute function core.f_consult_assign_cursor();
-- 검증(롤백): 커서=권혁찬 상태에서 권혁찬 건 → 김규완 : 커서 김규완 / → 박은지(풀 밖) : 그대로 / 다른 건 이동 : 그대로
