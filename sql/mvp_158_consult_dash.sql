-- mvp_158 (2026-09-17) — 관리자 [상담 대시보드] 메뉴 + core.f_consult_stats 에 제품·금액
-- "문의 처리현황도 대시보드처럼 봤으면 좋겠어 메뉴를 늘려서라도 · 제품명과 가격도 가져올 수 있으면"
-- core.f_consult_stats (prosrc 치환, 시그니처 그대로 · fn_consult_stats/fn_store_consult_stats 가 그대로 씀):
--   c 에 interest(관심 카테고리) · product(구매 제품명 = 연결 주문 품목명 → purchase_item → 관심 모델 → 카테고리 → '(제품 미기록)') · amount(연결 주문 같은 주문번호 net 합계 → expected_amount → 0)
--   agg/cha/hd 에 amount 합계 → total.amount, periods[].amount, channels[].amount, handlers[].amount
--   새 키 interests[{i,total,bought,rate}] (쉼표로 여러 개 적힌 카테고리는 쪼개고 괄호 설명은 뗌) · purchases[{pn,n,amount}] (금액순)
insert into core.menu_item (code, group_code, label, sort, state, note, envs)
values ('cdash','crm','상담 대시보드', 15, 'on', '문의 → 구매 흐름 · 채널·담당자·관심 제품·구매 제품', array['test','prod'])
on conflict (code) do update set label=excluded.label, group_code=excluded.group_code, sort=excluded.sort, state='on';
-- 화면: admin.html #v-cdash · loadCdash · cdBars(기간 막대 + 금액) · cdHBars(가로 막대) · KPI 6장 · 채널×기간 표. 기간은 상단 기간 바(P), 범위는 localStorage dc_cd_scope.
-- 2026-07~09 확인: 문의 155 · 구매 49 · 금액 1억6,122만 · 관심 1위 냉장고 31 · 구매 제품 '(제품 미기록)' 18건 7,854만(판매 입력 연결 안 된 구매완료).
