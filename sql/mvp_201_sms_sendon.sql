-- mvp_201 · 문자 발송 (센드온) — 설정 · 템플릿 · 발송 엔진 · 관리자/담당자 RPC (2026-10-12 · v188)
-- 센드온 API: POST https://api.sendon.io/v2/messages/sms · Authorization: Basic base64(계정ID:API KEY)
--   응답은 늘 HTTP 200, 본문 code 로 판정 · 허용 IP(Supabase egress 43.201.156.141) 를 센드온 콘솔에 등록해야 호출된다
--   type SMS(90바이트)/LMS(2000바이트 · title 필수) · from 발신번호(숫자만) · to [번호…] · message · isAd(기본 true!)
-- 모드 test = 센드온을 부르지 않고 crm.sms_message 에 'test' 로만 기록 · live = 실제 호출 (crm.send_log 에도 쌓여 다음 추출에서 빠진다)

-- ─── 1. 설정 (키는 서버에만 · 화면엔 앞4·뒤4 마스킹) ─────────────────────────
create table if not exists core.sms_config (
  id            int primary key default 1 check (id = 1),
  provider      text not null default 'sendon',
  account_id    text,
  api_key       text,
  sender_no     text,
  mode          text not null default 'test' check (mode in ('test','live')),
  enabled       boolean not null default true,        -- 담당자 화면에 [문자] 버튼을 보일지
  ad_prefix     text not null default '(광고)',
  ad_footer     text not null default '',             -- 예: 무료수신거부 080-000-0000
  daily_limit   int  not null default 2000,
  last_check_at timestamptz, last_check jsonb,
  egress_ip     text, egress_at timestamptz,
  updated_at    timestamptz not null default now(), updated_by text
);
insert into core.sms_config (id) values (1) on conflict (id) do nothing;
alter table core.sms_config enable row level security;

-- ─── 2. 템플릿 — {이름} {담당자} {매장전화} {견적링크} {기한} {모델} {월요금} {콜백시각} {링크} ─────────
create table if not exists crm.sms_template (
  code   text primary key, label text not null, body text not null,
  scope  text not null default 'both' check (scope in ('store','admin','both')),
  is_ad  boolean not null default false, sort int not null default 100, active boolean not null default true,
  note   text, updated_at timestamptz not null default now()
);
alter table crm.sms_template enable row level security;
insert into crm.sms_template (code, label, body, scope, is_ad, sort, note) values
 ('quote_link',    '견적서 링크',     E'[삼성스토어 시흥점] {이름} 님 견적서입니다.\n{모델}\n{월요금}\n{견적링크}\n({기한}일간 열람 가능)\n문의 {담당자} 프로 · {매장전화}', 'store', false, 10, '견적서 [보내기] 창에서 자동으로 채워집니다'),
 ('callback_today','콜백 당일 안내',  E'[삼성스토어 시흥점] {이름} 님, 오늘 {콜백시각}에 {담당자} 프로가 연락드리겠습니다. 문의 {매장전화}', 'store', false, 20, null),
 ('thanks',        '상담 감사',       E'[삼성스토어 시흥점] {이름} 님, 오늘 상담 감사합니다. 궁금한 점은 {담당자} 프로에게 편하게 연락 주세요. {매장전화}', 'store', false, 30, null),
 ('camp_default',  '캠페인 기본 (광고)', E'{이름} 님, 삼성스토어 시흥점입니다.\n\n(여기에 안내 내용)\n\n{링크}', 'admin', true, 40, '광고는 (광고) 머리말과 수신거부 꼬리말이 자동으로 붙습니다'),
 ('test',          '테스트 문자',     E'[삼성스토어 시흥점] 테스트 문자입니다 — {이름} 님께 보내는 연동 확인용이며 답장하지 않으셔도 됩니다.', 'both', false, 90, null)
on conflict (code) do nothing;

-- ─── 3. 보낸 문자 한 줄씩 (테스트·실제 모두) ────────────────────────────────
create table if not exists crm.sms_message (
  id            bigserial primary key,
  batch_id      uuid not null,
  campaign      text, kind text not null default 'manual',       -- quote·callback·thanks·manual·campaign·test
  buyer_key     text, name text, phone text not null,
  d8            text generated always as (right(regexp_replace(phone, '\D', '', 'g'), 8)) stored,
  consult_id    bigint, quote_no text,
  msg_type      text not null, title text, body text not null, bytes int not null, is_ad boolean not null default false,
  mode          text not null check (mode in ('test','live')),
  status        text not null check (status in ('test','sent','failed','blocked')),
  block_reason  text,
  provider_group_id text, provider_code int, provider_msg text,
  sent_by       text, created_at timestamptz not null default now()
);
create index if not exists ix_sms_msg_at   on crm.sms_message (created_at desc);
create index if not exists ix_sms_msg_by   on crm.sms_message (sent_by, created_at desc);
create index if not exists ix_sms_msg_d8   on crm.sms_message (d8, created_at desc);
alter table crm.sms_message enable row level security;

create table if not exists core.sms_api_log (
  id bigserial primary key, at timestamptz not null default now(), path text, req jsonb,
  http_status int, code int, message text, ok boolean, ms int, called_by text
);
alter table core.sms_api_log enable row level security;

-- ─── 4. 도우미 ───────────────────────────────────────────────────────────
-- 바이트 = 통신사 셈법(EUC-KR): ASCII 1 · 그 밖(한글·기호) 2
create or replace function core.f_sms_bytes(p text) returns int language sql immutable as $f$
  select coalesce((select sum(case when ascii(c) < 128 then 1 else 2 end) from regexp_split_to_table(coalesce(p,''), '') c), 0)::int;
