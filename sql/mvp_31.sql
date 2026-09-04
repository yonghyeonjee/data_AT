-- ═══ mvp_31 : 담당자 화면 — 콜백 약속 · 내 고객 · 고객 이력 · 재구매 표시 · 상품명 자동완성
alter table crm.consult add column if not exists callback_at timestamptz, add column if not exists callback_done_at timestamptz;
create index if not exists consult_callback_idx on crm.consult (handler, callback_at) where callback_at is not null and callback_done_at is null;

-- 상담 저장: 콜백 예정 포함
create or replace function public.fn_store_consult_submit(p_code text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $fn$
declare
  v_me text := core.f_staff(p_code);
  v_key char(16); v_id bigint; v_ref text; v_hand text;
  v_name text := nullif(trim(p_data->>'customer_name'), '');
  v_phone text := nullif(trim(p_data->>'customer_phone'), '');
  v_link char(16) := nullif(trim(p_data->>'buyer_key'),'');
  v_cb timestamptz := core.f_ts(p_data->>'callback_at');
begin
  if v_link is not null then
    if not exists (select 1 from crm.customer c where c.buyer_key = v_link) then raise exception '선택한 고객을 찾을 수 없습니다'; end if;
    if v_name is null then select c.name into v_name from crm.customer c where c.buyer_key = v_link; end if;
  end if;
  if v_name is null then raise exception '고객명은 필수입니다'; end if;
  v_hand := coalesce(nullif(p_data->>'handler',''), v_me);
  if v_hand <> v_me and not exists (select 1 from core.staff s where s.name = v_hand and s.active) then
    raise exception '등록되지 않은 담당자입니다: %', v_hand;
  end if;
  if v_link is not null then
    v_key := v_link;
    update crm.customer set last_seen_at = now(),
      consent_marketing = consent_marketing or coalesce((p_data->>'consent_marketing')::boolean,false)
    where buyer_key = v_link;
  else
    v_key := core.f_buyer_key(v_name, v_phone);
    if v_key is not null then
      insert into crm.customer (buyer_key, name, phone, first_seen_at, last_seen_at, consent_marketing, consent_source, source_channels)
      values (v_key, v_name, nullif(regexp_replace(coalesce(v_phone,''), '\D', '', 'g'),''), now(), now(),
              coalesce((p_data->>'consent_marketing')::boolean, false), 'store', array['store_consult'])
      on conflict (buyer_key) do update set last_seen_at = now(),
        consent_marketing = crm.customer.consent_marketing or excluded.consent_marketing;
    end if;
  end if;
  v_ref := 'SC' || to_char(now(),'YYMMDD') || '-' || lpad(nextval('crm.consult_id_seq')::text, 6, '0');
  insert into crm.consult (source, source_ref, consult_at, handler, customer_name, phone, buyer_key,
    inflow_route, interest_category, interest_model_code, result, expected_amount, expected_purchase_date,
    consent_marketing, content, notes, callback_at)
  values ('store', v_ref, coalesce((p_data->>'consult_at')::timestamptz, now()), v_hand, v_name, v_phone, v_key,
    nullif(p_data->>'inflow_route',''), nullif(p_data->>'interest_category',''),
    nullif(upper(trim(p_data->>'interest_model_code')),''), coalesce(nullif(p_data->>'result',''), '진행중'),
    (p_data->>'expected_amount')::numeric, (p_data->>'expected_purchase_date')::date,
    coalesce((p_data->>'consent_marketing')::boolean, false), nullif(p_data->>'content',''), nullif(p_data->>'notes',''), v_cb)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'ref', v_ref, 'handler', v_hand, 'callback_at', v_cb);
end
$fn$;

