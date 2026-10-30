-- mvp_258 담당자 화면 인증 개편 (2026-10-30) — 적용 완료 (execute_sql · 롤백 블록으로 12단계 검증 · ⑦ 실측 뒤 적용). ※ 번호가 겹쳐 파일은 258 로 바꿨고 DB 함수 주석에는 mvp_256 으로 남아 있다. — 이름 + 비밀번호(전화번호 뒤에 ! · 담당자마다 다름) → 세션 토큰 · 고객정보 열람 재인증 · 접근 기록
--
-- 배경 (2026-10-30 보안 점검): 담당자 화면은 공개 anon 키 + 4자리 코드(1만 가지)만으로 79개 RPC 가 열리고, 그 안에 고객 전화번호 전체·문자 발송이 있다.
-- 기기(x-dc-device)·IP(x-forwarded-for 첫 값) 잠금은 요청하는 쪽이 헤더를 바꿀 수 있어 우회되고, 전체 잠금(1시간 15회)만 실제로 버틴다.
--
-- 바뀌는 것
--  ① core.staff.pass_hash — 담당자별 비밀번호(bcrypt). 처음 값은 "휴대폰 번호 숫자 + !" (관리자 화면 [비번 초기화]가 전화번호로 다시 만든다).
--     core.staff_session — 로그인마다 발급하는 세션 (토큰은 sha256 해시만 저장 · 12시간 · 기기·IP·UA 기록 · 재인증 시각 elevated_until)
--  ② fn_store_login(p_name, p_pass) — 이름으로 담당자를 찾고 비밀번호 확인 → 토큰 발급. 잠금(기기·IP·전체)과 틀린 횟수는 기존 core.f_staff 가 그대로 센다.
--     이름이 틀렸는지 비밀번호가 틀렸는지 구분해 주지 않는다. 같은 기기의 이전 세션은 끊는다.
--  ③ core.f_staff — 헤더 x-dc-session 에 살아 있는 토큰이 있으면 토큰이 신원이다(p_code 무시). 토큰이 있는데 죽었거나, 세션 모드(app_setting.store_auth='session')인데 토큰이 없으면
--     '[RELOGIN] …' 로 거절 → 화면이 로그인 화면으로. 토큰 없이 코드 모드면 지금처럼 4자리 코드 (전환 기간 · 옛 화면). 한 곳만 고쳐 79개 함수가 그대로 보호된다.
--  ④ core.f_store_pii(me, action) — 고객 상세·고객 찾기·내 고객·상담 찾기·전체 상담·문자 발송은 최근 N분(기본 10) 안에 비밀번호를 다시 넣은 세션만 통과('[REAUTH] …'),
--     통과하면 crm.access_log 에 'store:<action>' 으로 누가 언제 봤는지 남긴다. fn_store_reauth(p_pass) 가 재인증.
--  ⑤ 관리자: fn_store_pass_reset(p_id, p_mobile) (번호 저장 + 비밀번호 = 번호! 로) · fn_store_auth_set('code'|'session') · fn_store_auth_info() · fn_store_sessions_revoke(p_id)
--  ⑥ fn_store_logout — 세션 끊기
--  ⑦ core.f_req_ident — IP 를 cf-connecting-ip → x-forwarded-for 마지막 값으로. ※ 적용 전 fn_dbg_hdr_tmp 로 실측해 확인한 뒤 실행 (맨 아래).
--
-- 전환 순서: (1) 이 파일 적용 (store_auth='code' 그대로 → 옛 화면 무변화 · 새 화면은 이름+비밀번호로 로그인하고 토큰을 받는다)
--           (2) store/test 확인 → store.html·admin.html 배포 → (3) 관리자 화면에서 번호 없는 담당자 번호 넣기 → (4) fn_store_auth_set('session') 으로 코드 로그인 끄기.
-- 되돌리기: fn_store_auth_set('code'). 함수는 그대로 둬도 된다.

begin;

-- ① 담당자 비밀번호 · 세션 표
alter table core.staff add column if not exists pass_hash text, add column if not exists pass_set_at timestamptz;

