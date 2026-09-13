-- mvp_112 · 전체 상담·배정 목록을 문의 온 순서(최근 먼저)로 (2026-09-13)
--
-- 전에는 미배정 → 진행전 → 내 것 → 진행중 → 날짜 순이라 7월 미배정 건이 맨 위에 붙어 있었다.
-- 점장이 보는 것은 "무엇이 새로 왔나" 이므로 consult_at 내림차순 하나로 줄인다.
-- 미배정은 [미배정] 범위 버튼과 홈의 "미배정 문의 n건" 알림이 따로 잡아 준다.
-- fn_store_consults_my(내 상담)의 급한 순 정렬(지난 콜백 → 오래 방치)은 그대로 둔다.

do $outer$
declare v_src text; v_args text; v_old text; v_hits int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where p.proname = 'fn_store_consults_all';
  if v_src is null then raise exception 'fn_store_consults_all 없음'; end if;
  v_old := $q$order by (k.handler is null) desc, (k.result = '진행전') desc, (k.handler = v_me) desc, (k.result = '진행중') desc, k.consult_at desc$q$;
  v_hits := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  if v_hits <> 2 then raise exception '치환 지점이 %개입니다 (기대 2) — 중단', v_hits; end if;   -- jsonb_agg 안 · 서브쿼리 안
  execute format('create or replace function public.fn_store_consults_all(%s) returns jsonb
                  language plpgsql stable security definer
                  set search_path to ''pg_catalog'',''public'' as %L',
                 v_args, replace(v_src, v_old, 'order by k.consult_at desc, k.id desc'));
end $outer$;
