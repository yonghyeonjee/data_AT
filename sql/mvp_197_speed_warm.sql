-- mvp_197 · 2026-10-10 · 속도 점검 — 쓸데없이 느리게 하던 것 두 가지 (DB 에는 이미 반영됨)
--
-- ① core.f_dash_warm 이 15분마다 6.5~7초씩 돌았다 (할 일이 없을 때도).
--    워머가 굽는 '지난달' 키(예: 2026-09-01|2026-09-30|ledger·manual·dps)를 같은 함수 끝의
--    "끝 날짜가 3일 지난 키 정리" 가 바로 지웠다 → 매번 3벌(약 6초)을 굽고 지움.
--    [지난달]을 누른 사람은 캐시를 못 만나 직접 굽는다(2~8초 · /dash/ 는 anon 3초라 실패할 수 있다).
--    + 쓰지 않는 변수 d_all 이 orders_live 전체 min(order_at) 을 매번 계산(0.6초).
--    → 정리에서 지난달 키를 빼고, d_all 줄을 지웠다. 할 일 없는 회차 6.6초 → 23ms.
-- ② fn_crm_options (발송 대상 추출 화면의 채널·카테고리·지역 목록) 가 열 때마다 고객 6.2만·주문 19만 줄을
--    distinct 로 훑었다 (340~745ms). 목록은 거의 안 바뀌므로 core.rpc_cache 'crm_options' 에 70분 캐시,
--    f_rpc_warm(5분)이 60분마다 다시 굽는다. 본문은 core.f_crm_options_build() 로 옮김(서버 원본에서 case 껍데기만 벗김).
--    → 0.9ms. ACL 그대로 (authenticated·service_role, anon 없음).

-- ① f_dash_warm
do $outer$
declare v_src text; v_args text; p1 text := '\n\s*d_all date := coalesce\(\(select min\(order_at at time zone ''Asia/Seoul''\)::date from core\.orders_live\), d - 365\);';
        p2 text := 'split_part\(cache_key, ''\|'', 2\)::date < d - 3;';
        b2 text := 'split_part(cache_key, ''|'', 2)::date < d - 3
     and cache_key not like ((date_trunc(''month'', d) - interval ''1 month'')::date::text || ''|'' || (date_trunc(''month'', d) - interval ''1 day'')::date::text || ''|%'');  /* 지난달 키는 워머가 굽는 키 — 지우면 매번 다시 굽고 지운다 (mvp_197) */';
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p where p.proname='f_dash_warm' and p.pronamespace='core'::regnamespace;
  if regexp_count(v_src,p1)<>1 then raise exception 'p1 지점 %', regexp_count(v_src,p1); end if;
  if regexp_count(v_src,p2)<>1 then raise exception 'p2 지점 %', regexp_count(v_src,p2); end if;
  v_src := regexp_replace(v_src,p1,'');
  if position('d_all' in v_src)>0 then raise exception 'd_all 남음'; end if;
  v_src := regexp_replace(v_src,p2,b2);
  execute format('create or replace function core.f_dash_warm(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;

-- ② fn_crm_options 캐시
do $outer$
declare v_src text; v_w text; v_anchor text := '  return ''warmed in ''';
begin
  select prosrc into v_src from pg_proc where proname='fn_crm_options' and pronamespace='public'::regnamespace;
  if position('jsonb_agg(distinct s)' in v_src)=0 then raise exception '지점 없음 options'; end if;
  v_src := regexp_replace(v_src, '^\s*select case when core\.f_role\(\) = ''anon'' then null else ', 'select ');
  v_src := regexp_replace(v_src, '\s*end\s*$', '');
  if position('f_role' in v_src)>0 then raise exception '껍데기 안 벗겨짐'; end if;
  execute format('create or replace function core.f_crm_options_build() returns jsonb language sql stable security definer set search_path to ''pg_catalog'',''public'' as %L', v_src);
  revoke all on function core.f_crm_options_build() from public, anon, authenticated;

  create or replace function public.fn_crm_options() returns jsonb
  language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
  declare v jsonb; v_at timestamptz;
  begin
    if core.f_role() = 'anon' then return null; end if;
    select payload, built_at into v, v_at from core.rpc_cache where cache_key = 'crm_options';
    if v is not null and v_at > now() - interval '70 minutes' then return v; end if;
    v := core.f_crm_options_build();
    insert into core.rpc_cache (cache_key, payload, built_at, build_ms) values ('crm_options', v, now(), 0)
      on conflict (cache_key) do update set payload = excluded.payload, built_at = excluded.built_at;
    return v;
  end $f$;
  revoke all on function public.fn_crm_options() from public, anon;
  grant execute on function public.fn_crm_options() to authenticated, service_role;

  select prosrc into v_w from pg_proc where proname='f_rpc_warm' and pronamespace='core'::regnamespace;
  if (length(v_w)-length(replace(v_w, v_anchor, '')))/length(v_anchor) <> 1 then raise exception '지점 수 이상 warm'; end if;
  v_w := replace(v_w, v_anchor, '  if not exists (select 1 from core.rpc_cache where cache_key=''crm_options'' and built_at > now() - interval ''60 minutes'') then
    v := core.f_crm_options_build();
    insert into core.rpc_cache(cache_key,payload,built_at,build_ms) values (''crm_options'',v,now(),0)
      on conflict (cache_key) do update set payload=excluded.payload, built_at=now();
  end if;
' || v_anchor);
  execute format('create or replace function core.f_rpc_warm() returns text language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_w);
end $outer$;
