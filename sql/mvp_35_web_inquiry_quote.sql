-- mvp_35: 홈페이지 구독문의(GAS) · 구독 견적서(GAS) → Datacenter 이중 적재
create extension if not exists pgcrypto with schema extensions;

-- 1) 서버간 호출용 키 (GAS → Supabase). 해시만 저장.
create table if not exists core.api_key (
  name text primary key, key_hash text not null, note text, created_at timestamptz default now());
insert into core.api_key(name, key_hash, note)
values ('gas_forward', '47839933fcd938ba0c538274e4384be4582ff04891f73b7b8954b1b65aac33c3', 'GAS 구독문의/견적 전달용')
on conflict (name) do update set key_hash = excluded.key_hash;

create or replace function core.f_api_ok(p_name text, p_key text) returns boolean
language sql stable security definer set search_path = pg_catalog, public, extensions as $$
  select exists (select 1 from core.api_key k where k.name = p_name
                 and k.key_hash = encode(extensions.digest(coalesce(p_key,''), 'sha256'), 'hex'));
$$;

-- 2) consult source 확장 (fn_submission_to_consult 가 'web' 을 넣고 있었음)
alter table crm.consult drop constraint if exists consult_source_check;
alter table crm.consult add constraint consult_source_check
  check (source in ('ecount_prospect','portal_form','web_inquiry','store','godo','web','web_subscription'));

-- 3) 구독문의 접수 (GAS doPost 에서 호출)
create or replace function public.fn_submit_inquiry(p_key text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_name text := left(nullif(trim(p_data->>'customerName'),''), 40);
  v_phone text := nullif(regexp_replace(coalesce(p_data->>'phone',''), '\D', '', 'g'),'');
  v_staff text := nullif(trim(p_data->>'assignedStaff'),'');
  v_ts timestamptz := coalesce(core.f_ts(p_data->>'timestamp'), now());
  v_type text := coalesce(nullif(p_data->>'inquiryType',''), '구독');
  v_ref text; v_key char(16); v_id bigint; v_hand text; v_result text; v_content text; v_route text;
begin
  if not core.f_api_ok('gas_forward', p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_name is null or v_phone is null then raise exception '고객명/연락처가 없습니다'; end if;
  if v_staff ~* 'test' or v_name ~* 'test|테스트' then return jsonb_build_object('ok', true, 'skipped', 'test'); end if;

  v_hand := (select s.name from core.staff s where s.name = v_staff limit 1);       -- 미배정/미등록 → null
  v_ref := to_char(v_ts at time zone 'Asia/Seoul', 'YYYYMMDDHH24MISS') || '-' || right(v_phone, 4);
  v_result := case p_data->>'result'
                when '상담완료-계약' then '구매완료' when '상담완료-보류' then '보류'
                when '상담거절' then '종료' when '기타' then '종료' else '진행중' end;
  v_route := '홈페이지-' || v_type || case when nullif(p_data->>'referralSource','') is not null
                                          then ' (' || left(p_data->>'referralSource', 60) || ')' else '' end;
  v_content := concat_ws(' / ',
      case when nullif(p_data->>'purchasePurpose','') is not null then '목적: '||(p_data->>'purchasePurpose') end,
      case when nullif(p_data->>'region','') is not null then '지역: '||(p_data->>'region') end,
      case when nullif(p_data->>'contactMethod','') is not null then '희망연락: '||(p_data->>'contactMethod') end,
      case when nullif(p_data->>'existingSubscription','') is not null then '기존구독: '||(p_data->>'existingSubscription') end,
      case when nullif(p_data->>'prepayIntent','') is not null then '선납: '||(p_data->>'prepayIntent') end,
      case when nullif(p_data->>'otherQuoteSource','') is not null and (p_data->>'otherQuoteSource') <> '처음 문의드려요'
           then '타견적: '||(p_data->>'otherQuoteSource') end,
      case when nullif(p_data->>'diagRecommend','') is not null then '진단추천: '||(p_data->>'diagRecommend') end,
      nullif(left(p_data->>'memo', 800), ''));

  v_key := core.f_buyer_key(v_name, v_phone);
  insert into crm.customer (buyer_key, name, phone, region, first_seen_at, last_seen_at, consent_marketing, consent_source, source_channels)
  values (v_key, v_name, v_phone, left(nullif(p_data->>'region',''),60), v_ts, v_ts, false, 'web', array['web_subscription'])
  on conflict (buyer_key) do update set last_seen_at = greatest(crm.customer.last_seen_at, excluded.last_seen_at),
    region = coalesce(crm.customer.region, excluded.region),
    source_channels = (select array_agg(distinct x) from unnest(crm.customer.source_channels || excluded.source_channels) x);

  insert into crm.consult (source, source_ref, consult_at, handler, customer_name, phone, buyer_key, inflow_route,
    interest_category, membership_status, result, content, notes, consent_marketing, raw_payload)
  values ('web_subscription', v_ref, v_ts, v_hand, v_name, v_phone, v_key, v_route,
    left(nullif(p_data->>'modelName',''), 200), nullif(p_data->>'membershipStatus',''), v_result, v_content,
    nullif(concat_ws(' · ', case when nullif(p_data->>'giftConsult','') is not null then '상담사은품 '||(p_data->>'giftConsult') end,
                            case when nullif(p_data->>'giftPaid','') is not null then '결제사은품 '||(p_data->>'giftPaid') end), ''),
    false, p_data)
  on conflict (source, source_ref) do update set
    handler = coalesce(excluded.handler, crm.consult.handler),
    result = case when p_data ? 'result' then excluded.result else crm.consult.result end,
    notes = coalesce(excluded.notes, crm.consult.notes),
    content = coalesce(excluded.content, crm.consult.content),
    raw_payload = excluded.raw_payload, updated_at = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'ref', v_ref, 'handler', v_hand, 'result', v_result);
end $$;
revoke all on function public.fn_submit_inquiry(text, jsonb) from public;
grant execute on function public.fn_submit_inquiry(text, jsonb) to anon, authenticated, service_role;

-- 4) 구독 견적서
create table if not exists crm.quote (
  id bigserial primary key,
  quote_no text not null, version int not null default 1,
  issued_at timestamptz not null default now(),
  counselor text, quote_type text,
  customer_name text, phone text, buyer_key char(16),
  region text, models text, item_count int, multi_count int,
  total numeric, benefit numeric, final_price numeric, monthly numeric, real_monthly numeric,
  prepay_amount numeric, card text, memo text,
  summary jsonb, quote jsonb,
  created_at timestamptz default now(), updated_at timestamptz default now(),
  unique (quote_no, version));