$f$;
-- {이름} 같은 자리를 값으로 — 값이 없는 자리는 빈 글로. 줄이 비면(값이 없어 빈 줄) 그 줄은 뺀다
create or replace function core.f_sms_render(p_body text, p_vars jsonb) returns text language plpgsql immutable as $f$
declare k text; v text := coalesce(p_body,'');
begin
  if p_vars is not null and jsonb_typeof(p_vars) = 'object' then
    for k in select jsonb_object_keys(p_vars) loop v := replace(v, '{'||k||'}', coalesce(p_vars->>k,'')); end loop;
  end if;
  v := regexp_replace(v, '\{[^{}\n]{1,20}\}', '', 'g');
  v := regexp_replace(v, '\n[ \t·]*\n', E'\n', 'g');
  return btrim(v, E' \n');
end $f$;
create or replace function core.f_sms_mask(p text) returns text language sql immutable as $f$
  select case when p is null or length(regexp_replace(p,'\D','','g')) < 8 then p
              else left(regexp_replace(p,'\D','','g'),3)||'-****-'||right(regexp_replace(p,'\D','','g'),4) end;
$f$;

-- ─── 5. 발송 엔진 — 한 번의 보내기(batch) · 수신자 묶음 · 본문 하나 ──────────────
-- p_rows: [{phone, name, key, consult_id, quote_no, vars{…}}] · 본문의 {이름} 은 name 으로 (vars 가 우선)
-- 광고(p_is_ad)면 머리말 '(광고)' + 꼬리말(080) 을 붙인다. 수신거부(crm.sms_optout)·번호 형식·같은 번호 중복은 blocked.
-- live 모드: 같은 본문끼리 묶어 센드온을 한 번씩 부른다(개인화 본문이면 사람마다 한 번 — 화면이 조각을 작게 보낸다).
-- 줄 모음은 temp table 이 아니라 jsonb 배열(v_q) — MCP 로 함수를 올릴 수 있게.
create or replace function core.f_sms_send(p_rows jsonb, p_body text, p_title text, p_campaign text, p_kind text,
                                           p_is_ad boolean, p_by text, p_opt jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare c core.sms_config%rowtype; v_batch uuid := gen_random_uuid(); r jsonb; v_phone text; v_name text; v_body text; v_bytes int;
        v_type text; v_reason text; v_seen text[] := '{}'; v_today int; v_live boolean; v_q jsonb := '[]'::jsonb; v_i int := 0;
        v_calls int := 0; v_groups jsonb := '[]'::jsonb; v_tel text;
        g record; v_res record; v_http int; v_json jsonb; v_code int; v_msg text; v_gid text; v_t timestamptz; v_auth text; v_payload jsonb;
        v_title text; v_kind text := coalesce(nullif(p_kind,''),'manual'); v_prefix text; v_footer text; v_force_test boolean;
        v_max int := coalesce(nullif(p_opt->>'max','')::int, 500); v_first text; v_first_type text; v_first_bytes int;
begin
  select * into c from core.sms_config where id = 1;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception '받는 사람이 없습니다' using errcode='22023'; end if;
  if jsonb_array_length(p_rows) > v_max then raise exception '한 번에 %명까지 보낼 수 있습니다 (지금 %명)', v_max, jsonb_array_length(p_rows) using errcode='22023'; end if;
  if btrim(coalesce(p_body,'')) = '' then raise exception '보낼 내용이 없습니다' using errcode='22023'; end if;
  v_force_test := coalesce((p_opt->>'test')::boolean, false);
  v_live := c.mode = 'live' and not v_force_test;
  if v_live and (coalesce(c.account_id,'') = '' or coalesce(c.api_key,'') = '' or coalesce(c.sender_no,'') = '') then
    raise exception '센드온 계정·API KEY·발신번호를 먼저 설정에 넣어 주세요' using errcode='22023'; end if;
  v_prefix := case when p_is_ad then coalesce(nullif(c.ad_prefix,''),'(광고)') else '' end;
  v_footer := case when p_is_ad then coalesce(c.ad_footer,'') else '' end;
  v_title  := coalesce(nullif(btrim(p_title),''), '삼성스토어 시흥점');
  v_tel    := coalesce((select value from core.app_setting where key='store_tel'),'');
  if v_live then
    select count(*) into v_today from crm.sms_message where mode='live' and status='sent' and created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
    if v_today + jsonb_array_length(p_rows) > c.daily_limit then
      raise exception '오늘 발송 상한(%건)을 넘습니다 — 지금까지 %건. 설정에서 상한을 올리거나 내일 보내세요', c.daily_limit, v_today using errcode='22023'; end if;
  end if;

  -- 1) 줄마다 본문을 만들고 검사한다 (테스트·실제 공통)
  for r in select value from jsonb_array_elements(p_rows) loop
    v_phone := regexp_replace(coalesce(r->>'phone',''), '\D', '', 'g');
    v_name  := coalesce(nullif(r->>'name',''), '고객');
    v_body  := core.f_sms_render(p_body, coalesce(r->'vars','{}'::jsonb) || jsonb_build_object('이름', v_name, '매장전화', v_tel));
    if p_is_ad then
      if v_body !~ '^\(광고\)' then v_body := v_prefix || ' ' || v_body; end if;
      if v_footer <> '' and position(v_footer in v_body) = 0 then v_body := v_body || E'\n' || v_footer; end if;
    end if;
    v_bytes := core.f_sms_bytes(v_body);
    v_type  := case when v_bytes <= 90 then 'SMS' else 'LMS' end;
    v_reason := null;
    if v_phone !~ '^01[016789][0-9]{7,8}$' then v_reason := '번호 형식';
    elsif v_phone = any(v_seen) then v_reason := '같은 번호 중복';
    elsif exists (select 1 from crm.sms_optout o where o.released_at is null and o.d8 = right(v_phone, 8)) then v_reason := '수신거부';
    elsif v_bytes > 2000 then v_reason := '2,000바이트 초과';
    end if;
    v_seen := v_seen || v_phone;
    v_q := v_q || jsonb_build_object('i', v_i, 'phone', v_phone, 'name', v_name, 'key', nullif(r->>'key',''), 'consult_id', nullif(r->>'consult_id',''),
                                     'quote_no', nullif(r->>'quote_no',''), 'body', v_body, 'bytes', v_bytes, 'msg_type', v_type,
                                     'status', case when v_reason is null then 'ok' else 'blocked' end, 'reason', v_reason);
    v_i := v_i + 1;
    if v_first is null then v_first := v_body; v_first_type := v_type; v_first_bytes := v_bytes; end if;
  end loop;

  -- 2) 실제 발송 — 같은 본문·종류끼리 한 번에
  if v_live then
    v_auth := 'Basic ' || replace(encode(convert_to(c.account_id || ':' || c.api_key, 'UTF8'), 'base64'), E'\n', '');
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', coalesce(p_opt->>'timeout_ms', '4000'));
    for g in select x->>'body' body, x->>'msg_type' msg_type, array_agg(x->>'phone' order by (x->>'i')::int) phones
               from jsonb_array_elements(v_q) x where x->>'status' = 'ok' group by 1, 2 loop
      v_payload := jsonb_build_object('type', g.msg_type, 'from', regexp_replace(c.sender_no,'\D','','g'), 'to', to_jsonb(g.phones),
                                      'message', g.body, 'isAd', coalesce(p_is_ad,false), 'useCredit', false)
                   || case when g.msg_type = 'LMS' then jsonb_build_object('title', v_title) else '{}'::jsonb end;
      v_t := clock_timestamp(); v_calls := v_calls + 1; v_json := null; v_code := null; v_msg := null; v_gid := null; v_http := null;
      begin
        select status, content into v_res from extensions.http((
          'POST', 'https://api.sendon.io/v2/messages/sms',
          array[extensions.http_header('Authorization', v_auth), extensions.http_header('Accept', 'application/json')],
          'application/json', v_payload::text)::extensions.http_request);
        v_http := v_res.status;
        begin v_json := v_res.content::jsonb; exception when others then v_json := jsonb_build_object('_raw', left(v_res.content, 300)); end;
        v_code := coalesce(nullif(v_json->>'code','')::int, v_http);
        v_msg  := coalesce(v_json->>'message', left(v_res.content, 200));
        v_gid  := v_json#>>'{data,groupId}';
        if v_http <> 200 then v_msg := 'HTTP ' || v_http || ' · ' || coalesce(v_msg,''); end if;
      exception when others then v_code := 0; v_msg := '연결 실패 · ' || sqlerrm;
      end;
      insert into core.sms_api_log (path, req, http_status, code, message, ok, ms, called_by)
      values ('/v2/messages/sms', v_payload - 'to' || jsonb_build_object('to_n', cardinality(g.phones)), v_http, v_code, left(v_msg, 300),
              v_code = 200, extract(milliseconds from clock_timestamp() - v_t)::int, p_by);
      select coalesce(jsonb_agg(case when x->>'status' = 'ok' and x->>'body' = g.body and x->>'msg_type' = g.msg_type
                                     then x || jsonb_build_object('status', case when v_code = 200 then 'sent' else 'failed' end, 'reason', case when v_code = 200 then null else v_msg end, 'gid', v_gid)
                                     else x end order by (x->>'i')::int), '[]'::jsonb)
        into v_q from jsonb_array_elements(v_q) x;
      v_groups := v_groups || jsonb_build_object('group_id', v_gid, 'code', v_code, 'message', v_msg, 'n', cardinality(g.phones));
    end loop;
    perform extensions.http_reset_curlopt();
  else
    select coalesce(jsonb_agg(case when x->>'status' = 'ok' then x || '{"status":"test"}'::jsonb else x end order by (x->>'i')::int), '[]'::jsonb) into v_q from jsonb_array_elements(v_q) x;
  end if;

  -- 3) 기록 — 줄마다 crm.sms_message · 실제로 나간 것(실패 포함)은 crm.send_log 에도 (다음 추출에서 빠지도록)
  insert into crm.sms_message (batch_id, campaign, kind, buyer_key, name, phone, consult_id, quote_no, msg_type, title, body, bytes, is_ad, mode, status, block_reason, provider_group_id, sent_by)
  select v_batch, nullif(p_campaign,''), v_kind, x->>'key', x->>'name', x->>'phone', (x->>'consult_id')::bigint, x->>'quote_no', x->>'msg_type',
         case when x->>'msg_type'='LMS' then v_title end, x->>'body', (x->>'bytes')::int, coalesce(p_is_ad,false),
         case when v_live then 'live' else 'test' end, x->>'status', x->>'reason', x->>'gid', p_by
    from jsonb_array_elements(v_q) x;
  if v_live then
    insert into crm.send_log (buyer_key, channel, campaign, sent_at, status, error_msg)
    select x->>'key', 'sms', coalesce(nullif(p_campaign,''), 'sms_' || to_char(now() at time zone 'Asia/Seoul','YYMMDD')), now(),
           case when x->>'status'='sent' then 'sent' else 'failed' end, x->>'reason'
      from jsonb_array_elements(v_q) x where length(coalesce(x->>'key','')) = 16 and x->>'status' in ('sent','failed')
    on conflict (campaign, buyer_key) do update set sent_at = excluded.sent_at, status = excluded.status, error_msg = excluded.error_msg;
  end if;

  return jsonb_build_object('batch_id', v_batch, 'mode', case when v_live then 'live' else 'test' end, 'total', jsonb_array_length(p_rows),
    'sent',    (select count(*) from jsonb_array_elements(v_q) x where x->>'status'='sent'),
    'test',    (select count(*) from jsonb_array_elements(v_q) x where x->>'status'='test'),
    'blocked', (select count(*) from jsonb_array_elements(v_q) x where x->>'status'='blocked'),
    'failed',  (select count(*) from jsonb_array_elements(v_q) x where x->>'status'='failed'),
    'calls', v_calls, 'groups', v_groups,
    'preview', jsonb_build_object('body', v_first, 'type', v_first_type, 'bytes', v_first_bytes, 'title', case when v_first_type='LMS' then v_title end),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('phone', core.f_sms_mask(x->>'phone'), 'name', x->>'name', 'status', x->>'status', 'reason', x->>'reason', 'type', x->>'msg_type', 'bytes', (x->>'bytes')::int) order by (x->>'i')::int), '[]'::jsonb)
                from (select x from jsonb_array_elements(v_q) x order by (x->>'i')::int limit 60) s));
