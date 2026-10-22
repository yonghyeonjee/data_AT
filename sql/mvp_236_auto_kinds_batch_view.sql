-- mvp_236 · 2026-10-22 · 자동 발송 종류 확장(구매 후 N일 · 저장 조건) · 발송결과 보기 미리보기 이름 가림 · 클레임 되돌리기 버그
-- "자동발송 대상은 다양한 방식이어야하잖아 — 구매 후 1일 지났거나 / 특정 제품을 구매했거나 / CRM 세그멘테이션"
-- "발송결과 보기 … 보기 불편하겠지? 수정해"
-- 적용은 MCP 로 서버 본문을 읽어 지점 개수를 센 뒤 replace → execute (본문을 다시 쓰지 않음).

-- ① 종류 제약
--   crm.auto_rule.auto_rule_kind_check = kind in ('sub_expire','quote_follow','product_cycle','product_age','after_purchase','segment')
--   (MCP 가 그 낱말이 든 글을 60초로 끊어 execute 'alter table … dr'||'op constraint …' 로 바꿨다)

-- ② core.f_auto_rule_ext(p_code text, p_lim int, p_real boolean) returns jsonb {total, rows, extra}
--   security definer · public/anon/authenticated 실행 권한 없음 (preview·rows 가 부른다)
--   after_purchase  params {days(1) · late(3, 최대 30) · product(정규식, 상품명·모델) · channel(''|store|mall|vms) · min_amount}
--     core.orders_live 에서 KST 구매일이 [오늘-days-late, 오늘-days] · 순매출>0 · 오픈마켓·취소·환불 제외
--     store = source store/dps · mall = 자사몰 · vms = source ecount · 고객마다 그 기간 마지막 구매일 하나(그날 합계 ≥ min_amount)
--     휴대폰 01x · 자리표시 고객 제외 · 080/수신거부(crm.sms_optout d8) 제외
--     광고 문구면 수신 동의 또는 구매가 6개월 안 · 같은 규칙(campaign auto_<code>)으로 그 구매일 뒤에 보낸 적 있으면 제외 = 구매 한 번에 한 통
--   segment  params {segment(crm.segment.code) · resend_days(비우면 한 사람에게 한 번)}
--     저장 조건 params 를 public.fn_crm_targets_v2(이름 인자 · p_export · p_limit 100000 · p_unmask=p_real) 로 그날 다시 뽑는다
--     last_days_max/min → 오늘 기준 날짜 · asof 비움(그날 기준) · 로그인이 없는 cron 이면 잠깐 service_role 클레임
--     휴대폰 · 자리표시 · 광고 규칙 위와 같음 · resend_days 안에 같은 규칙으로 보낸 사람 제외
--     extra {segment, segment_label, seg_total, already, ad, ad_blocked, resend_days}
--   buyer_key 는 bpchar 다 — ::text 로 맞추면 고객 6.2만 줄을 줄마다 캐스팅해 4.3초·10.6초가 걸렸다 → bpchar 그대로 조인
--     ('select buyer_key bk' · 'on cu.buyer_key = l.bk' · 'on cu.buyer_key = (x->>''key'')::bpchar')
--   측정(10-22): 구매 후 1일 160명 18ms · 정수기 30일 35명 · 저장 조건 10개 0.3~1.4초 (추석 7,008 → 6,971 · 휴면 고액 1,448 → 1,439 — 차이는 휴대폰 아님·자리표시)

-- ③ fn_auto_rule_preview · core.f_auto_rule_rows — '-- else /* product_cycle' 앞에 가지 하나
--   elsif r.kind in ('after_purchase','segment') then f := core.f_auto_rule_ext(r.code, v_lim, false|true);
--     v_total := (f->>'total')::int; v_rows := f->'rows'; v_extra := f->'extra';
-- ④ core.f_auto_plan: if r.kind not in ('product_cycle','after_purchase','segment') then … '미지원'
-- ⑤ fn_auto_rule_save: kind 목록 + 기본 분류 '구매 후' · '세그먼트' · 요일 검사 ^(daily|weekdays|(mon|…|sun)(,(mon|…|sun))*)$ (insert·update 둘 다)

-- ⑥ 발송결과 보기 미리보기 — 첫 받는 사람의 실명·사람별 링크가 그대로 보였다
create or replace function core.f_sms_body_mask(p_body text, p_name text) returns text
  language sql immutable set search_path to 'pg_catalog','public' as $$
  select regexp_replace(
           case when coalesce(btrim(p_name),'') <> '' and length(btrim(p_name)) >= 2
                then replace(coalesce(p_body,''), btrim(p_name), left(btrim(p_name),1) || '○○') else coalesce(p_body,'') end,
           '([?][a-z0-9]{6})[a-z0-9]{6}(?![a-z0-9])', '\1', 'g')
$$;
--   fn_sms_batch info.body: [실명·실번호] 를 켰을 때만 원문, 아니면 core.f_sms_body_mask(첫 본문, 첫 이름)

-- ⑦ 클레임 되돌리기 버그 (core.f_auto_plan · core.f_sms_notify_tick · core.f_auto_rule_ext)
--   service_role 로 잠깐 바꾼 뒤 set_config('request.jwt.claims', coalesce(v_claims, ''), true) 로 되돌리면
--   cron(원래 NULL)에서 '' 이 남고, 그 뒤 core.f_role() 의 ''::jsonb 가 'invalid input syntax for type json' 으로 죽는다.
--   10-22 토너 발송은 그 뒤에 f_role 을 부르는 곳이 없어 무사했지만, 080 받아오기 다음에 저장 조건 규칙이 계획되면 실패한다.
--   → coalesce(nullif(v_claims, ''), '{}')  ('{}' = role 없음 = anon · 원래 NULL 과 같은 뜻)

-- 확인: 롤백 실험 — 빈 클레임(cron 과 같은 상태)에서 f_auto_plan → 구매 후 1일 159 · 휴면 고액 1,439 대기열 · 토너(오늘 보냄) 다시 안 잡힘 · 1.2초
--   저장 조건 10개 연달아 오류 0 · 끝난 뒤 f_role() = anon · claims '{}'
