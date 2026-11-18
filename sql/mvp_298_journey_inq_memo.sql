-- mvp_298 · 2026-11-17 · 고객 흐름 문의 줄에 고객 메모 (DB 에 적용됨)
-- "store 개별 상담에는 채널은 자세히 안 나와도 돼 · 대신 문의할 때 메모 내용은 보여줘야지"
-- core.f_customer_journey 의 문의·상담 이벤트 x 에 'memo'(raw_payload.memo · 1000자) 를 더한다.
-- 요약 줄(s)은 그대로(content 90자) — 관리자 화면은 지금처럼 본다.
-- 담당자 화면(store.html · store/test)은 유입 경로·캠페인 태그를 빼고 메모를 '문의 메모' 상자로 전부 보이며,
-- 요약 줄 끝에 잘려 붙은 메모 앞부분은 떼어 낸다.
do $outer$
declare v_def text; v_old text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core'
   where p.proname='f_customer_journey';
  v_old := $q$'superseded', k.superseded_by,$q$;
  v_new := $q$'memo', left(nullif(btrim(k.raw_payload->>'memo'),''), 1000), 'superseded', k.superseded_by,$q$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception '지점 개수 %', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $outer$;