end $f$;
revoke all on function core.f_sms_send(jsonb,text,text,text,text,boolean,text,jsonb) from public, anon, authenticated;

-- ─── 6. 관리자 RPC ───────────────────────────────────────────────────────
create or replace function public.fn_sms_config_get() returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $f$
declare c core.sms_config%rowtype;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 볼 수 있습니다' using errcode='42501'; end if;
  select * into c from core.sms_config where id = 1;
  return jsonb_build_object(
    'account_id', c.account_id, 'has_key', coalesce(c.api_key,'') <> '',
    'key_masked', case when coalesce(c.api_key,'') = '' then null else left(c.api_key,4)||repeat('•',10)||right(c.api_key,4) end,
    'sender_no', c.sender_no, 'mode', c.mode, 'enabled', c.enabled, 'ad_prefix', c.ad_prefix, 'ad_footer', c.ad_footer,
    'daily_limit', c.daily_limit, 'last_check_at', to_char(c.last_check_at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'last_check', c.last_check,
    'egress_ip', c.egress_ip, 'egress_at', to_char(c.egress_at at time zone 'Asia/Seoul','MM-DD HH24:MI'),
    'updated_at', to_char(c.updated_at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'updated_by', c.updated_by,
    'templates', (select coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label,'body',body,'scope',scope,'is_ad',is_ad,'sort',sort,'active',active,'note',note) order by sort, code), '[]'::jsonb) from crm.sms_template),
    'today', (select jsonb_build_object('live', count(*) filter (where mode='live' and status='sent'), 'test', count(*) filter (where mode='test'), 'failed', count(*) filter (where status='failed'), 'blocked', count(*) filter (where status='blocked'))
                from crm.sms_message where created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'),
    'week', (select jsonb_build_object('live', count(*) filter (where mode='live' and status='sent'), 'test', count(*) filter (where mode='test')) from crm.sms_message where created_at >= now() - interval '7 days'),
    'api_recent', (select coalesce(jsonb_agg(jsonb_build_object('at', to_char(at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'path', path, 'code', code, 'ok', ok, 'message', message, 'ms', ms, 'by', called_by) order by at desc), '[]'::jsonb)
                     from (select * from core.sms_api_log order by at desc limit 10) l));
end $f$;
revoke all on function public.fn_sms_config_get() from public, anon;
grant execute on function public.fn_sms_config_get() to authenticated, service_role;

create or replace function public.fn_sms_config_save(p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare t jsonb; v_email text := (select p.email from public.profiles p where p.id = auth.uid()); v_mode text;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 바꿀 수 있습니다' using errcode='42501'; end if;
  v_mode := nullif(p_data->>'mode','');
  if v_mode is not null and v_mode not in ('test','live') then raise exception '모드는 test 또는 live' using errcode='22023'; end if;
  if nullif(btrim(p_data->>'sender_no'),'') is not null and regexp_replace(p_data->>'sender_no','\D','','g') !~ '^0[0-9]{8,10}$' then
    raise exception '발신번호는 숫자만 9~11자리 (예: 03180423166)' using errcode='22023'; end if;
  update core.sms_config set
    account_id  = case when p_data ? 'account_id' then nullif(btrim(p_data->>'account_id'),'') else account_id end,
    api_key     = coalesce(nullif(btrim(p_data->>'api_key'),''), api_key),
    sender_no   = case when p_data ? 'sender_no' then nullif(regexp_replace(p_data->>'sender_no','\D','','g'),'') else sender_no end,
    mode        = coalesce(v_mode, mode),
    enabled     = coalesce((p_data->>'enabled')::boolean, enabled),
    ad_prefix   = coalesce(nullif(btrim(p_data->>'ad_prefix'),''), ad_prefix),
    ad_footer   = case when p_data ? 'ad_footer' then btrim(coalesce(p_data->>'ad_footer','')) else ad_footer end,
    daily_limit = coalesce(nullif(p_data->>'daily_limit','')::int, daily_limit),
    updated_at = now(), updated_by = v_email
   where id = 1;
  if coalesce((p_data->>'clear_key')::boolean, false) then update core.sms_config set api_key = null where id = 1; end if;
  if p_data ? 'templates' and jsonb_typeof(p_data->'templates') = 'array' then
    for t in select value from jsonb_array_elements(p_data->'templates') loop
      if coalesce(t->>'code','') !~ '^[a-z0-9_]{2,40}$' then raise exception '템플릿 코드는 영문 소문자·숫자·_ (%)', t->>'code' using errcode='22023'; end if;
      if coalesce((t->>'delete')::boolean,false) then delete from crm.sms_template where code = t->>'code'; continue; end if;
      insert into crm.sms_template (code, label, body, scope, is_ad, sort, active, note)
      values (t->>'code', coalesce(nullif(t->>'label',''), t->>'code'), coalesce(t->>'body',''), coalesce(nullif(t->>'scope',''),'both'),
              coalesce((t->>'is_ad')::boolean,false), coalesce(nullif(t->>'sort','')::int,100), coalesce((t->>'active')::boolean,true), t->>'note')
      on conflict (code) do update set label=excluded.label, body=excluded.body, scope=excluded.scope, is_ad=excluded.is_ad, sort=excluded.sort, active=excluded.active, note=excluded.note, updated_at=now();
    end loop;
  end if;
  insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), v_email, 'sms_config:save', 1,
    'mode=' || coalesce(v_mode,'(그대로)') || case when nullif(btrim(p_data->>'api_key'),'') is not null then ' · 키 교체' else '' end);
  return public.fn_sms_config_get();
