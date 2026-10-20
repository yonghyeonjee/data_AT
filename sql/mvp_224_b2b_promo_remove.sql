-- mvp_224 · 2026-10-20 · B2B 구독 문의에서 '프로모션 N%'(고객 화면 예상 할인) 빼기 — 적용 기록
-- "이거 프로모션 25%는 무슨 내용이야? 왜 이걸 가져오지?" → "완전히 빼기 — 카드·상담 내용 둘 다"
-- promoTier = 구독 페이지 B2B 창구(evt=b2b)가 고른 제품·수량으로 계산한 '상담 가능한 최대 할인'(20·25·30% · 대상외).
-- 확정 할인이 아닌데 잔디 카드에 '프로모션 25%' 로 찍혀 확정 할인으로 읽힐 수 있었다.
--
-- fn_submit_inquiry 부분 치환 3곳 (pg_get_functiondef → 지점 수 검증 → execute):
--  ① content: case when nullif(p_data->>'promoTier','') is not null then '프로모션: '||(p_data->>'promoTier') end,  → 삭제
--  ② 잔디 detail: , case when … then '프로모션 '||(p_data->>'promoTier') end)  → )
--  ③ memo: nullif(left(p_data->>'memo', 800), '')
--        → nullif(left(regexp_replace(coalesce(p_data->>'memo',''), '\n?예상 프로모션:[^\n]*', '', 'g'), 800), '')
-- 기존 줄 정리 (B2B 구독 3건 · #590 실제 · #531·#532 테스트):
update crm.consult
   set content = regexp_replace(regexp_replace(content, ' / 프로모션: [^/]*?(?= / |$)', '', 'g'), '\n?예상 프로모션:[^\n]*', '', 'g'),
       updated_at = now()
 where channel_code = 'gas_b2b_subscribe' and content ~ '프로모션';
-- raw_payload(받은 원본 그대로)의 promoTier 키는 남는다 — 화면·카드 어디에도 안 보인다.
-- 롤백 실험: 가짜 B2B 접수(promoTier 25% · 메모에 '예상 프로모션' 줄) → content·카드 상담 정보 둘 다 프로모션 없음 · '요청:' 줄은 남음.
