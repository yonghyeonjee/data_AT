-- mvp_138 (2026-09-14) 견적서 페이지 → 데이터센터 직접 호출 (GAS 왕복 제거)
-- 발행·발행 내역·지난 견적 열기·기존 고객 찾기·고객 링크가 전부 anon + 페이지 보안 코드(core.f_quote_page_ok) 로 바로 온다.
-- 시트는 더 이상 페이지가 쓰지 않는다. 시트 [견적내역] 을 계속 채우려면 GAS 가 fn_quote_feed 를 15분마다 읽어 붙인다 (tools/gas/quote_forward.gs pullQuotesFromDatacenter).
begin;

-- 1) fn_submit_quote 본문 → core.f_quote_store(p_data)  (키 검사만 뺀 내부 함수. 본문은 서버 원본에서 그대로)
do $outer$
declare v_src text;
        v_line text := E'  if not core.f_api_ok(''gas_forward'', p_key) then raise exception ''권한이 없습니다'' using errcode=''42501''; end if;\n';
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_submit_quote';
  if v_src is null then raise exception 'fn_submit_quote 없음'; end if;
  if position('core.f_quote_store' in v_src) > 0 then raise exception '이미 적용됨'; end if;
  if (length(v_src) - length(replace(v_src, v_line, ''))) / length(v_line) <> 1 then raise exception '키 검사 지점이 1개가 아님'; end if;
  execute format('create or replace function core.f_quote_store(p_data jsonb) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L',
                 replace(v_src, v_line, ''));
end $outer$;
revoke all on function core.f_quote_store(jsonb) from public;

create or replace function public.fn_submit_quote(p_key text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_api_ok('gas_forward', p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_quote_store(p_data);
end $$;

-- 2) 고객 링크: fn_quote_share_key 본문 → core.f_quote_share(p_no, p_by, p_days)
do $outer$
declare v_src text;
        v_line text := E'  if not core.f_api_ok(''quote_lookup'', p_key) then\n    raise exception ''키가 맞지 않습니다'' using errcode=''42501''; end if;\n';
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_quote_share_key';
  if position('core.f_quote_share(' in v_src) > 0 then raise exception '이미 적용됨'; end if;
  if (length(v_src) - length(replace(v_src, v_line, ''))) / length(v_line) <> 1 then raise exception '키 검사 지점이 1개가 아님'; end if;
  execute format('create or replace function core.f_quote_share(p_no text, p_by text default null, p_days integer default 180) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L',
                 replace(v_src, v_line, ''));
end $outer$;
revoke all on function core.f_quote_share(text, text, integer) from public;

create or replace function public.fn_quote_share_key(p_key text, p_no text, p_by text default null, p_days integer default 180) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_api_ok('quote_lookup', p_key) then raise exception '키가 맞지 않습니다' using errcode='42501'; end if;
  return core.f_quote_share(p_no, p_by, p_days);
end $$;

-- 3) 기존 고객 찾기 — 후보를 먼저 v_lim 건으로 줄인 뒤 주문·상담·지난 견적을 센다.
--    (전엔 '김' 처럼 11,000명이 걸리면 전부에 대해 하위 질의 3개를 돌려 2~7초 → anon 3초 제한에 걸린다)
create index if not exists ix_cust_name_trgm on crm.customer using gin (name extensions.gin_trgm_ops);

create or replace function core.f_quote_customer_lookup(p_q text, p_limit integer default 8) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare
  v_q    text := nullif(btrim(coalesce(p_q,'')),'');
  v_dig  text := nullif(regexp_replace(coalesce(p_q,''),'\D','','g'),'');
  v_name text;
  v_lim  int  := least(greatest(coalesce(p_limit,8),1), 20);
