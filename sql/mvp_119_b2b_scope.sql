-- mvp_119 · VMS·B2B 상담은 매장 화면에서 숨긴다 (온라인사업부·개발, 또는 내가 담당인 건만 보임)
--   core.f_consult_is_b2b(source, channel_code)  : source='web_b2b' or channel_code='vms'
--   core.f_staff_sees_b2b(name)                  : core.staff.dept ~* '온라인|개발|B2B|VMS'
--   crm.consult_scoped                           : consult_live + 위 조건. dc.me 는 각 fn_store_* 가 begin 직후 set_config 로 넣는다
--   fn_store_status · consults_my · consults_all · consult_find · my_customers · customer_detail · customer_search
--     → 본문의 crm.consult_live 를 crm.consult_scoped 로 치환 + perform set_config('dc.me', v_me, true)
--   core.f_consult_assign_default (트리거) : web_b2b 는 박은지 프로 고정 배정
--   기존 미완료 B2B/VMS 상담 → 박은지 (notes 에 '2026-09-13 B2B/VMS 담당 박은지로 이관 (이전 …)')
create or replace function core.f_consult_is_b2b(p_source text, p_channel text) returns boolean
language sql immutable as $$ select p_source = 'web_b2b' or p_channel = 'vms' $$;
create or replace function core.f_staff_sees_b2b(p_name text) returns boolean
language sql stable as $$ select exists (select 1 from core.staff s where s.name = p_name and coalesce(s.dept,'') ~* '온라인|개발|B2B|VMS') $$;
create or replace view crm.consult_scoped as
  select k.* from crm.consult_live k
  where core.f_staff_sees_b2b(current_setting('dc.me', true))
     or not core.f_consult_is_b2b(k.source, k.channel_code)
     or k.handler = current_setting('dc.me', true);
do $outer$
declare r record; v_src text; v_args text; v_new text; n int;
begin
  for r in select p.oid, p.proname from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public'
           where p.proname in ('fn_store_status','fn_store_customer_search','fn_store_consults_my','fn_store_consults_all','fn_store_my_customers','fn_store_customer_detail','fn_store_consult_find') loop
    select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p where p.oid=r.oid;
    if position('crm.consult_scoped' in v_src) > 0 then raise exception '% 이미 적용', r.proname; end if;
    if position(E'\nbegin\n' in v_src) = 0 then raise exception '% begin 없음', r.proname; end if;
    v_new := replace(v_src, 'crm.consult_live', 'crm.consult_scoped');
    v_new := overlay(v_new placing E'\nbegin\n  perform set_config(''dc.me'', coalesce(v_me,''''), true);\n' from position(E'\nbegin\n' in v_new) for length(E'\nbegin\n'));
    execute format('create or replace function public.%I(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', r.proname, v_args, v_new);
  end loop;
  select pg_get_functiondef(p.oid) into v_src from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='core' where p.proname='f_consult_assign_default';
  n := (length(v_src)-length(replace(v_src, $x$  if nullif(trim(coalesce(new.handler,'')),'') is not null then return new; end if;$x$,'')))/length($x$  if nullif(trim(coalesce(new.handler,'')),'') is not null then return new; end if;$x$);
  if n <> 1 then raise exception 'assign_default 지점 %개', n; end if;
  execute replace(v_src, $x$  if nullif(trim(coalesce(new.handler,'')),'') is not null then return new; end if;$x$,
                         $x$  if nullif(trim(coalesce(new.handler,'')),'') is not null then return new; end if;
  if new.source = 'web_b2b' then new.handler := '박은지'; return new; end if;   -- B2B 는 온라인사업부 박은지 프로$x$);
end $outer$;
update crm.consult c set handler='박은지', notes=concat_ws(' · ', nullif(c.notes,''), '2026-09-13 B2B/VMS 담당 박은지로 이관 (이전 '||coalesce(c.handler,'미배정')||')'), updated_at=now()
 where c.hidden_at is null and c.deleted_at is null and core.f_consult_is_b2b(c.source, c.channel_code)
   and core.f_consult_bucket(c.result) in ('open','hold') and coalesce(c.handler,'') <> '박은지';