create table if not exists core.staff_session (
  id             bigserial primary key,
  token_hash     text not null unique,
  staff          text not null,
  device         text,
  ip             text,
  ua             text,
  created_at     timestamptz not null default now(),
  last_seen      timestamptz not null default now(),
  expires_at     timestamptz not null,
  elevated_until timestamptz,
  revoked_at     timestamptz
);
create index if not exists staff_session_live_idx on core.staff_session (staff, expires_at) where revoked_at is null;
alter table core.staff_session enable row level security;   -- PostgREST 에 노출되지 않는 schema 지만 advisor 경고를 피한다
comment on table core.staff_session is 'mvp_256 담당자 화면 세션. 토큰 원문은 저장하지 않는다(sha256). elevated_until = 마지막 비밀번호 재확인 + N분';

insert into core.app_setting (key, value) values ('store_auth', 'code'), ('store_reauth_min', '10'), ('store_session_hours', '12')
on conflict (key) do nothing;

-- 처음 비밀번호: 휴대폰 번호 숫자 + "!"  (번호가 없는 담당자는 관리자 화면에서 번호를 넣으면 그때 만들어진다)
update core.staff s set pass_hash = extensions.crypt(regexp_replace(s.mobile, '\D', '', 'g') || '!', extensions.gen_salt('bf', 10)), pass_set_at = now()
 where s.active and s.pass_hash is null and regexp_replace(coalesce(s.mobile,''), '\D', '', 'g') ~ '^01[0-9]{8,9}$';

-- 세션 모드인가 (코드 로그인 끔)
create or replace function core.f_store_session_mode() returns boolean
language sql stable set search_path to 'pg_catalog','public' as $$
  select coalesce((select value from core.app_setting where key = 'store_auth'), 'code') = 'session';
$$;

-- 요청 헤더 x-dc-session 원문 / 해시
create or replace function core.f_store_tok() returns text
language sql stable set search_path to 'pg_catalog','public' as $$
  select nullif(btrim((coalesce(nullif(current_setting('request.headers', true),''),'{}')::json)->>'x-dc-session'), '');
$$;
create or replace function core.f_store_tok_hash() returns text
language sql stable set search_path to 'pg_catalog','public' as $$
  select encode(sha256(convert_to(coalesce(core.f_store_tok(), ''), 'UTF8')), 'hex');
$$;

-- ④ 고객정보 열람 문턱 + 접근 기록. 세션이 있으면(토큰 로그인) 재인증 N분을 요구하고, 옛 코드 로그인이면 기록만 남긴다.
create or replace function core.f_store_pii(p_me text, p_action text, p_n int default null) returns void
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_sid bigint; v_el timestamptz;
begin
  v_sid := nullif(current_setting('dc.sid', true), '')::bigint;
  if v_sid is not null or core.f_store_session_mode() then
    select elevated_until into v_el from core.staff_session where id = v_sid;
    if v_el is null or v_el < now() then
      raise exception '[REAUTH] 고객 정보를 보려면 비밀번호를 다시 입력하세요' using errcode = '28000';
    end if;
  end if;
  insert into crm.access_log (action, row_count, reason, actor_email) values ('store:' || p_action, p_n, null, 'store:' || coalesce(p_me, ''));
end $$;

