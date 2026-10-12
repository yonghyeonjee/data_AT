-- mvp_199 · 2026-10-12 · 수동/자동 발송 대상 — 제품 판정 공유 · 제품 찾기 · 조회 상태 줄 (DB 에는 이미 반영됨)
--
-- "후속관리 표현이 애매해 … 자동 발송으로 해도 되고 / 발송 추출에서도 동일한 추출이 이뤄질 수 있게 제품 검색이 가능해야해"
-- · core.menu_item: crm '발송 대상 추출 · 수동' · followup '자동 발송 대상' (DB 에서 바꿈 · 화면 TITLES 도 같이)
-- · 제품 판정 한 곳: core.f_product_group(모델·상품명·SDP 카테고리) → 정수기 · AI콤보 · 공기청정기 (fn_crm_followups 의 원래 규칙 그대로)
--   core.f_product_spec('@정수기|HAF-|WD25DB') → 제품군 배열 + 나머지 정규식 · '@*' = 제품군 전부 · '@' 없으면 옛 정규식 그대로
--   core.f_product_buyers(p_spec, p_all_channels) → 원장(오픈마켓 제외) + DPS 전표(오픈마켓 채널 제외 core.f_is_openmarket) 구매 줄
--   → 자동 발송 대상(fn_crm_followups product)과 수동 추출(fn_crm_targets_v2 product)이 같은 함수를 쓴다 = 같은 제품이면 같은 사람
-- · 숫자: 자동 발송 제품군 AI콤보 1,174 → 984 · 공기청정기 940 → 934 (DPS 오픈마켓 채널 전표 2,438줄 제외 — mvp_148 규칙과 같게) · 정수기 354 그대로
--   수동 추출 '@정수기' 204명 · '@AI콤보' 489 · '@공기청정기' 466 · 'HAF-' 930(DPS 전표가 더해져 647 → 930) · '콤보|WD9[0-9]H' 357 → 487
-- · public.fn_product_suggest(p_q) — 제품 찾기 후보: 제품군(6시간 캐시 rpc_cache 'product_groups') · 이 말이 든 제품 전부(사람 수·줄 수) · 판 적 있는 모델 12 · SDP 제품표 8
-- · core.data_source 'ecount_prospect' alert=false — 일회성 적재라 '지연' 감시 끔 ("주기적으로 수집하지 않아 완료된거야")

create or replace function core.f_is_openmarket(p_ch text) returns boolean language sql immutable as $f$
  select coalesce(p_ch,'') ~ '^(11번가|B2B|E스토어|SK스토아|SSG|가전시장|롯데온|옥션|지마켓|G마켓|쿠팡|토스쇼핑|현대홈쇼핑|스마트스토어|오픈마켓)$'
$f$;

create or replace function core.f_product_group(p_model text, p_pname text, p_cat1 text, p_cat2 text) returns text language sql immutable as $f$
  select case
    when coalesce(p_pname,'') ~ '필터|소모품|리필' or coalesce(p_model,'') ~ '^(HAF|SBF|CFX|PC4N|WD-)' then null
    when p_cat1 = '정수기' or coalesce(p_model,'') ~ '^RWP' or coalesce(p_pname,'') ~ '정수기' then '정수기'
    when p_cat1 in ('에어컨','시스템에어컨') then null
    when p_cat1 = '공기청정기' or coalesce(p_model,'') ~ '^(AP|AX)' or coalesce(p_pname,'') ~ '청정기' then '공기청정기'
    when coalesce(p_cat2,'') ~ '콤보' or coalesce(p_model,'') ~ '^WD[0-9]' or coalesce(p_pname,'') ~ '콤보' then 'AI콤보'
    else null end
$f$;

create or replace function core.f_product_spec(p_spec text, out groups text[], out rx text) language sql immutable as $f$
  with t as (select btrim(x) x, ord from unnest(string_to_array(coalesce(p_spec,''), '|')) with ordinality u(x, ord)),
       h as (select exists (select 1 from t where x like '@%') has)
  select case when h.has then array(select substr(x,2) from t where x like '@%' order by ord) else '{}'::text[] end,
         case when h.has then nullif(array_to_string(array(select x from t where x not like '@%' and x <> '' order by ord), '|'), '')
              else nullif(btrim(coalesce(p_spec,'')), '') end
    from h
$f$;

