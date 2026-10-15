-- mvp_218 · 2026-10-15 · 발송 링크 관리 [구매] = 링크를 누른 사람의 주문만 + 자동 발송 설정 3건 (이미 적용됨 · 기록)
-- "이 문자를 보고 들어온 주문만 해야지" — 전엔 bought = 수신자의 발송 뒤 아무 주문(기간 제한도 없음) → 토너 재구매가 그대로 '구매' 로 찍혔다.
--
-- ① 사람별 링크 토큰 — 단축 링크 슬러그(6자) + 토큰(6자) = 12자. 착지 페이지(r/index.html · 고도몰 /data/r.html)의
--    슬러그 검사 ^[a-z0-9]{3,12}$ 안이라 착지는 그대로. fn_link_go 가 12자면 갈라서 crm.link_rcpt 로 누구인지 적는다.
create table if not exists crm.link_rcpt (slug text not null references crm.link(slug), tok text not null, buyer_key char(16) not null, campaign text,
  created_at timestamptz not null default now(), primary key (slug, tok), unique (slug, buyer_key));
alter table crm.link_rcpt enable row level security;
alter table crm.link_hit add column if not exists tok text, add column if not exists buyer_key char(16);
create index if not exists ix_link_hit_bk on crm.link_hit (buyer_key) where buyer_key is not null;
-- core.f_link_rcpt(slug, key, campaign) → tok (같은 사람은 같은 토큰)
-- core.f_sms_link_personalize(body, key, campaign) → 본문 안 short_base||slug 를 short_base||slug||tok 로 (정규식 이스케이프는 alternation — 괄호식 안 '[.' 는 collating element)
-- fn_link_go(p_slug, p_ref, p_ua) : 12자면 link_rcpt 조회 → link_hit(slug, tok, buyer_key)
-- (본문은 서버에 적용된 그대로 — pg_get_functiondef 로 볼 것)
--
-- ② core.f_sms_send : 렌더 직후, 실제 발송(v_live)일 때만
--    if v_live then v_body := core.f_sms_link_personalize(v_body, nullif(r->>'key',''), nullif(p_campaign,'')); end if;
--    → 사람마다 본문이 달라지므로 화면 조각은 20명(SMS_LINK_RX 가 단축 링크를 보면 personal)
--
-- ③ fn_utm_campaigns : bought/bought_amt = 이 캠페인 링크의 link_hit(buyer_key 있는 것) 뒤 30일 안 주문(테스트 제외 · net>0)
--    + clicks_known · clickers · rcpt_links · bought_rcpt30(옛 규칙을 30일로 제한한 참고값 — 화면 툴팁에만)
--    fn_order_list · fn_order_summary 의 p_campaign 조건도 같은 규칙.
--
-- ④ 자동 발송 설정: fn_crm_followups('product', {pay}) onetime(구독이 아닌 것 — 온라인 주문의 구분 없음도 일시불) / sub / all
--    fn_auto_rule_preview product_age 가 params.pay 를 넘김 · combo_24 params.pay='onetime'
update crm.auto_rule set params = coalesce(params,'{}'::jsonb) || '{"pay":"onetime"}'::jsonb where code = 'combo_24';
-- 롤백 실험: 개인화 본문 'r.html?6nyudxnkc3fp'(같은 사람 같은 토큰 · 뒤에 글자 붙은 'x' 는 안 바꿈) → anon fn_link_go 12자 → hit buyer_key ✓ →
--   가짜 주문 → fn_utm_campaigns bought 1 · amt 50000 · clickers 1 · rcpt 1 · rcpt30 47 → fn_order_list(p_campaign) 1건 · summary net 50000 (raise 로 롤백)
