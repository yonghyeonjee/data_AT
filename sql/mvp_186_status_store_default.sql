-- mvp_186 · 2026-10-06 · 일 마감 '최근 마감'·'미마감' 목록이 비던 것
-- 증상: 담당자 화면 일 마감 탭에서 10월 마감이 지워진 것처럼 보였다 (차효범 프로님 10/1~10/6 마감 11줄은 DB 에 그대로,
--       삭제 기록 crm.access_log 'store_daily_delete' 0건).
-- 원인: fn_store_status(p_code, p_store text DEFAULT NULL) — 기본값이 '시흥점'(mvp_31) 에서 NULL 로 바뀌어 있었다.
--       화면은 p_store 를 안 보내므로 closed_recent·closed_mine·unclosed_days·unclosed_mine 의 `store = p_store` 가
--       전부 거짓 → 빈 목록. (월 마감 fn_store_month_close 는 매장 조건이 없어 정상이었다.)
-- 고침: 본문 시작에서 비어 있으면 '시흥점' 으로 채운다. 시그니처·ACL 그대로 (create or replace).
do $outer$
declare v_src text; v_args text; v_old text := E'begin\n  perform set_config(''dc.me''';
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_store_status';
  if (length(v_src)-length(replace(v_src,v_old,'')))/length(v_old) <> 1 then raise exception '지점 수가 1이 아님'; end if;
  execute format('create or replace function public.fn_store_status(%s) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L',
                 v_args, replace(v_src, v_old,
                   E'begin\n  p_store := coalesce(nullif(p_store, ''''), ''시흥점'');   -- 화면은 p_store 를 안 보낸다 (기본값이 NULL 이 되어 마감 목록이 비었다 · mvp_186)\n  perform set_config(''dc.me'''));
end $outer$;
-- 확인: 차효범 closed_mine 7일(10/1~10/6·9/29) · unclosed_days 9/24~27·9/30 · ACL anon/authenticated/service_role 그대로.
