-- mvp_307 (2026-11-23) — 구독 문의 가짜 번호 숨김 · 카카오 채널 요청(잔디 카드 + 순번 배정)
-- 적용 기록용. DB 에는 이미 반영돼 있다. 페이지 쪽은 tools/godo/sub_phone.md (SUB v1.7.3 ~ v1.7.5).
-- 주의: MCP execute_sql 로 다시 보낼 때는 CLAUDE.md '알아둘 함정' 의 금지 낱말을 피할 것.

-- ── 1. 가짜 번호 판정 (페이지 window.samSubPhoneCheck 와 같은 규칙) ─────────────────────────
create or replace function core.f_digits_plain(s text) returns boolean
language sql immutable set search_path to 'pg_catalog' as $f$
  /* 숫자 글자가 전부 같거나(0000) 1씩 오르내리면(1234 · 4321 · 7890) true */
  select s ~ '^[0-9]{2,}$' and (
       not exists (select 1 from generate_series(2, length(s)) i where substr(s, i, 1) <> substr(s, i - 1, 1))
    or not exists (select 1 from generate_series(2, length(s)) i where (substr(s, i, 1)::int - substr(s, i - 1, 1)::int + 10) % 10 <> 1)
    or not exists (select 1 from generate_series(2, length(s)) i where (substr(s, i - 1, 1)::int - substr(s, i, 1)::int + 10) % 10 <> 1));
$f$;

create or replace function core.f_phone_fake(p text) returns boolean
language plpgsql immutable set search_path to 'pg_catalog' as $f$
/* 형식이 틀린 번호는 여기서 판단하지 않는다(false).
   1) 앞 번호(010 · 지역번호) 뒤가 전부 같은 숫자거나 1씩 이어지는 숫자
   2) 010 바로 뒤가 0 · 1 (배정된 적 없는 대역)
   3) 휴대폰 앞 4 · 뒤 4자리가 둘 다 같은 숫자거나 이어지는 숫자 */
declare d text := regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g'); t text;
begin
  if d ~ '^01[016789][0-9]{7,8}$' then
    t := substr(d, 4);
    if core.f_digits_plain(t) then return true; end if;
    if length(t) = 8 then
      if left(d, 3) = '010' and left(t, 1) in ('0', '1') then return true; end if;
      if core.f_digits_plain(left(t, 4)) and core.f_digits_plain(right(t, 4)) then return true; end if;
    end if;
    return false;
  elsif d ~ '^0[0-9]{8,10}$' and left(d, 2) <> '01' then
    return core.f_digits_plain(substr(d, case when left(d, 2) = '02' then 3 else 4 end));
  end if;
  return false;
end $f$;
revoke all on function core.f_digits_plain(text) from public, anon, authenticated;
revoke all on function core.f_phone_fake(text) from public, anon, authenticated;

-- ── 2. fn_submit_inquiry — 부분 치환 1곳 (Turnstile 확인 블록 안 · 새 접수만) ────────────────
-- 지점(1개): "      v_spam := true; v_test := true; v_hand := '지용현';\n    end if;\n  end if;"  (봇 확인 실패 블록 끝)
-- 그 안쪽 end if 뒤에 끼운 글:
--     if not v_test and not v_spam and core.f_phone_fake(v_phone) then
--       v_why := '가짜 번호 의심';
--       v_spam := true; v_test := true; v_hand := '지용현';
--     end if;
-- → 저장은 하되 숨김 · 순번 안 돎 · 카드 없음 · crm.customer 에 안 넣음 · [삭제됨] 에서 복구. 테스트 이름은 테스트 경로 그대로.
-- pg_get_functiondef 를 읽어 지점 개수(1)를 확인하고 replace 한 뒤 execute (권한 · security definer · search_path 그대로).

