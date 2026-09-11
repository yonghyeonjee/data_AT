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


/* ═══════════════════════════════════════════════════════════════
   2026-09-11 추가 — "진행전" 이 화면에서 빠지던 것 (DB 적용 완료)

   지메일로 들어온 문의는 result='진행전' 로 들어간다. 그런데
   fn_store_consults_all 이 열린 상담을 result in ('진행중','보류') 로 하드코딩하고 있어
   방금 들어온 문의가 [진행중 전체] 목록 · "진행중 N" 건수 · 출처/담당 칩에서 통째로 빠졌다.
   (crm.consult 에는 정상으로 들어가 있고 잔디 알림도 나갔는데 화면에만 안 보이던 상태)

   → core.f_consult_bucket(result) in ('open','hold') 로 바꿨다. 진행전 → open.
   → 정렬도 바꿨다 : 미배정 → 진행전(새 문의) → 내 상담 → 최근
   → counts 에 'new' (진행전 건수) 추가. 화면 요약줄에 "새 문의 N" 으로 나온다.

   잔디 알림도 이때 붙였다 :
     core.notify_channel.jandi_crm  = 웹훅 주소 + enabled
     core.notify_rule.inquiry_homepage (event 'inquiry.homepage')
     fn_inquiry_mail_ingest 이 한 건 넣을 때마다 core.f_notify 호출 (실패해도 적재는 진행)
   ═══════════════════════════════════════════════════════════════ */


/* ═══════════════════════════════════════════════════════════════
   2026-09-11 추가 ② — 문의 창구(채널) vs 방문경로 정리  (DB 적용 완료)

   홈페이지 폼의 "방문경로"(네이버·구글검색 / 온라인카페·커뮤니티 / 블로그 / 지인소개 / 기타)는
   창구가 아니라 홈페이지 문의의 세부다. 채널로 쪼개면 홈페이지 문의가 갈라진다.

   · core.inq_channel.naver → active=false (창구 목록에서 뺌. 기존 17건의 값은 그대로 둠)
   · 라벨·설명 정리 : 홈페이지 문의 = samsungat.co.kr 게시판 / 구독 문의 = 시흥몰·P몰 구독 페이지
   · core.inq_route 신설 — 유입경로 표준 목록 (채널별). fn_inq_codes 가 같이 내려준다.
     담당자 화면 상담 입력의 유입경로 드롭다운이 고른 채널 것을 위로 올려 보여준다.
   · core.f_consult_stats 에 'routes' 추가 — 채널 × 유입경로 × 구매 성공률.
     처리현황(담당자·관리자)에 "채널 안에서 유입경로별로" 접이식 표로 나온다.
   · fn_inquiry_mail_ingest : 사업자 게시판(제목에 사업자/법인/기업/B2B) 구분.
     내용 앞에 [사업자], crm.customer.account_type='business', 이메일 저장.
   ═══════════════════════════════════════════════════════════════ */

create table if not exists core.inq_route (
  code text primary key, label text not null, channel_code text, sort_no int default 100, active boolean default true);
alter table core.inq_channel add column if not exists note text;