-- 콜백 완료 / 미루기
create or replace function public.fn_store_callback(p_code text, p_id bigint, p_action text, p_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $fn$
declare v_me text := core.f_staff(p_code);
begin
  if p_action = 'done' then
    update crm.consult set callback_done_at = now(), updated_at = now(),
      notes = concat_ws(' / ', notes, '콜백 완료 '||to_char(now() at time zone 'Asia/Seoul','MM-DD HH24:MI')||' '||v_me)
    where id = p_id;
  elsif p_action = 'reschedule' then
    if p_at is null then raise exception '새 시간을 지정하세요'; end if;
    update crm.consult set callback_at = p_at, callback_done_at = null, updated_at = now() where id = p_id;
  elsif p_action = 'clear' then
    update crm.consult set callback_at = null, callback_done_at = null, updated_at = now() where id = p_id;
  else raise exception '알 수 없는 동작'; end if;
  return jsonb_build_object('ok', true);
end
$fn$;
revoke all on function public.fn_store_callback(text,bigint,text,timestamptz) from public;
grant execute on function public.fn_store_callback(text,bigint,text,timestamptz) to anon, authenticated, service_role;

-- 매장 상태: 콜백 · 내 고객 · 진행중 상담 · 최근 상품명 추가
create or replace function public.fn_store_status(p_code text, p_store text default '시흥점')
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $fn$
declare v_me text := core.f_staff(p_code); v_now timestamptz := now();
begin
  return jsonb_build_object(
    'me', v_me,
    'staff', (select coalesce(jsonb_agg(s.name order by s.name), '[]'::jsonb) from core.staff s where s.active),
    'today_sales', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'time', to_char(o.created_at at time zone 'Asia/Seoul','HH24:MI'), 'kind', o.sale_kind, 'stage', o.status,
        'product', o.product_name_raw, 'amount', o.gross_amount, 'handler', o.handler,
        'mine', o.handler = v_me,
        'customer', coalesce(left(c.name,1) || '*' || right(c.name,1),
                             left(o.buyer_name_raw,1) || '*' || right(o.buyer_name_raw,1), '-'))
        order by o.created_at desc), '[]'::jsonb)
      from core.orders o left join crm.customer c on c.buyer_key = o.buyer_key
      where o.source = 'store' and o.created_at >= (current_date::timestamp at time zone 'Asia/Seoul')),
    'open_sales', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'date', (o.order_at at time zone 'Asia/Seoul')::date, 'kind', o.sale_kind,
        'product', o.product_name_raw, 'amount', o.gross_amount, 'handler', o.handler, 'mine', o.handler = v_me,
        'customer', coalesce(left(c.name,1) || '*' || right(c.name,1),
                             left(o.buyer_name_raw,1) || '*' || right(o.buyer_name_raw,1), '-'))
        order by (o.handler = v_me) desc, o.order_at desc), '[]'::jsonb)
      from (select * from core.orders o where o.source = 'store' and o.status = '매출'
              and o.order_at >= v_now - interval '60 days' order by (o.handler = v_me) desc, o.order_at desc limit 60) o
      left join crm.customer c on c.buyer_key = o.buyer_key),
    'open_count', (select count(*) from core.orders where source='store' and status='매출'),
    -- 콜백 약속: 내 건, 미완료, 지난 14일 ~ 앞으로 30일
    'callbacks', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'ref', k.source_ref, 'at', k.callback_at, 'name', k.customer_name,
        'phone', case when k.phone is null then null else left(regexp_replace(k.phone,'\D','','g'),3)||'-****-'||right(regexp_replace(k.phone,'\D','','g'),4) end,
        'interest', k.interest_category, 'model', k.interest_model_code, 'content', left(k.content, 120), 'result', k.result,
        'overdue', k.callback_at < v_now, 'today', (k.callback_at at time zone 'Asia/Seoul')::date = (v_now at time zone 'Asia/Seoul')::date,
        'expected', k.expected_amount, 'mine', k.handler = v_me, 'handler', k.handler)
        order by k.callback_at), '[]'::jsonb)
      from crm.consult k
      where k.callback_at is not null and k.callback_done_at is null
        and k.callback_at between v_now - interval '14 days' and v_now + interval '30 days'
        and (k.handler = v_me or k.handler is null)),
    'callback_today', (select count(*) from crm.consult k where k.handler = v_me and k.callback_done_at is null
        and (k.callback_at at time zone 'Asia/Seoul')::date <= (v_now at time zone 'Asia/Seoul')::date and k.callback_at is not null),
    -- 진행중 상담 (내 건, 최근 90일)
    'my_open_consults', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'ref', k.source_ref, 'at', k.consult_at, 'name', k.customer_name, 'interest', k.interest_category,
        'model', k.interest_model_code, 'expected', k.expected_amount, 'expect_date', k.expected_purchase_date,
        'content', left(k.content, 80), 'route', k.inflow_route, 'callback_at', k.callback_at)
        order by k.consult_at desc), '[]'::jsonb)
      from (select * from crm.consult k where k.handler = v_me and k.result in ('진행중','보류')
              and k.consult_at >= v_now - interval '90 days' order by k.consult_at desc limit 30) k),
    -- 내 고객: 최근 기록의 담당이 나인 고객 (구매·상담 기준), 최근 20명
    'my_customers', (select coalesce(jsonb_agg(jsonb_build_object(
        'key', x.buyer_key, 'name', c.name,
        'phone', case when c.phone is null then null when length(c.phone) >= 10 then left(c.phone,3)||'-****-'||right(c.phone,4) else '***' end,
        'last_at', x.last_at, 'last_what', x.last_what, 'consent', c.consent_marketing,
        'orders', (select count(*) from core.orders o where o.buyer_key = x.buyer_key),
        'spent', (select coalesce(sum(o.gross_amount - o.refund_amount),0) from core.orders o where o.buyer_key = x.buyer_key))
        order by x.last_at desc), '[]'::jsonb)
      from (
        select buyer_key, max(at) last_at, (array_agg(what order by at desc))[1] last_what
        from (
          select o.buyer_key, o.order_at at, o.handler, '구매 '||coalesce(o.product_name_raw,'') what from core.orders o where o.buyer_key is not null and o.handler is not null
          union all
          select k.buyer_key, k.consult_at, k.handler, '상담 '||coalesce(k.interest_category,'') from crm.consult k where k.buyer_key is not null and k.handler is not null
        ) e
        group by buyer_key
        having (array_agg(handler order by at desc))[1] = v_me
        order by max(at) desc limit 20) x
      join crm.customer c on c.buyer_key = x.buyer_key),
    'my_customer_count', (select count(*) from (
        select buyer_key from (
          select o.buyer_key, o.order_at at, o.handler from core.orders o where o.buyer_key is not null and o.handler is not null
          union all
          select k.buyer_key, k.consult_at, k.handler from crm.consult k where k.buyer_key is not null and k.handler is not null
        ) e group by buyer_key having (array_agg(handler order by at desc))[1] = v_me) t),
    -- 상품명 자동완성: 매장 입력 최근 180일 상위 40
    'recent_products', (select coalesce(jsonb_agg(p order by n desc), '[]'::jsonb) from (
        select product_name_raw p, count(*) n from core.orders where source='store' and order_at >= v_now - interval '180 days'
        and product_name_raw is not null group by 1 order by 2 desc limit 40) t),
    'today_consults', (select count(*) from crm.consult
      where source = 'store' and created_at >= (current_date::timestamp at time zone 'Asia/Seoul')),
    'unclosed_days', (select coalesce(jsonb_agg(d order by d), '[]'::jsonb) from (
        select gs::date d from generate_series(current_date - 14, current_date - 1, '1 day') gs
        where not exists (select 1 from core.store_daily sd where sd.store = p_store and sd.biz_date = gs::date)) t),
    'closed_recent', (select coalesce(jsonb_agg(jsonb_build_object('d', biz_date, 'net', net) order by biz_date desc), '[]'::jsonb)
      from (select biz_date, sum(sales - refund) net from core.store_daily
            where store = p_store and biz_date >= current_date - 7 group by biz_date) t));
