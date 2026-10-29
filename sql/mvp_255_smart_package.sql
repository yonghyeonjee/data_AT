-- mvp_255 · 2026-10-29 · 삼성전자 스마트 패키지 (상품상세 가격 아래 안내 카드) 데이터를 데이터센터가 관리
-- 고도몰 상품상세(goods_view)는 로직만 담은 smartpackage_module.js 를 두고, 데이터는 https://db.samsungat.co.kr/sdp/spkg/data.js 에서 읽는다.
-- 판(release) = 한 달 엑셀 하나 · 기간(period_from~to)을 갖는다 · 반영(active)된 판 중 오늘 기간인 것을 화면이 고른다
-- → 다음 달 판을 미리 반영해 두면 1일 0시에 저절로 바뀐다. 같은 기간과 겹치는 판을 반영하면 옛 판은 내려간다.
create schema if not exists spkg;

create table if not exists spkg.release (
  id bigserial primary key,
  ver text not null unique,                 -- 예: 2611-1
  label text,                               -- 예: 2026년 11월 스마트 패키지
  period_from date not null,
  period_to date not null,
  data jsonb not null,                      -- {n:{칩:"모델 …"}, s:{…}, p:{…}, ladder:[[2,10],…], bonus:"3만"}
  stats jsonb,                              -- {n,s,p,cats}
  src text, note text,
  active boolean not null default false,
  created_at timestamptz not null default now(), created_by text,
  published_at timestamptz, published_by text,
  deployed_at timestamptz,
  check (period_to >= period_from)
);
alter table spkg.release enable row level security;

create table if not exists spkg.publish_log (
  id bigserial primary key, at timestamptz not null default now(),
  release_id bigint, ver text, kind text not null, by_user text, note text
);
alter table spkg.publish_log enable row level security;

create or replace function public.fn_spkg_releases()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '권한이 없습니다' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'ver', r.ver, 'label', r.label, 'from', r.period_from, 'to', r.period_to,
      'stats', r.stats, 'src', r.src, 'note', r.note, 'active', r.active,
      'created_at', r.created_at, 'created_by', r.created_by,
      'published_at', r.published_at, 'published_by', r.published_by, 'deployed_at', r.deployed_at,
      'live', r.active and current_date between r.period_from and r.period_to)
      order by r.period_from desc, r.id desc) from spkg.release r), '[]'::jsonb);
end $$;

create or replace function public.fn_spkg_get(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '권한이 없습니다' using errcode = '42501'; end if;
  return (select jsonb_build_object('id', id, 'ver', ver, 'label', label, 'from', period_from, 'to', period_to, 'data', data, 'stats', stats, 'active', active)
            from spkg.release where id = p_id);
end $$;

-- 같은 기간과 겹치는 반영 판은 내린다 (판 하나 = 기간 하나)
create or replace function core.f_spkg_activate(p_id bigint, p_by text)
returns void language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare r spkg.release;
begin
  select * into r from spkg.release where id = p_id;
  update spkg.release o set active = false
   where o.active and o.id <> p_id and daterange(o.period_from, o.period_to, '[]') && daterange(r.period_from, r.period_to, '[]');
  update spkg.release set active = true, published_at = now(), published_by = p_by where id = p_id;
  insert into spkg.publish_log (release_id, ver, kind, by_user) values (p_id, r.ver, 'publish', p_by);
end $$;

create or replace function public.fn_spkg_save(p_label text, p_from date, p_to date, p_data jsonb, p_stats jsonb default null,
                                               p_src text default null, p_note text default null, p_publish boolean default false)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_by text := coalesce(auth.jwt()->>'email', 'admin'); v_ver text; v_id bigint; v_n int;
begin
  if core.f_role() <> 'admin' then raise exception '권한이 없습니다' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception '기간을 확인해 주세요'; end if;
  if p_data is null or jsonb_typeof(p_data->'n') is distinct from 'object' or jsonb_typeof(p_data->'ladder') is distinct from 'array'
     or jsonb_array_length(p_data->'ladder') = 0 then raise exception '데이터 형식이 맞지 않습니다 (n · ladder)'; end if;
  select count(*) into v_n from spkg.release where ver like to_char(p_from, 'YYMM') || '-%';
  v_ver := to_char(p_from, 'YYMM') || '-' || (v_n + 1);
  insert into spkg.release (ver, label, period_from, period_to, data, stats, src, note, created_by)
  values (v_ver, coalesce(nullif(p_label, ''), to_char(p_from, 'YYYY"년" FMMM"월" 스마트 패키지')), p_from, p_to, p_data, p_stats, p_src, p_note, v_by)
  returning id into v_id;
  insert into spkg.publish_log (release_id, ver, kind, by_user, note) values (v_id, v_ver, 'save', v_by, p_src);
  if p_publish then perform core.f_spkg_activate(v_id, v_by); end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'ver', v_ver, 'active', p_publish);
