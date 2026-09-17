-- mvp_152 (2026-09-17) — UTM 관리: 캠페인 · 단축 링크 · 클릭
--
-- 왜
--   UTM 이 캠페인명에서 즉석으로 만들어져 링크에만 실려 나가고 어디에도 저장되지 않았다.
--   같은 발송이 네 군데에 각각 다른 이름으로 남았다 — access_log.reason(추출) · utm_campaign(링크) ·
--   센드온 캠페인명 · send_log.campaign(이미 보낸 고객). 한 글자라도 다르면 추출→발송→클릭→구매가 안 이어진다.
--   GA4 수집(tools/ga/collect.mjs)은 date·pagePath 만 가져와 utm_campaign 이 우리 DB 로 오지도 않았다.
--
-- 무엇
--   crm.campaign  코드(= utm_campaign, PK, yymm_주제) · 이름 · 문자 종류 · 랜딩 · 저장 조건(crm.segment.code) · 발송일
--   crm.link      슬러그 6자(헷갈리는 글자 제외) · 캠페인 · 랜딩 · UTM 붙은 긴 주소   → 단축 주소 https://db.samsungat.co.kr/r/?슬러그
--   crm.link_hit  클릭 기록 (슬러그 · 시각 · referrer · UA 앞 200자 — 개인정보 없음)
--   /r/index.html 착지 페이지 — fn_link_go(anon) 로 클릭을 적고 location.replace 로 긴 주소로 보낸다.
--   → 클릭 수를 GA4 없이 우리 DB 에서 바로 센다. 구매 열 = 그 캠페인 수신자 중 발송 뒤 주문.
--
-- RPC  fn_utm_campaigns / fn_utm_campaign_save / fn_utm_campaign_del(발송 이력 있으면 접기) / fn_utm_link_save / fn_utm_link_del(끄기·켜기 토글)
--      fn_link_go(p_slug, p_ref, p_ua) — anon. 나머지는 authenticated·service_role 만. 세 표는 RLS 만 켜고 정책 없음(definer 함수로만 접근).
--
-- 화면  관리자 메뉴 [UTM 관리](core.menu_item 'utm', crm 그룹) — 캠페인 표(발송·클릭·구매·매출) + 링크 줄(짧은/긴 주소 복사 · 클릭 · 끄기).
--       발송 대상 추출 [링크 만들기](utmQuick) — 캠페인명의 코드로 그 캠페인의 링크 창을 열고, 없으면 그 자리에서 등록(코드·이름·저장 조건 미리 채움) 뒤 링크.
--       [이미 보낸 고객] 캠페인 칸이 코드 목록(datalist)을 준다.
--
-- 데이터  캠페인 4건 등록(2608_toner · 2609_chuseok · 2609_toner · 2609_haf).
--        8/14 발송 이력 257줄의 campaign 을 '2026-08-14 토너·잉크 교체 안내 (LMS)' → '2608_toner' 로 (원래 이름은 campaign.note).

create table if not exists crm.campaign (
  code text primary key check (code ~ '^[a-z0-9][a-z0-9_]{2,39}$'),
  name text not null, medium text not null default 'lms' check (medium in ('sms','lms','mms','kakao','web')),
  landing text, segment_code text, send_on date, note text, active boolean not null default true,
  created_by text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists crm.link (
  slug text primary key, campaign text not null references crm.campaign(code) on delete cascade,
  label text, landing text not null, url text not null,
  utm_source text not null default 'sendon', utm_medium text, utm_campaign text, utm_content text, utm_term text,
  active boolean not null default true, created_by text, created_at timestamptz not null default now());
create table if not exists crm.link_hit (id bigserial primary key, slug text not null, at timestamptz not null default now(), ref text, ua text);
create index if not exists ix_link_hit_slug_at on crm.link_hit(slug, at);
alter table crm.campaign enable row level security; alter table crm.link enable row level security; alter table crm.link_hit enable row level security;

-- 헬퍼: core.f_slug(6) · core.f_utm_tok(값 → [a-z0-9_.-]) · core.f_utm_url(랜딩, source, medium, campaign, content, term)
-- RPC 본문은 DB 에 있다 (pg_get_functiondef 로 읽을 것). 여기서는 권한만 다시 적는다.
-- revoke all on function public.fn_utm_campaigns(), ...fn_link_go(text,text,text) from public, anon;
-- grant execute on function public.fn_utm_campaigns(), fn_utm_campaign_save(jsonb), fn_utm_campaign_del(text), fn_utm_link_save(jsonb), fn_utm_link_del(text) to authenticated, service_role;
-- grant execute on function public.fn_link_go(text,text,text) to anon, authenticated, service_role;

insert into core.menu_item (code, group_code, label, sort, state, note, envs)
values ('utm','crm','UTM 관리',50,'on','캠페인 · 단축 링크 · 클릭', array['test','prod'])
on conflict (code) do update set label=excluded.label, group_code=excluded.group_code, sort=excluded.sort, state='on';

insert into crm.campaign (code, name, medium, landing, segment_code, send_on, note, created_by) values
 ('2608_toner','토너·잉크 교체 안내 (8/14)','lms',null,null,'2026-08-14','send_log 원래 캠페인명: 2026-08-14 토너·잉크 교체 안내 (LMS)','system'),
 ('2609_chuseok','추석 구독 할인 대축제','mms','https://www.samsungsh.co.kr/board/view.php?bdId=blog&sno=90','camp_chuseok_0918','2026-09-18',null,'system'),
 ('2609_toner','VMS 토너 교체 안내','lms',null,'camp_toner_0921','2026-09-21',null,'system'),
 ('2609_haf','정수기 필터 교체 안내','lms',null,'camp_filter_0923','2026-09-23',null,'system')
on conflict (code) do nothing;
update crm.send_log set campaign='2608_toner' where campaign='2026-08-14 토너·잉크 교체 안내 (LMS)';

-- 남은 숙제: GA4 쪽에서도 보려면 tools/ga/collect.mjs 에 sessionCampaignName 차원 리포트를 추가해야 한다 (지금은 pagePath 만).
