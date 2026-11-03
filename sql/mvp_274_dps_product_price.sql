-- mvp_274 · DPS 제품 가격표 (2026-11-03)
-- DPS 기준정보 › MD010-0014 (모델별 적정판매가) — 구독이 아닌 일반 판매 기준가
-- DPS 수집기(tools\price)가 매일 품목별로 받아, 지난번 올린 것과 달라진 모델만 fn_dps_price_upsert 로 올린다.
-- 타사 품목(T1xx)은 올리지 않는다. running 은 매장이 DPS 에서 [러닝] 체크해 둔 것 — 단종 모델도 남아 있을 수 있다.
create table if not exists dps.product_price (
  matnr        text primary key,        -- 모델 코드
  matkl        text,                    -- 품목 코드 (A101 LED TV · E202 일반냉장고 …)
  matkl_name   text,                    -- 품목 이름
  maktx        text,                    -- 모델명 (DPS 원문)
  running      boolean,                 -- 러닝 체크
  stock        int,                     -- 현재고 (매장)
  price_fair   bigint,                  -- 적정판매가 (ZDISP)
  price_sec    bigint,                  -- SEC 출고가 (ZCHUL)
  price_out    bigint,                  -- 출고가 (ZCODE)
  first_seen   date not null default current_date,
  last_seen    date not null default current_date,
  price_changed_at timestamptz,
  updated_at   timestamptz not null default now()
);
create index if not exists product_price_matkl_idx on dps.product_price (matkl);
alter table dps.product_price enable row level security;
revoke all on dps.product_price from anon, authenticated;

-- 가격이 바뀔 때마다 한 줄 (처음 들어온 모델은 남기지 않는다)
create table if not exists dps.product_price_log (
  id         bigserial primary key,
  matnr      text not null,
  changed_at timestamptz not null default now(),
  old_fair bigint, new_fair bigint,
  old_sec  bigint, new_sec  bigint,
  old_out  bigint, new_out  bigint
);
create index if not exists product_price_log_matnr_idx on dps.product_price_log (matnr, changed_at desc);
alter table dps.product_price_log enable row level security;
revoke all on dps.product_price_log from anon, authenticated;

create or replace function public.fn_dps_price_upsert(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'public' as $$
declare v_rows int := 0; v_new int := 0; v_chg int := 0;
begin
  if core.f_role() not in ('admin','uploader') then raise exception 'DPS 적재는 관리자만 가능합니다' using errcode = '42501'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('rows', 0); end if;
  with src as (
    select distinct on (r->>'matnr')
           r->>'matnr' matnr, nullif(r->>'matkl','') matkl, nullif(r->>'matkl_name','') matkl_name, nullif(r->>'maktx','') maktx,
           (r->>'running')::boolean running, nullif(r->>'stock','')::int stock,
           nullif(r->>'price_fair','')::bigint price_fair, nullif(r->>'price_sec','')::bigint price_sec, nullif(r->>'price_out','')::bigint price_out
      from jsonb_array_elements(p_rows) r
     where coalesce(r->>'matnr','') <> ''),
  cmp as (
    select s.*, (p.matnr is null) is_new, p.price_fair o_fair, p.price_sec o_sec, p.price_out o_out,
           (p.matnr is not null and (p.price_fair, p.price_sec, p.price_out) is distinct from (s.price_fair, s.price_sec, s.price_out)) chg
      from src s left join dps.product_price p using (matnr)),
  lg as (
    insert into dps.product_price_log (matnr, old_fair, new_fair, old_sec, new_sec, old_out, new_out)
    select matnr, o_fair, price_fair, o_sec, price_sec, o_out, price_out from cmp where chg
    returning 1),
  up as (
    insert into dps.product_price as t (matnr, matkl, matkl_name, maktx, running, stock, price_fair, price_sec, price_out)
    select matnr, matkl, matkl_name, maktx, running, stock, price_fair, price_sec, price_out from cmp
    on conflict (matnr) do update set
      matkl = excluded.matkl, matkl_name = excluded.matkl_name, maktx = excluded.maktx, running = excluded.running, stock = excluded.stock,
      price_changed_at = case when (t.price_fair, t.price_sec, t.price_out) is distinct from (excluded.price_fair, excluded.price_sec, excluded.price_out) then now() else t.price_changed_at end,
      price_fair = excluded.price_fair, price_sec = excluded.price_sec, price_out = excluded.price_out,
      last_seen = current_date, updated_at = now()
    returning 1)
  select (select count(*) from up), (select count(*) from cmp where is_new), (select count(*) from lg)
    into v_rows, v_new, v_chg;
  return jsonb_build_object('rows', v_rows, 'new', v_new, 'price_changed', v_chg);
end $$;
revoke all on function public.fn_dps_price_upsert(jsonb) from public, anon;
grant execute on function public.fn_dps_price_upsert(jsonb) to authenticated, service_role;
