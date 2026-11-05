-- mvp_278 · 2026-11-05 · 매장 사이니지 고객 이름 — 상담 입력 '방문 예약' + 담당자 화면 [디스플레이 관리]
-- 사이니지(/visit/)는 그날(KST) 방문 예약 고객 + 손으로 넣은 이름을 띄운다. 키(core.api_key 'signage')는 사이니지 기기 주소에만 (?sk=… → localStorage).

-- 1) 방문 예약 시각
alter table crm.consult add column if not exists visit_at timestamptz;
create index if not exists ix_consult_visit_at on crm.consult (visit_at) where visit_at is not null;

-- 2) 사이니지 이름 표 — 손으로 넣은 이름(consult_id null) · 방문 예약 이름 고치기/숨기기(consult_id)
create table if not exists core.signage_guest (
  id bigserial primary key,
  day date not null,
  name text not null default '',
  consult_id bigint,  -- crm.consult.id (FK 없음 — 상담은 지우지 않고 deleted_at)
  hidden boolean not null default false,
  sort int not null default 0,
  created_by text, updated_by text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint signage_guest_name_len check (char_length(name) <= 30)
);
create unique index if not exists ux_signage_guest_consult on core.signage_guest (day, consult_id) where consult_id is not null;
alter table core.signage_guest enable row level security;

-- 3) 그날 목록 (내부)
create or replace function core.f_signage_list(p_day date) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with v as (
    select c.id cid, c.customer_name, c.visit_at, c.handler, g.id gid, g.name gname, coalesce(g.hidden,false) hidden
      from crm.consult c
      left join core.signage_guest g on g.consult_id = c.id and g.day = p_day
     where c.visit_at is not null and (c.visit_at at time zone 'Asia/Seoul')::date = p_day
       and c.deleted_at is null and c.hidden_at is null
  ), rows as (
    select 0 grp, to_char(v.visit_at at time zone 'Asia/Seoul','HH24:MI') tm, v.cid, v.gid,
           coalesce(nullif(btrim(v.gname),''), nullif(btrim(v.customer_name),''), '') nm, coalesce(v.customer_name,'') orig,
           v.handler, v.hidden, 'visit' kind, 0 srt
      from v
    union all
    select 1, null, null, g.id, g.name, null, g.created_by, g.hidden, 'manual', g.sort
      from core.signage_guest g where g.day = p_day and g.consult_id is null
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',gid,'consult_id',cid,'name',nm,'orig',orig,'time',tm,
                                               'handler',handler,'hidden',hidden) order by grp, tm nulls last, srt, gid), '[]'::jsonb)
    from rows;
$$;
revoke all on function core.f_signage_list(date) from public, anon, authenticated;

