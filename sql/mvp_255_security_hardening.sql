-- mvp_255 보안 보강 1차 (2026-10-30) — 2026-10-30 운영 DB 적용 완료 (execute_sql). 검증: new_user_inactive=t, bulk_result_checked=t, anon profiles 권한 (none), anon 호출 시 42501.
-- 배경: 2026-10-30 보안 점검. 아래 ①②는 즉시 막아야 하는 구멍, ③은 다층 방어.
--
-- ① 회원가입(Auth signup)이 켜져 있고, 가입 트리거 fn_handle_new_user 가 가입 요청의 raw_user_meta_data.role 을
--    그대로 profiles.role 에 넣었다 → 누구나 anon 키로 가입하면서 data:{role:'admin'} 을 보내고 메일만 확인하면 관리자.
--    고침: 새 계정은 항상 role='user', active=false (core.f_role() 은 active 가 아니면 'anon' 으로 본다).
--    ※ 추가로 Supabase 대시보드 Authentication → Sign In / Providers → "Allow new users to sign up" 을 꺼야 한다 (SQL 로는 못 바꿈).
-- ② fn_consult_bulk_result 가 anon 실행 가능인데 권한 검사가 없었다 → 공개키만으로 모든 상담 상태를 바꿀 수 있었다.
-- ③ public.profiles 에 anon INSERT/UPDATE/DELETE, authenticated 쓰기 권한이 남아 있었다 (RLS 가 막고 있었지만 회수).

begin;

-- ① 가입 트리거
create or replace function public.fn_handle_new_user() returns trigger
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
begin
  insert into public.profiles (id, email, role, active)
  values (new.id, new.email, 'user', false)   -- 가입 메타데이터의 role 을 믿지 않는다. 관리자가 계정 화면에서 켜 준다
  on conflict (id) do nothing;
  return new;
end $$;

-- ② 상담 일괄 상태 변경 — 권한 검사 추가 (본문 치환 방식 · CLAUDE.md 규칙)
do $outer$
declare v_src text; v_args text; v_n int;
        v_old text := E'declare n int;\nbegin';
        v_new text := E'declare n int;\nbegin\n  if core.f_role() not in (''admin'',''user'') then raise exception ''권한이 없습니다'' using errcode=''42501''; end if;';
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_consult_bulk_result';
  v_n := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'fn_consult_bulk_result 치환 지점 %개 (1개여야 함)', v_n; end if;
  execute format('create or replace function public.fn_consult_bulk_result(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L',
                 v_args, replace(v_src, v_old, v_new));
end $outer$;

-- ③ profiles 직접 권한 회수 (화면은 전부 RPC 로만 접근한다 · grep 으로 확인)
revoke all on public.profiles from anon;
revoke insert, update, delete, truncate, references, trigger on public.profiles from authenticated;

commit;

-- 확인
select
  (select prosrc from pg_proc where proname='fn_handle_new_user') like '%''user'', false)%'   as new_user_inactive,
  (select prosrc from pg_proc where proname='fn_consult_bulk_result') like '%core.f_role()%'  as bulk_result_checked,
  (select coalesce(string_agg(privilege_type, ','),'(none)') from information_schema.role_table_grants
    where grantee='anon' and table_schema='public' and table_name='profiles')                 as anon_profiles_priv;