begin
  if v_q is null or length(v_q) < 2 then
    return jsonb_build_object('ok', true, 'rows', '[]'::jsonb, 'note', '두 글자 이상 넣어 주세요');
  end if;
  v_name := nullif(btrim(regexp_replace(v_q, '[0-9\-\s]+', ' ', 'g')), '');   -- "최유정 3976" → 이름 부분
  if v_dig is not null and length(v_dig) < 4 then v_dig := null; end if;       -- 번호는 4자리부터
  if v_name is null and v_dig is null then
    return jsonb_build_object('ok', true, 'rows', '[]'::jsonb, 'note', '번호는 뒷 4자리 이상 넣어 주세요');
  end if;

  return (
    select jsonb_build_object('ok', true, 'q', v_q, 'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'key',   c.buyer_key,
        'name',  c.name,
        'phone', c.phone,
        'addr',  c.address,
        'birth', to_char(c.birth,'YYYY.MM.DD'),
        'last_at', to_char(c.last_seen_at at time zone 'Asia/Seoul','YYYY.MM.DD'),
        'orders',   (select count(*) from core.orders o where o.buyer_key = c.buyer_key),
        'consults', (select count(*) from crm.consult k where k.buyer_key = c.buyer_key and k.hidden_at is null),
        'last_quote', (
          select jsonb_build_object(
                   'no', q.quote_no, 'ver', q.version,
                   'at', to_char(q.issued_at at time zone 'Asia/Seoul','YYYY.MM.DD'),
                   'counselor', q.counselor, 'models', q.models,
                   'carrier', nullif(q.summary->>'carrier',''),
                   'wedding', nullif(q.summary->>'wedding',''),
                   'movein',  nullif(q.summary->>'movein',''),
                   'birth',   nullif(q.summary->>'birth',''),
                   'addr',    coalesce(nullif(q.summary->>'addr',''), q.region))
            from crm.quote q
           where q.buyer_key = c.buyer_key
           order by q.issued_at desc, q.version desc limit 1)
      ) order by c.pri, c.last_seen_at desc nulls last), '[]'::jsonb))
    from (
      select c.buyer_key, c.name, c.phone, c.address, c.birth, c.last_seen_at,
             case when v_name is not null and v_dig is not null
                       and c.name ilike '%'||v_name||'%' and c.phone like '%'||v_dig then 0
                  when v_dig is not null and c.phone like '%'||v_dig then 1
                  when v_name is not null and c.name = v_name then 2
                  when v_name is not null and c.name ilike v_name||'%' then 3
                  else 4 end pri
        from crm.customer c
       where c.name is not null and c.name <> '(미상)'
         and ( (v_name is not null and c.name ilike '%'||v_name||'%')
               or (v_dig is not null and c.phone like '%'||v_dig||'%') )
       order by pri, c.last_seen_at desc nulls last
       limit v_lim) c);
end $$;
revoke all on function core.f_quote_customer_lookup(text, integer) from public;

create or replace function public.fn_quote_customer_lookup(p_key text, p_q text, p_limit integer default 8) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_api_ok('quote_lookup', p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_quote_customer_lookup(p_q, p_limit);
end $$;

-- 4) 견적번호 = SH + yyMMdd + '-' + 당일 순번 3자리 (crm.quote 기준. 시트만 있던 번호와 겹치지 않게 전환 전 '일괄 적재' 1회)
create or replace function core.f_quote_next_no() returns text
language plpgsql volatile as $$
declare v_pfx text := 'SH' || to_char(now() at time zone 'Asia/Seoul', 'YYMMDD') || '-'; v_max int;
begin
  perform pg_advisory_xact_lock(hashtext('crm.quote.next_no'));
  select coalesce(max(core.f_int(substr(quote_no, length(v_pfx) + 1))), 0) into v_max
    from crm.quote where quote_no like v_pfx || '%';
  return v_pfx || lpad((v_max + 1)::text, 3, '0');
end $$;
revoke all on function core.f_quote_next_no() from public;

