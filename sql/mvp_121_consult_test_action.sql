-- mvp_121 · 담당자 화면에서 상담을 '테스트'로 표시 (숨김 + 통계 제외)
--   fn_store_consult_update 에 p_action='test' 추가 : hidden_at/hidden_by/hidden_reason='테스트' (부분 치환, 지점 1개 확인)
--   화면 : 펼친 줄 맨 아래 [테스트로] — dept 가 개발·온라인 인 담당자에게만. 복구는 관리자 문의 관리 [삭제됨]
do $outer$
declare v_def text; n int;
  s_old text := $x$  elsif p_action = 'hold' then$x$;
  s_new text := $x$  elsif p_action = 'test' then   -- 테스트로 표시 : 숨기고 통계에서 뺀다 (관리자 문의 관리 [삭제됨]에서 복구)
    update crm.consult set hidden_at = coalesce(hidden_at, now()), hidden_by = v_me, hidden_reason = '테스트', updated_at = now(),
      notes = concat_ws(' / ', notes, '테스트로 표시 '||v_stamp||' '||v_me) where id = p_id;
  elsif p_action = 'hold' then$x$;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_consult_update';
  if position('p_action = ''test''' in v_def) > 0 then raise exception '이미 적용'; end if;
  n := (length(v_def)-length(replace(v_def,s_old,'')))/length(s_old);
  if n <> 1 then raise exception '지점 %개', n; end if;
  execute replace(v_def, s_old, s_new);
end $outer$;

-- 2) 담당자가 개발 계정(dept='개발': 지용현·test)이면 자동으로 테스트 숨김 — 목록·통계에서 빠진다
--    (BEFORE insert or update of handler · 이름순으로 trg_consult_assign 다음에 돈다)
create or replace function core.f_consult_dev_is_test() returns trigger language plpgsql as $t$
begin
  if new.handler is not null and new.hidden_at is null and new.deleted_at is null
     and exists (select 1 from core.staff s where s.name = new.handler and s.dept = '개발') then
    new.hidden_at := now(); new.hidden_by := new.handler; new.hidden_reason := '테스트 (개발 계정 담당)';
  end if;
  return new;
end $t$;
drop trigger if exists trg_consult_dev_is_test on crm.consult;
create trigger trg_consult_dev_is_test before insert or update of handler on crm.consult
  for each row execute function core.f_consult_dev_is_test();
-- 기존: 가온상사(107, 실제 소모품 문의)는 박은지로 이관, 나머지 지용현 담당 4건(이름 없음)은 테스트 숨김
update crm.consult set handler='박은지', notes=concat_ws(' · ', nullif(notes,''), '2026-09-13 담당 박은지로 이관 (이전 지용현)'), updated_at=now() where id=107;
update crm.consult set hidden_at=now(), hidden_by='지용현', hidden_reason='테스트 (개발 계정 담당)', updated_at=now() where handler='지용현' and hidden_at is null and deleted_at is null;