end $f$;
revoke all on function public.fn_sms_config_save(jsonb) from public, anon;
grant execute on function public.fn_sms_config_save(jsonb) to authenticated, service_role;

-- 연결 확인 — 발신번호 목록·포인트를 읽는다(문자는 안 나감) + 우리 서버 공인 IP
create or replace function public.fn_sms_check() returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare c core.sms_config%rowtype; v_auth text; v_res record; v_http int; v_json jsonb; v_t timestamptz; v_out jsonb := '{}'::jsonb;
        v_nums jsonb; v_pts jsonb; v_ip text; v_code int; v_msg text; v_email text := (select p.email from public.profiles p where p.id = auth.uid());
begin
  if core.f_role() <> 'admin' then raise exception '관리자만' using errcode='42501'; end if;
  select * into c from core.sms_config where id = 1;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '4000');
  begin select content into v_ip from extensions.http_get('https://api.ipify.org'); exception when others then v_ip := null; end;
  if v_ip ~ '^[0-9.]+$' then update core.sms_config set egress_ip = v_ip, egress_at = now() where id = 1; else v_ip := c.egress_ip; end if;
  if coalesce(c.account_id,'') = '' or coalesce(c.api_key,'') = '' then
    perform extensions.http_reset_curlopt();
    return jsonb_build_object('ok', false, 'message', '계정 아이디와 API KEY 를 먼저 저장하세요', 'ip', v_ip); end if;
  v_auth := 'Basic ' || replace(encode(convert_to(c.account_id || ':' || c.api_key, 'UTF8'), 'base64'), E'\n', '');
  v_t := clock_timestamp();
  begin
    select status, content into v_res from extensions.http((
      'GET', 'https://api.sendon.io/v2/sender/numbers?cursor=0&limit=20',
      array[extensions.http_header('Authorization', v_auth), extensions.http_header('Accept', 'application/json')], null, null)::extensions.http_request);
    v_http := v_res.status;
    begin v_json := v_res.content::jsonb; exception when others then v_json := jsonb_build_object('_raw', left(v_res.content, 300)); end;
    v_code := coalesce(nullif(v_json->>'code','')::int, v_http); v_msg := coalesce(v_json->>'message', left(v_res.content,200));
    v_nums := case when jsonb_typeof(v_json#>'{data,list}') = 'array' then
      (select jsonb_agg(jsonb_build_object('number', x->>'senderNumber', 'status', x->>'senderStatus', 'name', x->>'displayName', 'default', x->>'isDefault', 'type', x->>'numberType')) from jsonb_array_elements(v_json#>'{data,list}') x) end;
  exception when others then v_code := 0; v_msg := '연결 실패 · ' || sqlerrm; end;
  insert into core.sms_api_log (path, req, http_status, code, message, ok, ms, called_by)
  values ('/v2/sender/numbers', '{}'::jsonb, v_http, v_code, left(v_msg,300), v_code = 200, extract(milliseconds from clock_timestamp() - v_t)::int, v_email);
  v_out := jsonb_build_object('ok', v_code = 200, 'code', v_code, 'message', v_msg, 'numbers', coalesce(v_nums,'[]'::jsonb), 'ip', v_ip);
  if v_code = 200 then
    begin
      select status, content into v_res from extensions.http((
        'GET', 'https://api.sendon.io/v2/point/points',
        array[extensions.http_header('Authorization', v_auth), extensions.http_header('Accept', 'application/json')], null, null)::extensions.http_request);
      v_json := v_res.content::jsonb; v_pts := v_json#>'{data,points,0,general}';
      v_out := v_out || jsonb_build_object('points', v_pts->>'points', 'credits', v_pts->>'credits');
    exception when others then v_out := v_out || jsonb_build_object('points_error', sqlerrm); end;
    v_out := v_out || jsonb_build_object('sender_ok', exists (select 1 from jsonb_array_elements(coalesce(v_nums,'[]'::jsonb)) x where regexp_replace(x->>'number','\D','','g') = regexp_replace(coalesce(c.sender_no,''),'\D','','g') and x->>'status' = 'ACTIVE'));
  end if;
  perform extensions.http_reset_curlopt();
  update core.sms_config set last_check_at = now(), last_check = v_out where id = 1;
  return v_out;
end $f$;
revoke all on function public.fn_sms_check() from public, anon;
grant execute on function public.fn_sms_check() to authenticated, service_role;

-- 관리자 보내기 — 수동 추출 명단(또는 내 번호 1건) · 캠페인 코드 · 광고 여부
create or replace function public.fn_sms_send(p_rows jsonb, p_body text, p_title text default null, p_campaign text default null,
                                              p_kind text default 'campaign', p_is_ad boolean default true, p_opt jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_role text := core.f_role(); v_email text := (select p.email from public.profiles p where p.id = auth.uid()); v jsonb;
begin
  if v_role not in ('admin','staff') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v := core.f_sms_send(p_rows, p_body, p_title, p_campaign, coalesce(p_kind,'campaign'), coalesce(p_is_ad,true), coalesce(v_email,'admin'), coalesce(p_opt,'{}'::jsonb) || jsonb_build_object('timeout_ms','5000'));
  insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), v_email, 'sms_send:' || (v->>'mode'), (v->>'total')::int, coalesce(p_campaign, p_kind));
  return v;
end $f$;
revoke all on function public.fn_sms_send(jsonb,text,text,text,text,boolean,jsonb) from public, anon;
grant execute on function public.fn_sms_send(jsonb,text,text,text,text,boolean,jsonb) to authenticated, service_role;

-- 보낸 문자 목록 (관리자) — 테스트·실제 · 검색 · 실명은 감사로그
create or replace function public.fn_sms_log(p_q text default null, p_mode text default null, p_status text default null, p_limit int default 50, p_offset int default 0, p_unmask boolean default false)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $f$
declare v_role text := core.f_role(); v_un boolean; v_total int; v_q text := nullif(btrim(coalesce(p_q,'')),''); v_d text;
begin
  if v_role not in ('admin','staff') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v_un := coalesce(p_unmask,false) and v_role = 'admin';
  v_d := nullif(regexp_replace(coalesce(v_q,''),'\D','','g'),'');
  if v_un then insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), (select p.email from public.profiles p where p.id = auth.uid()), 'sms_log:unmask', p_limit, v_q); end if;
  select count(*) into v_total from crm.sms_message m
   where (p_mode is null or p_mode = '' or m.mode = p_mode) and (p_status is null or p_status = '' or m.status = p_status)
     and (v_q is null or m.name ilike '%'||v_q||'%' or m.body ilike '%'||v_q||'%' or coalesce(m.campaign,'') ilike '%'||v_q||'%' or coalesce(m.sent_by,'') ilike '%'||v_q||'%' or (v_d is not null and length(v_d) >= 3 and m.phone like '%'||v_d||'%'));
  return jsonb_build_object('total', v_total,
    'summary', (select jsonb_build_object('live', count(*) filter (where mode='live' and status='sent'), 'test', count(*) filter (where mode='test'), 'failed', count(*) filter (where status='failed'), 'blocked', count(*) filter (where status='blocked')) from crm.sms_message),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'at', to_char(m.created_at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'mode', m.mode, 'status', m.status, 'kind', m.kind, 'campaign', m.campaign,
                'name', case when v_un then m.name else coalesce(left(m.name,1)||'*','') end, 'phone', case when v_un then m.phone else core.f_sms_mask(m.phone) end,
                'type', m.msg_type, 'bytes', m.bytes, 'is_ad', m.is_ad, 'body', m.body, 'reason', coalesce(m.block_reason, m.provider_msg), 'by', m.sent_by, 'group_id', m.provider_group_id, 'batch', m.batch_id) order by m.created_at desc, m.id desc), '[]'::jsonb)
              from (select * from crm.sms_message m
                     where (p_mode is null or p_mode = '' or m.mode = p_mode) and (p_status is null or p_status = '' or m.status = p_status)
                       and (v_q is null or m.name ilike '%'||v_q||'%' or m.body ilike '%'||v_q||'%' or coalesce(m.campaign,'') ilike '%'||v_q||'%' or coalesce(m.sent_by,'') ilike '%'||v_q||'%' or (v_d is not null and length(v_d) >= 3 and m.phone like '%'||v_d||'%'))
                     order by m.created_at desc, m.id desc limit least(greatest(coalesce(p_limit,50),1),500) offset greatest(coalesce(p_offset,0),0)) m));
