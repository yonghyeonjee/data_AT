-- mvp_174 · 상담 대시보드 → 문의 관리 드릴다운 · 문의 유형(구매 목적) 축 · 문의 관리에 홈페이지·매장 상담·가망고객 포함 (2026-09-22)
--
-- 왜: 관리자 [문의 관리] 의 [홈페이지] 칩이 실제로는 crm.quote(견적서)였고, 진짜 홈페이지 문의(지메일 자동 적재 · homepage_csv/gmail_homepage 198건)와
--     매장 상담(store)·가망고객(ecount_prospect)은 crm.v_inquiry 에 아예 없었다. 상담 대시보드 막대를 누르면 같은 조건으로 문의를 찾는 화면으로 가야 하는데
--     채널·유형·경로 조건이 fn_inquiry_list 에 없었다.
--
-- 1) core.f_consult_purpose(source, type_code, raw_payload, content) — 문의 유형(구매 목적) 한 줄. 구독 폼 purchasePurpose(신규구독·이사·입주·가전교체·혼수·신혼·사업자·B2B…)
--    → 내용의 '목적: ' → 홈페이지 문의 kind(사업자) → 폼(web_b2b 사업자·B2B / web_supply 소모품·렌탈) → 문의 유형 코드(구독·일시불·렌탈·소모품·일반 제품) → '(미기록)'.
--    v_inquiry 와 f_consult_stats 가 같은 함수를 쓰므로 대시보드에서 누른 값이 문의 관리 조건과 글자까지 같다.
-- 2) crm.v_inquiry 다시 만듦 — consult 가지가 모든 source 를 덮는다 (form: homepage·subscribe·supply·b2b·prospect·consult). 견적서는 '견적서', 방문 접수는 전부 'store'.
--    새 열 channel(대시보드 채널과 같은 규칙) · route(유입경로) · hidden(상담 화면에서 숨김·삭제한 건). auto_test 는 hidden_reason '테스트%' 도 본다.
-- 3) fn_inquiry_flag — consult 폼 6개 전부 crm.consult hidden_* 를 같이 바꾼다. 복구는 deleted_at 도 푼다.
-- 4) fn_inquiry_list — p_channel · p_category · p_route · p_purpose 추가 (쉼표 목록, 옛 시그니처 drop → create → grant authenticated,service_role · revoke public,anon).
--    hide_on = 플래그 hidden OR 상담 화면 숨김. 응답 줄에 channel·route, forms 목록 8개.
-- 5) core.f_consult_stats — c CTE 에 purpose, 응답 'purposes'(유형별 문의·구매·금액).
-- 6) 방문 접수(crm.submission) 의 매장방문 아닌 5건은 form 'subscribe' 라 crm.consult id 와 플래그 키가 겹쳤다 → form 'store' 로 옮김.

create or replace function core.f_consult_purpose(p_source text, p_type text, p_raw jsonb, p_content text)
returns text language sql immutable as $$
  select coalesce(
    nullif(btrim(p_raw->>'purchasePurpose'),''),
    nullif(btrim((regexp_match(coalesce(p_content,''), '목적: ([^/]+?)\s*(?:/|$)'))[1]),''),
    case when p_raw->>'kind' = '사업자' then '사업자·B2B' end,
    case p_source when 'web_b2b' then '사업자·B2B' when 'web_supply' then '소모품·렌탈' end,
    case p_type when 'subscribe' then '구독' when 'onetime' then '일시불' when 'rental' then '렌탈' when 'supply' then '소모품' when 'product' then '일반 제품' end,
    '(미기록)')
$$;

create or replace view crm.v_inquiry as
with q as (select distinct on (quote_no) * from crm.quote order by quote_no, version desc)
select 'quote'::text form, '견적서'::text form_label, q.id, q.issued_at at, q.customer_name name, q.phone,
       nullif(q.models,'') kind,
       nullif(concat_ws(' · ', case when q.final_price > 0 then to_char(q.final_price,'FM999,999,999')||'원' end,
                               case when q.monthly > 0 then '월 '||to_char(q.monthly,'FM999,999,999') end,
                               case when q.version > 1 then 'v'||q.version end),'') purpose,
       nullif(q.region,'') region, nullif(q.memo,'') memo, coalesce(q.counselor,'') handler, null::text status,
       q.buyer_key, q.quote_no ref, core.f_looks_test(q.customer_name, q.phone, q.memo, q.counselor) auto_test,
       '견적서'::text channel, null::text route, false hidden
  from q
