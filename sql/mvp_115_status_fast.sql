-- mvp_115 · fn_store_status 로그인 지연 (statement timeout 3s) 해소
-- 원인: '내 고객' 두 조각이 core.orders 16.8만 건을 매번 통째로 group by 함 (443 + 318 ms, 부하 시 2~7 s)
-- 조치: 내 이름이 걸린 이벤트만 먼저 뽑고(ix_order_handler), 그 뒤에 다른 담당자 이벤트가 있으면 제외
--       → 결과 동일, 본문은 두 조각만 치환 (지점 수 검증)
do $outer$
declare v_src text; v_args text; v_new text;
  a_old text := $a$      from (
        select buyer_key, max(at) last_at, (array_agg(what order by at desc))[1] last_what
        from (
          select o.buyer_key, o.order_at at, o.handler, '구매 '||coalesce(o.product_name_raw,'') what from core.orders o where o.buyer_key is not null and o.handler is not null
          union all
          select k.buyer_key, k.consult_at, k.handler, '상담 '||coalesce(k.interest_category,'') from crm.consult_live k where k.buyer_key is not null and k.handler is not null
        ) e
        group by buyer_key
        having (array_agg(handler order by at desc))[1] = v_me
        order by max(at) desc limit 20) x$a$;
  a_new text := $a$      from (
        select m.* from (
          select buyer_key, max(at) last_at, (array_agg(what order by at desc))[1] last_what
          from (
            select o.buyer_key, o.order_at at, '구매 '||coalesce(o.product_name_raw,'') what from core.orders o where o.handler = v_me and o.buyer_key is not null
            union all
            select k.buyer_key, k.consult_at, '상담 '||coalesce(k.interest_category,'') from crm.consult_live k where k.handler = v_me and k.buyer_key is not null
          ) e group by buyer_key) m
        where not exists (select 1 from core.orders o2 where o2.buyer_key = m.buyer_key and o2.handler is not null and o2.handler <> v_me and o2.order_at > m.last_at)
          and not exists (select 1 from crm.consult_live k2 where k2.buyer_key = m.buyer_key and k2.handler is not null and k2.handler <> v_me and k2.consult_at > m.last_at)
        order by m.last_at desc limit 20) x$a$;
  b_old text := $b$    'my_customer_count', (select count(*) from (
        select buyer_key from (
          select o.buyer_key, o.order_at at, o.handler from core.orders o where o.buyer_key is not null and o.handler is not null
          union all
          select k.buyer_key, k.consult_at, k.handler from crm.consult_live k where k.buyer_key is not null and k.handler is not null
        ) e group by buyer_key having (array_agg(handler order by at desc))[1] = v_me) t),$b$;
  b_new text := $b$    'my_customer_count', (select count(*) from (
        select buyer_key, max(at) last_at from (
          select o.buyer_key, o.order_at at from core.orders o where o.handler = v_me and o.buyer_key is not null
          union all
          select k.buyer_key, k.consult_at from crm.consult_live k where k.handler = v_me and k.buyer_key is not null
        ) e group by buyer_key) m
        where not exists (select 1 from core.orders o2 where o2.buyer_key = m.buyer_key and o2.handler is not null and o2.handler <> v_me and o2.order_at > m.last_at)
          and not exists (select 1 from crm.consult_live k2 where k2.buyer_key = m.buyer_key and k2.handler is not null and k2.handler <> v_me and k2.consult_at > m.last_at)),$b$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_store_status';
  if (length(v_src)-length(replace(v_src,a_old,'')))/length(a_old) <> 1 then raise exception 'my_customers 지점 %개', (length(v_src)-length(replace(v_src,a_old,'')))/length(a_old); end if;
  if (length(v_src)-length(replace(v_src,b_old,'')))/length(b_old) <> 1 then raise exception 'my_customer_count 지점 %개', (length(v_src)-length(replace(v_src,b_old,'')))/length(b_old); end if;
  v_new := replace(replace(v_src, a_old, a_new), b_old, b_new);
  execute format('create or replace function public.fn_store_status(%s) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_new);
end $outer$;