end $f$;
revoke all on function public.fn_sms_log(text,text,text,int,int,boolean) from public, anon;
grant execute on function public.fn_sms_log(text,text,text,int,int,boolean) to authenticated, service_role;

-- ─── 7. 담당자 RPC (4자리 코드 · anon) ─────────────────────────────────────
create or replace function public.fn_store_sms_info(p_code text) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $f$
declare v_me text := core.f_staff(p_code); c core.sms_config%rowtype;
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into c from core.sms_config where id = 1;
  return jsonb_build_object('me', v_me, 'enabled', c.enabled, 'mode', c.mode, 'ready', coalesce(c.account_id,'') <> '' and coalesce(c.api_key,'') <> '' and coalesce(c.sender_no,'') <> '',
    'sender_no', c.sender_no, 'store_tel', (select value from core.app_setting where key='store_tel'),
    'templates', (select coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label,'body',body,'is_ad',is_ad) order by sort, code), '[]'::jsonb) from crm.sms_template where active and scope in ('store','both')),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'at', m.created_at, 'mode', m.mode, 'status', m.status, 'kind', m.kind, 'name', m.name, 'phone', core.f_sms_mask(m.phone), 'type', m.msg_type, 'bytes', m.bytes, 'body', m.body, 'reason', coalesce(m.block_reason, m.provider_msg), 'consult_id', m.consult_id, 'quote_no', m.quote_no, 'by', m.sent_by) order by m.created_at desc), '[]'::jsonb)
                 from (select * from crm.sms_message m where m.sent_by = v_me and m.created_at >= now() - interval '90 days' order by m.created_at desc limit 100) m));
