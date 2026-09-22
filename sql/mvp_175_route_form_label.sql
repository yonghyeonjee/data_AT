-- mvp_175 · 유입경로 '홈페이지-…' → '구독 폼…' (2026-09-22)
-- "sh.co.kr 은 구독 form 이라고 하라니까 — samsungat.co.kr > 메일 > 만 홈페이지, 다른 도메인은 쇼핑몰이지 홈페이지도 아니야"
-- fn_submit_inquiry 가 유입경로를 '홈페이지-' || inquiryType || ' (referrer)' 로 만들어 구독 폼(시흥몰·P몰 도메인) 문의가 유입경로 표에 '홈페이지-구독 (www.samsungsh.co.kr)' 로 보였다.
--  · fn_submit_inquiry : v_route := '구독 폼' || (inquiryType 이 '구독' 이 아니면 '-'||inquiryType) || ' (referrer)'  →  '구독 폼 (www.samsungsh.co.kr)' · '구독 폼-혼수·입주·이사 (직접 유입)'
--  · core.form_def route : supply '홈페이지-소모품/렌탈' → '소모품 폼', b2b '홈페이지-B2B' → 'B2B 폼'
--  · core.f_consult_src : source 'web' 라벨 '홈페이지 폼' → '자체 폼'
--  · 옛 줄 정정 : web_subscription 65 · web_supply 4 · web_b2b 4 의 inflow_route 앞머리 치환 (regexp_replace, 뒤 referrer 그대로)
--  · 화면 : 관리자 상담 목록 SRC 라벨 web_subscription '홈페이지 구독문의' → '구독 폼', web '홈페이지' → '자체 폼', gmail_homepage/homepage_csv '홈페이지 문의'
do $outer$
declare v_src text; v_args text; v_a text := 'v_route := ''홈페이지-'' || v_type || case when';
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_submit_inquiry';
  if (length(v_src)-length(replace(v_src, v_a, '')))/length(v_a) <> 1 then raise exception 'submit 지점 없음'; end if;
  v_src := replace(v_src, v_a, '/* 자체 폼(쇼핑몰 도메인) 이지 홈페이지가 아니다 — 홈페이지 = samsungat.co.kr 문의 메일뿐 (mvp_175) */
  v_route := ''구독 폼'' || case when v_type <> ''구독'' then ''-'' || v_type else '''' end || case when');
  execute format('create or replace function public.fn_submit_inquiry(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core' where p.proname='f_consult_src';
  if position('when ''web''              then ''홈페이지 폼''' in v_src) = 0 then raise exception 'src 지점 없음'; end if;
  v_src := replace(v_src, 'when ''web''              then ''홈페이지 폼''', 'when ''web''              then ''자체 폼''');
  execute format('create or replace function core.f_consult_src(%s) returns text language sql immutable as %L', v_args, v_src);
end $outer$;
update core.form_def set route = case code when 'supply' then '소모품 폼' when 'b2b' then 'B2B 폼' else route end where code in ('supply','b2b');
update crm.consult set inflow_route = regexp_replace(regexp_replace(inflow_route, '^홈페이지-구독', '구독 폼'), '^홈페이지-', '구독 폼-')
 where source = 'web_subscription' and inflow_route like '홈페이지-%';
update crm.consult set inflow_route = regexp_replace(inflow_route, '^홈페이지-소모품/렌탈', '소모품 폼') where source = 'web_supply' and inflow_route like '홈페이지-%';
update crm.consult set inflow_route = regexp_replace(inflow_route, '^홈페이지-B2B', 'B2B 폼') where source = 'web_b2b' and inflow_route like '홈페이지-%';
-- 결과 : 구독 폼 45 · 구독 폼 (www.samsungsh.co.kr) 3 · 구독 폼 (samsungpmall.com) 3 · 구독 폼-혼수·입주·이사 (www.samsungsh.co.kr) 4 · … · 소모품 폼 4 · B2B 폼 4
