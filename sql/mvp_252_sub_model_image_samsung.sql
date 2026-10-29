-- mvp_252 (2026-10-29) 구독센터 제품 사진 — 삼성닷컴 대표 이미지를 먼저 쓴다
-- 왜: fn_sub_catalog 의 사진이 고도몰 목록용 썸네일(88px 가 많음)이라 구독센터 상세·목록에서 작게 보였다.
-- 무엇:
--   수집기 tools/subimg/collect.mjs (GitHub Actions sub-image.yml · 매일) 가 삼성닷컴 고객지원 모델 페이지
--   https://www.samsung.com/sec/support/model/<모델>/ 의 대표 사진(images.samsung.com/kdp/goods/… · CORS * · 핫링크 가능)을
--   core.sub_model_image (note 'auto:samsung.com/support · 제품명') 에 넣고, 확인 기록을 core.sub_model_image_check 에 남긴다.
--   fn_sub_catalog 는 core.sub_model_image 를 core.sub_model_image_auto 보다 먼저 쓴다 (종류 'm'). 못 찾은 모델은 지금처럼 고도몰 사진.
--   손으로 넣은 행(note 가 'auto:' 로 시작하지 않음)은 수집기가 건드리지 않는다.
-- 참고: core.f_sub_model_image_refresh (매시 10분) 도 core.sub_model_image 를 1순위(pri 0 · 'm') 로 모으므로 auto 표에도 곧 반영된다.
--       Edge Function sub-image-sync(samsungaicare) 는 'm'·'e' 가 아닌 모델만 보므로 이 표에 들어간 모델은 더 보지 않는다.

-- 확인 기록 — 매일 전부 다시 긁지 않으려고 (찾은 것 30일 · 못 찾은 것 7일(연속 실패마다 늘어 최대 30일) 뒤에 다시)
create table if not exists core.sub_model_image_check (
  model       text primary key,
  found       boolean not null,
  name        text,
  checked_at  timestamptz not null default now(),
  miss_count  integer not null default 0
);
alter table core.sub_model_image_check enable row level security;

-- 이번에 볼 모델: 활성 모델 중 확인 기록이 없거나 오래된 것 (p_all 이면 전부)
create or replace function public.fn_sub_image_samsung_targets(p_all boolean default false, p_limit integer default 1200)
returns table(model text)
language sql stable security definer set search_path to 'pg_catalog','core' as $$
  select m.model
  from (select distinct model from dps.sub_model where active) m
  left join core.sub_model_image_check c on c.model = m.model
  where p_all
     or c.model is null
     or (c.found and c.checked_at < now() - interval '30 days')
     or (not c.found and c.checked_at < now() - least(7 * (1 + c.miss_count / 3), 30) * interval '1 day')
  order by c.checked_at nulls first, m.model
  limit p_limit
$$;
revoke all on function public.fn_sub_image_samsung_targets(boolean, integer) from public, anon, authenticated;
grant execute on function public.fn_sub_image_samsung_targets(boolean, integer) to service_role;

-- 수집 결과 저장: [{model, image_url|null, name|null}]
--   찾은 것 → core.sub_model_image upsert (수동 행은 그대로) · 모두 → core.sub_model_image_check · 끝에 auto 표 다시 모음
create or replace function public.fn_sub_image_samsung_save(p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','core' as $$
declare n_found int := 0; n_saved int := 0; n_check int := 0; n_kept int := 0;
begin
  with r as (
    select upper(trim(x->>'model')) model, nullif(x->>'image_url','') image_url, nullif(x->>'name','') name
    from jsonb_array_elements(p_rows) x where coalesce(x->>'model','') <> ''
  ), hit as (
    select * from r where image_url is not null and image_url ~ '^https://images\.samsung\.com/kdp/goods/'
  ), up as (
    insert into core.sub_model_image as t (model, image_url, note, updated_at)
    select model, image_url, 'auto:samsung.com/support' || coalesce(' · ' || name, ''), now() from hit
    on conflict (model) do update
      set image_url = excluded.image_url, note = excluded.note, updated_at = now()
      where t.note like 'auto:%'            -- 손으로 넣은 행은 보존
    returning 1
  )
  select (select count(*) from hit), (select count(*) from up) into n_found, n_saved;
  n_kept := n_found - n_saved;

  insert into core.sub_model_image_check as c (model, found, name, checked_at, miss_count)
  select upper(trim(x->>'model')), coalesce(x->>'image_url','') <> '', nullif(x->>'name',''), now(),
         case when coalesce(x->>'image_url','') <> '' then 0 else 1 end
  from jsonb_array_elements(p_rows) x where coalesce(x->>'model','') <> ''
  on conflict (model) do update
    set found = excluded.found, name = coalesce(excluded.name, c.name), checked_at = now(),
        miss_count = case when excluded.found then 0 else c.miss_count + 1 end;
  get diagnostics n_check = row_count;

  perform core.f_sub_model_image_refresh();
  return jsonb_build_object('found', n_found, 'saved', n_saved, 'kept_manual', n_kept, 'checked', n_check);
end $$;
revoke all on function public.fn_sub_image_samsung_save(jsonb) from public, anon, authenticated;
grant execute on function public.fn_sub_image_samsung_save(jsonb) to service_role;

-- fn_sub_catalog: core.sub_model_image(직접 지정·삼성닷컴 수집) 가 있으면 그것을, 없으면 sub_model_image_auto (서버 원본을 읽어 지점만 바꾼다)
do $outer$
declare v_src text; v_args text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where p.proname = 'fn_sub_catalog';
  if v_src is null then raise exception 'fn_sub_catalog 없음'; end if;
  if (length(v_src) - length(replace(v_src, 'ia.image, ia.kind,', ''))) / length('ia.image, ia.kind,') <> 1 then raise exception '지점1 개수 다름'; end if;
  if (length(v_src) - length(replace(v_src, 'left join core.sub_model_image_auto ia on ia.model = m.model)', ''))) / length('left join core.sub_model_image_auto ia on ia.model = m.model)') <> 1 then raise exception '지점2 개수 다름'; end if;
  v_src := replace(v_src, 'ia.image, ia.kind,',
                   'coalesce(mi.image_url, ia.image) as image, case when mi.image_url is not null then ''m'' else ia.kind end as kind,');
  v_src := replace(v_src, 'left join core.sub_model_image_auto ia on ia.model = m.model)',
                   'left join core.sub_model_image_auto ia on ia.model = m.model' || chr(10) ||
                   '      left join core.sub_model_image mi on mi.model = m.model and coalesce(mi.image_url, '''') <> '''')');
  execute format('create or replace function public.fn_sub_catalog(%s) returns jsonb
                  language sql stable security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
