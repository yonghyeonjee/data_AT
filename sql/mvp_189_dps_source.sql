-- mvp_189 (2026-10-07) DPS(삼성 대리점 판매 시스템) 전표를 데이터센터에 — 적용 기록 (DB 에는 이미 반영됨)
--
-- 무엇: 바탕화면 「DPS 판매 수집기 1.2」가 모은 DPS 판매조회 전표 2년치(2024-10-21 ~ · 판매 16,742 + 해약/교환 3,435)를
--   ① dps 스키마에 전부 넣고(B2C 대시보드 원천) ② 그중 매장 판매사원 6명(이수혁·최태웅·김규완·송희봉·차효범·권혁찬)의
--   매장 전표만 원장(core.orders source='dps')·고객(crm.customer)으로 동기화한다 → 담당자 화면 [내 고객]에 보임.
-- 올리는 방법: 수집기 폴더 DPS_데이터센터_업로드.bat (관리자 로그인 → fn_dps_raw_upsert 68파일 → fn_dps_ledger_sync 반복)
-- Supabase 마이그레이션 이름: dps_store_sales_loader · orders_source_allow_dps · dps_loader_source_ref_per_line ·
--   category_more_model_prefixes · dps_rollback_clear_dps_fields · dps_raw_schema_and_ledger_sync · dps_ledger_sync_fix_ambiguous ·
--   dash_payload_dps_mode · upload_rollback_dps_raw_branch  (본문은 supabase_migrations.schema_migrations 에 그대로 있음)
--
-- ── 1. 고객 표 열 · 출처 카드 · 허용 출처 ─────────────────────────────────────
alter table crm.customer
  add column if not exists consent_dps boolean,          -- DPS 고객정보의 SMS 수신동의 (true/false/null) · consent_marketing 과 별도
  add column if not exists consent_dps_at timestamptz,
  add column if not exists dps_customer_no text,         -- DPS 고객번호
  add column if not exists dps_grade text;               -- DPS 멤버십 등급 (스타·로열블루·프레스티지 …)
insert into core.data_source (key, label, owner, how, feed_mode, expect_days, alert, active, sort_no, auto_plan)
values ('dps', 'DPS 매장 판매 (대리점 시스템)', '매장', 'DPS 판매 수집기(바탕화면)가 판매조회를 수집 → 데이터센터 업로드 스크립트로 적재. 매장 판매사원 6명 전표만, 온라인 담당·대표 명의 전표 제외', 'manual', 7, false, true, 25, '수집기가 매일 새 판매를 더하면 자동 적재로 전환')
on conflict (key) do nothing;
alter table core.orders drop constraint orders_source_check;
alter table core.orders add constraint orders_source_check check (source = any (array['shoplinker','godo','godo_hist','ecount','store','rental','manual','form','dps']));
-- (source, source_ref) 가 고유(ux_orders_source_ref)라 DPS 는 source_ref = 판매번호-줄번호

-- ── 2. 분류 규칙 보강 (core.f_category · 생성 열이라 기존 '기타' 줄은 다시 써서 재계산) ───
--   김치냉장고 RK·KMR · 큐브/와인 RW·RP·RH · 창문형/시스템 에어컨 AW·AC · 공기청정기 AX·AY · 인덕션/전자레인지/후드 NZ·MS·MC·NK·ME·NV
--   세탁기 WW·WV · 패널/브라켓/설치키트/페디스털 RA-·FPC-·FRC-·WMN·SKK-·HA-·PC1 (리모컨·액세서리). 샵링커 '기타' 2,395 → 406 줄.

