-- mvp_127 · 판매 [테스트로] + 담당자 화면 집계에서 테스트 주문 제외 (2026-09-13)
-- 전엔 core.orders.is_test 를 관리자 [주문·판매·매출 흐름] › 테스트 카드에서만 표시할 수 있었고,
-- 담당자 화면(확정 대기·오늘 판매·처리현황·일 마감 자동 채움)은 is_test 를 보지 않아 테스트 판매가 그대로 섞였다.

-- 1) 담당자 화면에서 표시 : 개발·온라인사업부 계정만. 같은 주문번호의 줄 전부.
create or replace function public.fn_store_sale_flag(p_code text, p_id bigint, p_test boolean default true)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_dept text; o core.orders%rowtype;
        v_stamp text := to_char(now() at time zone 'Asia/Seoul','MM-DD HH24:MI');
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select dept into v_dept from core.staff where name = v_me limit 1;
  if coalesce(v_dept,'') !~ '개발|온라인' then raise exception '테스트 표시는 개발·온라인사업부 계정만 할 수 있습니다' using errcode='42501'; end if;
  select * into o from core.orders where id = p_id and source = 'store';
  if o is null then raise exception '매장 판매 건이 아닙니다'; end if;
  update core.orders set is_test = p_test, updated_at = now(),
         notes = concat_ws(' / ', notes, case when p_test then '테스트로 표시 ' else '테스트 해제 ' end || v_stamp || ' ' || v_me)
   where order_no = o.order_no and source = 'store';
  return jsonb_build_object('ok', true, 'order_no', o.order_no, 'is_test', p_test);
end $$;
revoke all on function public.fn_store_sale_flag(text, bigint, boolean) from public;
grant execute on function public.fn_store_sale_flag(text, bigint, boolean) to anon, authenticated, service_role;

-- 2) 집계에서 제외 (부분 치환, 지점 수 검증) — 각 지점에 "and not coalesce(is_test,false)" 를 붙였다
--  fn_store_status        : "o.source = 'store'" ×2 (오늘 판매·확정 대기) · "o.source='store' and o.channel_name=p_store" ×1 (미마감 날)
--                           · "source='store' and status='매출'" ×1 (open_count) · "source='store' and order_at >= v_now - interval '180 days'" ×1 (상품명 추천)
--  fn_store_report        : "where source = 'store' and order_at >= core.f_kst(v_from)" ×1
--  fn_store_daily_prefill : "where o.source = 'store' and o.channel_name = p_store" ×1 · "from core.orders where source='store' and channel_name=p_store" ×1
--  (월 마감 fn_store_month_close 는 core.store_daily 만 읽으므로 일 마감 자동 채움이 빠지면 같이 빠진다)

-- 3) 2026-09-13 일괄 표시 : 홍길동 비스포크(181192) · 지용현 ㅇㄴㅇㄴ(178485) · 홍길동 fyfyfy(177611) · 지용현 ai 콤보 1원(175313)
--    notes '테스트 일괄 표시 2026-09-13 (홍길동·지용현·담당 test)'. 해제는 관리자 테스트 카드 [선택 → 해제].