end $f$;
revoke all on function public.fn_store_sms_info(text) from public;
grant execute on function public.fn_store_sms_info(text) to anon, authenticated, service_role;

-- 한 사람에게 한 통 — 견적서·콜백·감사·직접. 광고가 아니라 isAd=false. 바깥으로 나가는 호출이라 화면은 RPC_NO_RETRY.
create or replace function public.fn_store_sms_send(p_code text, p_phone text, p_name text, p_body text, p_kind text default 'manual',
                                                    p_consult_id bigint default null, p_quote_no text default null, p_key text default null)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_me text := core.f_staff(p_code); c core.sms_config%rowtype; v jsonb;
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into c from core.sms_config where id = 1;
  if not c.enabled then raise exception '문자 발송이 꺼져 있습니다 — 관리자 설정에서 켭니다' using errcode='22023'; end if;
  if core.f_sms_bytes(coalesce(p_body,'')) > 2000 then raise exception '2,000바이트를 넘습니다' using errcode='22023'; end if;
  v := core.f_sms_send(jsonb_build_array(jsonb_build_object('phone', p_phone, 'name', p_name, 'key', p_key, 'consult_id', p_consult_id, 'quote_no', p_quote_no)),
                       p_body, null, null, coalesce(nullif(p_kind,''),'manual'), false, v_me, jsonb_build_object('max', 1, 'timeout_ms', '2300'));
  return v || jsonb_build_object('me', v_me);
end $f$;
revoke all on function public.fn_store_sms_send(text,text,text,text,text,bigint,text,text) from public;
grant execute on function public.fn_store_sms_send(text,text,text,text,text,bigint,text,text) to anon, authenticated, service_role;

