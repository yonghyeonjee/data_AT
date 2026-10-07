-- mvp_190 (2026-10-07) 고객이 구독인지 일시불인지 — 원장과 DPS 구독정보로 표기 (적용 기록 · DB 에는 반영됨)
--
-- "기존 고객들이 구독인지 일시불인지 몰랐잖아. 기존 원장에서 구독으로 구분할 수 있어진 고객은 구독으로 표기하자.
--  물론 그 고객이 일시불과 구독을 동시에 했을 수도 있지" → 한 고객에 구분이 여럿일 수 있어 배열로 둔다.
-- Supabase 마이그레이션: customer_roll_sale_kinds_and_dps_sub
--
-- crm.customer_roll 열 추가
--   kinds text[]     원장(core.orders) 주문의 sale_kind 모음 — 구독·일시불·직판 (매장 입력 store · DPS 매장 전표 dps 가 채움)
--   sub_kinds text[] DPS 구독정보(dps.subscription)의 구분 모음 — 스마트·올인원·갤럭시AI. dps.sale 의 고객키(buyer_key)로 붙이므로
--                    원장에 넣지 않은 전표(온라인 담당 입력 등)의 구독도 같은 고객이면 표기된다
--   has_sub boolean  kinds 에 '구독'이 있거나 sub_kinds 가 있으면 true
-- core.f_customer_roll(): _cr 에 kinds 집계 추가 · dps 구독으로 sub_kinds/has_sub 갱신 · 바뀜 감지에 dps.sale.updated_at 포함
-- public.fn_customer_list(): 행에 kinds · sub · sub_kinds 추가 · p_source 에 '구독'/'일시불'을 주면 구매 구분으로 거른다 (서명 그대로)
-- 화면 admin.html 고객 통합: 채널 칩 옆에 [구독](초록) · [일시불]/[직판] 칩 · 칩 툴팁에 DPS 구독 종류 · 출처 드롭다운에 구독/일시불 항목
--
-- 2026-10-07 현재(DPS 적재 전) kinds 가 있는 고객 66명(매장 입력분) · 구독 20명. DPS 적재 뒤 매장 고객 3,762명 + DPS 구독 연결 고객이 채워진다.
alter table crm.customer_roll
  add column if not exists kinds text[],
  add column if not exists sub_kinds text[],
  add column if not exists has_sub boolean not null default false;
-- 함수 본문: supabase_migrations.schema_migrations 'customer_roll_sale_kinds_and_dps_sub'
