-- mvp_250 (2026-10-28) DPS 구독계약 (올인원 · 스마트 · 갤럭시AI구독클럽)
-- 원천: DPS 판매 > 판매생성/변경/조회
--   구독계약조회(올인원) sd010_0128List.do  (I_SSBTYPE FL=올인원 2.0 · SB=올인원, 신청일 91일까지)
--   구독계약조회(스마트) sd010_0129List.do  (신청일 31일까지)
--   갤럭시AI구독클럽     sd010_0130List.do  (판매일 14일까지)
-- 수집: DPS 판매 수집기 tools\contract\contract.playwriter.js (매일 자동 수집 끝, 최근 180일 신청분 다시 받음 — 상태·배송일이 바뀌므로)
-- 적재: tools\contract\upload_contract.mjs → parse_contract.mjs → fn_dps_subcontract_upsert (1,000건씩 → 마지막 p_final)
-- 키: allinone = 구독주문번호-모델-순번 (한 주문에 모델 여러 줄)
--     smart    = 구독번호-주문구분-모델[-상품명] (상품 줄 + 서비스 줄, 방문케어는 1회차·2회차… 줄이 따로)
--     aiclub   = 판매번호-항번
-- 연락처·주소·우편번호는 저장하지 않음. 이름은 DPS 화면이 가린 그대로(원*철).
-- 2026-10-28 첫 적재 2024-10-01~2026-10-28: 4,689건 (allinone 1,103 · smart 3,290 · aiclub 296 · 올인원(SB) 0)
--   판매번호가 dps.sale 에 있는 비율 약 76%

create table if not exists dps.sub_contract (
  kind text not null, key text not null,
  sale_no text, apply_date date, status text, model text, term_months int, service text, cycle int,
  ship_req date, ship_plan date, ship_done date, contract_date date, start_date date, end_date date, visit_date date, right_date date,
  monthly_fee numeric, product_fee numeric, prepay numeric, total_fee numeric,
  staff_code text, staff_name text,
  vals jsonb not null,
  first_seen date not null default current_date, last_seen date,
  updated_at timestamptz not null default now(), last_fetch text,
  primary key (kind, key)
);
-- 인덱스: sale_no · apply_date
create table if not exists dps.sub_contract_change (   -- new · status · changed (첫 적재는 기록 안 함)
  id bigserial primary key, fetch_id text not null, changed_on date not null default current_date,
  kind text not null, key text not null, change text not null, old_status text, new_status text, old_vals jsonb, new_vals jsonb
);
create table if not exists dps.sub_contract_fetch (
  fetch_id text primary key, started_at timestamptz not null default now(), finished_at timestamptz,
  date_from date, date_to date, rows int, n_new int, n_status int, n_changed int, uploaded_by uuid
);
-- RLS 켬(세 표 모두) · 함수로만 접근

-- public.fn_dps_subcontract_upsert(p_fetch_id text, p_rows jsonb, p_from date default null, p_to date default null, p_final boolean default false)  (admin·uploader)
--   p_rows: (kind, key) 로 upsert. vals 가 바뀌면 updated_at 갱신 + sub_contract_change 기록(상태가 바뀌면 change='status')
--   p_final: sub_contract_fetch 마감(건수·새 계약·상태 바뀜·값 바뀜)
--   기간 조회라 '목록에서 빠짐' 처리는 하지 않음
