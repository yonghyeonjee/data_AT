-- mvp_240 (2026-10-26) DPS 올인원구독모델조회 전체 목록 + 선납 할인표
-- 원천: DPS 판매 > 판매생성/변경/조회 > 올인원구독모델조회 (sd010_0127List.do · 조건 없이 POST 하면 전체 8,681행 · 응답 HTML 24MB)
--   모델명 칸 hover 표(선납금비율·선납금·선납/단품할인 적용 월 구독료·선납할인율·선납할인금액·단품할인율·단품할인금액)는
--   각 행의 data-tooltip 속성에 들어 있어 한 번 조회로 함께 받는다 (모델당 1~12줄).
-- 수집: DPS 판매 수집기 tools\submodel\submodel.playwriter.js (매일 자동 수집 끝, 실적 줄 다음)
-- 적재: tools\submodel\upload_submodel.mjs → parse_submodel.mjs 로 풀어 fn_dps_submodel_upsert (2,000행씩 → 마지막 호출 p_final)
-- 키: model + product(상품명) + term(구독기간) + service(서비스유형) + visit_cycle(방문주기) — 8,681행 전부 고유 (2026-10-26 확인)

create table if not exists dps.sub_model (
  model text not null, product text not null, term text not null, service text not null, visit_cycle int not null default 0,
  row_no int, category text, seg text, term_months int,
  monthly_fee numeric, product_fee numeric, total_fee numeric, product_fee_ex numeric,
  repair_amt numeric, care_amt numeric, bluepass_amt numeric,
  prepay jsonb not null default '[]'::jsonb,   -- [{ratio, prepay, monthly, prepay_rate, prepay_disc, single_rate, single_disc}]
  vals jsonb not null,                          -- 비교용 (row_no 뺀 행 전체)
  active boolean not null default true,         -- 지금 DPS 목록에 있음
  first_seen date not null default current_date, last_seen date,
  updated_at timestamptz not null default now(), last_fetch text,
  primary key (model, product, term, service, visit_cycle)
);
create table if not exists dps.sub_model_change (   -- new · changed · removed · returned (첫 전체 적재는 기록 안 함)
  id bigserial primary key, fetch_id text not null, changed_on date not null default current_date,
  model text, product text, term text, service text, visit_cycle int, kind text not null, old_vals jsonb, new_vals jsonb
);
create table if not exists dps.sub_model_fetch (
  fetch_id text primary key, started_at timestamptz not null default now(), finished_at timestamptz,
  rows int, n_new int, n_changed int, n_removed int, uploaded_by uuid
);
-- RLS 켬(세 표 모두) · 함수로만 접근

-- public.fn_dps_submodel_upsert(p_fetch_id text, p_rows jsonb, p_final boolean default false, p_expected int default null)  (admin·uploader)
--   p_rows: 키로 upsert, vals 가 바뀌면 updated_at 갱신 + sub_model_change 기록
--   p_final: 이번 fetch_id 로 올라온 건수가 p_expected 와 다르면 예외(일부만 올라온 채 '빠짐' 처리 방지)
--            → 이번에 안 보인 active 행을 active=false + 'removed' 기록 → sub_model_fetch 마감
-- 2026-10-26 첫 적재 8,681행 · 모델 1,027개 · 재적재 시 변경 0건 확인
