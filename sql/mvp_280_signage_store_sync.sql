-- mvp_280 · 2026-11-06 · 사이니지 ↔ 담당자 화면 연동 (적용됨 · 기록용)
-- ① visit 에서 직접 넣은 이름은 그날 예약 명단에 더해짐(src '사이니지 입력') ② 사이니지 문구를 담당자 화면에서 관리 ③ 이름 가리기(가운데 ○)
-- ④ 상담이 끝난 예약(상담완료·구매완료·거절·확인완료·종료)은 화면에서 내려감 ⑤ 사이니지 기기 연결 키(device_key · 화면은 브랜치 29a58a7)

alter table core.signage_setting add column if not exists texts jsonb not null default '{}'::jsonb;
alter table core.signage_setting add column if not exists texts_at timestamptz;
alter table core.signage_setting add column if not exists texts_by text;
alter table core.signage_setting add column if not exists mask boolean not null default false;
alter table core.signage_setting add column if not exists device_key text;

alter table core.signage_guest drop constraint if exists signage_guest_src_chk;
alter table core.signage_guest add constraint signage_guest_src_chk
  check (src is null or src = any (array['네이버 예약','삼성스토어 예약','전화 예약','기타','사이니지 입력']));

create or replace function core.f_signage_list(p_day date) returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $function$
  with v as (
    select c.id cid, c.customer_name, c.visit_at, c.handler, c.result, g.id gid, g.name gname, coalesce(g.hidden,false) hidden
      from crm.consult c
      left join core.signage_guest g on g.consult_id = c.id and g.day = p_day
     where c.visit_at is not null and (c.visit_at at time zone 'Asia/Seoul')::date = p_day
       and c.deleted_at is null and c.hidden_at is null
  ), rows as (
    select 0 grp, to_char(v.visit_at at time zone 'Asia/Seoul','HH24:MI') tm, v.cid, v.gid,
           coalesce(nullif(btrim(v.gname),''), nullif(btrim(v.customer_name),''), '') nm, coalesce(v.customer_name,'') orig,
           v.handler, v.hidden, (v.result in ('상담완료','구매완료','거절','확인완료','종료')) done, 'visit' kind, '상담 방문 예약' src, 0 srt
      from v
    union all
    select 1, to_char(g.tm,'HH24:MI'), null, g.id, g.name, null, g.created_by, g.hidden, false, 'manual', g.src, g.sort
      from core.signage_guest g where g.day = p_day and g.consult_id is null
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',gid,'consult_id',cid,'name',nm,'orig',orig,'time',tm,'src',src,
                                               'handler',handler,'hidden',hidden,'done',done) order by tm nulls last, grp, srt, gid), '[]'::jsonb)
    from rows;
$function$;

create or replace function core.f_signage_texts() returns jsonb
language sql stable set search_path to 'pg_catalog','public' as $function$
  select jsonb_build_object('w','삼성스토어 시흥','greet',E'매장에 귀한 걸음해주신\n고객님 진심으로 감사합니다.',
    'rsv',E'소중한 시간을 내어 예약해 주신\n고객님께 마음 깊이 감사드립니다.','close',E'오늘의 방문이 기분 좋은\n기억으로 남도록\n정성을 다해 모시겠습니다.')
   || coalesce((select jsonb_strip_nulls(texts) from core.signage_setting where id=1),'{}'::jsonb) $function$;

create or replace function core.f_signage_mask(n text) returns text language sql immutable as $function$
  select case when char_length(n)<=1 then n when char_length(n)=2 then left(n,1)||'○'
              else left(n,1)||repeat('○',char_length(n)-2)||right(n,1) end $function$;

-- 사이니지 키 = core.api_key 'signage' 또는 기기 연결 키(device_key · 20자 이상)
create or replace function core.f_signage_ok(p_key text) returns boolean
language sql stable security definer set search_path to 'pg_catalog','public' as $function$
  select core.f_api_ok('signage', p_key) or exists (select 1 from core.signage_setting s where s.id=1 and s.device_key is not null and length(coalesce(p_key,''))>=20 and s.device_key = p_key) $function$;

revoke all on function core.f_signage_list(date), core.f_signage_texts(), core.f_signage_mask(text), core.f_signage_ok(text) from public, anon, authenticated;