-- ─── 8. 담당자 알림 내역의 '문자' 상태 — '개발중' 글을 설정 모드로 ─────────────────
do $outer$
declare v_src text; v_args text; v_old text := $$'sms', jsonb_build_object('status','개발중', 'note','문자 자동 발송은 아직 연동 전입니다. 지금은 견적서 보내기에서 링크를 복사해 문자·카톡에 붙여 넣습니다')$$;
        v_new text := $$'sms', (select jsonb_build_object('status', case when c.mode='live' then '실제 발송' else '테스트 모드' end, 'mode', c.mode, 'enabled', c.enabled,
                 'note', case when c.mode='live' then '센드온으로 실제 발송됩니다 · 보낸 문자는 [문자 발송 내역] 에 쌓입니다' else '테스트 모드 — 보내기를 눌러도 실제로 나가지 않고 기록만 남습니다 (관리자 설정에서 실제 발송으로 바꿉니다)' end) from core.sms_config c where c.id=1)$$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_store_alerts';
  if (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 then raise exception 'fn_store_alerts 지점 %개', (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old); end if;
  execute format('create or replace function public.fn_store_alerts(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src, v_old, v_new));
end $outer$;

-- ─── 9. 메뉴 [메시지 발송 관리] · 기본은 보이되 꺼짐 · 연결 확인에 단가 · 센드온 수신거부 받아오기 ─────────
-- "일단은 눈에는 보이는데, 비활성화하고 나중에 활성하면 바꿀 수 있게" → enabled 기본 false (담당자 화면 [문자] 버튼은 보이되 잠김)
alter table core.sms_config alter column enabled set default false;
update core.sms_config set enabled = false where id = 1 and updated_by is null;
insert into core.menu_item (code, group_code, label, sort, state, note, envs)
values ('sms', 'crm', '메시지 발송 관리', 48, 'on', '센드온 문자 — 잔액·단가 · 설정 · 템플릿 · 수신거부 받아오기 · 발송 내역', '{test,prod}')
on conflict (code) do update set label = excluded.label, group_code = excluded.group_code, sort = excluded.sort, note = excluded.note, updated_at = now();
-- 발송 대상 추출을 못 보는 계정(dbuploader)은 이 메뉴도 못 본다
insert into core.menu_access (profile_id, menu_code)
select distinct a.profile_id, 'sms' from core.menu_access a where a.menu_code = 'crm'
  and not exists (select 1 from core.menu_access b where b.profile_id = a.profile_id and b.menu_code = 'sms');

-- 연결 확인 = 발신번호 + 포인트·크레딧 + 단가(SMS·LMS·MMS) + 우리 서버 IP. 문자는 안 나간다.
create or replace function public.fn_sms_check() returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare c core.sms_config%rowtype; v_auth text; v_res record; v_http int; v_json jsonb; v_t timestamptz; v_out jsonb := '{}'::jsonb;
        v_nums jsonb; v_pts jsonb; v_ip text; v_code int; v_msg text; v_email text := (select p.email from public.profiles p where p.id = auth.uid());
        v_hdr extensions.http_header[];
begin
  if core.f_role() <> 'admin' then raise exception '관리자만' using errcode='42501'; end if;
  select * into c from core.sms_config where id = 1;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '4000');
  begin select content into v_ip from extensions.http_get('https://api.ipify.org'); exception when others then v_ip := null; end;
  if v_ip ~ '^[0-9.]+$' then update core.sms_config set egress_ip = v_ip, egress_at = now() where id = 1; else v_ip := c.egress_ip; end if;
  if coalesce(c.account_id,'') = '' or coalesce(c.api_key,'') = '' then
    perform extensions.http_reset_curlopt();
    return jsonb_build_object('ok', false, 'message', '계정 아이디와 API KEY 를 먼저 저장하세요', 'ip', v_ip); end if;
  v_auth := 'Basic ' || replace(encode(convert_to(c.account_id || ':' || c.api_key, 'UTF8'), 'base64'), E'\n', '');
  v_hdr := array[extensions.http_header('Authorization', v_auth), extensions.http_header('Accept', 'application/json')];
  v_t := clock_timestamp();
  begin
    select status, content into v_res from extensions.http(('GET', 'https://api.sendon.io/v2/sender/numbers?cursor=0&limit=20', v_hdr, null, null)::extensions.http_request);
    v_http := v_res.status;
    begin v_json := v_res.content::jsonb; exception when others then v_json := jsonb_build_object('_raw', left(v_res.content, 300)); end;
    v_code := coalesce(nullif(v_json->>'code','')::int, v_http); v_msg := coalesce(v_json->>'message', left(v_res.content,200));
    v_nums := case when jsonb_typeof(v_json#>'{data,list}') = 'array' then
      (select jsonb_agg(jsonb_build_object('number', x->>'senderNumber', 'status', x->>'senderStatus', 'name', x->>'displayName', 'default', x->>'isDefault', 'type', x->>'numberType')) from jsonb_array_elements(v_json#>'{data,list}') x) end;
  exception when others then v_code := 0; v_msg := '연결 실패 · ' || sqlerrm; end;
  insert into core.sms_api_log (path, req, http_status, code, message, ok, ms, called_by)
  values ('/v2/sender/numbers', '{}'::jsonb, v_http, v_code, left(v_msg,300), v_code = 200, extract(milliseconds from clock_timestamp() - v_t)::int, v_email);
  v_out := jsonb_build_object('ok', v_code = 200, 'code', v_code, 'message', v_msg, 'numbers', coalesce(v_nums,'[]'::jsonb), 'ip', v_ip, 'at', now());
  if v_code = 200 then
    begin
      select status, content into v_res from extensions.http(('GET', 'https://api.sendon.io/v2/point/points', v_hdr, null, null)::extensions.http_request);
      v_json := v_res.content::jsonb; v_pts := v_json#>'{data,points,0,general}';
      v_out := v_out || jsonb_build_object('points', (v_pts->>'points')::numeric, 'credits', coalesce((v_pts->>'credits')::numeric, 0));
    exception when others then v_out := v_out || jsonb_build_object('points_error', sqlerrm); end;
    begin
      select status, content into v_res from extensions.http(('GET', 'https://api.sendon.io/v2/point/costs', v_hdr, null, null)::extensions.http_request);
      v_json := v_res.content::jsonb;
      v_out := v_out || jsonb_build_object('cost_name', v_json#>>'{data,costDisplayName}',
        'costs', (select coalesce(jsonb_object_agg(x->>'messageType', (x->>'pricing')::numeric), '{}'::jsonb) from jsonb_array_elements(coalesce(v_json#>'{data,pricings}','[]'::jsonb)) x where x->>'messageType' in ('SMS','LMS','MMS')));
    exception when others then v_out := v_out || jsonb_build_object('costs_error', sqlerrm); end;
    v_out := v_out || jsonb_build_object('sender_ok', exists (select 1 from jsonb_array_elements(coalesce(v_nums,'[]'::jsonb)) x where regexp_replace(x->>'number','\D','','g') = regexp_replace(coalesce(c.sender_no,''),'\D','','g') and x->>'status' = 'ACTIVE'));
  end if;
  perform extensions.http_reset_curlopt();
  update core.sms_config set last_check_at = now(), last_check = v_out where id = 1;
  return v_out;
end $f$;
revoke all on function public.fn_sms_check() from public, anon;
grant execute on function public.fn_sms_check() to authenticated, service_role;

-- 센드온 수신거부(통합 목록 · 080/웹/API 전부) → crm.sms_optout 로. 번호별 수신동의 끄기·되돌리기는 fn_sms_optout_import 규칙 그대로(mvp_195).
-- 센드온 주소록(그룹·멤버)은 API 가이드·Swagger 에 조회 엔드포인트가 없어 가져올 수 없다 — 우리 명단(고객 통합·발송 대상 추출)이 주소록이다.
create or replace function public.fn_sms_blocklist_pull(p_unified boolean default true) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare c core.sms_config%rowtype; v_auth text; v_hdr extensions.http_header[]; v_cursor text := '0'; v_page int := 0; v_rows jsonb := '[]'::jsonb;
        v_res record; v_http int; v_json jsonb; v_code int := 200; v_msg text; v_path text; v_items jsonb; v_total int; v_imp jsonb;
        v_t timestamptz := clock_timestamp(); v_email text := (select p.email from public.profiles p where p.id = auth.uid());
begin
  if core.f_role() <> 'admin' then raise exception '관리자만' using errcode='42501'; end if;
  select * into c from core.sms_config where id = 1;
  if coalesce(c.account_id,'') = '' or coalesce(c.api_key,'') = '' then raise exception '계정 아이디와 API KEY 를 먼저 저장하세요' using errcode='22023'; end if;
  v_auth := 'Basic ' || replace(encode(convert_to(c.account_id || ':' || c.api_key, 'UTF8'), 'base64'), E'\n', '');
  v_hdr := array[extensions.http_header('Authorization', v_auth), extensions.http_header('Accept', 'application/json')];
  v_path := case when coalesce(p_unified, true) then '/v2/contacts/blocklist/unified' else '/v2/contacts/blocklist' end;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '5000');
  loop
    v_page := v_page + 1;
    begin
      select status, content into v_res from extensions.http(('GET', 'https://api.sendon.io' || v_path || '?limit=200&cursor=' || v_cursor, v_hdr, null, null)::extensions.http_request);
      v_http := v_res.status;
      begin v_json := v_res.content::jsonb; exception when others then v_json := jsonb_build_object('_raw', left(v_res.content, 300)); end;
      v_code := coalesce(nullif(v_json->>'code','')::int, v_http); v_msg := coalesce(v_json->>'message', left(v_res.content, 200));
    exception when others then v_code := 0; v_msg := '연결 실패 · ' || sqlerrm; end;
    exit when v_code <> 200;
    v_items := v_json#>'{data,blocklist}'; v_total := coalesce(nullif(v_json#>>'{data,totalCount}','')::int, v_total);
    exit when jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0;
    v_rows := v_rows || (select coalesce(jsonb_agg(jsonb_build_object('phone', x->>'phoneNumber', 'opted_at', x->>'createdAt',
                          'note', '센드온 ' || coalesce(x->>'blockType','') || ' · ' || coalesce(x->>'messageType','') || coalesce(' · ' || nullif(x->>'senderNumber',''), ''))), '[]'::jsonb)
                          from jsonb_array_elements(v_items) x where coalesce(x->>'phoneNumber','') <> '');
    v_cursor := nullif(v_json#>>'{data,cursor}', '');
    exit when v_cursor is null or v_page >= 40 or clock_timestamp() - v_t > interval '6 seconds';
  end loop;
  perform extensions.http_reset_curlopt();
  insert into core.sms_api_log (path, req, http_status, code, message, ok, ms, called_by)
  values (v_path, jsonb_build_object('pages', v_page, 'fetched', jsonb_array_length(v_rows)), v_http, v_code, left(v_msg,300), v_code = 200, extract(milliseconds from clock_timestamp() - v_t)::int, v_email);
  if v_code <> 200 then return jsonb_build_object('ok', false, 'code', v_code, 'message', v_msg, 'fetched', jsonb_array_length(v_rows)); end if;
  if jsonb_array_length(v_rows) = 0 then return jsonb_build_object('ok', true, 'fetched', 0, 'total', coalesce(v_total,0), 'pages', v_page, 'message', '센드온 수신거부 목록이 비어 있습니다'); end if;
  v_imp := public.fn_sms_optout_import(v_rows, '센드온 API ' || to_char(now() at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), '센드온 API', null);
  return jsonb_build_object('ok', true, 'fetched', jsonb_array_length(v_rows), 'total', coalesce(v_total, jsonb_array_length(v_rows)), 'pages', v_page,
                            'partial', v_cursor is not null, 'import', v_imp, 'message', '받아온 번호 ' || jsonb_array_length(v_rows) || ' · 새 번호 ' || (v_imp->>'new') || ' · 고객 수신동의 끔 ' || (v_imp->>'off'));
end $f$;
revoke all on function public.fn_sms_blocklist_pull(boolean) from public, anon;
grant execute on function public.fn_sms_blocklist_pull(boolean) to authenticated, service_role;
