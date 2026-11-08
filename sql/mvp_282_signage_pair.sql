-- mvp_282 · 2026-11-08 · 사이니지 기기 연결 번호(TV 식 페어링) · 이름 없을 때 문구 (적용됨 · 기록용)
-- 왜: 사이니지 기기가 키(?sk=)를 받은 적이 없어 fn_signage_guests 호출 0 → 담당자 화면 이름이 안 뜨고, 기기에서 넣은 이름도 그 기기에만 남았다.
-- 어떻게: 키 없는 기기는 화면 아래에 6자리 '연결 번호'를 띄우고(fn_signage_pair · 10초마다), 담당자가 [디스플레이 관리] › [매장 화면 기기 연결]에
--        그 번호를 넣으면(fn_store_signage_device op pair) 기기 번호(uuid · localStorage sg_dev)가 열쇠가 된다(core.f_signage_ok). 해제(op revoke)하면 42501 → 기기가 다시 번호를 띄운다.
-- 롤백 실험(아래 맨 끝 주석): 번호 받기 → 같은 번호 → 연결 전 42501 → 틀린 번호 거절 → 연결 → 키 통과 → guests(none 문구·last_seen) → names_save → 이름 바꾸기 → 해제 → 다시 번호. 전부 기대대로.

create table if not exists core.signage_device (
  id bigserial primary key,
  device_id text not null unique,          -- 기기가 만든 uuid (localStorage sg_dev) · 연결되면 이것이 키
  pair_code text,                          -- 6자리 연결 번호 (20분 · 연결되면 null)
  code_at timestamptz,
  paired_at timestamptz,
  paired_by text,
  name text,                               -- '매장 화면 N' · 담당자가 고칠 수 있음
  ua text,
  last_seen_at timestamptz,                -- fn_signage_guests 가 5분에 한 번 찍음 → 켜져 있음/마지막 신호
  revoked_at timestamptz,                  -- 해제 (paired_at > revoked_at 이면 다시 연결된 것)
  revoked_by text,
  created_at timestamptz not null default now()
);
alter table core.signage_device enable row level security;

create or replace function core.f_signage_devices() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'paired_at',d.paired_at,'paired_by',d.paired_by,'last_seen_at',d.last_seen_at,
           'online', d.last_seen_at > now()-interval '10 minutes') order by d.paired_at), '[]'::jsonb)
    from core.signage_device d where d.paired_at is not null and (d.revoked_at is null or d.paired_at > d.revoked_at) $$;

create or replace function core.f_signage_pending() returns int
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select count(*)::int from core.signage_device d
   where d.pair_code is not null and d.code_at > now()-interval '20 minutes'
     and not (d.paired_at is not null and (d.revoked_at is null or d.paired_at > d.revoked_at)) $$;

create or replace function core.f_signage_seen(p_key text) returns void
language sql volatile security definer set search_path to 'pg_catalog','public' as $$
  update core.signage_device set last_seen_at=now() where device_id=p_key and (last_seen_at is null or last_seen_at < now()-interval '5 minutes') $$;

-- 키 = api_key 'signage' · 옛 device_key(mvp_280) · 연결된 기기 id(uuid)
create or replace function core.f_signage_ok(p_key text) returns boolean
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select core.f_api_ok('signage', p_key)
      or exists (select 1 from core.signage_setting s where s.id=1 and s.device_key is not null and length(coalesce(p_key,''))>=20 and s.device_key = p_key)
      or exists (select 1 from core.signage_device d where d.device_id = p_key and d.paired_at is not null and (d.revoked_at is null or d.paired_at > d.revoked_at)) $$;

-- 기본 문구 + 'none'(이름이 없을 때 · 따옴표는 화면이 붙임)
create or replace function core.f_signage_texts() returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object('w','삼성스토어 시흥','greet',E'매장에 귀한 걸음해주신\n고객님 진심으로 감사합니다.',
    'rsv',E'소중한 시간을 내어 예약해 주신\n고객님께 마음 깊이 감사드립니다.','close',E'오늘의 방문이 기분 좋은\n기억으로 남도록\n정성을 다해 모시겠습니다.',
    'none',E'정성을 다해서\n상담 도와드리겠습니다')
   || coalesce((select jsonb_strip_nulls(texts) from core.signage_setting where id=1),'{}'::jsonb) $$;

