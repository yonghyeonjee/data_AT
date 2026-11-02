-- mvp_258 · 삼성닷컴 구독 멤버십 포인트를 모델별로 보관·배포한다 (2026-11-02)
-- 왜: 구독탭(sdp/sub/sub_tab.js)·구독센터는 행사(sub.promo)의 "N개월 구독료 상당 포인트" 만 알았다. 삼성닷컴 구독 상품 페이지는 모델마다
--     "적립 예정 멤버십 포인트"(정률 aiscRate × 결제금액 + 기본 0.1% + 상품별 추가 포인트)를 보여 주는데, 이 값이 데이터센터에 없어 한 모델만 손으로 넣고 있었다.
-- 무엇:
--   sub.model_point        모델 → goods_id(삼성닷컴 상품번호 · 모델→상품 매핑 캐시) · 조회 기준 약정·총액 · 정률(aisc_rate %) · 기본률(basic_rate %) · 추가 포인트(mdl_add_point) · 총 포인트
--                          src 'samsung.com'(수집) | 'manual'(관리자·매장 손 입력 — 수집이 덮지 않는다)
--   sub.model_point_check  모델별 마지막 확인(찾음/못 찾음 · 실패 횟수 · 오류) — 못 찾은 모델은 7~30일 뒤 다시 본다
--   sub.model_point_fetch  수집 1회 기록 (대상·찾음·못 찾음·오류·저장·손 입력 보호)
--   fn_sub_point_targets(p_all, p_limit, p_key)   수집 대상 (dps.sub_model active 모델 + 최장 약정 최저 총액 + 캐시된 goods_id)  — service_role 또는 API 키
--   fn_sub_point_upsert(p_rows, p_key, p_meta)    수집 결과 저장 (tools/subpoint/collect.mjs · GitHub Actions sub-point.yml 매주 월요일)  — service_role 또는 API 키 'sub_point'
--   fn_sub_point_save(p_data) · fn_store_sub_point_save(p_code, p_data)   손 입력 (src manual) · 되돌리기(release) · 지우기(remove)
--   fn_sub_point_list(p_q, p_limit) · fn_store_sub_point_list(p_code, p_q, p_limit)   관리자·매장 읽기
--   sub.f_policy_view()   'points' 요약(마지막 수집·건수·실패)   sub.f_policy_export()   'points': {모델: {rate, base, add, total}}   sub.f_policy_ver()  포인트가 바뀌면 판도 바뀐다
--   sub.model_point 저장 트리거 → sub.f_deploy_kick (mvp_255) → 수집이 끝나면 바로 배포가 돈다
-- 화면: sub_tab.js 가 points[모델] 로 "적립 예정 멤버십 포인트"(= 결제 예상액 × (rate+base)% + add) 를 결제 내역에 한 줄 더 보여 주고 실제 구독료에서 뺀다 (행사 포인트와 둘 다 표시).
-- 키: API 키 값은 저장소에 없다 (core.api_key 'sub_point' 에 SHA-256 만 · 값은 _secrets.local.md · GitHub Secrets SUB_POINT_KEY). 서비스 롤 키로도 부를 수 있다.

begin;

create table if not exists sub.model_point (
  model          text primary key,
  goods_id       text,                                   -- 삼성닷컴 goodsId (G00…) — 모델→상품 매핑 캐시 (있으면 상품 페이지를 다시 읽지 않는다)
  term_months    int,                                    -- 조회 기준 약정(최장)
  price          int,                                    -- 조회 기준 총액 (dps.sub_model 최장 약정 최저 total_fee)
  total_point    int,                                    -- 삼성닷컴 응답 totalPoint (기준 총액일 때)
  apl_point      int,                                    -- 정률 포인트 (aiscRate × price)
  basic_point    int,                                    -- 기본 멤버십 포인트 (basicRate × price)
  mdl_add_point  int,                                    -- 상품별 추가 포인트
  aisc_rate      numeric(6,2),                           -- 정률 % (예 6.00)
  basic_rate     numeric(6,3),                           -- 기본 % (예 0.100)
  src            text not null default 'samsung.com' check (src in ('samsung.com','manual')),
  note           text,
  fetched_at     timestamptz,
  updated_at     timestamptz not null default now(),
  updated_by     text
);
create table if not exists sub.model_point_check (
  model       text primary key,
  found       boolean not null,
  checked_at  timestamptz not null default now(),
  miss_count  int not null default 0,
  goods_id    text,
  err         text
);
create table if not exists sub.model_point_fetch (
  id           bigserial primary key,
  started_at   timestamptz,
  finished_at  timestamptz not null default now(),
  targets      int, found int, missed int, errors int, saved int, kept_manual int,
  miss_models  jsonb,
  note         text,
  by_user      text
);
alter table sub.model_point       enable row level security;
alter table sub.model_point_check enable row level security;
alter table sub.model_point_fetch enable row level security;
revoke all on sub.model_point, sub.model_point_check, sub.model_point_fetch from public, anon, authenticated;

