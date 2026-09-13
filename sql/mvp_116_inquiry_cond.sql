-- mvp_116 · 문의 관리(관리자) 상태·담당 체크박스 조건
--   p_status : 쉼표로 묶은 여러 값 ('(없음)' = 상태 미기재)
--   p_handler: 새 인자, 쉼표로 묶은 여러 값 ('(미배정)' = 담당 없음)
-- 인자가 늘어나므로 옛 시그니처 drop → 새로 create → grant (한 트랜잭션)
do $outer$
declare v_src text; v_args text; v_ident text;
  s_old text := $x$and (p_status is null or p_status = '' or coalesce(v.status,'') = p_status)$x$;
  s_new text := $x$and (p_status is null or p_status = '' or coalesce(nullif(v.status,''),'(없음)') = any(string_to_array(p_status,',')))
     and (p_handler is null or p_handler = '' or coalesce(nullif(v.handler,''),'(미배정)') = any(string_to_array(p_handler,',')))$x$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid), pg_get_function_identity_arguments(p.oid) into v_src, v_args, v_ident
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_inquiry_list';
  if position('p_handler' in v_args) > 0 then raise exception '이미 적용됨'; end if;
  if (length(v_src)-length(replace(v_src,s_old,'')))/length(s_old) <> 1 then raise exception 'p_status 지점 없음'; end if;
  execute format('drop function public.fn_inquiry_list(%s)', v_ident);
  execute format('create function public.fn_inquiry_list(%s, p_handler text default null) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, s_old, s_new));
  -- 원래 권한 그대로: PUBLIC·anon 없음, authenticated·service_role 만
  execute 'revoke all on function public.fn_inquiry_list(text,text,text,date,date,integer,integer,boolean,text,text) from public';
  execute 'grant execute on function public.fn_inquiry_list(text,text,text,date,date,integer,integer,boolean,text,text) to authenticated, service_role';
end $outer$;
-- 기본 권한 설정이 anon 에 execute 를 붙여 두므로 한 번 더 걷어낸다 (원래 ACL 과 동일하게)
revoke execute on function public.fn_inquiry_list(text,text,text,date,date,integer,integer,boolean,text,text) from anon;
