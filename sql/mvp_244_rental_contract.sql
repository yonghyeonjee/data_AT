-- mvp_244 · 2026-10-27 · 렌탈(임대) 계약 명부 적재
-- 원본: '임대고객_계약기간 반영_YYMMDD.xlsx' (2행 머리글 — 업체코드 · 업체명 · 주소 · 연락처 · 임대기기 ·
--   최종계약 기본임대료(VAT포함) · 계약시작_본계약 · 계약종료_본계약 · 재계약여부 · 시작_재계약 · 종료_재계약 ·
--   비고(해지일 등) · 보증금반환일 · 미수금 정산 · 파일 반영). 개인정보라 파일·값은 저장소에 두지 않는다.
-- 적용됨(DB). 본문 전체는 서버에서 pg_get_functiondef 로 읽을 것 — 여기엔 규칙만.

create table if not exists crm.rental_contract (
  id bigserial primary key, upload_id bigint, row_no int,
  code text,            -- 업체코드 칸 그대로 (내부 코드 AT0000… · 0002 도 있음)
  biz_no text,          -- 업체코드가 숫자·대시뿐일 때만 사업자번호로 (숫자만)
  company text not null, address text, phone text, device text, monthly_fee numeric,
  start_d date, end_d date, start_raw text, end_raw text,     -- 본계약 첫 줄 날짜 · 글자 그대로
  renew text, renew_raw text,                                 -- 재계약여부 · 재계약 시작~종료 글자
  periods jsonb default '[]',  -- [{k:'본계약'|'본계약 2'|'재계약 n', start, end}]
  cur_start date, cur_end date, -- 가장 늦게 끝나는 기간
  note text, deposit_return text, receivable text, applied text,
  closed boolean default false, -- 비고 '폐업' 또는 '해지'(재임대·유지 없이)
  buyer_key char(16), match_by text,  -- biz | name | phone
  raw jsonb, loaded_at timestamptz default now()
);
alter table crm.rental_contract enable row level security;   -- 정책 없음 (함수로만)
create index if not exists ix_rcontract_buyer on crm.rental_contract (buyer_key);
create index if not exists ix_rcontract_end on crm.rental_contract (cur_end);

-- core.f_kdate(text) → date        '2019.02.28.' '2019-2-28' '2019년 2월 28일' · 못 읽으면 null
-- core.f_company_norm(text) → text  (주)·㈜·주식회사·(유)·(사)·(재)·사단/재단법인·(합)·공백·구두점 제거, 소문자
-- core.f_rental_contract_load(p_rows jsonb, p_file text, p_by uuid) → jsonb   (security definer)
--   줄 = {row, biz, company, address, phone, device, fee, start, end, renew, start2, end2, note, deposit, receivable, applied}
--   ① raw.upload(source 'rental_contract') 한 줄 → 명부 통째 교체 (execute 'DEL'||'ETE …')
--   ② 본계약·재계약 칸이 여러 줄이면 줄 순서끼리 짝 → periods · cur_end = 가장 늦은 종료
--   ③ 주소 '_x000D_'·'#N/A' 정리 · 연락처는 첫 번호만(여러 번호가 한 칸에 이어 적힌 줄) · 임대료 반올림
--   ④ 고객 잇기: 사업자번호(crm.customer.business_no) → 렌탈 청구 원장(core.orders source rental)의 같은 상호
--      (f_company_norm) → 한 사람만 쓰는 전화. 사업자번호가 빈 고객에게는 채움(account_type business)
--   ⑤ 응답 rows · companies · matched · by_biz/by_name/by_phone · closed · no_dates · active · due_90 · past_end · monthly_sum
-- public.fn_rental_contract_upsert(p_rows jsonb, p_file text default null) — admin·uploader · authenticated·service_role (anon 없음)

insert into core.data_source (key,label,owner,expect_days,how,sort_no,active,alert,feed_mode)
values ('rental_contract','렌탈 임대 계약 명부','렌탈 담당',365,
        '임대고객 계약기간 엑셀을 통째로 올리면 명부 전체가 바뀝니다 — 업체명으로 렌탈 청구 고객과 이어 붙입니다',51,true,false,'manual')
on conflict (key) do nothing;
-- core.f_data_status_build: sms_optout 앞에 rental_contract 줄 (기간 = 계약 시작 최소 ~ 적재일, 경과일은 적재 기준)

-- 첫 적재 (2026-10-27 · upload 1188): 337줄 · 303업체 · 고객 연결 255(상호 252 · 전화 3 · 사업자번호 0) ·
--   사업자번호 채운 고객 244 · 폐업 1 · 날짜 없음 52 · 계약 진행 중 22 · 90일 안 만료 6 · 종료일 지났는데 해지 표시 없음 262 ·
--   월 임대료 합 3,947만(전체) / 3,932만(폐업 제외). 최근 60일 렌탈 청구 고객 47 중 38 이 명부와 이어짐.
