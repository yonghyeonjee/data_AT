-- mvp_125 · fn_store_consults_my 에 p_filter 'pre'(연락 전 = result 진행전) · 'ing'(상담중 = open 버킷 중 진행전 제외) 와 counts pre/ing
-- 홈 흐름 띠 새 문의 → [연락 전], 내 상담 → [상담중] 칩으로 가서 숫자가 맞게. 부분 치환 4지점(정렬의 v_f in (...) 4곳 포함) × 2회
do $outer$
declare v_src text; v_args text; v_new text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_consults_my';
  if position('''ing''' in v_src) > 0 then raise exception '이미 적용'; end if;
  v_new := replace(v_src, $x$      'open',   count(*) filter (where bucket='open' and v_f <> 'trash'),$x$,
                          $x$      'open',   count(*) filter (where bucket='open' and v_f <> 'trash'),
      'pre',    count(*) filter (where result='진행전' and v_f <> 'trash'),
      'ing',    count(*) filter (where bucket='open' and result<>'진행전' and v_f <> 'trash'),$x$);
  v_new := replace(v_new, $x$count(*) filter (where v_f in ('all','trash') or bucket = v_f) tot$x$,
                          $x$count(*) filter (where v_f in ('all','trash') or bucket = v_f or (v_f = 'pre' and result = '진행전') or (v_f = 'ing' and bucket = 'open' and result <> '진행전')) tot$x$);
  v_new := replace(v_new, $x$where v_f in ('all','trash') or k.bucket = v_f$x$,
                          $x$where v_f in ('all','trash') or k.bucket = v_f or (v_f = 'pre' and k.result = '진행전') or (v_f = 'ing' and k.bucket = 'open' and k.result <> '진행전')$x$);
  v_new := replace(v_new, $x$v_f in ('open','hold')$x$, $x$v_f in ('open','hold','pre','ing')$x$);
  if v_new = v_src then raise exception '지점 없음'; end if;
  execute format('create or replace function public.fn_store_consults_my(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_new);
end $outer$;
