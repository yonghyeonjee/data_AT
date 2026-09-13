-- mvp_113 · 내 상담 · 전체 상담·배정에 기간(p_from · p_to) 추가 (2026-09-13)
--
-- 화면의 기간 바(캘린더 두 칸 + 전체·7일·30일·이 달)가 이 두 인자를 보낸다. 비우면 전과 같다.
-- 인자를 뒤에 붙이면 옛 시그니처와 오버로드가 둘이 되어 PostgREST 가 고르지 못하므로
-- 같은 트랜잭션 안에서 옛 것을 지우고 새로 만들고 실행 권한을 다시 준다.
-- 본문은 다시 쓰지 않고 기존 기간 조건 뒤에 두 조건만 덧붙인다.

do $outer$
declare v_src text; v_args text; v_ident text; v_new text; v_hits int; v_win text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid), pg_get_function_identity_arguments(p.oid) into v_src, v_args, v_ident
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_store_consults_my';
  if v_src is null then raise exception 'fn_store_consults_my 없음'; end if;
  if position('p_from' in v_args) > 0 then raise exception '이미 p_from 이 있습니다'; end if;
  v_win := $w$k.consult_at >= now() - interval '400 days'$w$;
  v_hits := (length(v_src) - length(replace(v_src, v_win, ''))) / length(v_win);
  if v_hits < 1 then raise exception '내 상담: 기간 조건 지점 없음'; end if;
  v_new := replace(v_src, v_win, v_win || $c$ and (p_from is null or k.consult_at >= (p_from::timestamp at time zone 'Asia/Seoul')) and (p_to is null or k.consult_at < ((p_to + 1)::timestamp at time zone 'Asia/Seoul'))$c$);
  execute format('drop function public.fn_store_consults_my(%s)', v_ident);
  execute format('create function public.fn_store_consults_my(%s, p_from date default null, p_to date default null) returns jsonb
                  language plpgsql stable security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_new);
  execute 'grant execute on function public.fn_store_consults_my(text,text,text,integer,integer,text,date,date) to anon, authenticated, service_role';

  select p.prosrc, pg_get_function_arguments(p.oid), pg_get_function_identity_arguments(p.oid) into v_src, v_args, v_ident
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_store_consults_all';
  if v_src is null then raise exception 'fn_store_consults_all 없음'; end if;
  if position('p_from' in v_args) > 0 then raise exception '이미 p_from 이 있습니다'; end if;
  v_win := $w$k.consult_at >= now() - interval '180 days'$w$;
  v_hits := (length(v_src) - length(replace(v_src, v_win, ''))) / length(v_win);
  if v_hits < 1 then raise exception '배정: 기간 조건 지점 없음'; end if;
  v_new := replace(v_src, v_win, v_win || $c$ and (p_from is null or k.consult_at >= (p_from::timestamp at time zone 'Asia/Seoul')) and (p_to is null or k.consult_at < ((p_to + 1)::timestamp at time zone 'Asia/Seoul'))$c$);
  execute format('drop function public.fn_store_consults_all(%s)', v_ident);
  execute format('create function public.fn_store_consults_all(%s, p_from date default null, p_to date default null) returns jsonb
                  language plpgsql stable security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_new);
  execute 'grant execute on function public.fn_store_consults_all(text,text,text,text,integer,text,date,date) to anon, authenticated, service_role';
end $outer$;
