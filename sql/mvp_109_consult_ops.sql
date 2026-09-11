/* ═══════════════════════════════════════════════════════════════
   mvp_109 — 상담 운영 개선 (2026-09-11)  ※ DB 에 적용 완료. 기록용.

   · crm.consult.method (대면/전화/메시지) · deleted_at/deleted_by/delete_reason (삭제 대기)
   · crm.consult_live : hidden + deleted 제외
   · core.staff_leave + core.f_staff_on_leave → core.f_assign_next 가 휴가자 건너뜀
   · core.staff_pref (담당자별 탭 순서 등) · app_setting.quick_links (자주 가는 링크)
   · core.web_traffic + fn_traffic_ingest (GA4) · fn_funnel_stats (방문→문의→성공, admin/dev)
   · fn_inquiry_mail_ingest (지메일 견적문의 → 상담 자동 등록 + 자동 배정)
   · fn_store_consults_my : 휴지통 필터 · 채널/방법 검색 · 전체 보기 시 미완료 우선 · 견적서 전부(quotes) · 지난 상담 수(prior)
   · fn_store_consults_all / fn_consult_list : 내 상담 → 미완료 → 최근 순, 채널 검색
   · fn_store_consult_update : delete / restore (담당자는 7일 내) / method
   · core.f_consult_stats + fn_consult_stats(admin) + fn_store_consult_stats(store)
   · consult_source_check 에 'gmail_homepage' 추가

   함수 본문은 DB 가 원본입니다 :
     select pg_get_functiondef('public.fn_store_consults_my'::regproc);
   ═══════════════════════════════════════════════════════════════ */

alter table crm.consult
  add column if not exists method text,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by text,
  add column if not exists delete_reason text;
create index if not exists consult_deleted_idx on crm.consult (deleted_at) where deleted_at is not null;

create table if not exists core.staff_leave (
  id bigserial primary key, staff_name text not null, from_date date not null, to_date date not null,
  note text, created_by text, created_at timestamptz default now(), check (to_date >= from_date));
create table if not exists core.staff_pref (
  staff_name text not null, key text not null, value jsonb, updated_at timestamptz default now(), primary key (staff_name, key));
create table if not exists core.web_traffic (
  day date not null, page text not null, path text, sessions int default 0, users int default 0, views int default 0,
  source text default 'ga4', updated_at timestamptz default now(), primary key (day, page));

-- API 키 (해시만 저장) : gmail_inquiry = gm-inq-2f7c9a41d3e85b60 · ga_traffic = ga-trf-9b1e4c72a8d05f36
-- quick_links 기본값 : DPS · 시흥몰(고객) · 시흥몰(관리자)
