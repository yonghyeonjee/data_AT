-- mvp_123 · 개발 계정(dept='개발')은 '테스트' 숨김 건을 자기 화면에서 본다 — 통계·다른 담당자에게는 여전히 안 보임
--   core.f_staff_is_dev(name)
--   crm.consult_scoped : consult_live 대신 crm.consult 에서 직접, hidden_reason like '테스트%' 이면 개발 계정에게만 통과 (열 순서는 consult_live 와 같게)
--   fn_store_consults_my : crm.consult 직접 읽는 base 조건에 같은 예외 (부분 치환)
--   fn_store_quotes · fn_store_alerts : 개발 계정은 테스트 견적도 봄
create or replace function core.f_staff_is_dev(p_name text) returns boolean language sql stable as $$
  select exists (select 1 from core.staff s where s.name = p_name and s.dept = '개발') $$;
drop view crm.consult_scoped;
create view crm.consult_scoped as
  select k.id, k.source, k.source_ref, k.consult_at, k.handler, k.customer_name, k.phone, k.buyer_key, k.inflow_route, k.interest_category, k.interest_model_code,
         k.purchase_item, k.membership_status, k.result, k.expected_amount, k.expected_purchase_date, k.linked_order_id, k.consent_marketing, k.content, k.notes, k.raw_payload,
         k.created_at, k.updated_at, k.callback_at, k.callback_done_at, k.hidden_at, k.hidden_by, k.hidden_reason, k.gift_name, k.gift_amount,
         k.next_category, k.next_model_code, k.next_expected_date, k.next_note, k.channel_code, k.channel_etc, k.type_code,
         (k.next_model_code is not null or k.next_category is not null) as has_next,
         k.interest_detail, k.method, k.deleted_at, k.deleted_by, k.delete_reason
  from crm.consult k
  where k.deleted_at is null
    and (k.hidden_at is null or (coalesce(k.hidden_reason,'') like '테스트%' and core.f_staff_is_dev(current_setting('dc.me', true))))
    and (core.f_staff_sees_b2b(current_setting('dc.me', true)) or not core.f_consult_is_b2b(k.source, k.channel_code) or k.handler = current_setting('dc.me', true));
do $outer$
declare v_src text; v_args text; n int;
  a_old text := $x$and not core.f_quote_is_test(quote_no, customer_name, counselor)$x$;
  a_new text := $x$and (core.f_staff_is_dev(v_me) or not core.f_quote_is_test(quote_no, customer_name, counselor))$x$;
  b_old text := $x$and not core.f_quote_is_test(s.quote_no, q.customer_name, s.issued_by)$x$;
  b_new text := $x$and (core.f_staff_is_dev(v_me) or not core.f_quote_is_test(s.quote_no, q.customer_name, s.issued_by))$x$;
  c_old text := $x$and k.hidden_at is null
       and k.consult_at >= now$x$;
  c_new text := $x$and (k.hidden_at is null or (coalesce(k.hidden_reason,'') like '테스트%' and core.f_staff_is_dev(v_me)))
       and k.consult_at >= now$x$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_quotes';
  n := (length(v_src)-length(replace(v_src,a_old,'')))/length(a_old); if n <> 1 then raise exception 'quotes 지점 %개', n; end if;
  execute format('create or replace function public.fn_store_quotes(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, a_old, a_new));
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_alerts';
  n := (length(v_src)-length(replace(v_src,b_old,'')))/length(b_old); if n <> 1 then raise exception 'alerts 지점 %개', n; end if;
  execute format('create or replace function public.fn_store_alerts(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, b_old, b_new));
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_consults_my';
  n := (length(v_src)-length(replace(v_src,c_old,'')))/length(c_old); if n <> 1 then raise exception 'consults_my 지점 %개', n; end if;
  execute format('create or replace function public.fn_store_consults_my(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, c_old, c_new));
end $outer$;