create index if not exists quote_buyer_key_idx on crm.quote(buyer_key);
create index if not exists quote_issued_idx on crm.quote(issued_at desc);
alter table crm.quote enable row level security;

create or replace function public.fn_submit_quote(p_key text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public as $$
declare s jsonb := coalesce(p_data->'summary', '{}'::jsonb);
        v_no text := nullif(trim(p_data->>'no'),''); v_ver int := coalesce((p_data->>'version')::int, 1);
        v_name text := left(nullif(trim(s->>'name'),''), 40);
        v_phone text := nullif(regexp_replace(coalesce(s->>'phone',''), '\D', '', 'g'),'');
        v_ts timestamptz := coalesce(core.f_ts(p_data->>'issuedAt'), now());
        v_key char(16); v_id bigint; v_hand text;
begin
  if not core.f_api_ok('gas_forward', p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_no is null then raise exception '견적번호가 없습니다'; end if;
  if v_name ~* 'test|테스트' then return jsonb_build_object('ok', true, 'skipped', 'test'); end if;
  v_hand := (select st.name from core.staff st where st.name = nullif(trim(s->>'counselor'),'') limit 1);
  v_key := core.f_buyer_key(v_name, v_phone);
  if v_key is not null then
    insert into crm.customer (buyer_key, name, phone, address, first_seen_at, last_seen_at, consent_marketing, consent_source, source_channels)
    values (v_key, v_name, v_phone, left(nullif(s->>'addr',''),200), v_ts, v_ts, false, 'quote', array['quote'])
    on conflict (buyer_key) do update set last_seen_at = greatest(crm.customer.last_seen_at, excluded.last_seen_at),
      address = coalesce(crm.customer.address, excluded.address),
      source_channels = (select array_agg(distinct x) from unnest(crm.customer.source_channels || excluded.source_channels) x);
  end if;
  insert into crm.quote (quote_no, version, issued_at, counselor, quote_type, customer_name, phone, buyer_key, region, models,
    item_count, multi_count, total, benefit, final_price, monthly, real_monthly, prepay_amount, card, memo, summary, quote)
  values (v_no, v_ver, v_ts, coalesce(v_hand, nullif(trim(s->>'counselor'),'')), nullif(s->>'type',''), v_name, v_phone, v_key,
    left(nullif(s->>'addr',''),200), left(nullif(s->>'models',''), 500),
    nullif(s->>'count','')::int, nullif(s->>'multiCount','')::int,
    nullif(s->>'total','')::numeric, nullif(s->>'benefit','')::numeric, nullif(s->>'finalP','')::numeric,
    nullif(s->>'monthly','')::numeric, nullif(s->>'realM','')::numeric, nullif(s->>'prepayAmt','')::numeric,
    nullif(s->>'card',''), left(nullif(s->>'memo',''), 2000), s, p_data->'quote')
  on conflict (quote_no, version) do update set issued_at = excluded.issued_at, counselor = excluded.counselor,
    customer_name = excluded.customer_name, phone = excluded.phone, buyer_key = excluded.buyer_key, region = excluded.region,
    models = excluded.models, item_count = excluded.item_count, multi_count = excluded.multi_count, total = excluded.total,
    benefit = excluded.benefit, final_price = excluded.final_price, monthly = excluded.monthly, real_monthly = excluded.real_monthly,
    prepay_amount = excluded.prepay_amount, card = excluded.card, memo = excluded.memo, summary = excluded.summary,
    quote = excluded.quote, updated_at = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'no', v_no, 'version', v_ver);
end $$;
revoke all on function public.fn_submit_quote(text, jsonb) from public;
grant execute on function public.fn_submit_quote(text, jsonb) to anon, authenticated, service_role;

-- 5) 조회: 관리자 견적 목록 (로그인 필요)
create or replace function public.fn_quote_list(p_from date, p_to date, p_q text default null, p_limit int default 200)
returns table (id bigint, quote_no text, version int, issued_at timestamptz, counselor text, quote_type text,
  customer_name text, phone text, models text, item_count int, multi_count int, total numeric, benefit numeric,
  final_price numeric, monthly numeric, card text, memo text, buyer_key char(16))
