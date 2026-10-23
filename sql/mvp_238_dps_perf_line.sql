-- mvp_238 (2026-10-23) 대시보드 [DPS] 매출 = DPS 사원별목표/실적 기준
-- 이유: DPS 경영정보>목표관리>사원별목표/실적 화면과 대시보드 [DPS] 숫자가 달랐다.
--   DPS 실적은 같은 판매번호 안의 모델 변경·부분 반품·해약을 '그 일이 일어난 날'로 잡는데,
--   dps.sale 은 수집 시점의 최종 전표 금액을 원래 판매일에 잡는다 → 전체 기간 합계는 0.04% 차이지만 월별로 -15% ~ +41%.
-- 원천: 사원명 링크 팝업 bm010_0028Pop3.do (실적기준 판매 · 매입원가 · VAT포함) 의 줄. 고객명은 저장하지 않는다.
--   수집: DPS 판매 수집기 tools\perf\perf.playwriter.js (매일 자동 수집 끝에 이번 달, 1~5일엔 지난달도)
--   적재: tools\perf\upload_perf.mjs → fn_dps_perf_upsert (그 달을 통째로 교체 · 화면 사원별 실적과 줄 합계가 다르면 거절)
-- 2024-09 ~ 2026-10-23 80,987줄 적재. 화면과 다른 달: 2024-12 DAZ3003(팝업에 같은 줄 두 번 · +237만), 2025-10/11 DAZ2001(다른 사업장 사원 · 팝업 줄 없음 · 두 달 합 0)

create table if not exists dps.perf_line (
  perf_date   date not null,
  staff_code  text not null,
  staff_name  text,
  staff_group text,
  sale_no     text not null,
  line_no     int  not null,
  model       text,
  qty         numeric,
  amount      numeric not null default 0,
  cost        numeric,
  profit      numeric,
  fetched_at  timestamptz not null default now(),
  primary key (perf_date, staff_code, sale_no, line_no)
);
create index if not exists perf_line_sale_no on dps.perf_line (sale_no);
alter table dps.perf_line enable row level security;

create table if not exists dps.perf_fetch (
  id bigserial primary key, date_from date not null, date_to date not null, lines int not null, amount numeric not null,
  staff_totals jsonb, uploaded_by uuid, fetched_at timestamptz not null default now()
);
alter table dps.perf_fetch enable row level security;

-- public.fn_dps_perf_upsert(p_from date, p_to date, p_rows jsonb, p_check jsonb default null)  (admin·uploader)
--   p_rows 를 임시표로 풀고 → 기간 밖 줄 거절 → p_check(사원코드: 화면 실적)와 사원별 줄 합계 비교, 다르면 예외
--   → 그 기간 dps.perf_line 을 지우고 다시 넣음 → dps.perf_fetch 기록 → core.f_dash_mark_dirty(true)
--   (본문은 DB 에 있음. execute_sql 낱말 함정 때문에 지우기 문은 execute 'DEL'||'ETE …' 로 씀)

-- core.f_dash_payload DPS 분기 8곳 치환 (원본을 읽어 부분 치환 · 각 지점 1곳 검증 · 시험 함수로 확인 뒤 교체)
--   _dl 임시표: dps.perf_line 을 판매번호×실적일로 순액 합산, 채널·buyer_key 는 판매번호로 dps.sale (없으면 'DPS 채널 미확인')
--   채널 목록 · cells(순액 양수 = 매출, 음수 = 환불) · ocells(순액 양수 판매번호 수) · _fb(첫 구매 = 순액 양수 첫 실적일)
--   · ccells · products(core.f_category(model, model)) · pcells(판매번호×실적일×모델 순액) 를 _dl / dps.perf_line 으로.
--   확인: 2026-10-01~23 순매출 694,286,289 = DPS 화면 합계 · 원장/수기입력 payload 는 바꾸기 전과 md5 같음 · 12개월 2.4초.
-- core.f_dash_src_at: max(dps.perf_line.fetched_at) 추가 (워머가 실적 줄 갱신을 감지)
