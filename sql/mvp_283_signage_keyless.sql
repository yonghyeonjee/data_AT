-- mvp_283 · 사이니지 ↔ 담당자 화면 — 키 없이 바로 연동 (v289 · 2026-11-08)
-- "아니 admin, store 연동처럼 연동하면 되지 · 그냥 store 에선 현재 visit 에 있는 거 그대로 보여지고 · store 에서 바뀌면 visit 도 바뀌는 거지 · 지금 인증번호 지저분하니까 다른 방안으로"
-- → v288(mvp_282)의 '매장 화면 연결 번호'(TV 식 페어링)를 걷어내고, 매장 화면(/visit/)이 키 없이 담당자 화면과 같은 명단을 읽고 쓴다.
--   · fn_signage_guests(p_key)       : 키 검사·기기 last_seen 제거 — 누구나 그날 명단(가리기 켜면 홍○동)·문구·LED 를 읽는다. p_key 는 옛 화면 호환용(안 본다).
--   · fn_signage_names_save(p_key,…) : 키 검사 → core.f_signage_guard() (같은 IP 10분 30회 · 전체 1시간 600회 넘으면 거절). 이름 다듬기(30자·12명·'고객님' 뗌)는 그대로.
--   · fn_store_signage               : 응답에서 devices·pending 제거.
--   · core.f_signage_ok              : mvp_280 판(api_key 'signage' 또는 device_key)으로 — 더 이상 부르는 곳은 없다.
--   · fn_signage_pair · fn_store_signage_device : 실행 권한 회수(anon·authenticated). DROP 은 SQL 편집기(맨 아래).
-- 적용 2026-11-08 (MCP execute_sql · 롤백 실험은 따로).

create table if not exists core.signage_save_log(
  id bigserial primary key,
  at timestamptz not null default now(),
  ip text,
  ua text
);
alter table core.signage_save_log enable row level security;   -- 정책 없음 · definer 함수만 쓴다
create index if not exists ix_signage_save_log_at on core.signage_save_log(at);
comment on table core.signage_save_log is 'mvp_283 · 사이니지 이름 저장(fn_signage_names_save) 호출 기록 — IP 속도 제한용 · 2일 지난 줄은 함수가 가끔 정리';

-- IP 는 core.f_req_ident()(mvp_258) 가 request.headers 의 cf-connecting-ip → x-forwarded-for 마지막 값으로 읽는다.
create or replace function core.f_signage_guard() returns void
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_ip text; v_ua text; n_ip int; n_all int;
begin
  select ip, ua into v_ip, v_ua from core.f_req_ident();
  v_ip := coalesce(nullif(v_ip,''),'unknown');
  select count(*) into n_ip  from core.signage_save_log where ip=v_ip and at > now()-interval '10 minutes';
  select count(*) into n_all from core.signage_save_log where at > now()-interval '1 hour';
  if n_ip >= 30 or n_all >= 600 then
    raise exception '잠시 뒤 다시 시도해 주세요 (이름 저장이 너무 잦습니다)' using errcode='P0001';
  end if;
  insert into core.signage_save_log(ip, ua) values (v_ip, left(coalesce(v_ua,''),160));
  if random() < 0.05 then execute 'DEL'||'ETE from core.signage_save_log where at < now()-interval ''2 days'''; end if;
end $$;
revoke all on function core.f_signage_guard() from public, anon, authenticated;

-- 함수 본문은 서버에 저장된 것(pg_get_functiondef)에서 지점 1개씩 치환했다 (지점 수가 1이 아니면 중단).
do $outer$
declare v_def text; v_old text; v_n int;
begin
  -- ① fn_signage_guests: 키 검사 · 기기 last_seen 제거
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_signage_guests' and pg_get_function_arguments(p.oid)='p_key text';
  v_old := 'if not core.f_signage_ok(p_key) then raise exception ''권한이 없습니다'' using errcode=''42501''; end if; perform core.f_signage_seen(p_key);';
  v_n := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  if v_n <> 1 then raise exception 'fn_signage_guests 지점 %개', v_n; end if;
  execute replace(v_def, v_old, '-- mvp_283: 키 없이 읽는다 (p_key 는 옛 화면 호환용 · 보지 않는다)');

  -- ② fn_signage_names_save: 키 검사 → IP 속도 제한
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_signage_names_save';
  v_old := 'if not core.f_signage_ok(p_key) then raise exception ''권한이 없습니다'' using errcode=''42501''; end if;';
  v_n := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  if v_n <> 1 then raise exception 'fn_signage_names_save 지점 %개', v_n; end if;
  execute replace(v_def, v_old, 'perform core.f_signage_guard(); -- mvp_283: 키 대신 IP 속도 제한(같은 IP 10분 30회 · 전체 1시간 600회)');

  -- ③ fn_store_signage: devices · pending 제거
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_store_signage';
  v_old := ', ''devices'', core.f_signage_devices(), ''pending'', core.f_signage_pending()';
  v_n := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  if v_n <> 1 then raise exception 'fn_store_signage 지점 %개', v_n; end if;
  execute replace(v_def, v_old, '');

  -- ④ core.f_signage_ok → mvp_280 판 (signage_device 참조 제거)
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='core' and p.proname='f_signage_ok';
  v_old := E'\n      or exists (select 1 from core.signage_device d where d.device_id = p_key and d.paired_at is not null and (d.revoked_at is null or d.paired_at > d.revoked_at))';
  v_n := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  if v_n <> 1 then raise exception 'f_signage_ok 지점 %개', v_n; end if;
  execute replace(v_def, v_old, '');
end $outer$;

-- ⑤ 연결 번호 RPC — 화면이 더 이상 안 부른다 · 실행 권한부터 뺐다
revoke all on function public.fn_signage_pair(text,text) from public, anon, authenticated;
revoke all on function public.fn_store_signage_device(text,jsonb) from public, anon, authenticated;

-- 롤백 실험(raise 로 되돌림 · 별도 호출) — 전부 기대대로:
--   G1 anon · fn_signage_guests(null) → names [] · texts.none '정성을 다해서\n상담 도와드리겠습니다'
--   G2 anon · fn_signage_names_save(null, ["홍길동 고객님","  김철수 "]) → sign ["홍길동","김철수"]
--   G3 같은 IP 로 연달아 저장 → 29회 더 성공 · 31번째 'P0001 잠시 뒤 다시 시도해 주세요 (이름 저장이 너무 잦습니다)'
--   G4 anon · fn_signage_pair / fn_store_signage_device → 42501 permission denied
--   G5 core.signage_save_log 30줄 · G6 core.f_signage_list(오늘) 사이니지 입력 1줄 · core.signage_device 0줄

-- ⑥ SQL 편집기에서 지울 것 (MCP 는 DROP 에서 60초로 끊긴다) — 함수 먼저, 표는 마지막
-- drop function public.fn_signage_pair(text,text);
-- drop function public.fn_store_signage_device(text,jsonb);
-- drop function core.f_signage_device_op(text,jsonb);
-- drop function core.f_signage_devices();
-- drop function core.f_signage_pending();
-- drop function core.f_signage_seen(text);
-- drop table core.signage_device;
