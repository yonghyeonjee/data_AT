-- mvp_304 · 2026-11-19 · 문의 자동 배정 — 역순 + 휴무자 건너뛰기 다시 켬 + 순번 되돌아가는 버그 고침
-- DB 에는 이미 적용됨 (이 파일은 기록). 함수 원본은 core.fn_src_backup tag = 'before mvp_304' (id 15~18).
--
-- 1) 순서 (데이터): 기본 순번표를 권혁찬 → 이수혁 → 송희봉 → 김규완 → 최태웅 → 차효범 으로.
--    select public.fn_assign_pool_save('default', array['권혁찬','이수혁','송희봉','김규완','최태웅','차효범']);
--    select public.fn_assign_cursor_set('default', '차효범');   -- 마지막 = 차효범 → 다음 = 권혁찬
--
-- 2) 휴무자 건너뛰기: mvp_302 가 core.f_assign_simple() 로 함께 꺼 두었던 것을 스위치와 떼어 다시 켰다.
--    f_assign_simple() 는 true 그대로 — 이제 품목·접수 종류 규칙만 끈다.
--
-- 3) 버그: f_assign_next 가 마지막 배정자의 순번을 "휴무자를 뺀 목록" 에서 찾았다.
--    마지막 배정자가 그날 휴무면 못 찾아 -1 → 1번부터 다시 돌았다 (11-18 #1052 · 11-19 #1064).
--    전체 순번표(core.assign_pool)에서 찾도록 바꿨다 — fn_assign_pool 의 미리보기와 같은 방식.

do $$
declare v_def text; v_new text; v_n int; r record;
  a1 text := '(core.f_assign_simple() or not core.f_staff_on_leave(s.name))';
  b1 text := 'not core.f_staff_on_leave(s.name)';
  a2 text := '(select so from pool where nm=v_last)';
  b2 text := '(select p0.sort_no from core.assign_pool p0 where p0.scope=v_sc and p0.active and p0.staff_name=v_last)   /* mvp_304: 마지막 배정자가 휴무여도 그 사람 자리 다음부터 — 처음으로 되돌아가지 않는다 */';
  a3 text := 'and not core.f_assign_simple() and not v_test and v_hand is not null and core.f_staff_on_leave(v_hand)';
  b3 text := 'and not v_test and v_hand is not null and core.f_staff_on_leave(v_hand)';
  a4 text := '휴가자 건너뛰기 · 휴가 재배정 · 품목/접수 종류 규칙을 끈다. 다시 켜려면 false 로.';
  b4 text := '품목/접수 종류 규칙을 끈다. 다시 켜려면 false 로.' || E'\n' || '     휴가자 건너뛰기 · 휴가 재배정은 mvp_304 에서 다시 켰다(이 스위치와 무관).';
begin
  for r in select p.oid, n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as fn, pg_get_function_identity_arguments(p.oid) as args
             from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where (n.nspname='core' and p.proname in ('f_assign_next','f_assign_simple')) or (n.nspname='public' and p.proname in ('fn_assign_pool','fn_submit_inquiry')) loop
    insert into core.fn_src_backup(fn,args,tag,src) values (r.fn, r.args, 'before mvp_304', pg_get_functiondef(r.oid));
  end loop;

  v_def := pg_get_functiondef('core.f_assign_next(text,text)'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a1,'')))/length(a1); if v_n <> 2 then raise exception 'f_assign_next a1 hits %', v_n; end if;
  v_new := replace(v_def,a1,b1);
  v_n := (length(v_new)-length(replace(v_new,a2,'')))/length(a2); if v_n <> 1 then raise exception 'f_assign_next a2 hits %', v_n; end if;
  execute replace(v_new,a2,b2);

  v_def := pg_get_functiondef('public.fn_assign_pool()'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a1,'')))/length(a1); if v_n <> 2 then raise exception 'fn_assign_pool a1 hits %', v_n; end if;
  execute replace(v_def,a1,b1);

  v_def := pg_get_functiondef('public.fn_submit_inquiry(text,jsonb)'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a3,'')))/length(a3); if v_n <> 1 then raise exception 'fn_submit_inquiry a3 hits %', v_n; end if;
  execute replace(v_def,a3,b3);

  v_def := pg_get_functiondef('core.f_assign_simple()'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a4,'')))/length(a4); if v_n <> 1 then raise exception 'f_assign_simple a4 hits %', v_n; end if;
  execute replace(v_def,a4,b4);
end $$;

-- 되돌림 테스트 (2026-11-19 16:30 · 휴무 = 이수혁(오후 반차) · 송희봉 · 김규완):
--   미리보기 = 권혁찬 · f_assign_next 5번 = 권혁찬 > 최태웅 > 차효범 > 권혁찬 > 최태웅
--   마지막 = 김규완(휴무)로 두면 미리보기 = 최태웅 · 실제 = 최태웅  (고치기 전이면 실제 = 권혁찬 = 1번)
-- 휴무로 건너뛴 사람에게 나중에 채워 주는 규칙은 없다.
