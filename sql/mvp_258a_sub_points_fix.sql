-- mvp_258a (2026-11-02) · fn_sub_point_upsert 고침: 임시표 열 이름 found 가 PL/pgSQL FOUND 변수와 겹쳐 "column reference found is ambiguous"(42702) → ok 로.
--   첫 Actions 수집(10분 걸려 모은 뒤 저장에서 실패)의 원인. 본문은 sql/mvp_258_sub_points.sql 의 같은 함수와 동일.
create or replace function public.fn_sub_point_upsert(p_rows jsonb, p_key text default null, p_meta jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare n_found int := 0; n_saved int := 0; n_kept int := 0; n_missed int := 0; n_check int := 0; v_id bigint; v_by text;
begin
  if not sub.f_point_api_ok(p_key) then raise exception '키가 맞지 않습니다' using errcode = '42501'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows 는 목록이어야 합니다' using errcode = '22023'; end if;
  v_by := case when coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role','') = 'service_role' then 'github-actions' else 'api:sub_point' end;

  create temp table _pt on commit drop as
    select r.*, (r.total_point is not null or r.aisc_rate is not null) ok from (   -- 열 이름 found 는 PL/pgSQL 의 FOUND 변수와 겹쳐 '모호' 오류 → ok
    select upper(regexp_replace(x->>'model', '\s', '', 'g')) model,
           nullif(btrim(x->>'goods_id'),'') goods_id,
           nullif(x->>'term_months','')::int term_months,
           nullif(regexp_replace(coalesce(x->>'price',''), '[^0-9]', '', 'g'),'')::int price,
           nullif(regexp_replace(coalesce(x->>'total_point',''), '[^0-9-]', '', 'g'),'')::int total_point,
           nullif(regexp_replace(coalesce(x->>'apl_point',''), '[^0-9-]', '', 'g'),'')::int apl_point,
           nullif(regexp_replace(coalesce(x->>'basic_point',''), '[^0-9-]', '', 'g'),'')::int basic_point,
           nullif(regexp_replace(coalesce(x->>'mdl_add_point',''), '[^0-9-]', '', 'g'),'')::int mdl_add_point,
           nullif(regexp_replace(coalesce(x->>'aisc_rate',''), '[^0-9.]', '', 'g'),'')::numeric aisc_rate,
           nullif(regexp_replace(coalesce(x->>'basic_rate',''), '[^0-9.]', '', 'g'),'')::numeric basic_rate,
           left(nullif(btrim(x->>'err'),''), 300) err
      from jsonb_array_elements(p_rows) x
     where coalesce(x->>'model','') <> '') r;
  select count(*) filter (where ok), count(*) filter (where not ok) into n_found, n_missed from _pt;

  -- 찾은 것 → sub.model_point (손 입력 행은 goods_id 만 보충)
  with up as (
    insert into sub.model_point as t (model, goods_id, term_months, price, total_point, apl_point, basic_point, mdl_add_point, aisc_rate, basic_rate, src, fetched_at, updated_at, updated_by)
    select model, goods_id, term_months, price, total_point, apl_point, basic_point, mdl_add_point, aisc_rate, basic_rate, 'samsung.com', now(), now(), v_by
      from _pt where ok
    on conflict (model) do update
      set goods_id = coalesce(excluded.goods_id, t.goods_id),
          term_months = case when t.src = 'manual' then t.term_months else excluded.term_months end,
          price       = case when t.src = 'manual' then t.price       else excluded.price end,
          total_point = case when t.src = 'manual' then t.total_point else excluded.total_point end,
          apl_point   = case when t.src = 'manual' then t.apl_point   else excluded.apl_point end,
          basic_point = case when t.src = 'manual' then t.basic_point else excluded.basic_point end,
          mdl_add_point = case when t.src = 'manual' then t.mdl_add_point else excluded.mdl_add_point end,
          aisc_rate   = case when t.src = 'manual' then t.aisc_rate   else excluded.aisc_rate end,
          basic_rate  = case when t.src = 'manual' then t.basic_rate  else excluded.basic_rate end,
          fetched_at  = case when t.src = 'manual' then t.fetched_at  else now() end,
          -- 값이 그대로면 updated_at 을 건드리지 않는다 (정책 판 번호가 쓸데없이 바뀌지 않게)
          updated_at  = case when t.src = 'manual' then t.updated_at
                             when (t.total_point, t.apl_point, t.basic_point, t.mdl_add_point, t.aisc_rate, t.basic_rate, t.price) is distinct from
                                  (excluded.total_point, excluded.apl_point, excluded.basic_point, excluded.mdl_add_point, excluded.aisc_rate, excluded.basic_rate, excluded.price) then now()
                             else t.updated_at end,
          updated_by  = case when t.src = 'manual' then t.updated_by else v_by end
    returning src)
  select count(*) filter (where src = 'samsung.com'), count(*) filter (where src = 'manual') into n_saved, n_kept from up;

  -- 모델별 확인 기록
  insert into sub.model_point_check as c (model, found, checked_at, miss_count, goods_id, err)
  select model, ok, now(), case when ok then 0 else 1 end, goods_id, case when ok then null else err end from _pt
  on conflict (model) do update
    set found = excluded.found, checked_at = now(),
        miss_count = case when excluded.found then 0 else c.miss_count + 1 end,
        goods_id = coalesce(excluded.goods_id, c.goods_id),
        err = excluded.err;
  get diagnostics n_check = row_count;

  insert into sub.model_point_fetch (started_at, targets, found, missed, errors, saved, kept_manual, miss_models, note, by_user)
  values (nullif(p_meta->>'started_at','')::timestamptz, nullif(p_meta->>'targets','')::int, n_found, n_missed, nullif(p_meta->>'errors','')::int,
          n_saved, n_kept, (select coalesce(jsonb_agg(model order by model), '[]'::jsonb) from (select model from _pt where not ok limit 500) m),
          left(p_meta->>'note', 500), v_by)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'fetch_id', v_id, 'found', n_found, 'missed', n_missed, 'saved', n_saved, 'kept_manual', n_kept, 'checked', n_check);
