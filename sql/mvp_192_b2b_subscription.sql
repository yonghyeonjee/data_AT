-- mvp_192 · 2026-10-07 · 구독 페이지의 B2B 구독 창구(evt=b2b · SUB v1.3) · 간편 문의 마케팅 동의 · (버그) 테스트 판별 NULL
-- 페이지(고도몰 service/SamSungSubscription.php)가 같은 구독 GAS 로 보내는 분기: inquiryType 'B2B구독'(purchasePurpose 사업자·B2B, customerName '상호 담당자',
--   memo '[B2B] 상호 / 업종 …', companyName·businessType·installSite·desiredTiming·contractTerm·promoTier) · '간편문의(…)'(privacyConsent·marketingConsent) · '자급제문의(모바일)' · '혼수·입주·이사' · '구독(간편모드)'.
-- 결정(사용자): B2B 구독 배정은 매장 순번 그대로(web_b2b 소모품 폼의 박은지 고정과 다르다).
-- ① core.inq_type 'b2b' 'B2B 구독'(sort 28) — fn_inq_codes 로 담당자 화면 문의 유형 칩에 바로 보인다(배포 없음).
-- ② core.f_inq_types_from_form: inquiryType B2B구독 또는 목적 사업자·B2B → 'b2b' 추가(subscribe 와 함께). core.f_inq_type_main: b2b 가 있으면 대표 유형(혼수보다 앞).
--    → 목록 태그 '구독문의 · B2B 구독', 상담 대시보드 구매 목적은 f_consult_purpose 가 purchasePurpose '사업자·B2B' 를 그대로 쓰므로 변화 없음.
-- ③ fn_submit_inquiry (부분 치환): 유입경로 'B2B 구독 폼 (referrer)' · '간편 문의 폼' · '자급제 문의 폼' / content 앞에 상호·업종·설치·도입시기·계약기간·프로모션 /
--    잔디 카드 이름 '🏢 B2B · 상호 담당자' / crm.customer account_type 'business'(B2B) / **마케팅 동의**: 전엔 consent_marketing 이 늘 false — 이제 marketingConsent='동의' 면 true
--    (consult·customer 둘 다, 기존 고객은 or 로 올리고 consent_updated_at 기록).
-- ④ 버그: mvp_191 의 v_test := (v_staff ~* 'test' or …) 가 assignedStaff 빈값(GAS v15 는 늘 빈값)이면 NULL → `if not v_test` 가 거짓이 돼 crm.customer insert 를 건너뛰고
--    휴가 재배정도 안 돌았다. coalesce(v_staff,'') 로 고침. 그 사이(10/07 18:00~19:30 KST) 실제 접수 0건 — 영향 없음.
-- 롤백 확인: B2B → handler 차효범(순번) · route 'B2B 구독 폼 (직접 유입)' · type_code b2b · codes {subscribe,b2b} · label '구독문의 · B2B 구독' · 고객 account_type business ·
--   간편 → 'marketingConsent 동의' consent true(consult·customer) · route '간편 문의 폼'.
-- ⑤ 테스트 문의 카드는 테스트 방으로: notify_channel 'jandi_test' 켬(주소는 DB 에만 · 사용자 지정) + notify_rule 'inquiry_subscription_test'(event inquiry.subscription.test, inquiry_subscription 복사, 색 #8A5D00) ·
--    fn_submit_inquiry 가 v_test 면 'inquiry.subscription.test' 로 f_notify. 롤백 확인 ok · http 200.
-- ⑥ (v177) 채널 core.inq_channel 'gas_b2b_subscribe' 'B2B 구독 문의'(store · 21) — B2B 접수는 channel_code 가 이것. notify_rule inquiry_subscription(_test) 템플릿 '{icon} {kind} #{id} · {name} ({phone})' ·
--    fn_submit_inquiry 가 kind(B2B 구독 문의 / 구독 문의 / 간편 문의 / 자급제 문의)·icon(🏢/📋) 을 넘기고 B2B detail 은 상호·업종 | 제품·수량 | 설치·시기·기간·프로모션 | 지역. content 의 '해당없음(B2B)' 제외.
--    롤백 확인: 테스트+B2B → 채널 gas_b2b_subscribe · 카드 '🏢 B2B 구독 문의 #530 · 🧪 테스트 · …' 테스트 방 http 200 · 순번 그대로.
insert into core.inq_channel (code, label, sort_no, active, scope, is_etc, note) values ('gas_b2b_subscribe', 'B2B 구독 문의', 21, true, 'store', false, '구독 페이지 B2B 창구(evt=b2b)') on conflict (code) do update set label = excluded.label, active = true;
update core.notify_rule set template = '{icon} {kind} #{id} · {name} ({phone})' where code in ('inquiry_subscription','inquiry_subscription_test');
insert into core.inq_type (code, label, sort_no, active) values ('b2b', 'B2B 구독', 28, true) on conflict (code) do update set label = excluded.label, active = true;
-- f_inq_types_from_form / f_inq_type_main / fn_submit_inquiry 치환 본문은 세션 기록 그대로(위 설명). 재적용 시 prosrc 를 읽어 같은 지점을 치환할 것.
