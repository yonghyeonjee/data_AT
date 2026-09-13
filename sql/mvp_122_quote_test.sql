-- mvp_122 · 테스트 견적서를 담당자 화면(견적서 탭·홈 찾기·알림 내역)에서 뺀다
--   core.f_quote_is_test(quote_no, name, counselor) : 문의 관리에서 숨김/테스트 플래그 | 이름이 테스트 패턴 | 담당이 개발 계정
--   fn_store_quotes · fn_store_alerts 의 where 에 한 조건씩 부분 치환 (지점 1개 확인)
--   아직 플래그 없던 테스트 견적(홍길동·지용현·이순신·김철수·ㅇㅇㅇㅇ·wdsdsds 등)도 crm.inquiry_flag 에 hidden+is_test 로 올렸다 (20개 id)
create or replace function core.f_quote_is_test(p_quote_no text, p_name text, p_counselor text) returns boolean
language sql stable as $$
  select exists (select 1 from crm.inquiry_flag f join crm.quote q on q.id = f.src_id where f.form='quote' and q.quote_no = p_quote_no and (f.hidden or f.is_test))
      or coalesce(p_name,'') ~* '홍길동|이순신|지용현|테스트|test|^[ㄱ-ㅎㅏ-ㅣ]+$|^[0-9]+$'
      or exists (select 1 from core.staff s where s.name = p_counselor and s.dept = '개발')
$$;
insert into crm.inquiry_flag (form, src_id, is_test, hidden, note, updated_by)
select 'quote', q.id, true, true, '테스트 일괄 숨김 (견적서) 2026-09-13', '지용현' from crm.quote q
 where (q.customer_name ~* '홍길동|이순신|지용현|테스트|test|^[ㄱ-ㅎㅏ-ㅣ]+$|^[0-9]+$' or q.models ~* 'wdsdsds' or q.counselor in (select name from core.staff where dept='개발'))
on conflict (form, src_id) do update set is_test=true, hidden=true;
do $outer$
declare v_src text; v_args text; n int;
  a_old text := $x$where counselor = v_me and issued_at >= now() - interval '90 days'$x$;
  a_new text := $x$where counselor = v_me and issued_at >= now() - interval '90 days' and not core.f_quote_is_test(quote_no, customer_name, counselor)$x$;
  b_old text := $x$where (v_mgr or s.issued_by = v_me) and s.created_at >= now() - interval '90 days'$x$;
  b_new text := $x$where (v_mgr or s.issued_by = v_me) and s.created_at >= now() - interval '90 days' and not core.f_quote_is_test(s.quote_no, q.customer_name, s.issued_by)$x$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_quotes';
  n := (length(v_src)-length(replace(v_src,a_old,'')))/length(a_old); if n <> 1 then raise exception 'quotes 지점 %개', n; end if;
  execute format('create or replace function public.fn_store_quotes(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, a_old, a_new));
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_alerts';
  n := (length(v_src)-length(replace(v_src,b_old,'')))/length(b_old); if n <> 1 then raise exception 'alerts 지점 %개', n; end if;
  execute format('create or replace function public.fn_store_alerts(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, b_old, b_new));
end $outer$;
