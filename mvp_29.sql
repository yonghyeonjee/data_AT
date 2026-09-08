create or replace function public.fn_store_report(p_code text, p_mode text default 'day', p_from date default null, p_to date default null, p_handler text default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $fn$
declare v_me text := core.f_staff(p_code);
        v_mode text := case when p_mode in ('day','week','month') then p_mode else 'day' end;
        v_to date := coalesce(p_to, (now() at time zone 'Asia/Seoul')::date);
        v_from date;
        r jsonb;
begin
  v_from := coalesce(p_from, case v_mode when 'month' then (date_trunc('month', v_to) - interval '5 months')::date
                                         when 'week'  then v_to - 55 else v_to - 13 end);
  if v_to - v_from > 400 then raise exception '조회 기간은 400일 이내로 해주세요'; end if;
  with o as (
    select (order_at at time zone 'Asia/Seoul')::date d, handler, sale_kind, status, gross_amount, refund_amount, product_name_raw, buyer_name_raw, id
    from core.orders
    where source = 'store' and order_at >= core.f_kst(v_from) and order_at < core.f_kst(v_to + 1)
      and (p_handler is null or p_handler = '' or handler = p_handler)),
  b as (
    select case v_mode when 'month' then to_char(d,'YYYY-MM') when 'week' then to_char(date_trunc('week', d),'YYYY-MM-DD') else to_char(d,'YYYY-MM-DD') end p,
           coalesce(handler,'(미지정)') h, sale_kind, status, gross_amount, refund_amount, product_name_raw, buyer_name_raw, d, id from o)
  select jsonb_build_object(
    'me', v_me, 'mode', v_mode, 'from', v_from, 'to', v_to,
    'total', (select jsonb_build_object('cnt', count(*), 'gross', coalesce(sum(gross_amount),0), 'refund', coalesce(sum(refund_amount),0),
                'open', count(*) filter (where status='매출'), 'done', count(*) filter (where status='판매완료')) from b),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('p', p, 'h', h, 'cnt', cnt, 'gross', gross, 'refund', refund,
                'lump', lump, 'sub', sub, 'direct', direct, 'open', open) order by p desc, gross desc), '[]'::jsonb)
             from (select p, h, count(*) cnt, sum(gross_amount) gross, sum(refund_amount) refund,
                          sum(gross_amount) filter (where sale_kind='일시불') lump,
                          sum(gross_amount) filter (where sale_kind='구독') sub,
                          sum(gross_amount) filter (where sale_kind='직판') direct,
                          count(*) filter (where status='매출') open
                   from b group by p, h) t),
    'by_handler', (select coalesce(jsonb_agg(jsonb_build_object('h', h, 'cnt', cnt, 'gross', gross, 'open', open) order by gross desc), '[]'::jsonb)
                   from (select h, count(*) cnt, sum(gross_amount) gross, count(*) filter (where status='매출') open from b group by h) t),
    'by_period', (select coalesce(jsonb_agg(jsonb_build_object('p', p, 'cnt', cnt, 'gross', gross) order by p), '[]'::jsonb)
                  from (select p, count(*) cnt, sum(gross_amount) gross from b group by p) t),
    'lines', case when v_mode = 'day' then (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'd', d, 'h', h, 'kind', sale_kind, 'status', status,
                'product', product_name_raw, 'gross', gross_amount,
                'customer', case when buyer_name_raw is null or buyer_name_raw = '' then '-' else left(buyer_name_raw,1)||'*'||right(buyer_name_raw,1) end)
                order by d desc, h, id), '[]'::jsonb) from (select * from b order by d desc, id desc limit 200) t) else '[]'::jsonb end
  ) into r;
  return r;
end
$fn$;
revoke all on function public.fn_store_report(text,text,date,date,text) from public;
grant execute on function public.fn_store_report(text,text,date,date,text) to anon, authenticated, service_role;

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
                       from crm.consult k where k.buyer_key = c.buyer_key order by k.consult_at desc limit 1)
    ) x
    from crm.customer c
    where (c.name ilike '%'||v_q||'%')
       or (length(v_d) >= 4 and c.phone like '%'||v_d||'%')
    order by c.last_seen_at desc nulls last
    limit 10) s);
end
$fn$;
revoke all on function public.fn_store_customer_search(text,text) from public;
grant execute on function public.fn_store_customer_search(text,text) to anon, authenticated, service_role;
