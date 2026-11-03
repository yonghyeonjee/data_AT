-- mvp_263 · DPS 가망고객 (2026-11-02)
-- DPS 고객 › CRM활동(321등) › 가망내역 — 매장 사원이 DPS 에 등록한 '살 것 같은 고객' (구매예정일·관심 품목·진행상태)
-- DPS 수집기(tools\gamang)가 등록일 기준 최근 몇 달을 받아 fn_dps_prospect_upsert 로 올린다.
-- 이름·전화는 DPS 가 가려서 주므로 받지 않는다 — DPS 고객번호(kunnr) 로 crm.customer.dps_customer_no 와 잇는다.
create table if not exists dps.prospect (
  kunnr        text not null,           -- DPS 고객번호
  seqno        text not null,           -- 가망 번호
  posnr        text not null,           -- 품목 줄
  staff_code   text,                    -- 상담 사원 (DAZ3xxx)
  staff_name   text,                    -- DPS 가 가린 이름 (예: 김*완)
  status       text,                    -- S 성공 · N 부분성공 · P 진행중 · Z 종료
  reg_date     date,                    -- 등록일
  expect_date  date,                    -- 구매예정일
  contact_date date,                    -- 접촉예정일
  items        text[],                  -- 관심 품목 (TV·냉장고·김치냉장고·세탁기·에어컨·건조기·PC·모니터·프린터·소물·휴대폰·기타)
  purpose      text,                    -- 구매 목적 (교체·추가구입·선물·이사·신규·혼수)
  tendency     text,                    -- 고객 성향 (전반적만족·가격민감·제품민감·전반적불만족)
  mem_grade    text,                    -- DPS 멤버십 표시 코드 (원본 그대로)
  first_seen   date not null default current_date,
  last_seen    date not null default current_date,
  status_changed_at timestamptz,
  updated_at   timestamptz not null default now(),
  primary key (kunnr, seqno, posnr)
);
create index if not exists prospect_kunnr_idx on dps.prospect (kunnr);
create index if not exists prospect_expect_idx on dps.prospect (expect_date) where status = 'P';
alter table dps.prospect enable row level security;
revoke all on dps.prospect from anon, authenticated;

create or replace function public.fn_dps_prospect_upsert(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'public' as $$
declare v_rows int := 0; v_new int := 0; v_st int := 0;
begin
  if core.f_role() not in ('admin','uploader') then raise exception 'DPS 적재는 관리자만 가능합니다' using errcode = '42501'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('rows', 0); end if;
  with src as (
    select distinct on (r->>'kunnr', r->>'seqno', r->>'posnr')
           r->>'kunnr' kunnr, r->>'seqno' seqno, r->>'posnr' posnr,
           nullif(r->>'staff_code','') staff_code, nullif(r->>'staff_name','') staff_name, nullif(r->>'status','') status,
           nullif(r->>'reg_date','')::date reg_date, nullif(r->>'expect_date','')::date expect_date, nullif(r->>'contact_date','')::date contact_date,
           coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(r->'items','[]'::jsonb)) x), '{}') items,
           nullif(r->>'purpose','') purpose, nullif(r->>'tendency','') tendency, nullif(r->>'mem_grade','') mem_grade
      from jsonb_array_elements(p_rows) r
     where coalesce(r->>'kunnr','') <> '' and coalesce(r->>'seqno','') <> ''),
  cmp as (select s.*, p.status old_status, (p.kunnr is null) is_new from src s left join dps.prospect p using (kunnr, seqno, posnr)),
  up as (
    insert into dps.prospect as t (kunnr, seqno, posnr, staff_code, staff_name, status, reg_date, expect_date, contact_date, items, purpose, tendency, mem_grade)
    select kunnr, seqno, coalesce(posnr,''), staff_code, staff_name, status, reg_date, expect_date, contact_date, items, purpose, tendency, mem_grade from cmp
    on conflict (kunnr, seqno, posnr) do update set
      staff_code = excluded.staff_code, staff_name = excluded.staff_name,
      status_changed_at = case when t.status is distinct from excluded.status then now() else t.status_changed_at end,
      status = excluded.status, reg_date = excluded.reg_date, expect_date = excluded.expect_date, contact_date = excluded.contact_date,
      items = excluded.items, purpose = excluded.purpose, tendency = excluded.tendency, mem_grade = excluded.mem_grade,
      last_seen = current_date, updated_at = now()
    returning 1)
  select (select count(*) from up), (select count(*) from cmp where is_new), (select count(*) from cmp where not is_new and old_status is distinct from status)
    into v_rows, v_new, v_st;
  return jsonb_build_object('rows', v_rows, 'new', v_new, 'status_changed', v_st);
end $$;
revoke all on function public.fn_dps_prospect_upsert(jsonb) from public, anon;
grant execute on function public.fn_dps_prospect_upsert(jsonb) to authenticated, service_role;