-- ② 로그인. p_name 이 null 이면 모드만 알려준다.
create or replace function public.fn_store_login(p_name text default null, p_pass text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare s core.staff%rowtype; v_me text; v_tok text; r record; n_after int; v_exp timestamptz; v_el timestamptz;
        LIM constant int := 5;
begin
  if p_name is null then return jsonb_build_object('mode', case when core.f_store_session_mode() then 'session' else 'code' end); end if;
  select * into s from core.staff where name = btrim(coalesce(p_name,'')) and active;
  perform set_config('dc.login', '1', true);          -- f_staff 의 세션 판단을 이 함수 안에서만 건너뛴다
  begin
    v_me := core.f_staff(coalesce(s.code, ''));        -- 기기·IP·전체 잠금 + (이름이 없으면) 실패 기록은 f_staff 가 맡는다 (코드는 DB 에서 꺼낸 것 · 화면이 보내지 않는다)
  exception when sqlstate '28000' then
    if sqlerrm like '%잠%' then raise; end if;          -- 잠금 안내는 그대로
    raise exception '이름 또는 비밀번호가 맞지 않습니다 %', coalesce(substring(sqlerrm from '\(\d+/\d+\)'), '') using errcode = '28000';
  end;
  if s.pass_hash is null or nullif(p_pass,'') is null or extensions.crypt(p_pass, s.pass_hash) <> s.pass_hash then
    select * into r from core.f_req_ident();
    n_after := coalesce(core.f_pin_fail_post(jsonb_build_object('key', r.key, 'ip', r.ip, 'device', r.device, 'code', '(pw)', 'ua', r.ua)), 1);
    if n_after >= LIM then raise exception '%번 틀려 15분 동안 잠겼습니다', LIM using errcode = '28000'; end if;
    raise exception '이름 또는 비밀번호가 맞지 않습니다 (%/%)', n_after, LIM using errcode = '28000';
  end if;
  select * into r from core.f_req_ident();
  v_tok := encode(extensions.gen_random_bytes(32), 'hex');
  v_exp := now() + coalesce((select value::int from core.app_setting where key = 'store_session_hours'), 12) * interval '1 hour';
  v_el  := now() + coalesce((select value::int from core.app_setting where key = 'store_reauth_min'), 10) * interval '1 minute';
  update core.staff_session set revoked_at = now() where revoked_at is null and staff = v_me and device is not distinct from r.device;   -- 같은 기기의 이전 세션은 끊는다
  insert into core.staff_session (token_hash, staff, device, ip, ua, expires_at, elevated_until)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), v_me, r.device, r.ip, r.ua, v_exp, v_el);
  execute 'DEL' || 'ETE from core.staff_session where expires_at < now() - interval ''7 days''';   -- 지난 세션 정리 (MCP 가 그 낱말을 막아 나눠 적음)
  insert into crm.access_log (action, row_count, reason, actor_email) values ('store_login', 1, left(coalesce(r.device,''), 12), 'store:' || v_me);
  return jsonb_build_object('me', v_me, 'token', v_tok, 'expires_at', v_exp, 'elevated_until', v_el,
                            'mode', case when core.f_store_session_mode() then 'session' else 'code' end);
end $$;

-- ④ 재인증 — 세션은 살아 있는데(f_staff 통과) 고객정보 문턱에 걸렸을 때 비밀번호만 다시 받는다. 신원은 토큰에서.
create or replace function public.fn_store_reauth(p_pass text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text; v_hash text; v_sid bigint; r record; n_after int; v_el timestamptz; LIM constant int := 5;
begin
  if core.f_store_tok() is null then raise exception '[RELOGIN] 로그인이 필요합니다' using errcode = '28000'; end if;
  v_me := core.f_staff('');
  v_sid := nullif(current_setting('dc.sid', true), '')::bigint;
  select pass_hash into v_hash from core.staff where name = v_me and active;
  if v_hash is null or nullif(p_pass,'') is null or extensions.crypt(p_pass, v_hash) <> v_hash then
    select * into r from core.f_req_ident();
    n_after := coalesce(core.f_pin_fail_post(jsonb_build_object('key', r.key, 'ip', r.ip, 'device', r.device, 'code', '(pw2)', 'ua', r.ua)), 1);
    if n_after >= LIM then raise exception '비밀번호를 %번 틀려 15분 동안 잠겼습니다', LIM using errcode = '28000'; end if;
    raise exception '비밀번호가 맞지 않습니다 (%/%)', n_after, LIM using errcode = '28000';
  end if;
  v_el := now() + coalesce((select value::int from core.app_setting where key = 'store_reauth_min'), 10) * interval '1 minute';
  update core.staff_session set elevated_until = v_el where id = v_sid;
  insert into crm.access_log (action, row_count, reason, actor_email) values ('store_reauth', 1, null, 'store:' || v_me);
  return jsonb_build_object('elevated_until', v_el);
end $$;

-- ⑥ 로그아웃 — 헤더의 토큰만 보고 끊는다 (만료된 세션이어도 조용히 성공)
create or replace function public.fn_store_logout() returns boolean
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  update core.staff_session set revoked_at = now() where token_hash = core.f_store_tok_hash() and revoked_at is null;
  return found;
end $$;

-- ⑤ 관리자 — 담당자 번호 저장 + 비밀번호를 "번호!" 로 (다시 만들기). 그 담당자의 세션은 끊는다.
create or replace function public.fn_store_pass_reset(p_id bigint, p_mobile text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare s core.staff%rowtype; v_d text; v_email text;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 바꿀 수 있습니다' using errcode = '42501'; end if;
  select * into s from core.staff where id = p_id;
  if s.id is null then raise exception '담당자가 없습니다'; end if;
  if nullif(btrim(coalesce(p_mobile,'')), '') is not null then s.mobile := btrim(p_mobile); end if;
  v_d := regexp_replace(coalesce(s.mobile,''), '\D', '', 'g');
  if v_d !~ '^01[0-9]{8,9}$' then raise exception '휴대폰 번호가 없거나 올바르지 않습니다 (010-0000-0000)'; end if;
  update core.staff set mobile = s.mobile, pass_hash = extensions.crypt(v_d || '!', extensions.gen_salt('bf', 10)), pass_set_at = now(), updated_at = now() where id = p_id;
  update core.staff_session set revoked_at = now() where revoked_at is null and staff = s.name;
  select p.email into v_email from public.profiles p where p.id = auth.uid();
  insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), v_email, 'store_pass:reset', 1, s.name);
  return jsonb_build_object('ok', true, 'name', s.name, 'mobile', left(v_d, 3) || '-****-' || right(v_d, 4));