-- 기기(anon): 연결 번호 받기 · 연결됐는지 보기 (10초마다) · 기기 번호는 uuid 모양만 · 한 시간에 미연결 30대 넘으면 거절
create or replace function public.fn_signage_pair(p_device text, p_ua text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare d core.signage_device; c text; i int := 0;
begin
  if p_device !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception '기기 번호 형식' using errcode='22023'; end if;
  select * into d from core.signage_device where device_id=p_device;
  if d.id is null then
    if (select count(*) from core.signage_device where created_at > now()-interval '1 hour' and paired_at is null) >= 30 then
      raise exception '잠시 뒤 다시 시도해 주세요'; end if;
    insert into core.signage_device(device_id, ua, last_seen_at) values (p_device, left(p_ua,200), now()) returning * into d;
  else
    update core.signage_device set last_seen_at=now(), ua=coalesce(left(p_ua,200),ua) where id=d.id;
  end if;
  if d.paired_at is not null and (d.revoked_at is null or d.paired_at > d.revoked_at) then
    return jsonb_build_object('paired',true,'name',d.name);
  end if;
  if d.pair_code is null or d.code_at is null or d.code_at < now()-interval '20 minutes' then
    loop
      c := lpad((floor(random()*1000000))::int::text, 6, '0'); i := i+1;
      exit when i > 30 or not exists (select 1 from core.signage_device x where x.pair_code=c and x.code_at > now()-interval '20 minutes' and x.id<>d.id);
    end loop;
    update core.signage_device set pair_code=c, code_at=now() where id=d.id;
    d.pair_code := c;
  end if;
  return jsonb_build_object('paired',false,'code',d.pair_code);
end $$;

-- 담당자: 연결(번호) · 목록 · 해제 · 이름 — 본체는 core (롤백 실험용 · core.f_staff 없이 부른다)
create or replace function core.f_signage_device_op(p_me text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare op text := coalesce(p_data->>'op','list'); c text; v_id bigint; n int; nm text;
begin
  if op='pair' then
    c := regexp_replace(coalesce(p_data->>'code',''), '\D', '', 'g');
    if length(c) <> 6 then raise exception '연결 번호 6자리를 적어 주세요' using errcode='22023'; end if;
    select d.id into v_id from core.signage_device d
     where d.pair_code = c and d.code_at > now()-interval '20 minutes'
       and not (d.paired_at is not null and (d.revoked_at is null or d.paired_at > d.revoked_at))
     order by d.code_at desc limit 1;
    if v_id is null then raise exception '연결 번호가 맞지 않거나 시간이 지났습니다 — 매장 화면 아래 번호를 다시 확인해 주세요' using errcode='22023'; end if;
    select count(*) into n from core.signage_device d where d.paired_at is not null and (d.revoked_at is null or d.paired_at > d.revoked_at);
    nm := nullif(btrim(coalesce(p_data->>'name','')),'');
    update core.signage_device set paired_at=now(), paired_by=p_me, pair_code=null, code_at=null,
           name=coalesce(left(nm,30), name, '매장 화면 '||(n+1)) where id=v_id;
  elsif op='revoke' then
    v_id := (p_data->>'id')::bigint;
    update core.signage_device set revoked_at=now(), revoked_by=p_me
     where id=v_id and paired_at is not null and (revoked_at is null or paired_at > revoked_at);
    if not found then raise exception '연결된 기기가 아닙니다' using errcode='22023'; end if;
  elsif op='rename' then
    v_id := (p_data->>'id')::bigint; nm := nullif(btrim(coalesce(p_data->>'name','')),'');
    if nm is null then raise exception '기기 이름을 적어 주세요' using errcode='22023'; end if;
    update core.signage_device set name=left(nm,30) where id=v_id;
  end if;
  return jsonb_build_object('ok',true,'devices',core.f_signage_devices(),'pending',core.f_signage_pending());
end $$;

create or replace function public.fn_store_signage_device(p_code text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  return core.f_signage_device_op(v_me, coalesce(p_data,'{}'::jsonb));
end $$;

-- 부분 치환(서버 원본을 읽어 지점 1개 확인 뒤): fn_signage_guests 에 perform core.f_signage_seen(p_key) ·
-- fn_store_signage 응답에 'devices', core.f_signage_devices(), 'pending', core.f_signage_pending() · fn_store_signage_text_save 키 목록에 'none'
do $outer$
declare v_src text; v_args text; v_n int; v_old text; v_new text;
begin
  v_old := $a$using errcode='42501'; end if;$a$; v_new := $b$using errcode='42501'; end if; perform core.f_signage_seen(p_key);$b$;
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_signage_guests';
  v_n := (length(v_src)-length(replace(v_src,v_old,'')))/length(v_old);
  if v_n <> 1 then raise exception 'fn_signage_guests 지점 %', v_n; end if;
  execute format('create or replace function public.fn_signage_guests(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src,v_old,v_new));

  v_old := $a$'texts_by', (select texts_by from core.signage_setting where id=1))$a$;
  v_new := $b$'texts_by', (select texts_by from core.signage_setting where id=1), 'devices', core.f_signage_devices(), 'pending', core.f_signage_pending())$b$;
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_store_signage';
  v_n := (length(v_src)-length(replace(v_src,v_old,'')))/length(v_old);
  if v_n <> 1 then raise exception 'fn_store_signage 지점 %', v_n; end if;
  execute format('create or replace function public.fn_store_signage(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src,v_old,v_new));

  v_old := $a$array['w','greet','rsv','close']$a$; v_new := $b$array['w','greet','rsv','close','none']$b$;
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_store_signage_text_save';
  v_n := (length(v_src)-length(replace(v_src,v_old,'')))/length(v_old);
  if v_n <> 1 then raise exception 'fn_store_signage_text_save 지점 %', v_n; end if;
  execute format('create or replace function public.fn_store_signage_text_save(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, replace(v_src,v_old,v_new));
end $outer$;

grant execute on function public.fn_signage_pair(text,text), public.fn_store_signage_device(text,jsonb) to anon, authenticated, service_role;
revoke all on function core.f_signage_devices(), core.f_signage_pending(), core.f_signage_seen(text), core.f_signage_device_op(text,jsonb), core.f_signage_ok(text), core.f_signage_texts() from public, anon, authenticated;

-- 롤백 실험(raise 로 끝나 아무것도 안 남음) — 따로 보낸 호출:
-- do $t$ declare d text := '0f0f0f0f-1111-4222-8333-444444444444'; r jsonb; c text; g jsonb; x jsonb; s jsonb;
-- begin r := fn_signage_pair(d,'ua'); c := r->>'code'; … core.f_signage_device_op('테스트', {op:'pair',code:c}) → f_signage_ok(d) true → fn_signage_guests(d) texts.none ·
--   fn_signage_names_save(d,'["홍길동 고객님","김영희"]') sign 2 → rename → revoke → f_signage_ok false → fn_signage_pair 다시 번호 → raise 'ROLLBACK OK'; end $t$;
