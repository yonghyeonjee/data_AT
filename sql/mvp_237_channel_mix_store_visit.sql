-- mvp_237 · 2026-10-22 · '매장 상담' → '매장 직접 방문' 으로 합침 · 문의 → 구매 흐름 채널별 많이 들어온 문의(유형·관심 품목)
-- "매장 직접 방문과 매장 상담이 헷갈리는데 둘간의 차이가 없으면 하나로 합쳐 / 채널별로 어떤 문의가 많았는지도 궁금해"
-- 적용은 MCP 로 서버 본문을 읽어 지점 개수를 센 뒤 replace → execute (본문을 다시 쓰지 않음).

-- ① '매장 상담' 의 정체 = 담당자 판매 입력의 [다음에 살 것] 이 만드는 상담(inflow_route '매장 구매 후').
--    fn_store_sale_submit 이 그 insert 에 channel_code 를 안 넣어 표의 채널 칸이 core.f_consult_src('store') = '매장 상담' 으로 떨어졌다.
--    매장에서 산 고객이 매장에서 말한 다음 관심이라 매장 직접 방문과 같다 (6건 · 숨김 2 포함).
update crm.consult set channel_code = 'store_visit' where source = 'store' and channel_code is null;
--    fn_store_sale_submit: 'buyer_key, inflow_route,' → 'buyer_key, channel_code, inflow_route,'
--                          'v_key, ''매장 구매 후'','  → 'v_key, ''store_visit'', ''매장 구매 후'','   (각 1곳)
--    core.f_consult_src: when 'store' then '매장 상담' → '매장 직접 방문' (채널 코드가 비어도 같은 이름)

-- ② fn_inquiry_flow by_channel 에 줄마다
--    inquiries      그 채널 문의 건수(사람 수와 다를 때 화면에 '문의 N건')
--    purposes       [{label,n}] 상위 6 — core.f_consult_purpose(source,type_code,raw_payload,content) = 상담 대시보드 '문의 유형' 과 같은 셈
--    interests      [{label,n}] 상위 8 — interest_category 를 쉼표로 쪼개고 괄호 설명을 떼고 '알 수 없음' 제외 (한 문의 안 같은 품목은 한 번)
--    interest_none  관심 품목이 비었거나 '알 수 없음' 인 문의 수
--    inq CTE 에 purpose 열 추가 · 나머지 키·셈은 그대로 · ACL 그대로(authenticated·service_role)
--    10월(10-01~22) 0.12초: 구독 문의 = 혼수·신혼 8 · 신규구독 7 / 냉장고 9 · 세탁건조기 9 · TV 8
--                           매장 직접 방문 = 일반 제품 10 / 세탁기 6 · 건조기 4 · B2B = 소모품 주문 4 · 홈페이지 = 냉장고 8 · TV 7