-- ── 3. 카카오 채널 요청 ────────────────────────────────────────────────────────────────
create or replace function public.fn_kakao_request(p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog', 'public' as $f$
/* 구독 문의 페이지(SUB v1.7.5)의 번호 안내 창에서 [카카오톡 채널로 문의] 를 누른 고객 — 번호 없이 카카오로 상담을 원하는 경우.
   상담 한 건으로 남기고(채널 = 카카오채널 · 번호 없음) 잔디 CRM 방에 '카카오 채널 확인 필요' 카드를 보낸다.
   배정: 담당을 비워 넣는다 → 트리거 core.f_consult_assign_default → core.f_assign_next = 구독 폼과 같은 순번표
         (마지막 배정자 다음 사람 · 휴무자 건너뜀 · 끝이면 처음으로 이어짐). 순번표(core.assign_state)를 여기서 직접 고치지 않는다.
   거르기: Turnstile(사람 확인) 실패 · 10분에 5건 넘게 몰림 → 저장은 하되 숨김 · 순번 안 돎 · 카드 없음.
           이름에 테스트 → 테스트 방 카드 · 순번 안 돎. 같은 브라우저(cid)가 1시간 안에 다시 누르면 새로 만들지 않는다. */
declare
  v_name text := left(nullif(trim(regexp_replace(coalesce(p_data->>'customerName',''), '\s+', ' ', 'g')), ''), 40);
  v_item text := left(nullif(trim(p_data->>'modelName'), ''), 200);
  v_form text := left(coalesce(nullif(trim(p_data->>'formKind'), ''), '구독 신청서'), 30);
  v_cid  text := left(nullif(trim(p_data->>'cid'), ''), 40);
  v_memo text := left(nullif(trim(p_data->>'memo'), ''), 800);
  v_now timestamptz := now();
  v_ref text; v_id bigint; v_hand text; v_bv jsonb; v_why text; v_test boolean; v_spam boolean := false;
  v_src text; v_route text; v_content text; v_disp text;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' or length(p_data::text) > 8000 then
    raise exception '요청 형식이 올바르지 않습니다' using errcode = '22023';
  end if;
  if v_cid is not null then
    select c.id into v_id from crm.consult c
     where c.source = 'web_subscription' and c.channel_code = 'kakao' and c.consult_at > v_now - interval '60 minutes'
       and c.raw_payload->>'cid' = v_cid order by c.id desc limit 1;
    if v_id is not null then return jsonb_build_object('ok', true, 'again', true); end if;
  end if;
  v_test := coalesce(v_name, '') ~* 'test|테스트';
  v_bv := core.f_turnstile_verify(p_data->>'cfToken');
  if coalesce((v_bv->>'enforce')::boolean, false) and v_bv->>'ok' = 'false' then
    v_spam := true; v_why := '봇 확인 실패 (' || (v_bv->>'reason') || ')';
  elsif not v_test and (select count(*) from crm.consult c where c.source = 'web_subscription' and c.channel_code = 'kakao'
                           and c.consult_at > v_now - interval '10 minutes' and c.hidden_at is null and c.deleted_at is null) >= 5 then
    v_spam := true; v_why := '스팸 의심 (카카오 채널 요청 10분에 5건 넘음)';
  end if;
  v_hand := case when v_test or v_spam then '지용현' else null end;   /* null = 순번 배정(트리거) */
  v_disp := coalesce(v_name, '(이름 미입력)');
  v_ref := 'KKO' || to_char(v_now at time zone 'Asia/Seoul', 'YYYYMMDDHH24MISS') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  v_src := nullif(coalesce(core.f_inq_source(p_data), p_data->>'referralSource'), '');
  v_route := '카카오 채널 요청 · ' || v_form || case when v_src is not null then ' (' || left(v_src, 90) || ')' else '' end;
  v_content := concat_ws(' / ',
      '카카오톡 채널 상담 희망 (번호 미입력 · 카카오 채널 채팅에서 확인)',
      '접수 화면: ' || v_form,
      case when nullif(p_data->>'companyName','') is not null then '상호: ' || left(p_data->>'companyName', 60) end,
      case when nullif(p_data->>'purchasePurpose','') is not null then '목적: ' || left(p_data->>'purchasePurpose', 40) end,
      case when nullif(p_data->>'region','') is not null then '지역: ' || left(p_data->>'region', 60) end,
      v_memo);
  insert into crm.consult (source, source_ref, consult_at, handler, customer_name, phone, buyer_key, inflow_route,
    interest_category, result, content, consent_marketing, raw_payload, channel_code, type_code, type_codes)
  values ('web_subscription', v_ref, v_now, v_hand, v_disp, null, null, v_route,
    v_item, '진행전', v_content, false,
    (p_data - 'cfToken') || jsonb_build_object('kakaoRequest', true, 'contactMethod', '카카오톡') || case when v_bv is not null then jsonb_build_object('botVerify', v_bv) else '{}'::jsonb end,
    'kakao', core.f_inq_type_main(core.f_inq_types_from_form(p_data)), core.f_inq_types_from_form(p_data))
  returning id, handler into v_id, v_hand;
  if v_spam then
    update crm.consult set hidden_reason = v_why, hidden_at = coalesce(hidden_at, now()) where id = v_id;
  else
    perform core.f_notify(case when v_test then 'inquiry.subscription.test' else 'inquiry.subscription' end, jsonb_build_object(
      'id', v_id, 'name', case when v_test then '🧪 테스트 · ' else '' end || v_disp,
      'kind', '카카오 채널 확인 필요', 'icon', '💬', 'phone', '번호 없음 · 카카오톡 채널로 문의',
      'handler', coalesce(v_hand, '미배정') || case when v_test then ' (테스트 — 순번 안 돌림 · 통계 제외)' else '' end,
      'reassign', '',
      'detail', concat_ws(' | ',
        '카카오톡 채널 채팅함에서 ' || to_char(v_now at time zone 'Asia/Seoul', 'HH24:MI') || ' 무렵 들어온 고객을 확인해 주세요',
        '[카카오 채널 채팅 열기](https://business.kakao.com/space/10215965/channel/_NcxjaC/chats?t_src=business_partnercenter&t_ch=lnb&t_obj=%EB%82%B4%EC%B1%84%ED%8C%85_%ED%81%B4%EB%A6%AD)',   /* 채널 채팅 관리자 화면 바로가기 (v358) */
        v_form, v_item, nullif(left(coalesce(p_data->>'region',''), 40), ''), nullif(left(coalesce(v_memo,''), 200), '')),
      'ref', v_ref));
  end if;
  return jsonb_build_object('ok', true);
end $f$;
revoke all on function public.fn_kakao_request(jsonb) from public;
grant execute on function public.fn_kakao_request(jsonb) to anon, authenticated, service_role;

-- 롤백 실험(2026-11-23 · 알림 채널 · Turnstile 을 트랜잭션 안에서만 끄고 raise 로 되돌림)
--   순번표 마지막 = 차효범 · 오늘 휴무 권혁찬 · 김규완 → 요청 = 이수혁 / 같은 cid 재요청 = 변화 없음 /
--   다음 차례 송희봉을 휴무로 만들면 = 최태웅 / 테스트 이름 · 토큰 없음 = 지용현 숨김 · 순번 그대로.