language sql stable security definer set search_path = pg_catalog, public as $$
  select q.id, q.quote_no, q.version, q.issued_at, q.counselor, q.quote_type, q.customer_name, q.phone, q.models,
         q.item_count, q.multi_count, q.total, q.benefit, q.final_price, q.monthly, q.card, q.memo, q.buyer_key
  from crm.quote q
  where core.f_role() <> 'anon'
    and (q.issued_at at time zone 'Asia/Seoul')::date between p_from and p_to
    and (p_q is null or p_q = '' or q.customer_name ilike '%'||p_q||'%' or q.quote_no ilike '%'||p_q||'%'
         or q.models ilike '%'||p_q||'%' or q.counselor ilike '%'||p_q||'%' or q.phone like '%'||regexp_replace(p_q,'\D','','g')||'%')
  order by q.issued_at desc limit greatest(1, least(p_limit, 1000));
$$;
revoke all on function public.fn_quote_list(date, date, text, int) from public;
grant execute on function public.fn_quote_list(date, date, text, int) to authenticated;

-- 6) 조회: 매장 담당자 내 견적 (PIN)
create or replace function public.fn_store_quotes(p_code text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_me text := core.f_staff(p_code);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', q.id, 'no', q.quote_no, 'ver', q.version, 'at', q.issued_at, 'name', q.customer_name,
      'phone', case when q.phone is null then null else left(q.phone,3)||'-****-'||right(q.phone,4) end,
      'tel', q.phone, 'models', q.models, 'final', q.final_price, 'monthly', q.monthly, 'items', q.item_count,
      'key', q.buyer_key, 'memo', left(q.memo, 120)) order by q.issued_at desc), '[]'::jsonb)
    from (select distinct on (quote_no) * from crm.quote
          where counselor = v_me and issued_at >= now() - interval '90 days'
          order by quote_no, version desc) q);
end $$;
revoke all on function public.fn_store_quotes(text) from public;
grant execute on function public.fn_store_quotes(text) to anon, authenticated;