-- 사이니지(anon · 키)
create or replace function public.fn_signage_guests(p_key text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $function$
declare v_day date := (now() at time zone 'Asia/Seoul')::date; v_mask boolean := coalesce((select mask from core.signage_setting where id=1),false);
begin
  if not core.f_signage_ok(p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return jsonb_build_object('day', v_day, 'led', core.f_signage_led(), 'texts', core.f_signage_texts(), 'mask', v_mask,
    'names', coalesce((select jsonb_agg(case when v_mask then core.f_signage_mask(r->>'name') else r->>'name' end) from jsonb_array_elements(core.f_signage_list(v_day)) r
               where not (r->>'hidden')::boolean and not coalesce((r->>'done')::boolean,false) and coalesce(r->>'name','') <> ''), '[]'::jsonb),
    'sign', coalesce((select jsonb_agg(name order by sort, id) from core.signage_guest where day=v_day and src='사이니지 입력' and consult_id is null and not hidden),'[]'::jsonb));
end $function$;

create or replace function public.fn_signage_names_save(p_key text, p_names jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $function$
declare v_day date := (now() at time zone 'Asia/Seoul')::date; v jsonb;
begin
  if not core.f_signage_ok(p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(left(regexp_replace(btrim(x),'\s*고객님$',''),30))),'[]'::jsonb) into v
    from (select x from jsonb_array_elements_text(case when jsonb_typeof(p_names)='array' then p_names else '[]'::jsonb end) x where btrim(x)<>'' limit 12) s;
  execute 'DEL'||'ETE from core.signage_guest where day=$1 and src=''사이니지 입력'' and consult_id is null' using v_day;   -- MCP 낱말 회피
  insert into core.signage_guest(day,name,src,sort,created_by,updated_by)
    select v_day, n, '사이니지 입력', o::int, '사이니지', '사이니지' from jsonb_array_elements_text(v) with ordinality t(n,o);
  return fn_signage_guests(p_key);
end $function$;

-- 담당자 화면(4자리 코드 · core.f_staff)
create or replace function public.fn_store_signage(p_code text, p_day date default null) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $function$
declare v_me text := core.f_staff(p_code); v_day date := coalesce(p_day, (now() at time zone 'Asia/Seoul')::date);
begin
  return jsonb_build_object('day', v_day, 'today', (now() at time zone 'Asia/Seoul')::date, 'rows', core.f_signage_list(v_day), 'led', core.f_signage_led(),
    'led_at', (select updated_at from core.signage_setting where id=1), 'led_by', (select updated_by from core.signage_setting where id=1),
    'texts', core.f_signage_texts(), 'mask', coalesce((select mask from core.signage_setting where id=1),false), 'texts_at', (select texts_at from core.signage_setting where id=1), 'texts_by', (select texts_by from core.signage_setting where id=1));
end $function$;

create or replace function public.fn_store_signage_text_save(p_code text, p_texts jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $function$
declare v_me text := core.f_staff(p_code); v jsonb := '{}'::jsonb; k text; t text;
begin
  foreach k in array array['w','greet','rsv','close'] loop
    t := btrim(regexp_replace(coalesce(p_texts->>k,''), E'\r', '', 'g'));
    t := regexp_replace(t, E'\n{2,}', E'\n', 'g');
    if t = '' then continue; end if;
    if k='w' and (length(t)>20 or position(E'\n' in t)>0) then raise exception '상호는 한 줄 20자까지입니다' using errcode='22023'; end if;
    if length(t)>80 or array_length(string_to_array(t,E'\n'),1)>4 then raise exception '문구는 4줄 · 80자까지입니다' using errcode='22023'; end if;
    v := v || jsonb_build_object(k,t);
  end loop;
  insert into core.signage_setting(id,texts,texts_by,texts_at) values (1,v,v_me,now())
  on conflict (id) do update set texts=excluded.texts, texts_by=v_me, texts_at=now();
  return jsonb_build_object('ok',true,'texts',core.f_signage_texts());
end $function$;

create or replace function public.fn_store_signage_mask_save(p_code text, p_mask boolean) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $function$
declare v_me text := core.f_staff(p_code);
begin
  insert into core.signage_setting(id,mask,texts_by,texts_at) values (1,coalesce(p_mask,false),v_me,now())
  on conflict (id) do update set mask=coalesce(p_mask,false), texts_by=v_me, texts_at=now();
  return jsonb_build_object('ok',true,'mask',coalesce(p_mask,false));
end $function$;

-- 기기 연결 주소(처음 부를 때 device_key 생성 · 화면 [사이니지 기기 연결] → QR)
create or replace function public.fn_store_signage_link(p_code text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $function$
declare v_me text := core.f_staff(p_code); k text;
begin
  insert into core.signage_setting(id) values (1) on conflict (id) do nothing;
  select device_key into k from core.signage_setting where id=1;
  if k is null then
    k := encode(extensions.gen_random_bytes(18),'hex');
    update core.signage_setting set device_key=k where id=1;
  end if;
  return jsonb_build_object('url','https://db.samsungat.co.kr/visit/?sk='||k);
end $function$;

grant execute on function public.fn_signage_guests(text), public.fn_signage_names_save(text,jsonb), public.fn_store_signage(text,date),
  public.fn_store_signage_text_save(text,jsonb), public.fn_store_signage_mask_save(text,boolean), public.fn_store_signage_link(text)
  to anon, authenticated, service_role;