union all
select 'store', '매장 접수', s.id, s.submitted_at, s.customer_name, s.customer_phone,
       nullif(coalesce(s.product_name, s.request_type, s.visit_purpose),''), nullif(s.visit_purpose,''), null,
       nullif(concat_ws(' · ', nullif(s.message,''), nullif(s.next_product,'')),''), coalesce(s.handler,''), s.status,
       null, coalesce(s.inflow_route, s.channel_type), core.f_looks_test(s.customer_name, s.customer_phone, s.message, s.handler),
       case when s.request_type = '매장방문' then '매장 직접 방문' else '방문 접수' end, nullif(btrim(s.inflow_route),''), false
  from crm.submission s
union all
select case c.source when 'web_b2b' then 'b2b' when 'web_supply' then 'supply' when 'web_subscription' then 'subscribe'
                     when 'gmail_homepage' then 'homepage' when 'homepage_csv' then 'homepage' when 'ecount_prospect' then 'prospect' else 'consult' end,
       case c.source when 'web_b2b' then 'VMS·B2B 문의' when 'web_supply' then '소모품·렌탈 문의' when 'web_subscription' then '구독 문의'
                     when 'gmail_homepage' then '홈페이지 문의' when 'homepage_csv' then '홈페이지 문의' when 'ecount_prospect' then '가망고객' else '매장 상담' end,
       c.id, c.consult_at, c.customer_name, c.phone,
       nullif(coalesce(c.interest_category, c.purchase_item),''),
       core.f_consult_purpose(c.source, c.type_code, c.raw_payload, c.content),
       nullif((regexp_match(coalesce(c.content,''), '지역: ([^/]+?)\s*(?:/|$)'))[1],''),
       nullif(btrim(regexp_replace(regexp_replace(coalesce(c.content,''), '(목적|지역|희망연락|기존구독|선납|타견적|진단추천): [^/]*/?\s*', '', 'g'), '^\s*/\s*|\s*/\s*$', '', 'g')),''),
       coalesce(c.handler,''), c.result, c.buyer_key, c.source_ref,
       (core.f_looks_test(c.customer_name, c.phone, c.content, c.handler) or coalesce(c.hidden_reason,'') like '테스트%'),
       coalesce((select ch.label from core.inq_channel ch where ch.code = c.channel_code), core.f_consult_src(c.source, c.inflow_route), '기타'),
       nullif(btrim(c.inflow_route),''),
       ((c.hidden_at is not null and coalesce(c.hidden_reason,'') not like '테스트%') or c.deleted_at is not null)
  from crm.consult c;

-- 방문 접수 5건의 플래그를 store 로 (consult id 와 겹치던 것)
update crm.inquiry_flag f set form = 'store' where f.form = 'subscribe' and f.src_id in (select id from crm.submission where request_type <> '매장방문')
  and not exists (select 1 from crm.inquiry_flag g where g.form = 'store' and g.src_id = f.src_id);