-- 5) 페이지가 부르는 RPC (anon · 페이지 보안 코드). 코드가 틀리면 0.7초 쉬고 거절 — 무차별 대입을 늦춘다
create or replace function public.fn_quote_page_save(p_code text, p_no text default null, p_summary jsonb default '{}'::jsonb,
                                                     p_quote jsonb default '{}'::jsonb, p_namecard jsonb default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare
  v_no  text  := nullif(btrim(coalesce(p_no,'')),'');
  v_ver int;
  v_at  text  := to_char(now() at time zone 'Asia/Seoul', 'YYYY.MM.DD HH24:MI');
  v_q   jsonb := coalesce(p_quote, '{}'::jsonb);
  v_s   jsonb := coalesce(p_summary, '{}'::jsonb);
  r     jsonb;
begin
  if not core.f_quote_page_ok(p_code) then perform pg_sleep(0.7); raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_no is null then
    v_no := core.f_quote_next_no(); v_ver := 1;
  else
    select coalesce(max(version), 0) + 1 into v_ver from crm.quote where quote_no = v_no;
  end if;
  /* 이름 없이 발행한 견적도 저장한다 (시트 때와 같게) — 목록·고객 찾기에서는 '(미상)' 으로 빠진다 */
  if nullif(btrim(coalesce(v_s->>'name','')),'') is null and nullif(btrim(coalesce(v_q->'cust'->>'name','')),'') is null then
    v_s := v_s || jsonb_build_object('name', '(미상)');
  end if;
  v_q := jsonb_set(v_q, '{meta}', coalesce(v_q->'meta', '{}'::jsonb) || jsonb_build_object('no', v_no, 'version', v_ver, 'issuedAt', v_at));
  r := core.f_quote_store(jsonb_build_object('no', v_no, 'version', v_ver, 'issuedAt', v_at,
                                             'summary', v_s, 'quote', v_q, 'namecard', p_namecard));
  return jsonb_build_object('ok', true, 'no', v_no, 'version', v_ver, 'issuedAt', v_at, 'id', r->'id', 'items', r->'items_received');
end $$;

create or replace function public.fn_quote_page_list(p_code text, p_limit integer default 100) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_quote_page_ok(p_code) then perform pg_sleep(0.7); raise exception '권한이 없습니다' using errcode='42501'; end if;
  return jsonb_build_object('ok', true, 'quotes', coalesce((
    select jsonb_agg(jsonb_build_object(
        'issuedAt', to_char(x.issued_at at time zone 'Asia/Seoul', 'YYYY.MM.DD HH24:MI'),
        'no', x.quote_no, 'version', x.version, 'type', coalesce(x.quote_type,''),
        'name', coalesce(x.customer_name,''), 'phone', coalesce(x.phone,''), 'counselor', coalesce(x.counselor,''),
        'models', coalesce(x.models,''), 'total', coalesce(x.total,0), 'finalP', coalesce(x.final_price,0),
        'multiCount', x.multi_count, 'quote', x.quote) order by x.issued_at desc, x.version desc)
      from (select * from crm.quote order by issued_at desc, version desc
             limit least(greatest(coalesce(p_limit,100),1), 300)) x), '[]'::jsonb));
end $$;

create or replace function public.fn_quote_page_get(p_code text, p_no text) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v crm.quote;
begin
  if not core.f_quote_page_ok(p_code) then perform pg_sleep(0.7); raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into v from crm.quote where quote_no = nullif(btrim(coalesce(p_no,'')),'') order by version desc limit 1;
  if v.id is null then return jsonb_build_object('ok', true, 'quote', null); end if;
  return jsonb_build_object('ok', true, 'quote', v.quote, 'no', v.quote_no, 'version', v.version,
                            'issuedAt', to_char(v.issued_at at time zone 'Asia/Seoul', 'YYYY.MM.DD HH24:MI'));
end $$;

create or replace function public.fn_quote_page_customer(p_code text, p_q text, p_limit integer default 8) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_quote_page_ok(p_code) then perform pg_sleep(0.7); raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_quote_customer_lookup(p_q, p_limit);
end $$;

create or replace function public.fn_quote_page_share(p_code text, p_no text, p_by text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_quote_page_ok(p_code) then perform pg_sleep(0.7); raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_quote_share(p_no, p_by, 180);
end $$;

-- 6) 시트 [견적내역] 거울용 피드 (GAS 가 quote_lookup 키로 15분마다 읽어 없는 (번호,판) 만 붙인다)
create or replace function public.fn_quote_feed(p_key text, p_since timestamptz default null, p_limit integer default 200) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_api_ok('quote_lookup', p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
        'issuedAt', to_char(x.issued_at at time zone 'Asia/Seoul', 'YYYY.MM.DD HH24:MI'), 'no', x.quote_no, 'version', x.version,
        'summary', x.summary, 'quote', x.quote, 'created_at', x.created_at) order by x.created_at, x.version)
      from (select * from crm.quote where p_since is null or created_at > p_since
             order by created_at, version limit least(greatest(coalesce(p_limit,200),1), 500)) x), '[]'::jsonb),
    'server_time', now());
end $$;

revoke all on function public.fn_quote_page_save(text,text,jsonb,jsonb,jsonb), public.fn_quote_page_list(text,integer),
  public.fn_quote_page_get(text,text), public.fn_quote_page_customer(text,text,integer), public.fn_quote_page_share(text,text,text),
  public.fn_quote_feed(text,timestamptz,integer) from public;
grant execute on function public.fn_quote_page_save(text,text,jsonb,jsonb,jsonb), public.fn_quote_page_list(text,integer),
  public.fn_quote_page_get(text,text), public.fn_quote_page_customer(text,text,integer), public.fn_quote_page_share(text,text,text),
  public.fn_quote_feed(text,timestamptz,integer) to anon, authenticated, service_role;

commit;
