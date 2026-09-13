-- mvp_124 · 테스트 이름 견적서도 저장한다 — [고객에게 보내기] notfound 원인
--   fn_submit_quote 가 이름에 test·테스트 가 있으면 저장을 건너뛰어(skipped) crm.quote 에 없었고, fn_quote_share_key 가 notfound 를 돌려줬다.
--   건너뛰는 갈래를 없애고(정규식 치환 1지점), 저장되는 테스트 견적은 트리거 trg_quote_test_flag 가 문의 관리 플래그(hidden+is_test)를 자동으로 붙인다.
--   목록·통계에서는 core.f_quote_is_test 로 빠지고 개발 계정만 본다. share_key 의 실패 사유도 한국어 안내로.
do $outer$
declare v_src text; v_args text; v_new text; n int;
  pat text := $r$if v_name ~\* 'test\|테스트' then\s+return jsonb_build_object\('ok', true, 'skipped', 'test', 'no', v_no, 'version', v_ver\);\s+end if;$r$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_submit_quote';
  select count(*) into n from regexp_matches(v_src, pat, 'g');
  if n <> 1 then raise exception 'submit_quote 지점 %개', n; end if;
  v_new := regexp_replace(v_src, pat, '/* 테스트 이름(test·테스트)도 저장한다 — 목록·통계에서는 core.f_quote_is_test 로 빠지고 개발 계정만 본다. 건너뛰면 [고객에게 보내기]가 notfound 가 난다 */', 'g');
  execute format('create or replace function public.fn_submit_quote(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_new);
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_quote_share_key';
  n := (length(v_src)-length(replace(v_src,$x$'reason', 'notfound'$x$,'')))/length($x$'reason', 'notfound'$x$);
  if n <> 1 then raise exception 'share_key 지점 %개', n; end if;
  execute format('create or replace function public.fn_quote_share_key(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args,
    replace(v_src, $x$'reason', 'notfound'$x$, $x$'reason', '견적서가 아직 저장되지 않았습니다 — [발행 (시트 저장)]을 누른 뒤 다시 보내세요'$x$));
end $outer$;
create or replace function core.f_quote_test_flag() returns trigger language plpgsql as $t$
begin
  if coalesce(new.customer_name,'') ~* '홍길동|이순신|지용현|테스트|test|^[ㄱ-ㅎㅏ-ㅣ]+$|^[0-9]+$'
     or exists (select 1 from core.staff s where s.name = new.counselor and s.dept = '개발') then
    insert into crm.inquiry_flag (form, src_id, is_test, hidden, note, updated_by)
    values ('quote', new.id, true, true, '테스트 이름 자동 표시', coalesce(new.counselor,'system'))
    on conflict (form, src_id) do nothing;
  end if;
  return new;
end $t$;
drop trigger if exists trg_quote_test_flag on crm.quote;
create trigger trg_quote_test_flag after insert on crm.quote for each row execute function core.f_quote_test_flag();