end
$fn$;

-- 고객 찾기: 담당 프로 · 내 고객 여부 · 최근 이력 5건
create or replace function public.fn_store_customer_search(p_code text, p_q text)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $fn$
declare v_me text := core.f_staff(p_code); v_q text := trim(coalesce(p_q,'')); v_d text := regexp_replace(trim(coalesce(p_q,'')), '\D', '', 'g');
begin
  if length(v_q) < 2 then raise exception '2글자 이상 입력하세요'; end if;
  return (select coalesce(jsonb_agg(x order by x->>'last_seen' desc nulls last), '[]'::jsonb) from (
    select jsonb_build_object(
      'key', c.buyer_key, 'name', c.name,
      'phone', case when c.phone is null then null
                    when length(c.phone) >= 10 then left(c.phone,3)||'-****-'||right(c.phone,4) else '***' end,
      'consent', c.consent_marketing, 'channels', c.source_channels, 'region', c.region,
      'last_seen', c.last_seen_at,
      'orders', (select count(*) from core.orders o where o.buyer_key = c.buyer_key),
      'spent', (select coalesce(sum(o.gross_amount - o.refund_amount),0) from core.orders o where o.buyer_key = c.buyer_key),
      'last_product', (select o.product_name_raw from core.orders o where o.buyer_key = c.buyer_key order by o.order_at desc limit 1),
      'last_order_at', (select max(o.order_at) from core.orders o where o.buyer_key = c.buyer_key),
      'consults', (select count(*) from crm.consult k where k.buyer_key = c.buyer_key),
      'last_consult', (select jsonb_build_object('at', k.consult_at, 'handler', k.handler, 'result', k.result, 'interest', k.interest_category, 'ref', k.source_ref)
                       from crm.consult k where k.buyer_key = c.buyer_key order by k.consult_at desc limit 1),
      'handler', (select h from (
          select o.handler h, o.order_at at from core.orders o where o.buyer_key = c.buyer_key and o.handler is not null
          union all select k.handler, k.consult_at from crm.consult k where k.buyer_key = c.buyer_key and k.handler is not null
        ) e order by at desc limit 1),
      'history', (select coalesce(jsonb_agg(h order by (h->>'at') desc), '[]'::jsonb) from (
          select h from (
            select jsonb_build_object('type','구매','at',o.order_at,'handler',o.handler,'title',coalesce(o.product_name_raw,''),
                     'detail', concat_ws(' · ', o.channel_name, o.sale_kind, o.status, (o.gross_amount)::bigint::text||'원'), 'channel', o.channel_type) h, o.order_at at
            from core.orders o where o.buyer_key = c.buyer_key
            union all
            select jsonb_build_object('type','상담','at',k.consult_at,'handler',k.handler,'title',concat_ws(' ', k.interest_category, k.interest_model_code),
                     'detail', concat_ws(' · ', k.result, k.inflow_route, left(k.content,90), case when k.callback_at is not null and k.callback_done_at is null then '콜백 '||to_char(k.callback_at at time zone 'Asia/Seoul','MM-DD HH24:MI') end), 'ref', k.source_ref) h, k.consult_at
            from crm.consult k where k.buyer_key = c.buyer_key
          ) u order by at desc limit 6) t)
    ) x
    from crm.customer c
    where (c.name ilike '%'||v_q||'%')
       or (length(v_d) >= 4 and c.phone like '%'||v_d||'%')
    order by c.last_seen_at desc nulls last
    limit 10) s);
end
$fn$;