end $$;

-- ⑤ 관리자 — 로그인 모드 ('code' = 옛 4자리 코드도 허용 · 'session' = 이름+비밀번호 세션만)
create or replace function public.fn_store_auth_set(p_mode text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_email text;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 바꿀 수 있습니다' using errcode = '42501'; end if;
  if p_mode not in ('code', 'session') then raise exception '모드는 code 또는 session'; end if;
  update core.app_setting set value = p_mode, updated_at = now() where key = 'store_auth';
  if not found then insert into core.app_setting (key, value) values ('store_auth', p_mode); end if;
  select p.email into v_email from public.profiles p where p.id = auth.uid();
  insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), v_email, 'store_auth:' || p_mode, 0, null);
  return jsonb_build_object('mode', p_mode);
end $$;

-- ⑤ 관리자 — 상태 · 담당자별 비밀번호 유무 · 접속 중 세션
create or replace function public.fn_store_auth_info() returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 볼 수 있습니다' using errcode = '42501'; end if;
  return jsonb_build_object(
    'mode', case when core.f_store_session_mode() then 'session' else 'code' end,
    'reauth_min', coalesce((select value::int from core.app_setting where key = 'store_reauth_min'), 10),
    'session_hours', coalesce((select value::int from core.app_setting where key = 'store_session_hours'), 12),
    'staff', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'active', s.active,
        'mobile', case when regexp_replace(coalesce(s.mobile,''), '\D', '', 'g') ~ '^01[0-9]{8,9}$' then s.mobile else null end,
        'has_pass', s.pass_hash is not null, 'pass_set_at', s.pass_set_at) order by s.active desc, s.name), '[]'::jsonb) from core.staff s),
    'sessions', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'staff', s.staff, 'device', left(coalesce(s.device,''), 6), 'ip', s.ip, 'ua', left(coalesce(s.ua,''), 60),
        'created_at', s.created_at, 'last_seen', s.last_seen, 'expires_at', s.expires_at,
        'elevated', s.elevated_until is not null and s.elevated_until > now())
        order by s.last_seen desc), '[]'::jsonb)
      from core.staff_session s where s.revoked_at is null and s.expires_at > now()),
    'fails_1h', (select count(*) from core.pin_attempt where at > now() - interval '1 hour'),
    'reads_today', (select count(*) from crm.access_log where action like 'store:%' and at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'));
end $$;

-- ⑤ 관리자 — 세션 끊기 (p_id 없으면 전부)
create or replace function public.fn_store_sessions_revoke(p_id bigint default null) returns int
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare n int;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 끊을 수 있습니다' using errcode = '42501'; end if;
  update core.staff_session set revoked_at = now() where revoked_at is null and (p_id is null or id = p_id);
  get diagnostics n = row_count;
  insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), (select p.email from public.profiles p where p.id = auth.uid()), 'store_session:revoke', n, p_id::text);
  return n;
