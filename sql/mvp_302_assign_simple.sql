-- mvp_302 · 2026-11-19 · 문의 자동 배정 = 단순 순번 (휴가·품목·접수 종류 규칙 끔)
-- (적용됨 — 이 파일은 기록용)
--
-- 왜: "데이터 센터에서 상담사 배정하는거 휴가자 없이 그냥 순서대로 돌게 다른 규칙은 일단 다 꺼두는 걸로 ·
--      그냥 현재 저장된 1~6번 순서대로만 돌게 · store에서 수동으로 재배정하시겠다네"
--
-- 스위치 core.f_assign_simple() = true 인 동안:
--  ① core.f_assign_next      — 후보 범위를 'default'(기본 순번표) 하나로 · 휴가자도 건너뛰지 않음
--                              (core.staff.active 가 꺼진 사람·순번표에서 뺀 사람은 전처럼 빠진다)
--  ② fn_submit_inquiry        — 배정된 사람이 휴가면 다음 사람으로 다시 배정하던 것을 안 함
--  ③ core.f_consult_assign_cursor (crm.consult handler 변경 트리거)
--                            — 마지막 배정 건을 수동으로 넘겨도 순번(마지막 배정)이 따라가지 않음
--  ④ fn_assign_pool           — '다음' 표시도 휴가와 무관하게 순서대로 · 응답에 simple
-- 그대로인 것: web_b2b 는 박은지 프로님 고정 · 테스트 문의는 순번 안 돌림 · 마지막 배정 지정(fn_assign_cursor_set).
--
-- 다시 켜려면(휴가 건너뛰기·규칙·순번 따라가기 전부 되살아남):
--   create or replace function core.f_assign_simple() returns boolean language sql stable
--     set search_path to 'pg_catalog','public' as $f$ select false $f$;
-- 원문 백업: core.fn_src_backup tag 'before mvp_302' (4함수)
--
-- 시험(롤백 블록 · 11-19 는 김규완·송희봉 휴무 · 이수혁 반차): 마지막 차효범 뒤로
--   김규완 → 송희봉 → 이수혁 → 권혁찬 → 최태웅 → 차효범 → 김규완 (접수 종류·품목을 섞어 넣어도 같은 순서) ·
--   마지막 배정 건을 수동으로 다른 사람에게 넘겨도 순번 그대로 · fn_assign_pool simple=true.

create or replace function core.f_assign_simple() returns boolean language sql stable set search_path to 'pg_catalog','public' as $f$
  /* 문의 자동 배정 단순 순번 모드 (mvp_302 · 2026-11-19) — true 면 기본 순번표(1~6번)만 순서대로 돈다:
     휴가자 건너뛰기 · 휴가 재배정 · 품목/접수 종류 규칙 · 수동 재배정 시 순번 따라가기를 전부 끈다. 다시 켜려면 false 로. */
  select true
$f$;

do $outer$
declare r record; v_def text; v_n int; p record;
begin
  for r in select * from (values
    ('core.f_assign_next(text,text)'), ('core.f_consult_assign_cursor()'), ('public.fn_submit_inquiry(text,jsonb)'), ('public.fn_assign_pool()')) t(fn) loop
    insert into core.fn_src_backup (fn, args, tag, src)
    select r.fn, pg_get_function_arguments(r.fn::regprocedure), 'before mvp_302', pg_get_functiondef(r.fn::regprocedure);
  end loop;
  for p in select * from (values
    ('core.f_assign_next(text,text)', 1, 'foreach v_sc in array v_cands loop',
       $b$if core.f_assign_simple() then v_cands := array['default']; end if;   /* mvp_302: 단순 순번 — 품목·접수 종류 규칙 끔 */
  foreach v_sc in array v_cands loop$b$),
    ('core.f_assign_next(text,text)', 2, 'and s.active and not core.f_staff_on_leave(s.name)',
       'and s.active and (core.f_assign_simple() or not core.f_staff_on_leave(s.name))'),
    ('core.f_consult_assign_cursor()', 1, 'if new.handler is distinct from old.handler and old.handler is not null and new.handler is not null',
       'if not core.f_assign_simple() and new.handler is distinct from old.handler and old.handler is not null and new.handler is not null'),
    ('public.fn_submit_inquiry(text,jsonb)', 1, 'and not v_test and v_hand is not null and core.f_staff_on_leave(v_hand) then',
       'and not core.f_assign_simple() and not v_test and v_hand is not null and core.f_staff_on_leave(v_hand) then'),
    ('public.fn_assign_pool()', 2, 'and s.active and not core.f_staff_on_leave(s.name)',
       'and s.active and (core.f_assign_simple() or not core.f_staff_on_leave(s.name))'),
    ('public.fn_assign_pool()', 1, $a$'next'$a$, $b$'simple', core.f_assign_simple(), 'next'$b$)
  ) t(fn, want, a, b) loop
    v_def := pg_get_functiondef(p.fn::regprocedure);
    v_n := (length(v_def) - length(replace(v_def, p.a, ''))) / length(p.a);
    if v_n <> p.want then raise exception '% 지점 % 개 (기대 %): %', p.fn, v_n, p.want, left(p.a, 40); end if;
    execute replace(v_def, p.a, p.b);
  end loop;
end $outer$;
