-- mvp_149 (2026-09-15) — 저장 조건(crm.segment)이 조용히 어긋나던 것
--
-- 발단: 관리자에서 [토너·잉크 재구매 주기] 를 누르니 95명이 나왔다. 그런데 목록에는
--       냉장고·갤럭시 워치·식기세척기 구매자가 있었다 — 토너가 한 명도 없었다.
--
-- 원인 1) params 의 kind_goods 를 화면(segToForm)이 읽지 않는다. 그런 키가 admin.html 어디에도 없다.
--          그래서 이 조건은 실제로 '최근 60~180일 전에 아무거나 산 수신동의 고객' 을 뽑고 있었다.
-- 원인 2) b2b_repeat 의 kind 값이 '사업자' 인데 화면 select 의 값은 'business' 다.
--          select 에 없는 값을 넣으면 조용히 '전체' 가 되므로 사업자 조건이 통째로 빠져 있었다.
--
-- 둘 다 '조건은 걸려 있는데 실제로는 안 걸린다' 는 같은 병이다. 화면 쪽에도 경고를 넣었다
-- (admin.html SEG_KEYS + segToForm — 모르는 키, select 에 없는 값이면 토스트로 알린다. 테스트 N1~N3)

-- ① 토너를 거르지 않는 조건을 내린다 (되살리려면 active=true)
update crm.segment
   set active = false,
       note = note || ' — [사용 중지 2026-09-15] 이 조건은 토너를 거르지 않습니다(kind_goods 미적용). 새 관리자 배포 후 교체'
 where code = 'toner_repeat' and active;

-- ② 사업자 조건이 빠지던 것
update crm.segment
   set params = jsonb_set(params, '{kind}', '"business"')
 where code = 'b2b_repeat' and params->>'kind' = '사업자';

-- ③ 새 관리자(대상 기준·제품·기준일 = mvp_144·147·148)가 배포된 뒤 켤 조건들.
--    지금은 active=false 로 둔다 — 옛 화면은 basis·product·asof 를 못 읽어 엉뚱한 명단이 나온다.
insert into crm.segment (code, label, note, params, builtin, active, sort) values
 ('toner_repeat_v2','토너·잉크 재구매 주기 (거래처)',
  '소모품 거래처 중 자기 주문 주기가 돌아온 곳 — 주기는 간격 중앙값, 1년 넘게 안 산 곳은 제외, 한 번이라도 보낸 사람은 제외',
  '{"basis":"repeat","no_send_days":36500,"sort":"recent"}'::jsonb, true, false, 30),
 ('camp_chuseok_0918','[9월] 추석 구독 할인 · 9/18 발송',
  '자사몰 회원 중 마케팅 수신 동의 + 휴대폰 있는 분 전체 — 연휴에 가족과 매장에 오시라는 문자',
  '{"basis":"consent","sort":"recent"}'::jsonb, true, false, 40),
 ('camp_toner_0921','[9월] VMS 토너 교체 · 9/21 발송',
  '기준일 2026-09-21 로 고정 — 언제 눌러도 같은 310명이 나온다. 8/14 발송분은 자동 제외',
  '{"basis":"repeat","asof":"2026-09-21","no_send_days":36500,"sort":"recent"}'::jsonb, true, false, 41),
 ('camp_filter_0923','[9월] 정수기 필터 교체 · 9/23 발송',
  '자사몰·VMS 에서 HAF- 필터를 2025-09-23 ~ 2026-06-23 사이에 산 분 — 오픈마켓 구매는 근거로 세지 않는다',
  '{"basis":"product","product":"HAF-","from":"2025-09-23","to":"2026-06-23","no_send_days":36500,"sort":"recent"}'::jsonb, true, false, 42)
on conflict (code) do update
  set label=excluded.label, note=excluded.note, params=excluded.params, sort=excluded.sort;

-- ④ 배포를 확인한 뒤 이 한 줄을 실행해 켠다
-- update crm.segment set active = true
--  where code in ('toner_repeat_v2','camp_chuseok_0918','camp_toner_0921','camp_filter_0923');

-- ───────── 확인한 깔때기 (2026-09-15) ─────────
-- 추석 (수신동의)   전체 62,699 → 수신동의 6,907 → 휴대폰 있음 3,742
--                   유입: S몰 1,784 · AT몰 1,068 · P몰 823 · 시흥몰 153 · 샵링커 131 · 이카운트 61 · 매장 9
-- VMS 토너 (재구매) 발송 가능 42,809 → 휴대폰 38,686 → 2회 이상 10,024 → 1년 내 2,576
--                   → 주기 도래(D-30~D+14, 기준일 09-21) 360 → 8/14 발송분 제외 310
--                   출처: 이카운트 283 · 샵링커 27 · S몰 11 · P몰 4 · AT몰 1 · 주기 중앙값 114일
-- 정수기 필터       필터 구매자 4,102 → 오픈마켓 제외 238 (P몰 120·시흥몰 83·AT몰 19·S몰 11·VMS 5)
--                   → 3개월~1년 지난 분 56
