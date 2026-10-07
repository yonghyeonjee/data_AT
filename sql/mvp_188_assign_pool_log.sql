-- mvp_188 · 2026-10-07 · 문의 자동 배정 순번 — "자꾸 이름순으로 바뀐다"
-- 사실 확인: 순번표(core.assign_pool)를 자동으로 다시 쓰는 코드는 없다 (prosrc 에 assign_pool 을 쓰는 함수는 f_assign_next·f_consult_assign_cursor·
--   fn_assign_pool·fn_assign_pool_save 넷뿐, cron 없음). pg_stat_statements(8/28~) 로 fn_assign_pool_save 호출은 **3번**, 마지막이 2026-10-07 01:43:55Z(=10:43 KST,
--   관리자 화면 · 폰) 로 지금 순서(최태웅 → 차효범 → 김규완 → 송희봉 → 이수혁 → 권혁찬). 그 전엔 9/8 에 만들 때 들어간 **이름순(권·김·송·이·차·최)** 그대로였다 —
--   9/29~10/6 배정이 이름순으로 돈 이유. 화면에서 ‹ › 로 옮기고 [이 규칙 저장] 을 안 누르면 다음에 열 때 저장된(이름) 순서로 보여 "자꾸 바뀐다" 가 된다.
-- ① core.assign_pool_log — 누가(by_user: JWT email) 언제 어떤 순서(before → after)로 저장했는지. RLS on(정책 없음 · 함수만 쓴다).
-- ② fn_assign_pool_save 가 저장마다 한 줄 남긴다 (v_before 를 먼저 떠 둔다). 시그니처·ACL 그대로.
-- ③ fn_assign_pool 응답에 'saved'(scope 별 마지막 저장 at·by·names) — 화면 상태 줄 '순서 저장 10-07 10:43 yonghyeonjee'.
-- ④ 10/07 10:43 저장분을 첫 기록으로 넣어 둔다(로그 생기기 전 · edge log 로 확인).
-- 화면(admin.html·admin/test v172): ‹ › ✕ [+ 넣기] 가 **바로 저장**(savePool(true)), ✕ 는 confirm. 폰 칩 버튼 40px. 테스트 ptest/pool_probe.mjs A1~A8 × 1280·390 = 15.
create table if not exists core.assign_pool_log (
  id bigserial primary key, at timestamptz not null default now(),
  by_user text, by_role text, scope text not null, before_names text[], after_names text[]);
alter table core.assign_pool_log enable row level security;
do $outer$
declare v_src text; v_args text;
  a1 text := $q$  update core.assign_pool set active = false where scope = p_scope;$q$;
  b1 text := $q$  v_before := (select coalesce(array_agg(staff_name order by sort_no), '{}') from core.assign_pool where scope = p_scope and active);
  update core.assign_pool set active = false where scope = p_scope;$q$;
  a2 text := $q$  return jsonb_build_object('ok', true, 'scope', p_scope, 'n', i/10);$q$;
  b2 text := $q$  /* 누가 언제 어떤 순서로 저장했는지 남긴다 — "자꾸 이름순으로 바뀐다" 추적용 (mvp_188) */
  insert into core.assign_pool_log (by_user, by_role, scope, before_names, after_names)
  values (coalesce(auth.jwt()->>'email', current_setting('request.jwt.claims', true)::jsonb->>'role'), core.f_role(), p_scope, v_before, coalesce(p_names,'{}'::text[]));
  return jsonb_build_object('ok', true, 'scope', p_scope, 'n', i/10);$q$;
  a3 text := $q$declare n text; i int := 0;$q$;
  b3 text := $q$declare n text; i int := 0; v_before text[];$q$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_assign_pool_save';
  if (length(v_src)-length(replace(v_src,a1,'')))/length(a1) <> 1 then raise exception 'a1 지점'; end if;
  if (length(v_src)-length(replace(v_src,a2,'')))/length(a2) <> 1 then raise exception 'a2 지점'; end if;
  if (length(v_src)-length(replace(v_src,a3,'')))/length(a3) <> 1 then raise exception 'a3 지점'; end if;
  v_src := replace(replace(replace(v_src, a1, b1), a2, b2), a3, b3);
  execute format('create or replace function public.fn_assign_pool_save(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_assign_pool';
  a1 := $q$    'state', (select$q$;
  b1 := $q$    'saved', (select coalesce(jsonb_agg(jsonb_build_object('scope', scope, 'at', to_char(at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'by', by_user, 'names', after_names) order by at desc), '[]'::jsonb)
               from (select distinct on (scope) scope, at, by_user, after_names from core.assign_pool_log order by scope, at desc) l),
    'state', (select$q$;
  if (length(v_src)-length(replace(v_src,a1,'')))/length(a1) <> 1 then raise exception 'pool a1 지점'; end if;
  execute format('create or replace function public.fn_assign_pool(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, a1, b1));
end $outer$;
insert into core.assign_pool_log (at, by_user, by_role, scope, before_names, after_names)
values ('2026-10-07 01:43:55+00', '(관리자 화면 · 로그 생기기 전)', 'admin', 'default', array['권혁찬','김규완','송희봉','이수혁','차효범','최태웅'], array['최태웅','차효범','김규완','송희봉','이수혁','권혁찬']);
-- 롤백 확인: service_role 로 save → log 1줄(before 최·차·김·송·이·권 → after 차·최·…) · 되돌린 뒤 순번표 그대로.
-- 기본 순번 (2026-10-07): 최태웅 → 차효범 → 김규완 → 송희봉 → 이수혁 → 권혁찬. **이름순 아니다. 세션에서 다시 넣지 말 것.**
