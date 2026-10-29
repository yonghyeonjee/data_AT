-- mvp_254 (2026-10-29) 구독 페이지 봇 차단 — 자급제 스팸 대응 + Cloudflare Turnstile 서버 확인
-- 이미 DB 에 적용됨 (기록용). secret 은 여기 적지 않는다.

-- ① 자급제 스팸 (14:13~14:33 · 21건 · 인스타그램 광고 주소 utm_source=meta&utm_medium=instagram_1022 · evt=preorder)
--    · 21건 hidden_reason '스팸 의심 (자급제 폼 반복 제출 · 인스타그램 광고 주소)' · 스팸이 만든 crm.customer 삭제
--    · 순번 core.assign_state default last_staff → '김규완' (assign_pool_log kind cursor)
--    fn_submit_inquiry 부분 치환:
--      v_spam := 자급제 and (pageUrl ~* 'utm_source=meta|instagram' or 3분 안 자급제 2건 이상)
--             or botCheck.hp = '1' or botCheck.ms < 4000 or botCheck.human = '0'   (SUB v1.6.2 페이지 검사값)
--      스팸이면 v_test := true · v_hand := '지용현' (순번·고객 표 영향 없음) · 끝에서 숨김
--      잔디 접수 카드: v_type not like '자급제%' 일 때만

-- ② Turnstile
create table if not exists core.turnstile_config (
  id int primary key default 1 check (id = 1),
  site_key text, secret text,
  mode text not null default 'log' check (mode in ('off','log','enforce')),
  timeout_ms int not null default 1500,
  updated_at timestamptz not null default now()
);
alter table core.turnstile_config enable row level security;
revoke all on core.turnstile_config from public, anon, authenticated;
-- insert into core.turnstile_config (id, site_key, secret, mode) values (1, '0x4AAAAAAFqp7LFwZAAhjdVD', '<SECRET — DB 에만>', 'log');

create or replace function core.f_turnstile_verify(p_token text)
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog','public' as $f$
declare c core.turnstile_config%rowtype; r record; j jsonb; t0 timestamptz := clock_timestamp();
begin
  select * into c from core.turnstile_config where id = 1;
  if not found or c.mode = 'off' or c.secret is null then
    return jsonb_build_object('checked', false, 'reason', 'off', 'enforce', false);
  end if;
  if nullif(trim(coalesce(p_token,'')),'') is null then
    return jsonb_build_object('checked', true, 'ok', false, 'reason', 'no_token', 'enforce', c.mode = 'enforce');
  end if;
  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', c.timeout_ms::text);
    select * into r from extensions.http(('POST', 'https://challenges.cloudflare.com/turnstile/v0/siteverify',
        array[]::extensions.http_header[], 'application/x-www-form-urlencoded',
        'secret=' || extensions.urlencode(c.secret) || '&response=' || extensions.urlencode(left(p_token, 2048)))::extensions.http_request);
    if r.status <> 200 then
      return jsonb_build_object('checked', true, 'ok', null, 'reason', 'http_' || r.status, 'enforce', c.mode = 'enforce',
        'ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
    end if;
    j := r.content::jsonb;
    return jsonb_build_object('checked', true, 'ok', coalesce((j->>'success')::boolean, false),
      'reason', case when coalesce((j->>'success')::boolean, false) then 'pass' else coalesce(j->'error-codes'->>0, 'fail') end,
      'codes', j->'error-codes', 'host', j->>'hostname', 'at', j->>'challenge_ts', 'action', j->>'action',
      'enforce', c.mode = 'enforce', 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
  exception when others then
    /* Cloudflare 가 응답하지 않으면 막지 않는다 (실제 고객을 잃지 않게) — ok null */
    return jsonb_build_object('checked', true, 'ok', null, 'reason', 'unreachable', 'err', left(sqlerrm, 200),
      'enforce', c.mode = 'enforce', 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
  end;
end $f$;
revoke all on function core.f_turnstile_verify(text) from public, anon, authenticated;

-- ③ fn_submit_inquiry 부분 치환 (pg_get_functiondef + 지점 개수 1 확인 + replace + execute)
--   declare  … v_spam boolean := false;  → + v_bv jsonb; v_why text;
--   v_ref 계산 바로 뒤:
--     if not exists (select 1 from crm.consult c where c.source = 'web_subscription' and c.source_ref = v_ref) then
--       v_bv := core.f_turnstile_verify(p_data->>'cfToken');
--       if coalesce((v_bv->>'enforce')::boolean, false) and v_bv->>'ok' = 'false' and not v_spam then
--         v_why := '봇 확인 실패 (' || (v_bv->>'reason') || ')';
--         v_spam := true; v_test := true; v_hand := '지용현';
--       end if;
--     end if;
--   insert raw_payload: p_data → (p_data - 'cfToken') || jsonb_build_object('botVerify', v_bv)
--   on conflict raw_payload: 재전송에 botVerify 가 없으면 이전 botVerify 유지
--   숨김 사유: coalesce(v_why, '스팸 의심 (자급제 폼 반복 제출)') · 응답에 'bot' (reason)
-- 롤백 시험 5경우: log·토큰 없음 → 기록만 / enforce·토큰 없음 → 숨김 no_token / enforce·가짜 토큰 → 숨김 invalid-input-response /
--   enforce·재전송 → 검사 안 함 / enforce·Cloudflare 응답 없음 → 정상 접수(ok null)
-- 켜기: update core.turnstile_config set mode = 'enforce' where id = 1;

-- ④ 2026-10-29 16:00 — 막는 모드 켬 · 인스타그램 규칙 풀기 (사용자 결정: 본 페이지 SUB v1.6.3 반영 확인 뒤)
--   fn_submit_inquiry 부분 치환: 자급제 스팸 조건에서 "pageUrl ~* 'utm_source=meta|instagram' or" 를 뺌
--     (남은 규칙 = 3분 안 자급제 2건 이상 · 페이지 botCheck · Turnstile)
--   update core.turnstile_config set mode = 'enforce' where id = 1;
--   롤백 시험: 인스타 주소 자급제·토큰 없음 → '봇 확인 실패 (no_token)' / 인스타 주소·Cloudflare 응답 없음 → 정상 접수(송희봉 배정)
--             일반 구독·가짜 토큰 → '봇 확인 실패 (invalid-input-response)'
--   미리보기 페이지 https://db.samsungat.co.kr/tools/godo/ts_demo.html?mode=check|pass|block (Cloudflare 테스트 키)