end $$;

-- fn_sub_point_targets 에 p_offset 추가 (PostgREST 가 RPC 결과를 1000행에서 자르고 Range 헤더도 무시 → 수집기가 1000행씩 이어 받는다). 활성 구독 모델 1131개(2026-11-02).
drop function if exists public.fn_sub_point_targets(boolean, int, text);
-- ── 수집 대상 ── 활성 구독 모델마다 최장 약정의 최저 총액(무상수리) · 캐시된 goods_id
--   p_offset: 1000행 단위로 이어 받기 (sql/mvp_258a 에서 추가)
--   p_all=false: 처음 보는 모델 + 찾은 지 6일 넘은 모델 + 못 찾은 모델은 7·14·21…(최대 30)일 뒤
create or replace function public.fn_sub_point_targets(p_all boolean default false, p_limit int default 3000, p_key text default null, p_offset int default 0)
returns table(model text, term_months int, price int, goods_id text)
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if not sub.f_point_api_ok(p_key) then raise exception '키가 맞지 않습니다' using errcode = '42501'; end if;
  return query
    with a as (select s.model, max(s.term_months) mt from dps.sub_model s where s.active and s.term_months > 0 group by s.model),
         pr as (select a.model, a.mt, min(s.total_fee)::int price
                  from a join dps.sub_model s on s.model = a.model and s.active and s.term_months = a.mt
                 where s.total_fee > 0 group by a.model, a.mt)
    select pr.model, pr.mt, pr.price, coalesce(mp.goods_id, c.goods_id)
      from pr
      left join sub.model_point mp on mp.model = pr.model
      left join sub.model_point_check c on c.model = pr.model
     where p_all
        or c.model is null
        or (c.found and c.checked_at < now() - interval '6 days')
        or (not c.found and c.checked_at < now() - least(7 * (1 + c.miss_count / 3), 30) * interval '1 day')
     order by c.checked_at nulls first, pr.model
     limit least(p_limit, 1000) offset greatest(coalesce(p_offset, 0), 0);   -- PostgREST 는 한 번에 1000행까지 → 수집기가 p_offset 으로 이어 받는다 (RPC 에는 Range 헤더가 안 먹음 · 2026-11-02)
end $$;
revoke all on function public.fn_sub_point_targets(boolean, int, text, int) from public, anon, authenticated;
grant execute on function public.fn_sub_point_targets(boolean, int, text, int) to anon, authenticated, service_role;