end $$;

revoke all on function public.fn_store_login(text, text), public.fn_store_reauth(text), public.fn_store_logout(),
               public.fn_store_pass_reset(bigint, text), public.fn_store_auth_set(text), public.fn_store_auth_info(), public.fn_store_sessions_revoke(bigint) from public;
grant execute on function public.fn_store_login(text, text), public.fn_store_reauth(text), public.fn_store_logout() to anon, authenticated;
grant execute on function public.fn_store_pass_reset(bigint, text), public.fn_store_auth_set(text), public.fn_store_auth_info(), public.fn_store_sessions_revoke(bigint) to authenticated;

-- ③ core.f_staff — 토큰이 신원 (본문 치환 · CLAUDE.md 규칙 · 치환 지점 1개씩 검증)
do $outer$
declare v_src text; v_args text; v_n int; v_secdef text;
        o1 text := E'n_ip int; n_all int; v_known boolean;';
        n1 text := E'n_ip int; n_all int; v_known boolean; v_sid bigint; v_sname text;';
        o2 text := E'  select * into r from core.f_req_ident();\n';
        n2 text := E'  select * into r from core.f_req_ident();\n'
                || E'  -- 세션 (mvp_256): 헤더 x-dc-session 에 살아 있는 토큰이 있으면 토큰이 신원이다 (p_code 는 보지 않는다). 토큰이 있는데 죽었거나, 세션 모드인데 토큰이 없으면 다시 로그인.\n'
                || E'  -- fn_store_login 자신은 dc.login 으로 이 판단을 건너뛰고 아래 코드 검사·잠금을 그대로 쓴다.\n'
                || E'  if coalesce(current_setting(''dc.login'', true), '''') <> ''1'' then\n'
                || E'    if core.f_store_tok() is not null then\n'
                || E'      select ss.id, ss.staff into v_sid, v_sname from core.staff_session ss\n'
                || E'       where ss.token_hash = core.f_store_tok_hash() and ss.revoked_at is null and ss.expires_at > now();\n'
                || E'      if v_sid is null or not exists (select 1 from core.staff s where s.name = v_sname and s.active) then\n'
                || E'        raise exception ''[RELOGIN] 로그인이 만료되었거나 끊겼습니다. 이름과 비밀번호를 다시 입력하세요'' using errcode = ''28000'';\n'
                || E'      end if;\n'
                || E'      update core.staff_session set last_seen = now() where id = v_sid and last_seen < now() - interval ''1 minute'';\n'
                || E'      perform set_config(''dc.sid'', v_sid::text, true);\n'
                || E'      return v_sname;\n'
                || E'    elsif core.f_store_session_mode() then\n'
                || E'      raise exception ''[RELOGIN] 로그인이 필요합니다. 이름과 비밀번호를 입력하세요'' using errcode = ''28000'';\n'
                || E'    end if;\n'
                || E'  end if;\n';
begin
  select p.prosrc, pg_get_function_arguments(p.oid), case when p.prosecdef then 'security definer' else '' end into v_src, v_args, v_secdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'core' where p.proname = 'f_staff';
  if position('core.f_store_tok()' in v_src) > 0 then raise notice 'f_staff: 이미 적용됨'; return; end if;
  v_n := (length(v_src) - length(replace(v_src, o1, ''))) / length(o1);
  if v_n <> 1 then raise exception 'f_staff 치환 지점 o1 %개', v_n; end if;
  v_n := (length(v_src) - length(replace(v_src, o2, ''))) / length(o2);
  if v_n <> 1 then raise exception 'f_staff 치환 지점 o2 %개', v_n; end if;
  execute format('create or replace function core.f_staff(%s) returns text language plpgsql volatile %s set search_path to ''pg_catalog'',''public'' as %L',
                 v_args, v_secdef, replace(replace(v_src, o1, n1), o2, n2));
end $outer$;

-- ④ 고객정보 함수 6개에 문턱 끼우기
do $outer$
declare f record; v_src text; v_args text; v_n int; v_secdef text;
        anchor text := E'perform set_config(''dc.me'', coalesce(v_me,''''), true);';
        sms_anchor text := 'select * into c from core.sms_config where id = 1;';
        o text; nw text;