-- ── 3. dps 스키마 (전표 원본) ─────────────────────────────────────────────────
create schema if not exists dps;
create table if not exists dps.sale (
  sale_no text primary key, doc_type text not null, sale_date date not null,
  customer_no text, buyer_name text, buyer_phone text, buyer_address text, buyer_key char(16),
  staff_code text, staff_name text, order_reason text, receiver text, receiver_phone text, etc_note text,
  amount numeric not null default 0, mapping_level text, channel_tag text, channel text,
  is_store boolean not null default false, is_subscription boolean not null default false, item_count int not null default 0,
  upload_id bigint, synced_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists dps.sale_item (sale_no text references dps.sale on delete cascade, line_no int, model text, qty numeric default 1, amount numeric default 0,
  receiver text, address text, category text generated always as (core.f_category(model, model)) stored, primary key (sale_no, line_no));
create table if not exists dps.subscription (sale_no text references dps.sale on delete cascade, seq int, kind text, status text, service text, model text,
  monthly_fee numeric, term_months int, start_date date, end_date date, right_date date, total_fee numeric, note text, primary key (sale_no, seq));
create table if not exists dps.customer (customer_no text primary key, consent_text text, privacy text, marketing text, ad text, sms text, dm text, tm text,
  member boolean, status text, grade text, membership text, points numeric, premium numeric, manager text, store text, age_gender text, checked_at date, updated_at timestamptz default now());
-- 네 표 모두 RLS 켬(정책 없음) — public 함수(security definer)로만 읽고 쓴다.
-- channel 값은 대시보드 채널명과 같다: 매장(시흥)·매장구독(시흥)·P몰·S몰·AT몰·시흥·SSG·쿠팡·E스토어·B2B·… + DPS 전용
--   'DPS 대표 입력'(장성원 명의) · 'DPS 소모품(대량)'(수량 6개 이상 소모품 재고 등록) · 'DPS 온라인(채널 미확인)' · 'DPS 기타'
-- 채널 판정은 수집 PC 의 build_dps_raw.mjs 가 한다 (맵핑 수준 A1~D2 · 기타사항 채널 표기 · 판매사원 규칙).

-- ── 4. 함수 ───────────────────────────────────────────────────────────────────
-- core.f_dps_raw_upsert(p_file, p_rows, p_by, p_note) / public.fn_dps_raw_upsert(p_file, p_rows)   관리자·업로더
--   raw.upload source='dps_raw' · 전표 upsert(판매번호) · 품목·구독은 지우고 다시 · 고객정보는 조회일이 같거나 새 것만 덮음 · f_dash_mark_dirty()
-- core.f_dps_bulk_upsert(p_file, p_rows, p_by, p_note) / public.fn_dps_bulk_upsert(p_file, p_rows)
--   raw.upload source='dps' · 고객 upsert(source_channels += dps · dps_customer_no · dps_grade · consent_dps)
--   · 다른 경로 동의 기록이 없는 고객만 consent_marketing 도 DPS 값으로(consent_source='dps') + crm.consent_history(source 'dps')
--   · 매장 화면에서 담당자가 이미 넣은 같은 판매(같은 고객·같은 모델군·3일 이내)는 DPS 전표를 넣지 않고 그 줄 비고에 'DPS 판매번호 N 와 같은 판매'
--   · core.orders(source 'dps', channel '매장'/'시흥점', order_no=판매번호, line_no=품목순, handler=판매사원 이름, sale_kind 구독/일시불,
--     option_text=구독 내용, notes=판매번호·고객번호·판매사원·주문사유·기타사항, alt_order_no=DPS 고객번호, recv_*)
-- core.f_dps_ledger_sync(p_limit, p_by) / public.fn_dps_ledger_sync(p_limit)
--   dps.sale 중 is_store 이고 synced_at 이 비어 있는 전표를 p_limit 개씩(기본 150 · REST 8초 제한) 줄로 만들어 f_dps_bulk_upsert 에 넘기고 synced_at 기록.
--   구독 전표의 자리표시 품목(A4용지·AA2P …)은 구독 제품 모델로 바꿔 넣고 option_text 에 '전표 품목 A4용지 5,000원' 을 남긴다.
-- core.f_upload_rollback_dps(upload_id) · public.fn_upload_rollback 에 source 'dps'(원장 줄·생성 고객·동의 원복·매장 화면 표시 제거)와 'dps_raw'(전표 삭제) 분기
-- public.fn_store_my_customers: 내 고객 = consult_scoped 담당 + core.orders handler 가 나이고 source in ('store','dps')

-- ── 5. 대시보드 (core.f_dash_payload p_mode='dps' · f_dash_src_at · f_dash_warm) ────────
--   mode 'dps': 채널 = dps.sale.channel, 매출 = 판매 전표 금액, 환불 = 해약/교환 전표 |금액|, 주문 수 = 판매번호, 고객 셀 = buyer_key(첫 구매일은 DPS 안에서),
--     제품·pcells = dps.sale_item(분류 f_category), 렌탈·직판 블록은 빈 값. 'source' 키가 'dps'.
--   mode 'ledger': 매장(시흥)·매장구독(시흥) 셀이 source in ('store','dps') 를 본다 → DPS 과거 매장 매출이 원장 기준에 들어온다.
--     그날 그 구분의 판매 입력(store·dps)이 있으면 일 마감 snapshot 은 안 쓴다(mvp_154 규칙 그대로).
--   mode 'manual' 은 channel_daily 만 (전엔 p_mode <> 'ledger' 라 새 모드에도 섞였음).
--   f_dash_src_at 에 dps.sale.updated_at 추가 · f_dash_warm 이 ['ledger','manual','dps'] 를 미리 굽는다.
-- 화면: admin.html 집계 기준 세그먼트에 [DPS] (db-dps · DASH_V 165) · dash/index.html basisseg 에 m-dps · dashBasis() 가 'dps' 허용 · ?mode=dps

-- ── 6. 되돌리기 메모 ─────────────────────────────────────────────────────────
-- 데이터 가져오기 화면 되돌리기(fn_upload_rollback)에 'dps'(원장 동기화 업로드)와 'dps_raw'(원본 전표 업로드)를 고르면 된다.
-- 원장 동기화를 다시 하려면: update dps.sale set synced_at = null where is_store;  →  업로드 스크립트 --sync-only