-- fn_inquiry_flag : consult 폼 6개 · 복구는 deleted_at 도
do $outer$
declare v_src text; v_args text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_inquiry_flag';
  if position('p_form in (''subscribe'',''supply'',''b2b'')' in v_src) = 0 then raise exception 'flag 지점 없음 1'; end if;
  if (length(v_src) - length(replace(v_src, ' and source in (''web_supply'',''web_b2b'',''web_subscription'')', ''))) / length(' and source in (''web_supply'',''web_b2b'',''web_subscription'')') <> 2 then raise exception 'flag 지점 없음 2'; end if;
  v_src := replace(v_src, 'p_form in (''subscribe'',''supply'',''b2b'')', 'p_form in (''subscribe'',''supply'',''b2b'',''homepage'',''prospect'',''consult'')');
  v_src := replace(v_src, ' and source in (''web_supply'',''web_b2b'',''web_subscription'')', '');
  v_src := replace(v_src, 'set hidden_at = null, hidden_by = null, hidden_reason = null where', 'set hidden_at = null, hidden_by = null, hidden_reason = null, deleted_at = null where');
  execute format('create or replace function public.fn_inquiry_flag(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;

-- fn_inquiry_list : 채널·관심·경로·유형 조건 (시그니처 바뀜)
drop function if exists public.fn_inquiry_list(text,text,text,date,date,integer,integer,boolean,text,text);
create or replace function public.fn_inquiry_list(p_form text default null, p_status text default null, p_q text default null, p_from date default null, p_to date default null,
  p_limit integer default 25, p_offset integer default 0, p_unmask boolean default false, p_show text default 'real', p_handler text default null,
  p_channel text default null, p_category text default null, p_route text default null, p_purpose text default null)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $fn$
declare v_role text := core.f_role(); v_total int; v_rows jsonb;
begin
  if v_role = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  drop table if exists pg_temp._iq;
  create temp table _iq on commit drop as
  select v.*, coalesce(f.is_test, v.auto_test) as test_on, (coalesce(f.hidden,false) or v.hidden) as hide_on,
         (f.form is not null) as flagged, f.note as flag_note
    from crm.v_inquiry v
    left join crm.inquiry_flag f on f.form = v.form and f.src_id = v.id
   where (p_form is null or p_form = '' or v.form = any(string_to_array(p_form,',')))
     and (p_status is null or p_status = '' or coalesce(nullif(v.status,''),'(없음)') = any(string_to_array(p_status,',')))
     and (p_handler is null or p_handler = '' or coalesce(nullif(v.handler,''),'(미배정)') = any(string_to_array(p_handler,',')))
     and (p_channel is null or p_channel = '' or v.channel = any(string_to_array(p_channel,',')))
     and (p_route is null or p_route = '' or coalesce(nullif(btrim(v.route),''),'(경로 없음)') = any(string_to_array(p_route,',')))
     and (p_purpose is null or p_purpose = '' or coalesce(v.purpose,'(미기록)') = any(string_to_array(p_purpose,',')))
     and (p_category is null or p_category = '' or coalesce(v.kind,'') ilike '%'||p_category||'%')
     and (p_from is null or v.at >= (p_from::timestamp at time zone 'Asia/Seoul'))
     and (p_to   is null or v.at <  ((p_to + 1)::timestamp at time zone 'Asia/Seoul'))
     and (p_q is null or p_q = '' or v.name ilike '%'||p_q||'%'
          or regexp_replace(coalesce(v.phone,''),'\D','','g') like '%'||regexp_replace(p_q,'\D','','g')||'%'
          or coalesce(v.kind,'') ilike '%'||p_q||'%' or coalesce(v.memo,'') ilike '%'||p_q||'%'
          or coalesce(v.region,'') ilike '%'||p_q||'%' or coalesce(v.purpose,'') ilike '%'||p_q||'%'
          or coalesce(v.handler,'') ilike '%'||p_q||'%' or coalesce(v.ref,'') ilike '%'||p_q||'%');
  if p_show = 'real'   then delete from _iq where test_on or hide_on;
  elsif p_show = 'test' then delete from _iq where not test_on or hide_on;
  elsif p_show = 'hidden' then delete from _iq where not hide_on;
  end if;

  select count(*) into v_total from _iq;
  select coalesce(jsonb_agg(x order by ord desc), '[]'::jsonb) into v_rows from (
    select at ord, jsonb_build_object(
      'form', form, 'form_label', form_label, 'id', id,
      'at', to_char(at at time zone 'Asia/Seoul','MM-DD HH24:MI'),
      'at_full', to_char(at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'),
      'name', case when p_unmask and v_role='admin' then name else regexp_replace(coalesce(name,''),'(?<=.).','*','g') end,
      'phone', case when p_unmask and v_role='admin' then phone
                    else regexp_replace(regexp_replace(coalesce(phone,''),'\D','','g'),'^(\d{3})(\d+)(\d{4})$','\1-****-\3') end,
      'tel', regexp_replace(coalesce(phone,''),'\D','','g'),
      'kind', kind, 'purpose', purpose, 'region', region, 'memo', memo, 'channel', channel, 'route', route,
      'handler', nullif(handler,''), 'status', status, 'ref', ref,
      'is_test', test_on, 'hidden', hide_on, 'flagged', flagged, 'note', flag_note) x
    from _iq order by at desc limit greatest(p_limit,1) offset greatest(p_offset,0)) t;
  if coalesce(p_offset,0) = 0 and p_unmask and v_role = 'admin' then
    insert into crm.access_log (actor, actor_email, action, row_count, reason)
    values (auth.uid(), (select email from public.profiles where id = auth.uid()), 'inquiry_list:unmask', least(v_total,p_limit), '문의 관리');
  end if;
  return jsonb_build_object('rows', v_rows, 'total', v_total, 'show', p_show, 'limit', greatest(p_limit,1),
    'by_form', (select coalesce(jsonb_object_agg(form, n),'{}'::jsonb) from (select form, count(*) n from _iq group by form) f),
    'counts', (select jsonb_build_object(
        'real', count(*) filter (where not test_on and not hide_on),
        'test', count(*) filter (where test_on and not hide_on),
        'hidden', count(*) filter (where hide_on)) from crm.v_inquiry v
        left join crm.inquiry_flag f on f.form=v.form and f.src_id=v.id
        cross join lateral (select coalesce(f.is_test, v.auto_test) test_on, (coalesce(f.hidden,false) or v.hidden) hide_on) z),
    'summary', jsonb_build_object(
      'total', v_total,
      'unassigned', (select count(*) from _iq where coalesce(handler,'') = ''),
      'open', (select count(*) from _iq where coalesce(status,'') in ('접수','진행전','진행중','보류','대기','미처리')),
      'last_at', (select to_char(max(at) at time zone 'Asia/Seoul','MM-DD HH24:MI') from _iq),
      'today', (select count(*) from _iq where (at at time zone 'Asia/Seoul')::date = (now() at time zone 'Asia/Seoul')::date)),
    'facets', jsonb_build_object(
      'channel', (select coalesce(jsonb_agg(jsonb_build_object('k', k, 'n', n) order by n desc),'[]'::jsonb) from (select channel k, count(*) n from _iq group by 1) z),
      'purpose', (select coalesce(jsonb_agg(jsonb_build_object('k', k, 'n', n) order by n desc),'[]'::jsonb) from (select coalesce(purpose,'(미기록)') k, count(*) n from _iq group by 1) z)),
    'forms', (select jsonb_agg(jsonb_build_object('code',code,'label',label) order by ord) from (values
        ('homepage','홈페이지 문의',1),('subscribe','구독 문의',2),('quote','견적서',3),('supply','소모품·렌탈 문의',4),
        ('b2b','VMS·B2B 문의',5),('store','매장 접수',6),('consult','매장 상담',7),('prospect','가망고객',8)) v(code,label,ord)));
end $fn$;
revoke all on function public.fn_inquiry_list(text,text,text,date,date,integer,integer,boolean,text,text,text,text,text,text) from public, anon;
grant execute on function public.fn_inquiry_list(text,text,text,date,date,integer,integer,boolean,text,text,text,text,text,text) to authenticated, service_role;

-- core.f_consult_stats : purpose 열 + purposes 키
do $outer$
declare v_src text; v_args text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core' where p.proname='f_consult_stats';
  if position('coalesce(nullif(btrim(r.inflow_route),''''),''(경로 없음)'') route,' in v_src) = 0 then raise exception 'stats 지점 없음 1'; end if;
  if position('  ), rt as (' in v_src) = 0 then raise exception 'stats 지점 없음 2'; end if;
  if position('    ''routes'', (select' in v_src) = 0 then raise exception 'stats 지점 없음 3'; end if;
  v_src := replace(v_src, 'coalesce(nullif(btrim(r.inflow_route),''''),''(경로 없음)'') route,',
                          'coalesce(nullif(btrim(r.inflow_route),''''),''(경로 없음)'') route,
           core.f_consult_purpose(r.source, r.type_code, r.raw_payload, r.content) purpose,   /* 문의 유형(구매 목적) — mvp_174 */');
  v_src := replace(v_src, '  ), rt as (', '  ), pp as (
    select purpose, count(*) total, count(*) filter (where bought) bought, coalesce(sum(amount) filter (where bought), 0) amount from cs group by purpose
  ), rt as (');
  v_src := replace(v_src, '    ''routes'', (select', '    ''purposes'', (select coalesce(jsonb_agg(jsonb_build_object(''pp'', purpose, ''total'', total, ''bought'', bought, ''amount'', amount,
                 ''rate'', case when total > 0 then round(100.0 * bought / total, 1) else 0 end) order by total desc), ''[]''::jsonb) from pp),
    ''routes'', (select');
  execute format('create or replace function core.f_consult_stats(%s) returns jsonb language plpgsql stable security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;

-- ── 7) UTM 관리 [구매]·[매출] → 통합 원장 : fn_order_list · fn_order_summary 에 p_campaign (수신자의 발송 뒤 주문 · 발송 실패 제외 · 테스트 제외 = fn_utm_campaigns 의 bought 규칙)
--    pg_get_functiondef 로 머리(인자 추가)와 where 한 줄만 치환 → 새 시그니처 create → 옛 시그니처 drop → grant anon,authenticated,service_role (원래 ACL 그대로).
do $outer$
declare v_def text; v_name text;
begin
  foreach v_name in array array['fn_order_list','fn_order_summary'] loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=v_name;
    if position('p_q_field text DEFAULT NULL::text)' in v_def) = 0 then raise exception '% 지점 없음 1', v_name; end if;
    if position('and (p_category is null or p_category = '''' or o.category = p_category)' in v_def) = 0 then raise exception '% 지점 없음 2', v_name; end if;
    v_def := replace(v_def, 'p_q_field text DEFAULT NULL::text)', 'p_q_field text DEFAULT NULL::text, p_campaign text DEFAULT NULL::text)');
    v_def := replace(v_def, 'and (p_category is null or p_category = '''' or o.category = p_category)',
      'and (p_category is null or p_category = '''' or o.category = p_category)
      /* 캠페인 수신자의 발송 뒤 주문 (UTM 관리 [구매] 드릴다운 · mvp_174) — fn_utm_campaigns 의 bought 와 같은 규칙 */
      and (p_campaign is null or p_campaign = '''' or (not coalesce(o.is_test,false) and exists (select 1 from crm.send_log l
           where l.campaign = p_campaign and coalesce(l.status,'''') <> ''failed'' and l.buyer_key = o.buyer_key and o.order_at >= l.sent_at)))');
    execute v_def;
  end loop;
end $outer$;
drop function if exists public.fn_order_list(date,date,text,text,text,integer,integer,boolean,text,text,text,text,text,text);
drop function if exists public.fn_order_summary(date,date,text,text,text,text,text,text,text,text);
grant execute on function public.fn_order_list(date,date,text,text,text,integer,integer,boolean,text,text,text,text,text,text,text) to anon, authenticated, service_role;
grant execute on function public.fn_order_summary(date,date,text,text,text,text,text,text,text,text,text) to anon, authenticated, service_role;

-- ── 8) 문의 관리 facets.purpose 에서 견적서(purpose = 금액 문자열)는 뺀다
do $outer$
declare v_src text; v_args text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_inquiry_list';
  if position('from (select coalesce(purpose,''(미기록)'') k, count(*) n from _iq group by 1) z' in v_src) = 0 then raise exception 'facet 지점 없음'; end if;
  v_src := replace(v_src, 'from (select coalesce(purpose,''(미기록)'') k, count(*) n from _iq group by 1) z', 'from (select coalesce(purpose,''(미기록)'') k, count(*) n from _iq where form <> ''quote'' group by 1) z');
  execute format('create or replace function public.fn_inquiry_list(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;

-- 확인 (2026-09-22 · 롤백 블록 · authenticated 관리자 클레임) : 전체 325 (homepage 198 · subscribe 60 · prospect 32 · quote 16 · consult 16 · b2b 3) · 테스트 58 · 삭제 53
--   p_form=homepage & p_purpose=사업자·B2B → 7 · p_channel=구독 문의 → 60 (유형: 신규구독 22 · 이사·입주 14 · 가전교체 12 · 혼수·신혼 5 · 기타 4 · 사전예약·사업자·B2B·자급제구매 1)
--   f_consult_stats 7~9월 purposes : 일반 제품 101(구매 37) · 신규구독 22 · 이사·입주 15 · 가전교체 12 · 혼수·신혼 5 · 기타 4 · 사업자·B2B 4 · 일시불 2 · (미기록) 2 · 구독 1 …
