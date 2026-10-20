-- mvp_225 · 2026-10-20 · 문의 폼 유입 추적 — 처음 들어온 곳 → 직전 페이지 (적용 기록)
-- "추적안돼?" → 오늘 B2B 구독 #590 은 referralSource 가 'www.samsungsh.co.kr'(호스트만)이라 어느 페이지에서 왔는지 몰랐다.
-- 페이지(tools/godo/sub_track.html)가 referrerFull · entry* · lastExt* · gaClientId 를 싣고, 서버가 읽는다. GAS 는 그대로(Object.assign 으로 전부 넘김).
create or replace function core.f_url_host(u text) returns text language sql immutable as $$
  select nullif(lower(substring(coalesce(u,'') from '^[A-Za-z]+://([^/?#:]+)')), '')
$$;
create or replace function core.f_utm_label(u text) returns text language sql immutable as $$
  select nullif(concat_ws('/',
    nullif(lower(substring(coalesce(u,'') from '[?&]utm_source=([^&#]+)')),''),
    nullif(lower(substring(coalesce(u,'') from '[?&]utm_medium=([^&#]+)')),''),
    nullif(lower(substring(coalesce(u,'') from '[?&]utm_campaign=([^&#]+)')),'')), '')
$$;
-- core.f_ref_label(u)  : 주소 → '네이버 검색'·'네이버 블로그'·'구글'·'인스타그램'… / 우리 사이트면 '사이트 내 · 블로그 글 119 | 게시판 x | 상품 상세 n | 상품 목록 n | 페이지 htmid | 메인'
-- core.f_inq_source(p) : 처음 들어온 곳(pageUrl UTM > entryLanding UTM > entryRef 외부 > lastExt UTM·외부 '· 재방문' > referrerFull 외부)
--                        ' → ' 직전 페이지(referrerFull 이 사이트 안일 때) · 새 값이 하나도 없으면 null(옛 페이지 = 옛 동작) · 둘 다 없으면 '직접 유입'
-- core.f_consult_campaign(raw) : pageUrl → entryLanding → lastExtLanding 의 utm_campaign (발송 링크 관리 [문의] 연결)
-- (함수 본문은 DB 에 적용된 그대로 — pg_get_functiondef 로 볼 것)
--
-- fn_submit_inquiry 부분 치환 2곳 (v_route 유입경로):
--   case when nullif(p_data->>'referralSource','') is not null
--     → case when nullif(coalesce(core.f_inq_source(p_data), p_data->>'referralSource'),'') is not null
--   left(p_data->>'referralSource', 60) → left(coalesce(core.f_inq_source(p_data), p_data->>'referralSource'), 90)
-- 확인: 롤백 실험 — 새 값 있는 B2B 접수 'B2B 구독 폼 (네이버 검색 → 사이트 내 · 블로그 글 119)' · 옛 페이지 접수 '구독 폼 (www.samsungsh.co.kr)' 그대로.
