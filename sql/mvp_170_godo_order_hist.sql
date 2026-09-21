-- mvp_170 (2026-09-21 · v134) — 이미 DB 에 반영됨. 기록용.
-- 고도몰 과거 주문(2021~2025.07, 주문통합리스트) 원본 적재 자리.
--   raw.godo_order_hist(row_hash pk, mall, order_no, ordered_at, data jsonb, source excel|api, source_file, upload_id, uploaded_by, loaded_at) · RLS on · 정책 없음(쓰기는 함수로만)
--   core.f_godo_order_hist_put(p_mall,p_file,p_rows,p_source) — 본체. raw.upload 한 줄(source 'godo_order_hist') + on conflict do nothing. 응답 {rows,new,dup}
--   public.fn_godo_order_hist_upsert(p_mall,p_file,p_rows) — GodomallCollector.exe(P몰·AT몰·S몰, dbuploader 로그인). f_role admin|uploader. 이름·인자·응답 키는 exe 와의 약속
--   public.fn_godo_order_hist_ingest(p_key,p_mall,p_file,p_rows) — tools/godo/collect.mjs(시흥몰 OpenAPI, GitHub Actions). core.api_key 'godo_order_hist'(값은 _secrets.local.md · GitHub Secrets GODO_INGEST_KEY)
-- 원장(core.orders)·고객(crm.customer)에는 안 쓴다 — 검수 뒤 판단.
-- 롤백 확인(2026-09-21): dbuploader 2행 new 2 → 다시 dup 2 · 잘못된 몰 P0001 · anon 42501 · user 롤 42501 · 키 맞음 new 1 · 키 틀림 42501.

create table if not exists raw.godo_order_hist (
  row_hash text primary key, mall text not null check (mall in ('P몰','S몰','AT몰','시흥몰')),
  order_no text, ordered_at timestamp, data jsonb not null,
  source text not null default 'excel' check (source in ('excel','api')), source_file text, upload_id bigint,
  uploaded_by uuid default auth.uid(), loaded_at timestamptz not null default now());
create index if not exists godo_order_hist_mall_no on raw.godo_order_hist (mall, order_no);
create index if not exists godo_order_hist_at on raw.godo_order_hist (ordered_at);
create index if not exists godo_order_hist_file on raw.godo_order_hist (source_file);
alter table raw.godo_order_hist enable row level security;

create or replace function core.f_godo_order_hist_put(p_mall text, p_file text, p_rows jsonb, p_source text)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_in int; v_new int; v_up bigint;
begin
  if p_mall not in ('P몰','S몰','AT몰','시흥몰') then raise exception '알 수 없는 몰: %', p_mall; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then return jsonb_build_object('rows',0,'new',0,'dup',0); end if;
  v_in := jsonb_array_length(p_rows);
  insert into raw.upload (source, file_name, row_count, error_count, note) values ('godo_order_hist', p_file, v_in, 0, p_mall || ' · ' || p_source) returning id into v_up;
  with ins as (
    insert into raw.godo_order_hist (row_hash, mall, order_no, ordered_at, data, source, source_file, upload_id)
    select r->>'h', p_mall, nullif(r->>'order_no',''),
           case when coalesce(r->>'ordered_at','') ~ '^\d{4}-\d{2}-\d{2}' then (r->>'ordered_at')::timestamp end,
           coalesce(r->'data','{}'::jsonb), p_source, p_file, v_up
      from jsonb_array_elements(p_rows) r where coalesce(r->>'h','') <> ''
    on conflict (row_hash) do nothing returning 1)
  select count(*) into v_new from ins;
  update raw.upload set note = note || ' · 새 ' || v_new || ' · 중복 ' || (v_in - v_new) where id = v_up;
  return jsonb_build_object('rows', v_in, 'new', v_new, 'dup', v_in - v_new);
end $$;
revoke all on function core.f_godo_order_hist_put(text,text,jsonb,text) from public, anon, authenticated;

create or replace function public.fn_godo_order_hist_upsert(p_mall text, p_file text, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if coalesce(core.f_role(),'') not in ('admin','uploader') then raise exception '권한이 없습니다' using errcode = '42501'; end if;
  return core.f_godo_order_hist_put(p_mall, p_file, p_rows, 'excel');
end $$;
revoke all on function public.fn_godo_order_hist_upsert(text,text,jsonb) from public, anon;
grant execute on function public.fn_godo_order_hist_upsert(text,text,jsonb) to authenticated, service_role;

-- insert into core.api_key (name, key_hash, note) values ('godo_order_hist', '<sha256>', '…');   -- 값은 저장소에 없다
create or replace function public.fn_godo_order_hist_ingest(p_key text, p_mall text, p_file text, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_api_ok('godo_order_hist', p_key) then raise exception '키가 맞지 않습니다' using errcode='42501'; end if;
  return core.f_godo_order_hist_put(p_mall, p_file, p_rows, 'api');
end $$;
revoke all on function public.fn_godo_order_hist_ingest(text,text,text,jsonb) from public;
grant execute on function public.fn_godo_order_hist_ingest(text,text,text,jsonb) to anon, authenticated, service_role;
