-- mvp_259 · 모델별 "구독 전용" 표시 (일시불 판매 없음) — 2026-11-02
-- 왜: WD90H25BHW(AI 콤보 화이트)처럼 삼성이 구독으로만 파는 모델이 시흥몰에 일시불 상품(1000000942 · 3,400,000원)으로도 올라 있어
--     구독센터 상품 페이지가 "일시불 3,400,000원"·"일시불보다 ○원" 비교를 보여줬다. 삼성닷컴 페이지에는 구독 전용 표식이 없어(색상별 HTML 동일) 자동 판정이 안 되므로
--     관리자·매장(점장님·대표님)이 모델마다 표시한다.
-- 무엇: sub.model_flag(model, sub_only, note) · 저장 = sub.f_point_save 의 'subOnly' 항목(관리자 fn_sub_point_save · 매장 fn_store_sub_point_save 그대로)
--       fn_sub_catalog 배열에 6번째 항목(1 = 구독 전용)을 더하고 구독 전용이면 일시불가는 0 → 구독센터(sub_view.js)·구독탭(sub_tab.js)·다품목(sub_bundle.js)이 일시불 비교를 뺀다
--       sub.f_point_list 는 구독 전용만 표시된 모델(포인트 행 없음)도 보여 준다 · 저장 트리거로 바로 배포(sdp-publish → sub_catalog.js)
-- 적용 뒤: select sub.f_point_save('{"model":"WD90H25BHW","subOnly":true,"note":"삼성 구독 전용 색상"}', 'admin');  select public.fn_sub_catalog()->'m'->'WD90H25BHW';

create table if not exists sub.model_flag (
  model      text primary key,
  sub_only   boolean not null default false,
  note       text,
  updated_at timestamptz not null default now(),
  updated_by text
);
alter table sub.model_flag enable row level security;
revoke all on sub.model_flag from public, anon, authenticated;
drop trigger if exists trg_deploy_kick on sub.model_flag;
create trigger trg_deploy_kick after insert or update or delete on sub.model_flag
  for each statement execute function sub.f_deploy_kick();

-- 표시 저장 본체 (true 면 넣고 false 면 지운다 · 바뀐 것만 기록)
create or replace function sub.f_flag_set(p_model text, p_sub_only boolean, p_note text, p_by text) returns boolean
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_old jsonb; v_new jsonb;
begin
  select to_jsonb(f) - 'updated_at' - 'updated_by' into v_old from sub.model_flag f where f.model = p_model;
  if coalesce(p_sub_only, false) then
    insert into sub.model_flag as t (model, sub_only, note, updated_by) values (p_model, true, p_note, p_by)
    on conflict (model) do update set sub_only = true, note = coalesce(excluded.note, t.note), updated_by = p_by, updated_at = now();
  else
    delete from sub.model_flag where model = p_model;
  end if;
  select to_jsonb(f) - 'updated_at' - 'updated_by' into v_new from sub.model_flag f where f.model = p_model;
  if v_old is distinct from v_new then
    insert into sub.policy_log (kind, key, before, after, by_user) values ('flag', p_model, v_old, v_new, p_by);
    return true;
  end if;
  return false;
end $$;

