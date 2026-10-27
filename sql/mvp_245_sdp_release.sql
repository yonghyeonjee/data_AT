-- mvp_245 · SDP 구독 계산기 데이터를 데이터센터에서 관리·배포 (2026-10-27)
-- 고도몰 계산기(service/calc_subscribe.php)·견적서 페이지가 읽는 data_*.js 의 원본을 DB(sdp 스키마)에 판(release)으로 쌓고,
-- 반영(publish)한 판을 GitHub Actions(sdp-publish.yml)가 db.samsungat.co.kr/sdp/*.js 로 만들어 올린다.
--   변수 값(body)은 JSON '글자 그대로' 저장한다 — jsonb 는 키 순서를 바꿔 계산기 목록 순서(탭·모델)가 흐트러진다.
--   INC(모델별 판매 인센티브)는 공개 저장소에 올리지 않는다 — 고도몰 /data/js/data_inc.js 에만 둔다.

create schema if not exists sdp;

create table if not exists sdp.release (
  id           bigserial primary key,
  ver          text not null unique,
  note         text,
  src          text,
  created_at   timestamptz not null default now(),
  created_by   text,
  published_at timestamptz,
  published_by text,
  stats        jsonb
);
create table if not exists sdp.release_file (
  release_id bigint not null references sdp.release(id),
  file       text   not null,
  sort       int    not null,
  head       text   not null default '',
  tail       text   not null default '',
  primary key (release_id, file)
);
create table if not exists sdp.release_var (
  release_id bigint not null references sdp.release(id),
  file       text   not null,
  name       text   not null,
  sort       int    not null,
  lead       text   not null default '',
  body       text   not null,
  md5        text generated always as (md5(body)) stored,
  primary key (release_id, name)
);
create table if not exists sdp.publish_log (
  id         bigserial primary key,
  release_id bigint,
  ver        text,
  kind       text not null,           -- publish | deployed
  at         timestamptz not null default now(),
  by_user    text,
  note       text
);
alter table sdp.release      enable row level security;
alter table sdp.release_file enable row level security;
alter table sdp.release_var  enable row level security;
alter table sdp.publish_log  enable row level security;
revoke all on all tables in schema sdp from public, anon, authenticated;

-- 누가 했나
create or replace function core.f_sdp_actor() returns text
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce((select email from public.profiles where id = auth.uid()),
                  case when coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role','') = 'service_role' then 'service' end,
                  'sql');
$$;

-- jsonb 를 두 단계까지 펼친다 (DATA: 품목 › 모델 · POINT_TABLE: 모델 › 연수_케어 …)
create or replace function core.f_sdp_flat(j jsonb) returns table (k text, v jsonb)
language sql immutable as $$
  select k1 || coalesce(' › ' || k2, ''), coalesce(v2, v1)
    from jsonb_each(case when jsonb_typeof(j) = 'object' then j else jsonb_build_object('', j) end) a(k1, v1)
    left join lateral jsonb_each(case when jsonb_typeof(v1) = 'object' then v1 end) b(k2, v2) on true;
$$;

-- 두 판의 차이 (a = 새 판, b = 비교 대상 · 변수마다 더해짐/빠짐/바뀜 항목 수와 보기 20개)
create or replace function core.f_sdp_diff(p_a bigint, p_b bigint) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with a as (select name, file, md5, body::jsonb j from sdp.release_var where release_id = p_a),
       b as (select name, file, md5, body::jsonb j from sdp.release_var where release_id = p_b),
       v as (select coalesce(a.name, b.name) name, coalesce(a.file, b.file) file,
                    case when b.name is null then 'added' when a.name is null then 'removed'
                         when a.md5 = b.md5 then 'same' else 'changed' end st, a.j aj, b.j bj
               from a full join b on a.name = b.name),
       d as (select v.name, v.file, v.st,
                    (select jsonb_build_object(
                       'added',   count(*) filter (where y.k is null),
                       'removed', count(*) filter (where x.k is null),
                       'changed', count(*) filter (where x.k is not null and y.k is not null and x.v <> y.v),
                       'sample',  coalesce((select jsonb_agg(s) from (
                                    select jsonb_build_object('k', coalesce(x2.k, y2.k),
                                             'st', case when y2.k is null then 'added' when x2.k is null then 'removed' else 'changed' end) s
                                      from core.f_sdp_flat(v.aj) x2 full join core.f_sdp_flat(v.bj) y2 on x2.k = y2.k
                                     where y2.k is null or x2.k is null or x2.v <> y2.v
                                     limit 20) q), '[]'::jsonb))
                       from core.f_sdp_flat(v.aj) x full join core.f_sdp_flat(v.bj) y on x.k = y.k) items
               from v where v.st = 'changed')
  select jsonb_build_object(
    'a', p_a, 'b', p_b,
    'vars_same',    (select count(*) from v where st = 'same'),
    'vars_changed', (select count(*) from v where st = 'changed'),
    'vars_added',   coalesce((select jsonb_agg(name) from v where st = 'added'), '[]'::jsonb),
    'vars_removed', coalesce((select jsonb_agg(name) from v where st = 'removed'), '[]'::jsonb),
    'changed',      coalesce((select jsonb_agg(jsonb_build_object('name', name, 'file', file) || items order by file, name) from d), '[]'::jsonb));
$$;

-- 판 저장 (공통) — 지금 최신 판과 변수가 전부 같으면 새 판을 만들지 않는다 (날마다 수집해도 바뀐 날만 쌓인다)
create or replace function core.f_sdp_save(p_payload jsonb, p_src text, p_publish boolean) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_id bigint; v_ver text; v_last bigint; v_pub bigint; v_by text := core.f_sdp_actor();
        f jsonb; x jsonb; fi int := 0; vi int; v_n int := 0; v_same boolean; v_diff jsonb;
begin
  if jsonb_typeof(p_payload->'files') <> 'array' or jsonb_array_length(p_payload->'files') = 0 then
    raise exception 'files 가 비었습니다' using errcode = '22023'; end if;
  -- 형식 검사 (body 는 JSON 이어야 한다 · INC 는 받지 않는다)
  for f in select * from jsonb_array_elements(p_payload->'files') loop
    if coalesce(f->>'file','') !~ '^data_[a-z_]+$' then raise exception '파일 이름이 이상합니다: %', f->>'file' using errcode = '22023'; end if;
    for x in select * from jsonb_array_elements(f->'vars') loop
      if coalesce(x->>'name','') !~ '^[A-Za-z_][A-Za-z0-9_]*$' then raise exception '변수 이름이 이상합니다: %', x->>'name' using errcode = '22023'; end if;
      if x->>'name' = 'INC' then raise exception 'INC(판매 인센티브)는 공개 배포 대상이 아닙니다 — 빼고 보내 주세요' using errcode = '22023'; end if;
      perform (x->>'body')::jsonb;
      v_n := v_n + 1;
    end loop;
  end loop;

  select id into v_last from sdp.release order by id desc limit 1;
  select id into v_pub  from sdp.release where published_at is not null order by published_at desc limit 1;

  v_ver := coalesce(nullif(p_payload->>'ver',''),
           to_char(now() at time zone 'Asia/Seoul','YYMMDD') || '-' ||
           (select count(*) + 1 from sdp.release where created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'));
  if exists (select 1 from sdp.release where ver = v_ver) then raise exception '이미 있는 판 이름입니다: %', v_ver using errcode = '23505'; end if;

  insert into sdp.release (ver, note, src, created_by) values (v_ver, p_payload->>'note', p_src, v_by) returning id into v_id;
  for f in select * from jsonb_array_elements(p_payload->'files') loop
    fi := fi + 1; vi := 0;
    insert into sdp.release_file (release_id, file, sort, head, tail)
    values (v_id, f->>'file', fi, coalesce(f->>'head',''), coalesce(f->>'tail',''));
    for x in select * from jsonb_array_elements(f->'vars') loop
      vi := vi + 1;
      insert into sdp.release_var (release_id, file, name, sort, lead, body)
      values (v_id, f->>'file', x->>'name', fi * 100 + vi, coalesce(x->>'lead',''), x->>'body');
    end loop;
  end loop;

  -- 바로 앞 판과 같으면 되돌린다 (새 판 없음)
  if v_last is not null then
    select not exists (
      (select name, md5 from sdp.release_var where release_id = v_id
       except select name, md5 from sdp.release_var where release_id = v_last)
      union all
      (select name, md5 from sdp.release_var where release_id = v_last
       except select name, md5 from sdp.release_var where release_id = v_id))
      into v_same;
    if v_same then raise exception using errcode = 'P0001', message = 'SDP_SAME:' || v_last; end if;
  end if;

  v_diff := case when v_pub is not null then core.f_sdp_diff(v_id, v_pub) end;
  update sdp.release set stats = jsonb_build_object('vars', v_n, 'files', fi, 'diff_vs', v_pub, 'diff', v_diff) where id = v_id;
  if p_publish then
    update sdp.release set published_at = now(), published_by = v_by where id = v_id;
    insert into sdp.publish_log (release_id, ver, kind, by_user, note) values (v_id, v_ver, 'publish', v_by, '저장과 함께 반영');
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'ver', v_ver, 'vars', v_n, 'published', p_publish, 'diff', v_diff);
exception when others then
  if sqlerrm like 'SDP_SAME:%' then
    return jsonb_build_object('ok', true, 'same', true, 'id', split_part(sqlerrm, ':', 2)::bigint,
                              'ver', (select ver from sdp.release where id = split_part(sqlerrm, ':', 2)::bigint),
                              'note', '바로 앞 판과 같아 새 판을 만들지 않았습니다');
  end if;
  raise;
end $$;

-- ① 수집기·관리자가 판을 올린다 (관리자 로그인 또는 API 키 'sdp_ingest')
create or replace function public.fn_sdp_release_save(p_payload jsonb, p_key text default null, p_publish boolean default false) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if not (core.f_role() = 'admin' or core.f_api_ok('sdp_ingest', p_key)) then
    raise exception '권한이 없습니다' using errcode = '42501'; end if;
  return core.f_sdp_save(p_payload, case when core.f_role() = 'admin' then 'admin' else 'api' end, coalesce(p_publish, false));
end $$;

-- ② 저장소의 JSON 파일로 판을 만든다 (관리자 · 큰 첫 적재용 — MCP 로는 못 보내는 크기)
create or replace function public.fn_sdp_import_url(p_url text, p_publish boolean default false) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_st int; v_body text;
begin
  if core.f_role() <> 'admin' then raise exception '권한이 없습니다' using errcode = '42501'; end if;
  if coalesce(p_url,'') !~ '^https://raw\.githubusercontent\.com/yonghyeonjee/data_at/' then raise exception '저장소 밖 주소는 받지 않습니다'; end if;
  select h.status, h.content into v_st, v_body from extensions.http_get(p_url) h;
  if v_st <> 200 then raise exception '파일을 못 받았습니다 (HTTP %)', v_st; end if;
  return core.f_sdp_save(v_body::jsonb, 'url ' || p_url, coalesce(p_publish, false));
end $$;

-- ③ 판 목록 (관리자)
create or replace function public.fn_sdp_releases(p_limit int default 30) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select case when core.f_role() not in ('admin','staff') then null else jsonb_build_object(
    'current', (select jsonb_build_object('id', id, 'ver', ver, 'published_at', published_at)
                  from sdp.release where published_at is not null order by published_at desc limit 1),
    'deployed', (select jsonb_build_object('ver', ver, 'at', at, 'note', note)
                   from sdp.publish_log where kind = 'deployed' order by id desc limit 1),
    'rows', coalesce((select jsonb_agg(r order by r.id desc) from (
              select id, ver, note, src, created_at, created_by, published_at, published_by,
                     stats->'vars' vars, stats->'diff'->'vars_changed' changed, stats->'diff_vs' diff_vs
                from sdp.release order by id desc limit greatest(1, least(coalesce(p_limit,30), 200))) r), '[]'::jsonb)) end;
$$;

-- ④ 두 판 비교 (관리자 · b 를 비우면 지금 반영된 판)
create or replace function public.fn_sdp_diff(p_a bigint, p_b bigint default null) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() not in ('admin','staff') then raise exception '권한이 없습니다' using errcode = '42501'; end if;
  return core.f_sdp_diff(p_a, coalesce(p_b, (select id from sdp.release where published_at is not null and id <> p_a order by published_at desc limit 1)));
end $$;

-- ⑤ 반영 (관리자) — 이 판이 다음 배포(10분 안팎)부터 계산기에 나간다. 옛 판으로 되돌리기도 같은 함수
create or replace function public.fn_sdp_publish(p_id bigint, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_ver text; v_by text := core.f_sdp_actor();
begin
  if core.f_role() <> 'admin' then raise exception '권한이 없습니다' using errcode = '42501'; end if;
  update sdp.release set published_at = now(), published_by = v_by where id = p_id returning ver into v_ver;
  if v_ver is null then raise exception '없는 판입니다: %', p_id; end if;
  insert into sdp.publish_log (release_id, ver, kind, by_user, note) values (p_id, v_ver, 'publish', v_by, p_note);
  return jsonb_build_object('ok', true, 'id', p_id, 'ver', v_ver);
end $$;

-- ⑥ 배포기(GitHub Actions · service_role)가 반영된 판을 통째로 받는다
create or replace function public.fn_sdp_export() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with r as (select * from sdp.release where published_at is not null order by published_at desc limit 1)
  select jsonb_build_object('id', r.id, 'ver', r.ver, 'published_at', r.published_at,
           'files', (select jsonb_agg(jsonb_build_object('file', f.file, 'head', f.head, 'tail', f.tail,
                       'vars', (select jsonb_agg(jsonb_build_object('name', v.name, 'lead', v.lead, 'body', v.body) order by v.sort)
                                  from sdp.release_var v where v.release_id = r.id and v.file = f.file)) order by f.sort)
                       from sdp.release_file f where f.release_id = r.id))
    from r;
$$;

-- ⑦ 배포기가 올린 뒤 알려 준다
create or replace function public.fn_sdp_deployed(p_ver text, p_note text default null) returns jsonb
language sql volatile security definer set search_path to 'pg_catalog','public' as $$
  insert into sdp.publish_log (release_id, ver, kind, by_user, note)
  select (select id from sdp.release where ver = p_ver), p_ver, 'deployed', 'github-actions', p_note
  returning jsonb_build_object('ok', true, 'id', id);
$$;

revoke all on function public.fn_sdp_release_save(jsonb, text, boolean) from public;
revoke all on function public.fn_sdp_import_url(text, boolean)          from public;
revoke all on function public.fn_sdp_releases(int)                      from public;
revoke all on function public.fn_sdp_diff(bigint, bigint)               from public;
revoke all on function public.fn_sdp_publish(bigint, text)              from public;
revoke all on function public.fn_sdp_export()                           from public;
revoke all on function public.fn_sdp_deployed(text, text)               from public;
revoke all on function core.f_sdp_save(jsonb, text, boolean)            from public;
revoke all on function core.f_sdp_diff(bigint, bigint)                  from public;
revoke all on function core.f_sdp_actor()                               from public;
grant execute on function public.fn_sdp_release_save(jsonb, text, boolean) to anon, authenticated, service_role;  -- anon 은 API 키가 있어야 통과
grant execute on function public.fn_sdp_import_url(text, boolean)          to authenticated, service_role;
grant execute on function public.fn_sdp_releases(int)                      to authenticated, service_role;
grant execute on function public.fn_sdp_diff(bigint, bigint)               to authenticated, service_role;
grant execute on function public.fn_sdp_publish(bigint, text)              to authenticated, service_role;
grant execute on function public.fn_sdp_export()                           to service_role;
grant execute on function public.fn_sdp_deployed(text, text)               to service_role;
-- Supabase 기본 권한이 새 public 함수에 anon·authenticated 실행을 자동으로 준다 → 명시적으로 걷는다 (적용함)
revoke execute on function public.fn_sdp_export() from anon, authenticated;
revoke execute on function public.fn_sdp_deployed(text, text) from anon, authenticated;
revoke execute on function public.fn_sdp_import_url(text, boolean) from anon;
revoke execute on function public.fn_sdp_releases(int) from anon;
revoke execute on function public.fn_sdp_diff(bigint, bigint) from anon;
revoke execute on function public.fn_sdp_publish(bigint, text) from anon;
