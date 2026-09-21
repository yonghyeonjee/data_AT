-- mvp_169 (2026-09-21 · v133) — 이미 DB 에 반영됨. 기록용.
-- 개발 계정(지용현)이 맡은 건은 트리거가 테스트 숨김(hidden_reason '테스트 (개발 계정 담당)')을 붙이는데,
-- 목록(fn_store_consults_my)은 개발 계정에게 보여 주면서 fn_store_consult_update 는 hidden_at is null 만 찾아
-- [삭제]·[테스트로]·상태 변경이 전부 400 '상담을 찾을 수 없습니다' 였다 (#440 지용현).
-- ① fn_store_consult_update 조회 조건: hidden_at is null OR (hidden_reason like '테스트%' and core.f_staff_is_dev(v_me))
-- ② fn_store_handler_load: role_note 로만 점장을 판정해 개발 계정이 403 → core.f_staff_is_mgr(v_me) 로 (화면 is_mgr 과 같은 판정)
do $outer$
declare v_def text; v_old text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_store_consult_update';
  v_old := $q$select * into r from crm.consult where id = p_id and hidden_at is null and (deleted_at is null or p_action = 'restore');$q$;
  v_new := $q$select * into r from crm.consult where id = p_id
     and (hidden_at is null or (hidden_reason like '테스트%' and core.f_staff_is_dev(v_me)))   /* 개발 계정은 테스트 숨김 건도 (mvp_169) */
     and (deleted_at is null or p_action = 'restore');$q$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'update 지점 %개', v_n; end if;
  execute replace(v_def, v_old, v_new);

  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_store_handler_load';
  v_old := $q$select coalesce(s.role_note,'') = any(array['점장','대표','전체','개발']) into v_mgr from core.staff s where s.code = p_code;$q$;
  v_new := $q$v_mgr := core.f_staff_is_mgr(v_me);   /* 화면의 is_mgr 과 같은 판정 (mvp_169) */$q$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'handler_load 지점 %개', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $outer$;
-- 롤백 확인: #440 에 test → delete → restore 전부 ok, fn_store_handler_load 도 ok (2026-09-21)