-- 수집이 끝나면(저장 문장 1번) 배포가 걸리게 — 정책·행사와 같은 트리거 (mvp_255)
drop trigger if exists trg_deploy_kick on sub.model_point;
create trigger trg_deploy_kick after insert or update or delete on sub.model_point
  for each statement execute function sub.f_deploy_kick();

-- 수집기 인증: 서비스 롤(core.f_role() = 'admin') 또는 API 키 'sub_point'
create or replace function sub.f_point_api_ok(p_key text) returns boolean
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role','') = 'service_role'
      or (coalesce(p_key,'') <> '' and core.f_api_ok('sub_point', p_key));
$$;

-- ── 수집 대상 ── 활성 구독 모델마다 최장 약정의 최저 총액(무상수리) · 캐시된 goods_id
--   p_all=false: 처음 보는 모델 + 찾은 지 6일 넘은 모델 + 못 찾은 모델은 7·14·21…(최대 30)일 뒤
create or replace function public.fn_sub_point_targets(p_all boolean default false, p_limit int default 3000, p_key text default null)
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
     limit p_limit;
end $$;

-- ── 수집 결과 저장 ──
--   p_rows: [{model, goods_id, term_months, price, total_point, apl_point, basic_point, mdl_add_point, aisc_rate, basic_rate, err}]
--           total_point 또는 aisc_rate 가 있으면 '찾음'. 없으면 '못 찾음'(err 에 이유). 일시 오류(네트워크)는 수집기가 보내지 않는다 → 다음에 다시
--   p_meta: {started_at, targets, errors, note}
--   손 입력 행(src manual)은 값은 그대로 두고 goods_id 가 비어 있을 때만 채운다
create or replace function public.fn_sub_point_upsert(p_rows jsonb, p_key text default null, p_meta jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare n_found int := 0; n_saved int := 0; n_kept int := 0; n_missed int := 0; n_check int := 0; v_id bigint; v_by text;
begin
  if not sub.f_point_api_ok(p_key) then raise exception '키가 맞지 않습니다' using errcode = '42501'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows 는 목록이어야 합니다' using errcode = '22023'; end if;
  v_by := case when coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role','') = 'service_role' then 'github-actions' else 'api:sub_point' end;

  create temp table _pt on commit drop as
    select r.*, (r.total_point is not null or r.aisc_rate is not null) found from (
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
  select count(*) filter (where found), count(*) filter (where not found) into n_found, n_missed from _pt;

  -- 찾은 것 → sub.model_point (손 입력 행은 goods_id 만 보충)
  with up as (
    insert into sub.model_point as t (model, goods_id, term_months, price, total_point, apl_point, basic_point, mdl_add_point, aisc_rate, basic_rate, src, fetched_at, updated_at, updated_by)
    select model, goods_id, term_months, price, total_point, apl_point, basic_point, mdl_add_point, aisc_rate, basic_rate, 'samsung.com', now(), now(), v_by
      from _pt where found
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
  select model, found, now(), case when found then 0 else 1 end, goods_id, case when found then null else err end from _pt
  on conflict (model) do update
    set found = excluded.found, checked_at = now(),
        miss_count = case when excluded.found then 0 else c.miss_count + 1 end,
        goods_id = coalesce(excluded.goods_id, c.goods_id),
        err = excluded.err;
  get diagnostics n_check = row_count;

  insert into sub.model_point_fetch (started_at, targets, found, missed, errors, saved, kept_manual, miss_models, note, by_user)
  values (nullif(p_meta->>'started_at','')::timestamptz, nullif(p_meta->>'targets','')::int, n_found, n_missed, nullif(p_meta->>'errors','')::int,
          n_saved, n_kept, (select coalesce(jsonb_agg(model order by model), '[]'::jsonb) from (select model from _pt where not found limit 500) m),
          left(p_meta->>'note', 500), v_by)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'fetch_id', v_id, 'found', n_found, 'missed', n_missed, 'saved', n_saved, 'kept_manual', n_kept, 'checked', n_check);
end $$;

-- ── 손 입력 (관리자·매장 공용 본체) ──
--   p_data: {model, add(추가 포인트 원), rate(정률 % · 비우면 있던 값/수집값 유지), base(기본 % · 비우면 0.1), goods_id, note, release(true → 수집이 다시 덮게), remove(true → 지움)}
create or replace function sub.f_point_save(p_data jsonb, p_by text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_model text := upper(regexp_replace(coalesce(p_data->>'model',''), '\s', '', 'g')); v_old jsonb; v_new jsonb;
        v_add int; v_rate numeric; v_base numeric; v_note text := nullif(btrim(coalesce(p_data->>'note','')),'');
begin
  if v_model = '' then raise exception '모델번호가 비었습니다' using errcode = '22023'; end if;
  select to_jsonb(p) - 'updated_at' - 'updated_by' into v_old from sub.model_point p where p.model = v_model;
  if coalesce((p_data->>'remove')::boolean, false) then
    if v_old is null then raise exception '% 는 포인트 표에 없습니다', v_model using errcode = '22023'; end if;
    delete from sub.model_point where model = v_model;
    delete from sub.model_point_check where model = v_model;
    insert into sub.policy_log (kind, key, before, after, by_user) values ('point', v_model, v_old, null, p_by);
    return jsonb_build_object('ok', true, 'model', v_model, 'removed', true);
  end if;
  if coalesce((p_data->>'release')::boolean, false) then
    if v_old is null then raise exception '% 는 포인트 표에 없습니다', v_model using errcode = '22023'; end if;
    update sub.model_point set src = 'samsung.com', note = v_note, updated_by = p_by, updated_at = now() where model = v_model;
    select to_jsonb(p) - 'updated_at' - 'updated_by' into v_new from sub.model_point p where p.model = v_model;
    insert into sub.policy_log (kind, key, before, after, by_user) values ('point', v_model, v_old, v_new, p_by);
    return jsonb_build_object('ok', true, 'model', v_model, 'released', true);
  end if;
  if p_data ? 'add' then
    v_add := nullif(regexp_replace(coalesce(p_data->>'add',''), '[^0-9-]', '', 'g'),'')::int;
    if v_add is not null and (v_add < 0 or v_add > 10000000) then raise exception '추가 포인트는 0~10,000,000 사이여야 합니다' using errcode = '22023'; end if;
  end if;
  if p_data ? 'rate' then
    v_rate := nullif(regexp_replace(coalesce(p_data->>'rate',''), '[^0-9.]', '', 'g'),'')::numeric;
    if v_rate is not null and (v_rate < 0 or v_rate >= 100) then raise exception '정률은 0~100 사이 %% 로 적어 주세요 (6%% → 6)' using errcode = '22023'; end if;
  end if;
  if p_data ? 'base' then
    v_base := nullif(regexp_replace(coalesce(p_data->>'base',''), '[^0-9.]', '', 'g'),'')::numeric;
    if v_base is not null and (v_base < 0 or v_base >= 100) then raise exception '기본률은 0~100 사이 %% 로 적어 주세요' using errcode = '22023'; end if;
  end if;
  insert into sub.model_point as t (model, goods_id, mdl_add_point, aisc_rate, basic_rate, src, note, updated_by)
  values (v_model, nullif(btrim(coalesce(p_data->>'goods_id','')),''), v_add, v_rate, coalesce(v_base, 0.1), 'manual', v_note, p_by)
  on conflict (model) do update
    set goods_id      = coalesce(nullif(btrim(coalesce(p_data->>'goods_id','')),''), t.goods_id),
        mdl_add_point = case when p_data ? 'add'  then v_add  else t.mdl_add_point end,
        aisc_rate     = case when p_data ? 'rate' and v_rate is not null then v_rate else t.aisc_rate end,
        basic_rate    = case when p_data ? 'base' and v_base is not null then v_base else coalesce(t.basic_rate, 0.1) end,
        src = 'manual', note = v_note, updated_by = p_by, updated_at = now();
  select to_jsonb(p) - 'updated_at' - 'updated_by' into v_new from sub.model_point p where p.model = v_model;
  if v_old is distinct from v_new then
    insert into sub.policy_log (kind, key, before, after, by_user) values ('point', v_model, v_old, v_new, p_by); end if;
  return jsonb_build_object('ok', true, 'model', v_model);
end $$;

-- ── 읽기 (관리자·매장 공용 본체) ── 모델 검색 · 최근 바뀐 것 먼저 · 손 입력 먼저
create or replace function sub.f_point_list(p_q text, p_limit int) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with m as (select model, min(category) cat, min(seg) seg from dps.sub_model where active group by model),
       q as (select upper(regexp_replace(coalesce(p_q,''), '\s', '', 'g')) q)
  select coalesce(jsonb_agg(jsonb_build_object(
           'model', p.model, 'cat', m.cat, 'seg', m.seg, 'goods_id', p.goods_id, 'term', p.term_months, 'price', p.price,
           'total', p.total_point, 'apl', p.apl_point, 'basic', p.basic_point, 'add', p.mdl_add_point, 'rate', p.aisc_rate, 'base', p.basic_rate,
           'src', p.src, 'note', p.note,
           'fetched', to_char(p.fetched_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'),
           'updated', to_char(p.updated_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'by', p.updated_by,
           'active', m.model is not null)
         order by (p.src = 'manual') desc, p.updated_at desc, p.model), '[]'::jsonb)
    from (select * from sub.model_point p, q
           where q.q = '' or p.model like '%' || q.q || '%'
              or exists (select 1 from m where m.model = p.model and (m.cat ilike '%' || p_q || '%' or m.seg ilike '%' || p_q || '%'))
           order by (p.src = 'manual') desc, p.updated_at desc, p.model
           limit greatest(1, least(coalesce(p_limit, 300), 2000))) p
    left join m on m.model = p.model;
$$;
-- 못 찾은 모델 (관리자 화면 "실패" 목록)
create or replace function sub.f_point_missed(p_limit int) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('model', c.model, 'at', to_char(c.checked_at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'n', c.miss_count, 'err', c.err) order by c.checked_at desc), '[]'::jsonb)
    from (select * from sub.model_point_check where not found
            and model in (select model from dps.sub_model where active)
           order by checked_at desc limit greatest(1, least(coalesce(p_limit, 200), 2000))) c;
$$;

-- ── 화면용 읽기에 포인트 요약 (본문 치환 · CLAUDE.md 규칙) ──
do $outer$
declare v_src text; v_n int;
        v_old text := $q$'ver', sub.f_policy_ver(),$q$;
        v_new text := $q$'points', (select jsonb_build_object(
                 'n', (select count(*) from sub.model_point),
                 'n_rate', (select count(*) from sub.model_point where coalesce(aisc_rate,0) > 0 or coalesce(mdl_add_point,0) > 0),
                 'n_add', (select count(*) from sub.model_point where coalesce(mdl_add_point,0) > 0),
                 'n_manual', (select count(*) from sub.model_point where src = 'manual'),
                 'n_missed', (select count(*) from sub.model_point_check c where not c.found and c.model in (select model from dps.sub_model where active)),
                 'n_active', (select count(distinct model) from dps.sub_model where active),
                 'last', (select jsonb_build_object('at', to_char(f.finished_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'targets', f.targets, 'found', f.found,
                                                    'missed', f.missed, 'errors', f.errors, 'saved', f.saved, 'kept_manual', f.kept_manual, 'note', f.note, 'by', f.by_user)
                            from sub.model_point_fetch f order by f.id desc limit 1))),
    'ver', sub.f_policy_ver(),$q$;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'sub' where p.proname = 'f_policy_view';
  if v_src is null then raise exception 'sub.f_policy_view 없음'; end if;
  if position('''points'', (select jsonb_build_object(' in v_src) > 0 then raise notice 'f_policy_view: 이미 points 가 있음 — 건너뜀'; return; end if;
  v_n := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'f_policy_view 치환 지점 %개 (1개여야 함)', v_n; end if;
  execute format('create or replace function sub.f_policy_view() returns jsonb language sql stable security definer set search_path to ''pg_catalog'',''public'' as %L',
                 replace(v_src, v_old, v_new));
end $outer$;

-- ── 배포 파일에 points: {모델: {rate, base, add, total}} (정률·추가 포인트가 하나라도 있는 모델만) ──
do $outer$
declare v_src text; v_n int;
        v_old text := $q$'overrides', sub.f_price_override_live()$q$;
        v_new text := $q$'points', (select coalesce(jsonb_object_agg(model, jsonb_strip_nulls(jsonb_build_object(
                'rate', case when coalesce(aisc_rate,0) > 0 then aisc_rate end,
                'base', case when coalesce(basic_rate,0) > 0 then basic_rate end,
                'add', case when coalesce(mdl_add_point,0) > 0 then mdl_add_point end,
                'total', case when coalesce(total_point,0) > 0 then total_point end))), '{}'::jsonb)
               from sub.model_point where coalesce(aisc_rate,0) > 0 or coalesce(mdl_add_point,0) > 0),
    'overrides', sub.f_price_override_live()$q$;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'sub' where p.proname = 'f_policy_export';
  if v_src is null then raise exception 'sub.f_policy_export 없음'; end if;
  if position('''points'', (select coalesce(jsonb_object_agg(model' in v_src) > 0 then raise notice 'f_policy_export: 이미 points 가 있음 — 건너뜀'; return; end if;
  v_n := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'f_policy_export 치환 지점 %개 (1개여야 함)', v_n; end if;
  execute format('create or replace function sub.f_policy_export() returns jsonb language sql stable security definer set search_path to ''pg_catalog'',''public'' as %L',
                 replace(v_src, v_old, v_new));
end $outer$;

-- ── 정책 판 번호에 포인트 변경 시각도 넣는다 (바뀌면 sub_policy.js · version.js 가 새 판으로 나간다) ──
do $outer$
declare v_src text; v_n int;
        v_old text := $q$(select max(updated_at) from sub.promo))$q$;
        v_new text := $q$(select max(updated_at) from sub.promo), (select max(updated_at) from sub.model_point))$q$;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'sub' where p.proname = 'f_policy_ver';
  if position('sub.model_point' in v_src) > 0 then raise notice 'f_policy_ver: 이미 반영 — 건너뜀'; return; end if;
  v_n := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'f_policy_ver 치환 지점 %개 (1개여야 함)', v_n; end if;
  execute format('create or replace function sub.f_policy_ver() returns text language sql stable security definer set search_path to ''pg_catalog'',''public'' as %L',
                 replace(v_src, v_old, v_new));
end $outer$;

-- ── 관리자 (아이디 로그인) ──
create or replace function public.fn_sub_point_save(p_data jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '모델 포인트 변경은 관리자만 할 수 있습니다' using errcode = '42501'; end if;
  return sub.f_point_save(p_data, core.f_sdp_actor());
end $$;
create or replace function public.fn_sub_point_list(p_q text default null, p_limit int default 300) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select case when core.f_role() = 'anon' then null
              else jsonb_build_object('rows', sub.f_point_list(p_q, p_limit), 'missed', sub.f_point_missed(200)) end;
$$;

-- ── 매장 (4자리 코드 · anon) — 보기는 누구나, 입력은 점장님·대표님 ──
create or replace function public.fn_store_sub_point_save(p_code text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not core.f_staff_is_mgr(v_me) then raise exception '모델 포인트는 점장님·대표님만 고칠 수 있습니다' using errcode = '42501'; end if;
  return sub.f_point_save(p_data, v_me);
end $$;
create or replace function public.fn_store_sub_point_list(p_code text, p_q text default null, p_limit int default 100) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  return jsonb_build_object('rows', sub.f_point_list(p_q, p_limit), 'can_edit', core.f_staff_is_mgr(v_me));
end $$;

revoke all on function sub.f_point_api_ok(text), sub.f_point_save(jsonb, text), sub.f_point_list(text, int), sub.f_point_missed(int),
              public.fn_sub_point_targets(boolean, int, text), public.fn_sub_point_upsert(jsonb, text, jsonb),
              public.fn_sub_point_save(jsonb), public.fn_sub_point_list(text, int),
              public.fn_store_sub_point_save(text, jsonb), public.fn_store_sub_point_list(text, text, int)
  from public, anon, authenticated;
grant execute on function public.fn_sub_point_targets(boolean, int, text)     to anon, authenticated, service_role;   -- 키로 막는다
grant execute on function public.fn_sub_point_upsert(jsonb, text, jsonb)      to anon, authenticated, service_role;   -- 키로 막는다
grant execute on function public.fn_sub_point_save(jsonb)                     to authenticated, service_role;
grant execute on function public.fn_sub_point_list(text, int)                 to authenticated, service_role;
grant execute on function public.fn_store_sub_point_save(text, jsonb)         to anon, authenticated, service_role;
grant execute on function public.fn_store_sub_point_list(text, text, int)     to anon, authenticated, service_role;

-- API 키 (값은 저장소에 없다 · 해시만) — 적용 뒤 별도 문장으로:
-- insert into core.api_key (name, key_hash, note) values ('sub_point', '<sha256 hex>', '삼성닷컴 구독 포인트 수집기(tools/subpoint/collect.mjs · GitHub Secrets SUB_POINT_KEY) → fn_sub_point_targets/upsert (2026-11-02)');

commit;

-- 확인
-- select * from fn_sub_point_targets(true, 5);                       (service_role)
-- select sub.f_policy_export()->'points';  select sub.f_policy_view()->'points';  select sub.f_policy_ver();
-- 처음 한 번: 기존 손 입력 540,000 은 행사(sub.promo amounts) 쪽 금액이라 그대로 두고, 멤버십 포인트는 수집기가 채운다.