-- 손 입력 본체(mvp_258) 에 'subOnly' 항목 — 표시만 바꿀 때(add·rate·base 없음)는 포인트 행을 만들지 않는다 (만들면 정률 없는 '손 입력' 행이 되어 포인트가 사라진다)
create or replace function sub.f_point_save(p_data jsonb, p_by text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_model text := upper(regexp_replace(coalesce(p_data->>'model',''), '\s', '', 'g')); v_old jsonb; v_new jsonb;
        v_add int; v_rate numeric; v_base numeric; v_note text := nullif(btrim(coalesce(p_data->>'note','')),''); v_flag boolean := false;
begin
  if v_model = '' then raise exception '모델번호가 비었습니다' using errcode = '22023'; end if;
  if p_data ? 'subOnly' then
    v_flag := sub.f_flag_set(v_model, coalesce((p_data->>'subOnly')::boolean, false), v_note, p_by);
    if not (p_data ? 'add' or p_data ? 'rate' or p_data ? 'base' or p_data ? 'remove' or p_data ? 'release') then
      return jsonb_build_object('ok', true, 'model', v_model, 'flag', v_flag);
    end if;
  end if;
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
  return jsonb_build_object('ok', true, 'model', v_model, 'flag', v_flag);
end $$;

-- 읽기: 포인트 행 + 구독 전용 표시만 있는 모델 (sub_only 항목 추가)
create or replace function sub.f_point_list(p_q text, p_limit int) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with m as (select model, min(category) cat, min(seg) seg from dps.sub_model where active group by model),
       q as (select upper(regexp_replace(coalesce(p_q,''), '\s', '', 'g')) q),
       u as (select model from sub.model_point union select model from sub.model_flag),
       r as (select u.model, p.*, f.sub_only, f.note flag_note, f.updated_at flag_at, f.updated_by flag_by,
                    coalesce(p.updated_at, f.updated_at) sort_at
               from u left join sub.model_point p on p.model = u.model left join sub.model_flag f on f.model = u.model, q
              where q.q = '' or u.model like '%' || q.q || '%'
                 or exists (select 1 from m where m.model = u.model and (m.cat ilike '%' || p_q || '%' or m.seg ilike '%' || p_q || '%'))
              order by (p.src = 'manual') desc nulls last, coalesce(p.updated_at, f.updated_at) desc, u.model
              limit greatest(1, least(coalesce(p_limit, 300), 2000)))
  select coalesce(jsonb_agg(jsonb_build_object(
           'model', r.model, 'cat', m.cat, 'seg', m.seg, 'goods_id', r.goods_id, 'term', r.term_months, 'price', r.price,
           'total', r.total_point, 'apl', r.apl_point, 'basic', r.basic_point, 'add', r.mdl_add_point, 'rate', r.aisc_rate, 'base', r.basic_rate,
           'src', coalesce(r.src, 'none'), 'note', coalesce(r.note, r.flag_note), 'sub_only', coalesce(r.sub_only, false),
           'fetched', to_char(r.fetched_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'),
           'updated', to_char(r.sort_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'by', coalesce(r.updated_by, r.flag_by),
           'active', m.model is not null)
         order by (r.src = 'manual') desc nulls last, r.sort_at desc, r.model), '[]'::jsonb)
    from r left join m on m.model = r.model;
$$;

-- 카탈로그 (mvp_252 본체) + 6번째 항목 구독 전용(1/0) · 구독 전용이면 일시불가 0
create or replace function public.fn_sub_catalog() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with m as (select distinct model from dps.sub_model where active),
  g as (select *, (goods_nm like '[구독]%') as sub_listing from core.godo_goods where active and display_fl and sell_fl),
  codes as (
    select sub_model code, 1 pri, goods_no, goods_nm, sub_listing, goods_price from g where sub_model is not null
    union all select model_no, 2, goods_no, goods_nm, sub_listing, goods_price from g where model_no is not null
    union all select goods_cd, 3, goods_no, goods_nm, sub_listing, goods_price from g where goods_cd is not null
    union all select unnest(option_codes), 4, goods_no, goods_nm, sub_listing, goods_price from g),
  pick as (select distinct on (code) * from codes where code <> '' order by code, sub_listing, pri, goods_no desc),
  named as (
    select m.model, k.goods_no, k.sub_listing, k.goods_price, coalesce(mi.image_url, ia.image) as image, case when mi.image_url is not null then 'm' else ia.kind end as kind,
      coalesce(f.sub_only, false) sub_only,
      case when k.goods_nm is not null and not k.sub_listing then k.goods_nm
           when p.product_name ~ '(삼성|삼섬|비스포크|BESPOKE|Bespoke|갤럭시|Galaxy)' then p.product_name
           else k.goods_nm end as raw
    from m left join pick k on k.code = m.model left join core.product p on p.model_code = m.model
      left join core.sub_model_image_auto ia on ia.model = m.model
      left join core.sub_model_image mi on mi.model = m.model and coalesce(mi.image_url, '') <> ''
      left join sub.model_flag f on f.model = m.model)
  select jsonb_build_object(
    'ver', to_char(now() at time zone 'Asia/Seoul', 'YYYYMMDDHH24MI'),
    'img', 'https://godomall-storage.cdn-nhncommerce.com/bbfe079be9069f71afe7ad9a5bf9cee9/goods/',
    'm', coalesce(jsonb_object_agg(model, jsonb_build_array(
        coalesce(goods_no, 0), coalesce(public.fn_sub_clean_name(raw, model), ''), coalesce(image, ''),
        case when goods_no is null or sub_listing or sub_only then 0 else coalesce(goods_price, 0)::bigint end,
        coalesce(kind, ''),
        case when sub_only then 1 else 0 end)), '{}'::jsonb))
  from named;
$$;

revoke all on function sub.f_flag_set(text, boolean, text, text) from public, anon, authenticated;

-- 첫 표시: AI 콤보 화이트 — 삼성 구독 전용 색상 (대표님 확인 2026-11-02)
select sub.f_point_save('{"model":"WD90H25BHW","subOnly":true,"note":"삼성 구독 전용 색상 (시흥몰 1000000942 는 일시불로 올라 있음)"}', 'admin');
