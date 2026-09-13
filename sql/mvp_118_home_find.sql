-- mvp_118 · 홈 [찾기] 를 전체 상담에서 · consults_all 의 검색 버그
-- 1) fn_store_consults_all : p_q 에 숫자가 없으면 regexp_replace(p_q,'\D','')='' 라서 phone like '%%' 가 전부 참 → 검색어가 무시됐다.
--    숫자 3자리 이상일 때만 번호로 본다 (부분 치환, 지점 1개 확인). fn_store_consults_my 는 v_dig=nullif(...) 라 원래 정상.
do $outer$
declare v_src text; v_args text; n int;
  s_old text := $x$or regexp_replace(coalesce(k.phone,''),'\D','','g') like '%'||regexp_replace(p_q,'\D','','g')||'%'$x$;
  s_new text := $x$or (length(regexp_replace(p_q,'\D','','g')) >= 3 and regexp_replace(coalesce(k.phone,''),'\D','','g') like '%'||regexp_replace(p_q,'\D','','g')||'%')$x$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_consults_all';
  n := (length(v_src)-length(replace(v_src,s_old,'')))/length(s_old);
  if n <> 1 then raise exception '지점 %개', n; end if;
  execute format('create or replace function public.fn_store_consults_all(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, s_old, s_new));
end $outer$;

-- 2) 담당자 누구나 전체 상담에서 찾는 함수 (홈 [찾기]). 열기 권한은 화면이 mine/점장으로 가른다.
create or replace function public.fn_store_consult_find(p_code text, p_q text, p_limit integer default 50)
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog','public' as $fn$
declare v_me text := core.f_staff(p_code); v_q text := nullif(btrim(coalesce(p_q,'')),''); v_d text := nullif(regexp_replace(coalesce(p_q,''),'\D','','g'),'');
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_q is null or length(v_q) < 2 then raise exception '2글자 이상 입력하세요'; end if;
  return jsonb_build_object('me', v_me, 'rows', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', k.id, 'ref', k.source_ref, 'at', to_char(k.consult_at at time zone 'Asia/Seoul','MM-DD'),
      'name', k.customer_name, 'tel', regexp_replace(coalesce(k.phone,''),'\D','','g'),
      'phone', case when k.phone is null then null else left(regexp_replace(k.phone,'\D','','g'),3)||'-****-'||right(regexp_replace(k.phone,'\D','','g'),4) end,
      'interest', k.interest_category, 'model', k.interest_model_code,
      'src', coalesce((select ch.label from core.inq_channel ch where ch.code = k.channel_code), core.f_consult_src(k.source, k.inflow_route)),
      'handler', k.handler, 'mine', k.handler = v_me, 'result', k.result, 'callback_at', k.callback_at,
      'content', left(k.content, 90)) order by k.consult_at desc, k.id desc), '[]'::jsonb)
    from (select * from crm.consult_live k
           where (k.customer_name ilike '%'||v_q||'%'
               or (v_d is not null and length(v_d) >= 3 and regexp_replace(coalesce(k.phone,''),'\D','','g') like '%'||v_d||'%')
               or coalesce(k.interest_model_code,'') ilike '%'||v_q||'%'
               or coalesce(k.source_ref,'') ilike '%'||v_q||'%'
               or coalesce(k.interest_category,'') ilike '%'||v_q||'%'
               or coalesce(k.interest_detail,'') ilike '%'||v_q||'%'
               or coalesce(k.content,'') ilike '%'||v_q||'%')
           order by k.consult_at desc, k.id desc limit least(greatest(coalesce(p_limit,50),1),100)) k));
end $fn$;
grant execute on function public.fn_store_consult_find(text,text,integer) to anon, authenticated, service_role;

-- 3) 테스트 상담 19건 숨김 (지용현·지용현 테스트·홍길동·이순신·test·fg·DDDDD·12312·이찬햑·강찬성·김하늘) — 되돌리기: hidden_* 를 null 로
update crm.consult set hidden_at=coalesce(hidden_at, now()), hidden_by=coalesce(hidden_by,'지용현'), hidden_reason=coalesce(hidden_reason,'테스트 일괄 숨김 2026-09-13')
 where id in (378,377,178,138,137,136,135,133,132,127,123,122,121,120,119,118,141,129,131);