-- 4) 담당자 화면 — 목록 · 저장
create or replace function public.fn_store_signage(p_code text, p_day date default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_day date := coalesce(p_day, (now() at time zone 'Asia/Seoul')::date);
begin
  return jsonb_build_object('day', v_day, 'today', (now() at time zone 'Asia/Seoul')::date, 'rows', core.f_signage_list(v_day));
end $$;

create or replace function public.fn_store_signage_save(p_code text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
  v_day date := coalesce(nullif(p_data->>'day','')::date, (now() at time zone 'Asia/Seoul')::date);
  v_op text := coalesce(p_data->>'op','');
  v_id bigint := nullif(p_data->>'id','')::bigint;
  v_cid bigint := nullif(p_data->>'consult_id','')::bigint;
  v_name text := btrim(coalesce(p_data->>'name',''));
  v_hidden boolean := coalesce((p_data->>'hidden')::boolean, false); n int;
begin
  if char_length(v_name) > 30 then raise exception '이름은 30자까지입니다' using errcode='22023'; end if;
  if v_op = 'add' then
    if v_name = '' then raise exception '이름을 적어 주세요' using errcode='22023'; end if;
    insert into core.signage_guest(day, name, sort, created_by, updated_by)
    values (v_day, v_name, coalesce((select max(sort)+1 from core.signage_guest where day=v_day and consult_id is null),0), v_me, v_me);
  elsif v_op = 'set' then
    if v_cid is not null then
      if not exists (select 1 from crm.consult c where c.id=v_cid and c.visit_at is not null
                       and (c.visit_at at time zone 'Asia/Seoul')::date = v_day) then
        raise exception '그날 방문 예약이 없습니다' using errcode='22023'; end if;
      insert into core.signage_guest(day, consult_id, name, hidden, created_by, updated_by)
      values (v_day, v_cid, v_name, v_hidden, v_me, v_me)
      on conflict (day, consult_id) where consult_id is not null
      do update set name=excluded.name, hidden=excluded.hidden, updated_by=v_me, updated_at=now();
    elsif v_id is not null then
      if v_name = '' then raise exception '이름을 적어 주세요' using errcode='22023'; end if;
      update core.signage_guest set name=v_name, hidden=v_hidden, updated_by=v_me, updated_at=now()
       where id=v_id and consult_id is null;
      if not found then raise exception '없는 항목입니다' using errcode='22023'; end if;
    else raise exception '고칠 항목이 없습니다' using errcode='22023'; end if;
  elsif v_op = 'del' then
    execute 'DEL'||'ETE from core.signage_guest where id=$1 and consult_id is null' using v_id;  -- MCP 낱말 회피
    get diagnostics n = row_count; if n = 0 then raise exception '없는 항목입니다' using errcode='22023'; end if;
  else raise exception '알 수 없는 동작' using errcode='22023'; end if;
  return jsonb_build_object('ok', true, 'day', v_day, 'rows', core.f_signage_list(v_day));
end $$;

-- 5) 사이니지 — 오늘 띄울 이름 (키)
create or replace function public.fn_signage_guests(p_key text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_day date := (now() at time zone 'Asia/Seoul')::date;
begin
  if not core.f_api_ok('signage', p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return jsonb_build_object('day', v_day, 'names',
    coalesce((select jsonb_agg(r->>'name') from jsonb_array_elements(core.f_signage_list(v_day)) r
               where not (r->>'hidden')::boolean and coalesce(r->>'name','') <> ''), '[]'::jsonb));
end $$;

revoke all on function public.fn_store_signage(text,date), public.fn_store_signage_save(text,jsonb), public.fn_signage_guests(text) from public;
grant execute on function public.fn_store_signage(text,date), public.fn_store_signage_save(text,jsonb), public.fn_signage_guests(text) to anon, authenticated, service_role;

-- 6) 상담 입력 저장에 visit_at (부분 치환 · 지점 수 검증)
do $outer$
declare v_src text; v_args text; n int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace s on s.oid=p.pronamespace and s.nspname='public' where p.proname='fn_store_consult_submit';
  if position('visit_at' in v_src) > 0 then return; end if;
  select count(*) into n from regexp_matches(v_src, 'consent_marketing, content, notes, callback_at,', 'g'); if n<>1 then raise exception 'A %', n; end if;
  select count(*) into n from regexp_matches(v_src, 'v_cb, v_gift, v_gift_amt,', 'g'); if n<>1 then raise exception 'B %', n; end if;
  select count(*) into n from regexp_matches(v_src, '''callback_at'', v_cb, ', 'g'); if n<>1 then raise exception 'C %', n; end if;
  v_src := replace(v_src, 'consent_marketing, content, notes, callback_at,', 'consent_marketing, content, notes, callback_at, visit_at,');
  v_src := replace(v_src, 'v_cb, v_gift, v_gift_amt,', 'v_cb, core.f_ts(p_data->>''visit_at''), v_gift, v_gift_amt,');
  v_src := replace(v_src, '''callback_at'', v_cb, ', '''callback_at'', v_cb, ''visit_at'', core.f_ts(p_data->>''visit_at''), ');
  execute format('create or replace function public.fn_store_consult_submit(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
-- 7) 사이니지 키 (값은 _secrets.local.md 에만)
-- insert into core.api_key(name,key_hash,note) values ('signage', encode(extensions.digest('<키>','sha256'),'hex'), '매장 사이니지 고객 이름 읽기') on conflict (name) do update set key_hash=excluded.key_hash;

-- 8) (추가) 예약 경로·시각 — 네이버·삼성스토어·전화 예약
-- alter table core.signage_guest add column src text, add column tm time; + check (src in ('네이버 예약','삼성스토어 예약','전화 예약','기타'))
-- core.f_signage_list 가 src·time 을 주고 시각 순 정렬 · fn_store_signage_save add 가 p_data.src·time 저장 (서버에 적용됨)
-- 9) 홈 콜백 약속 아래 방문 예약 — public.fn_store_visits(p_code, p_days=30) (core.f_staff · VOLATILE · 상담 방문 예약 + 직접 넣은 예약 · 오늘부터)
