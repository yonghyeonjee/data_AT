-- mvp_187 · 2026-10-06 · 일 마감·월 마감이 '판매완료' 만 더하던 것 → 매출(확정 전 포함)
-- 결정: 매출과 판매완료(확정)를 가르지 않고 전부 매출로 센다 — 대시보드(mvp_154 · 9/17) 와 같은 규칙.
-- 증상: 차효범 프로님 월 마감(10월) 이 날마다 0원. 9/14 에 일 마감의 판매완료 입력칸을 숨긴 뒤(판매 입력에서 자동으로 오게)
--       직원이 적는 금액은 전부 pending_sales(미확정) 로 들어갔는데, 월 마감·최근 마감 net 은 sales − refund 만 더했다.
--       9/14 이후 store_daily 에 sales 가 있는 줄은 9/21 직판 196만 하나(판매 입력에서 자동).
-- ① fn_store_month_close : sum(sales) ×9 → sum(sales + pending_sales) · sum(sales - refund) ×1 → sum(sales + pending_sales - refund)
--    응답 키는 그대로(sales·lump·sub·direct·net 이 확정 전 포함, pending 은 그중 확정 전 분).
-- ② fn_store_status closed_recent·closed_mine 의 net ×2 → sum(sales + pending_sales - refund) (pending 키 그대로).
-- fn_store_daily_prefill 은 그대로(sales·pending·refund 를 따로 주고 화면이 더한다). 시그니처·ACL 그대로(create or replace).
do $outer$
declare v_src text; v_args text; n int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_month_close';
  n := (length(v_src)-length(replace(v_src,'sum(sales)','')))/length('sum(sales)'); if n <> 9 then raise exception 'month_close sum(sales) 지점 % (9 기대)', n; end if;
  n := (length(v_src)-length(replace(v_src,'sum(sales - refund)','')))/length('sum(sales - refund)'); if n <> 1 then raise exception 'month_close net 지점 % (1 기대)', n; end if;
  v_src := replace(v_src, 'sum(sales - refund)', 'sum(sales + pending_sales - refund)');
  v_src := replace(v_src, 'sum(sales)', 'sum(sales + pending_sales)');
  execute format('create or replace function public.fn_store_month_close(%s) returns jsonb language plpgsql stable security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname='fn_store_status';
  n := (length(v_src)-length(replace(v_src,'sum(sales - refund) net','')))/length('sum(sales - refund) net'); if n <> 2 then raise exception 'status net 지점 % (2 기대)', n; end if;
  v_src := replace(v_src, 'sum(sales - refund) net', 'sum(sales + pending_sales - refund) net');
  execute format('create or replace function public.fn_store_status(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
-- 확인(차효범): 10월 월 마감 total.net 0 → 166,321,538 (일시불 117,057,818 · 구독 49,263,720) · closed_mine 10/06 net 8,442,631.
-- 화면(store.html·store/test v171): 입력 표 머리글 '매출(미확정)' → '매출' · 최근 마감 줄 '· 그중 확정 전 N' · 일 마감 요약 '매출 N (확정 전 M)' 과 저장된 마감 비교 ·
--   일일 업무 텍스트 '매출 N · 환불 M' · 월 마감 요약·텍스트 '판매완료' → '매출' · DPS 대사 마감 합계에 확정 전 포함. 테스트 ptest/daily_probe.mjs P1~P6 × PC·폰.