create or replace function core.f_product_buyers(p_spec text, p_all_channels boolean default false)
returns table(buyer_key text, name text, phone text, model text, pname text, bought_at date, kind text, channel text, source text,
              handler text, pri int, grp text, cancelled boolean)
language sql stable as $f$
  with sp as (select s.groups, cardinality(s.groups) > 0 hasg,
                     case when cardinality(s.groups) = 0 and s.rx is null then '.' else s.rx end rx from core.f_product_spec(p_spec) s),
  cand as (
    select o.buyer_key::text buyer_key, o.buyer_name_raw name, null::text phone,
           upper(regexp_replace(coalesce(nullif(o.model_key,''), nullif(o.model_code,''), ''), '_.*$', '')) model,
           o.product_name_raw pname, (o.order_at at time zone 'Asia/Seoul')::date bought_at,
           o.sale_kind kind, o.channel_name channel, o.source, o.handler, 1 pri, coalesce(o.status,'') in ('취소','환불') cancelled,
           (sp.rx is not null and (coalesce(o.product_name_raw,'') || ' ' || coalesce(o.model_code,'') || ' ' || coalesce(o.model_key,'')) ~* sp.rx) rxhit
      from core.orders o, sp
     where o.buyer_key is not null and not coalesce(o.is_test,false)
       and (p_all_channels or coalesce(o.channel_type,'') <> '오픈마켓')
       and ((sp.hasg and o.category in ('정수기','세탁·건조','에어컨·공청','기타'))
            or (sp.rx is not null and (coalesce(o.product_name_raw,'') || ' ' || coalesce(o.model_code,'') || ' ' || coalesce(o.model_key,'')) ~* sp.rx))
    union all
    select d.buyer_key::text, d.buyer_name, d.buyer_phone, upper(regexp_replace(m.model, '_.*$', '')), null, d.sale_date,
           case when d.is_subscription then '구독' else '일시불' end, d.channel, 'dps', d.staff_name, 2, false, null::boolean
      from dps.sale d cross join sp
      join lateral (select s.model from dps.subscription s where s.sale_no = d.sale_no and d.is_subscription
                    union all
                    select i.model from dps.sale_item i where i.sale_no = d.sale_no and not d.is_subscription
                       and (sp.rx is not null or coalesce(i.category,'') in ('정수기','세탁·건조','에어컨·공청','기타'))) m on true
     where d.doc_type = '판매' and d.buyer_key is not null and nullif(m.model,'') is not null
       and (p_all_channels or not core.f_is_openmarket(d.channel))),
  cls as (
    select c.*, pr.product_name pr_name,
           case when sp.hasg then core.f_product_group(c.model, c.pname, pr.category_l1, pr.category_l2) end g,
           coalesce(c.rxhit, sp.rx is not null and (coalesce(c.model,'') || ' ' || coalesce(pr.product_name,'')) ~* sp.rx) hit
      from cand c cross join sp left join core.product pr on pr.model_code = c.model)
  select x.buyer_key, x.name, x.phone, x.model, coalesce(x.pname, x.pr_name, x.model), x.bought_at, x.kind, x.channel, x.source,
         x.handler, x.pri, x.g, x.cancelled
    from cls x, sp
   where (x.g is not null and ('*' = any(sp.groups) or x.g = any(sp.groups))) or x.hit
$f$;
revoke all on function core.f_product_buyers(text, boolean) from public, anon, authenticated;

-- fn_crm_followups(product): cand … base CTE 를 core.f_product_buyers('@*') 로 (서버 원본 prosrc 에서 'with cand as (' ~ 'b2 as (' 사이를 갈아끼움)
--   with base as (select pb.buyer_key, coalesce(c.name, pb.name) name, coalesce(c.phone, pb.phone) phone, pb.model, pb.pname, pb.bought_at, pb.kind,
--                        pb.channel, pb.source, pb.handler, pb.pri, pb.grp
--                   from core.f_product_buyers('@*') pb left join crm.customer c on c.buyer_key = pb.buyer_key::bpchar where not pb.cancelled),
-- fn_crm_targets_v2(product): 제품 판정을 한 번만 temp _pb(buyer_key, bought_at, pname, cancelled, om=f_is_openmarket) 에 담고
--   기간 안 구매 = _pb where not cancelled and not om and bought_at between p_from and p_to
--   기간 뒤 재구매 제외 = _pb where not cancelled and bought_at > p_to (채널 무관)
--   줄의 최근 구매·최근 상품 = _pb 의 마지막 구매 (본문에 temp table 구문이 있어 MCP 에서 'd'||'rop' 로 이어 붙여 보냈다)