end $$;

create or replace function public.fn_spkg_publish(p_id bigint, p_active boolean default true)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_by text := coalesce(auth.jwt()->>'email', 'admin'); v_ver text;
begin
  if core.f_role() <> 'admin' then raise exception '권한이 없습니다' using errcode = '42501'; end if;
  select ver into v_ver from spkg.release where id = p_id;
  if v_ver is null then raise exception '없는 판입니다: %', p_id; end if;
  if p_active then perform core.f_spkg_activate(p_id, v_by);
  else update spkg.release set active = false where id = p_id;
       insert into spkg.publish_log (release_id, ver, kind, by_user) values (p_id, v_ver, 'unpublish', v_by); end if;
  return jsonb_build_object('ok', true, 'id', p_id, 'ver', v_ver, 'active', p_active);
end $$;

-- Actions 가 읽는다: 반영된 판 중 아직 안 끝난 것 (어제 끝난 것까지 — 자정 직후 캐시 대비)
create or replace function public.fn_spkg_export()
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object('releases', coalesce(jsonb_agg(jsonb_build_object('ver', ver, 'label', label, 'from', period_from, 'to', period_to,
           'n', data->'n', 's', coalesce(data->'s','{}'::jsonb), 'p', coalesce(data->'p','{}'::jsonb),
           'ladder', data->'ladder', 'bonus', coalesce(data->>'bonus','3만')) order by period_from, id), '[]'::jsonb))
    from spkg.release where active and period_to >= current_date - 1;
$$;

create or replace function public.fn_spkg_deployed(p_vers text[], p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_n int;
begin
  with u as (update spkg.release set deployed_at = now() where ver = any(p_vers) and (deployed_at is null or deployed_at < published_at) returning id, ver),
       l as (insert into spkg.publish_log (release_id, ver, kind, by_user, note) select id, ver, 'deployed', 'github-actions', p_note from u returning 1)
  select count(*) into v_n from l;
  return jsonb_build_object('ok', true, 'marked', v_n);
end $$;

revoke all on function public.fn_spkg_releases(), public.fn_spkg_get(bigint),
  public.fn_spkg_save(text,date,date,jsonb,jsonb,text,text,boolean), public.fn_spkg_publish(bigint,boolean),
  public.fn_spkg_export(), public.fn_spkg_deployed(text[],text), core.f_spkg_activate(bigint,text) from public, anon, authenticated;
grant execute on function public.fn_spkg_releases(), public.fn_spkg_get(bigint),
  public.fn_spkg_save(text,date,date,jsonb,jsonb,text,text,boolean), public.fn_spkg_publish(bigint,boolean) to authenticated;
grant execute on function public.fn_spkg_export(), public.fn_spkg_deployed(text[],text) to service_role;

-- 첫 판 2611-1 (11월) 은 저장소 tools/spkg/release/spkg_2611.json 을 DB 가 raw.githubusercontent 로 읽어 넣고 core.f_spkg_activate 로 반영했다.
