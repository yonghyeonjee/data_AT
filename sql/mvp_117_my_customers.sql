-- mvp_117 · 담당자 화면 [내 고객] 개편
--   fn_store_my_customers : 내가 상담·판매한 고객 목록 — 마지막 상태·상담 횟수·지난 날짜·마지막 채널, 검색어·기간·채널 조건
--   fn_store_customer_detail : 고객 한 명의 상담 이력 + 구매 이력 (아코디언)
-- 새 함수라 create 만. 권한은 fn_store_customer_search 와 같게 (anon·authenticated·service_role)

create or replace function public.fn_store_my_customers(
  p_code text, p_q text default null, p_from date default null, p_to date default null,
  p_channel text default null, p_limit integer default 100)
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog','public' as $fn$
declare v_me text := core.f_staff(p_code);
  v_q text := trim(coalesce(p_q,'')); v_d text := regexp_replace(trim(coalesce(p_q,'')), '\D', '', 'g');
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  return (select coalesce(jsonb_agg(x order by (x->>'last_at') desc nulls last), '[]'::jsonb) from (
    select jsonb_build_object(
      'key', c.buyer_key, 'name', c.name,
      'phone', case when c.phone is null then null when length(c.phone) >= 10 then left(c.phone,3)||'-****-'||right(c.phone,4) else '***' end,
      'tel', regexp_replace(coalesce(c.phone,''),'\D','','g'),
      'consent', c.consent_marketing,
      'consult_n', k.n, 'last_at', coalesce(k.last_at, o.last_order_at),
      'last_result', k.last_result, 'last_interest', k.last_interest, 'last_channel', k.last_channel, 'last_handler', k.last_handler,
      'days', v_today - (coalesce(k.last_at, o.last_order_at) at time zone 'Asia/Seoul')::date,
      'open_callback', coalesce(k.cb,false),
      'orders', o.n, 'spent', o.spent, 'last_order_at', o.last_order_at, 'last_product', o.last_product) x
    from (
      select k0.buyer_key from crm.consult_live k0 where k0.handler = v_me and k0.buyer_key is not null
      union
      select o0.buyer_key from core.orders o0 where o0.handler = v_me and o0.source = 'store' and o0.buyer_key is not null
    ) b
    join crm.customer c on c.buyer_key = b.buyer_key
    left join lateral (
      select count(*) n, max(k.consult_at) last_at,
        (array_agg(k.result order by k.consult_at desc))[1] last_result,
        (array_agg(k.interest_category order by k.consult_at desc))[1] last_interest,
        (array_agg(coalesce(ch.label, core.f_consult_src(k.source, k.inflow_route)) order by k.consult_at desc))[1] last_channel,
        (array_agg(k.handler order by k.consult_at desc))[1] last_handler,
        bool_or(k.callback_at is not null and k.callback_done_at is null) cb,
        bool_or(k.channel_code = p_channel) ch_hit
      from crm.consult_live k left join core.inq_channel ch on ch.code = k.channel_code
      where k.buyer_key = c.buyer_key
    ) k on true
    left join lateral (
      select count(*) n, coalesce(sum(o.gross_amount - o.refund_amount),0) spent, max(o.order_at) last_order_at,
        (array_agg(o.product_name_raw order by o.order_at desc))[1] last_product
      from core.orders o where o.buyer_key = c.buyer_key
    ) o on true
    where (p_channel is null or p_channel = '' or coalesce(k.ch_hit,false))
      and (v_q = '' or c.name ilike '%'||v_q||'%' or (length(v_d) >= 4 and c.phone like '%'||v_d||'%'))
      and (p_from is null or (coalesce(k.last_at, o.last_order_at) at time zone 'Asia/Seoul')::date >= p_from)
      and (p_to   is null or (coalesce(k.last_at, o.last_order_at) at time zone 'Asia/Seoul')::date <= p_to)
    order by coalesce(k.last_at, o.last_order_at) desc nulls last
    limit greatest(coalesce(p_limit,100),1)) s);
end $fn$;

create or replace function public.fn_store_customer_detail(p_code text, p_key text)
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog','public' as $fn$
declare v_me text := core.f_staff(p_code);
begin
  return jsonb_build_object(
    'consults', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'ref', k.source_ref, 'at', k.consult_at, 'handler', k.handler, 'mine', k.handler = v_me, 'result', k.result,
        'channel', coalesce(ch.label, core.f_consult_src(k.source, k.inflow_route)), 'route', k.inflow_route, 'type', ty.label, 'method', k.method,
        'interest', k.interest_category, 'model', k.interest_model_code, 'detail', k.interest_detail,
        'content', k.content, 'notes', k.notes, 'expected', k.expected_amount, 'expect_date', k.expected_purchase_date,
        'callback_at', k.callback_at, 'callback_done', k.callback_done_at is not null,
        'bought', k.purchase_item, 'next_cat', k.next_category, 'next_model', k.next_model_code, 'next_date', k.next_expected_date, 'gift', k.gift_name)
        order by k.consult_at desc), '[]'::jsonb)
      from crm.consult_live k
      left join core.inq_channel ch on ch.code = k.channel_code
      left join core.inq_type ty on ty.code = k.type_code
      where k.buyer_key = p_key),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'at', o.order_at, 'product', o.product_name_raw, 'amount', o.gross_amount, 'refund', o.refund_amount,
        'status', o.status, 'kind', o.sale_kind, 'channel', o.channel_name, 'handler', o.handler)
        order by o.order_at desc), '[]'::jsonb)
      from (select * from core.orders o where o.buyer_key = p_key order by o.order_at desc limit 20) o));
end $fn$;

grant execute on function public.fn_store_my_customers(text,text,date,date,text,integer) to anon, authenticated, service_role;
grant execute on function public.fn_store_customer_detail(text,text) to anon, authenticated, service_role;