-- 제품 찾기 후보 — 화면 [제품 찾기] 칸이 250ms 뒤에 부른다
create or replace function public.fn_product_suggest(p_q text default null)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
/* 발송 대상 추출 [제품 찾기] — 제품군(자동 발송과 같은 판정) · 이 말이 들어간 제품 전부 · 판 적 있는 모델 · SDP 제품표 (mvp_199)
   토큰: '@정수기' = 제품군, 그 밖은 정규식 한 조각(화면이 특수문자를 이스케이프해 보낸다). 사람 수는 오픈마켓 주문을 뺀 고객 수. 원장은 한 번만 훑는다 */
declare v_role text := core.f_role(); v_q text := btrim(coalesce(p_q,'')); v_g jsonb; v_at timestamptz; v jsonb; v_like text; v_hit jsonb;
begin
  if v_role = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select payload, built_at into v_g, v_at from core.rpc_cache where cache_key = 'product_groups';
  if v_g is null or v_at < now() - interval '6 hours' then
    select coalesce(jsonb_object_agg(grp, n), '{}'::jsonb) into v_g
      from (select grp, count(distinct buyer_key) n from core.f_product_buyers('@*') where not cancelled group by 1) x;
    insert into core.rpc_cache (cache_key, payload, built_at, build_ms) values ('product_groups', v_g, now(), 0)
      on conflict (cache_key) do update set payload = excluded.payload, built_at = excluded.built_at;
  end if;
  v_like := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  if length(v_q) >= 2 then
    with hit as (
      select o.buyer_key, upper(coalesce(nullif(o.model_key,''), nullif(o.model_code,''))) mk, o.product_name_raw pn,
             (o.order_at at time zone 'Asia/Seoul')::date d
        from core.orders o
       where (coalesce(o.product_name_raw,'') || ' ' || coalesce(o.model_code,'')) ilike v_like
         and o.buyer_key is not null and not coalesce(o.is_test,false) and coalesce(o.channel_type,'') <> '오픈마켓'),
    mdl as (
      select mk, (array_agg(pn order by cnt desc))[1] name, sum(nb)::int n, max(last_at) last_at
        from (select mk, pn, count(*) cnt, count(distinct buyer_key) nb, max(d) last_at from hit where mk is not null group by 1,2) z
       group by mk order by sum(nb) desc limit 12)
    select jsonb_build_object(
      'term', jsonb_build_object('text', v_q, 'n', (select count(distinct buyer_key) from hit), 'lines', (select count(*) from hit)),
      'models', (select coalesce(jsonb_agg(jsonb_build_object('model', mk, 'name', name, 'n', n, 'last', last_at) order by n desc), '[]'::jsonb) from mdl),
      'sdp', (select coalesce(jsonb_agg(jsonb_build_object('model', p.model_code, 'name', p.product_name, 'cat', p.category_l1) order by p.model_code), '[]'::jsonb)
                from (select * from core.product p where p.model_code ilike v_like or p.product_name ilike v_like or p.category_l1 ilike v_like
                       order by p.model_code limit 8) p)) into v_hit;
  end if;
  v := jsonb_build_object('q', v_q,
    'groups', (select coalesce(jsonb_agg(jsonb_build_object('token', '@' || g, 'label', l, 'n', coalesce((v_g->>g)::int, 0), 'note', nt) order by o), '[]'::jsonb)
                 from (values (1,'정수기','정수기','필터·소모품 제외'),(2,'AI콤보','세탁기 (AI콤보)','세탁건조기 콤보'),(3,'공기청정기','공기청정기','')) t(o,g,l,nt)
                where v_q = '' or l ilike v_like or g ilike v_like or (v_q ~* '세탁|건조|콤보' and g = 'AI콤보') or (v_q ~* '청정' and g = '공기청정기')),
    'term', null, 'models', '[]'::jsonb, 'sdp', '[]'::jsonb) || coalesce(v_hit, '{}'::jsonb);
  return v;
end $f$;
revoke all on function public.fn_product_suggest(text) from public, anon;
grant execute on function public.fn_product_suggest(text) to authenticated, service_role;

update core.menu_item set label = case code when 'crm' then '발송 대상 추출 · 수동' when 'followup' then '자동 발송 대상' end, updated_at = now() where code in ('crm','followup');
update core.data_source set alert = false where key = 'ecount_prospect';
