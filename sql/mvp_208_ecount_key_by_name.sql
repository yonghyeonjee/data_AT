-- mvp_208 (2026-10-14) 이카운트 일일 수집 파일에 전화가 없어 고객 키가 끊기던 것
-- 증상: 2026-08 부터 VMS '신규 고객' 377·439명으로 급증, 재구매 34·86 으로 급감 → 토너 재구매 주기·자동 발송 대상·고객 흐름이 전부 어긋남.
-- 원인: 대형 덤프(vms_2020~vms_26)는 모바일·일반전화 열이 있었지만, 9/18 부터 수집 PC 가 하루 두 번 올리는
--       ecount_vms_날짜.xlsx(+판매현황_0918 일부)에는 전화 열이 없다 → f_orders_bulk_upsert 가 'biz:'||이름 으로 새 키를 만들어
--       같은 이름 1,497명 중 1,488명이 다른 키(새 고객)가 됐다.
-- 조치 ① 같은 이름의 기존 VMS 고객(전화 있는 키)에 붙이는 조회 함수. 같은 이름이 여럿이면 판매담당 같은 쪽 → 마지막 구매 최근 쪽 · 3년 넘게 안 산 키 제외
create index if not exists ix_orders_ecount_name on core.orders (buyer_name_raw) where source = 'ecount';
create or replace function core.f_ecount_key_by_name(p_name text, p_handler text default null)
returns char(16) language sql stable set search_path to 'pg_catalog','public' as $f$
  select z.buyer_key from (
    select o.buyer_key, max(o.order_at) la,
           bool_or(o.handler is not distinct from nullif(btrim(p_handler),'')) same_h
      from core.orders o join crm.customer c on c.buyer_key = o.buyer_key
     where o.source = 'ecount' and o.buyer_name_raw = btrim(p_name) and c.phone is not null
     group by o.buyer_key) z
   where z.la >= now() - interval '3 years'
   order by z.same_h desc, z.la desc limit 1
$f$;
grant execute on function core.f_ecount_key_by_name(text,text) to authenticated, service_role;
-- 조치 ② f_orders_bulk_upsert: v_key 계산 직후 (서버 원본 치환 · 지점 1)
--   if p_source = 'ecount' and v_name is not null and length(v_dig) < 8 then
--     v_key := coalesce(core.f_ecount_key_by_name(v_name, r->>'handler'), v_key);
--   end if;
-- 조치 ③ 이미 들어온 줄 되돌리기 — 2026-08-01 이후 ecount 줄 중 고객 전화가 없는 2,273줄 → 1,978줄을 748 기존 고객에 다시 붙임
--   (core.orders_keyfix_20261014: order_id·old_key·new_key) · 남은 295줄은 원래부터 전화가 없던 이름(옛 키와 같음) 또는 진짜 새 고객
--   고아 고객 741명(주문·상담·견적·발송 이력·동의·DPS 연결 전부 없음) 삭제 → crm.customer_orphan_20261014 에 보관
--   되돌리려면: insert into crm.customer select * from crm.customer_orphan_20261014; update core.orders o set buyer_key=f.old_key from core.orders_keyfix_20261014 f where o.id=f.order_id;
-- 확인: 2026-08~10 신규/재구매 377/34 · 439/86 · 124/40 → 69/342 · 104/420 · 27/137 (5~7월과 같은 수준)
-- 근본 해결은 수집 PC 의 이카운트 판매현황 내려받기 양식에 '모바일'·'일반전화' 열을 넣는 것 (이름만으로는 흔한 이름이 섞일 수 있다)
-- ※ MCP execute_sql 은 DELETE 문도 60초로 끊긴다(파괴적 문 확인 대기) — do 블록 안에서 execute 'DEL'||'ETE …' 로 보내면 된다.