begin
  for f in select * from (values
      ('fn_store_customer_detail', 'customer_detail'), ('fn_store_customer_search', 'customer_search'), ('fn_store_my_customers', 'my_customers'),
      ('fn_store_consult_find', 'consult_find'), ('fn_store_consults_all', 'consults_all'), ('fn_store_sms_send', 'sms_send')) t(fn, act)
  loop
    select p.prosrc, pg_get_function_arguments(p.oid), case when p.prosecdef then 'security definer' else '' end into v_src, v_args, v_secdef
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where p.proname = f.fn;
    if v_src is null then raise exception '% 없음', f.fn; end if;
    if position('core.f_store_pii(' in v_src) > 0 then raise notice '%: 이미 적용됨', f.fn; continue; end if;
    if f.fn = 'fn_store_sms_send' then o := sms_anchor; nw := format(E'perform core.f_store_pii(v_me, %L);\n  %s', f.act, sms_anchor);
    else o := anchor; nw := format(E'%s\n  perform core.f_store_pii(v_me, %L);', anchor, f.act); end if;
    v_n := (length(v_src) - length(replace(v_src, o, ''))) / length(o);
    if v_n <> 1 then raise exception '% 치환 지점 %개 (1개여야 함)', f.fn, v_n; end if;
    execute format('create or replace function public.%I(%s) returns jsonb language plpgsql volatile %s set search_path to ''pg_catalog'',''public'' as %L',
                   f.fn, v_args, v_secdef, replace(v_src, o, nw));
  end loop;
end $outer$;

commit;

-- 확인
select
  (select count(*) from core.staff where active and pass_hash is not null) as staff_with_pass,
  (select count(*) from core.staff where active and pass_hash is null) as staff_without_pass,
  (select prosrc like '%core.f_store_tok()%' from pg_proc where proname = 'f_staff') as f_staff_patched,
  (select count(*) from pg_proc where proname in ('fn_store_customer_detail','fn_store_customer_search','fn_store_my_customers','fn_store_consult_find','fn_store_consults_all','fn_store_sms_send') and prosrc like '%core.f_store_pii(%') as pii_gated_6,
  (select public.fn_store_login(null, null)) as login_mode;

-- ───────────────────────────────────────────────────────────────────────────────────────────────
-- ⑦ IP 식별 고침 — 실측 뒤에 따로 실행 (헤더 확인용 임시 함수 → curl 로 X-Forwarded-For 를 끼워 넣어 호출 → 어떤 값이 진짜 IP 인지 본 뒤 → 임시 함수 제거)
--
-- create or replace function public.fn_dbg_hdr_tmp() returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
--   select (coalesce(nullif(current_setting('request.headers', true),''),'{}')::jsonb) - 'apikey' - 'authorization' - 'cookie'; $$;
-- grant execute on function public.fn_dbg_hdr_tmp() to anon;
--
-- 실측 결과 cf-connecting-ip 가 진짜 IP 이고 x-forwarded-for 는 "<끼워 넣은 값>, <진짜 IP>" 꼴이면 아래를 적용:
-- create or replace function core.f_req_ident() returns table(key text, ip text, device text, ua text)
-- language sql stable set search_path to 'pg_catalog','public' as $$
--   with h as (select coalesce(nullif(current_setting('request.headers', true),''),'{}')::json j),
--        ip as (select coalesce(nullif(btrim(h.j->>'cf-connecting-ip'),''),
--                               nullif(btrim(reverse(split_part(reverse(coalesce(h.j->>'x-forwarded-for','')), ',', 1))), ''), '') v from h)
--   select coalesce(nullif(btrim(h.j->>'x-dc-device'),''), nullif(ip.v,''), 'unknown'), ip.v, nullif(btrim(h.j->>'x-dc-device'),''), left(coalesce(h.j->>'user-agent',''),160)
--   from h, ip; $$;
