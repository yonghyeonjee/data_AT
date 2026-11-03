-- mvp_275 (2026-11-03) — 폼 시트 상태 '상담완료' 는 판매가 아니다
-- "상담완료(판매전) 이어야하지 않나?" — 이소명 #55(web_b2b B-0009) 는 시트 상태가 '상담완료' 였는데
-- core.f_form_result 가 '상담완료|발주완료|구매|계약|완료' 를 한 번에 구매완료로 바꿔 판매 완료 · 판매 확인 필요에 떴다(mvp_40 부터).
-- 시트 상태가 남아 있는 web_b2b·web_supply 상담 27건 중 '상담완료' 는 #55 하나뿐(나머지는 '대기').
create or replace function core.f_form_result(p_status text) returns text
language sql immutable set search_path = pg_catalog, public as $$
  select case
    when p_status is null or btrim(p_status) = '' then '진행중'
    when p_status ~ '발주완료|구매|계약' then '구매완료'
    when p_status ~ '보류' then '보류'
    when p_status ~ '취소|거절|종료' then '종료'
    when p_status ~ '상담완료|완료' then '상담완료'
    else '진행중' end;
$$;
-- #55 바로잡음: result 상담완료 · sale_kind·linked_order_id 비움 · mvp_274 가 붙인 '이카운트 판매 … 에 이어짐' 메모 대신 사유 메모.
--   (이카운트 판매 20260825-1 은 원장·고객 흐름에 그대로 있다)
-- update crm.consult set result='상담완료', sale_kind=null, linked_order_id=null, notes=… where id=55;

-- 같이: 문자 문구 미리보기 smsRender(admin.html · admin/test · store.html · store/test) 가 옛 규칙(빈 줄을 지움)이라
-- Enter 두 번이 미리보기에서 한 줄로 보였다 → 서버 core.f_sms_render(mvp_227)와 같은 규칙으로. 서버 출력과 같은 입력 5개로 대조 일치.
