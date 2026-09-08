-- mvp_40: 홈페이지 폼 시트 → Datacenter 공용 적재 (시트는 그대로 쓰고, 같은 행을 우리 DB 에도 쌓는다)
--   supply : 삼성앤텍 소모품/렌탈 문의        (b2b_form.html · 접수번호 P/W/A-nnnn)
--   b2b    : 삼성앤텍_문의내역_VMS_ToJandi    (VMS_Form.html · 접수번호 B-nnnn · raw_B2B 탭)
-- GAS 는 정규화된 키로만 보낸다: ref, ts, name, phone, category, summary, status, handler, memo, extra

alter table crm.consult drop constraint if exists consult_source_check;
alter table crm.consult add constraint consult_source_check check (source = any (array[
  'ecount_prospect','portal_form','web_inquiry','store','godo','web','web_subscription',
  'web_supply','web_b2b','web_form']));

create table if not exists core.form_def (
  code text primary key,
  label text not null,
  consult_source text not null,
  route text not null,
  active bool not null default true
);
insert into core.form_def(code, label, consult_source, route) values
  ('supply', '소모품·렌탈 문의', 'web_supply', '홈페이지-소모품/렌탈'),
  ('b2b',    'B2B 소모품 주문',  'web_b2b',    '홈페이지-B2B')
on conflict (code) do update set label = excluded.label, consult_source = excluded.consult_source, route = excluded.route;

-- 시트 상태값 → consult.result
create or replace function core.f_form_result(p_status text) returns text
language sql immutable set search_path = pg_catalog, public as $$
  select case
    when p_status is null or btrim(p_status) = '' then '진행중'
    when p_status ~ '상담완료|발주완료|구매|계약|완료' then '구매완료'
    when p_status ~ '보류' then '보류'
    when p_status ~ '취소|거절|종료' then '종료'
    else '진행중' end;
$$;

create or replace function public.fn_submit_form(p_key text, p_form text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  d jsonb; f record;
  v_name text; v_phone text; v_ts timestamptz; v_ref text; v_key char(16);
  v_hand text; v_result text; v_content text; v_notes text;
  n_ok int := 0; n_skip int := 0;
begin
  if not core.f_api_ok('gas_forward', p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into f from core.form_def where code = p_form and active;
  if not found then raise exception '등록되지 않은 폼입니다: %', p_form; end if;
  if jsonb_typeof(p_rows) <> 'array' then p_rows := jsonb_build_array(p_rows); end if;

  for d in select value from jsonb_array_elements(p_rows) loop
    v_name  := left(nullif(btrim(coalesce(d->>'name','')),''), 60);
    v_phone := nullif(regexp_replace(coalesce(d->>'phone',''), '\D', '', 'g'), '');
    v_ref   := nullif(btrim(coalesce(d->>'ref','')), '');
    v_ts    := coalesce(core.f_kst_ts(d->>'ts'), now());

    -- 테스트·연락처 불량 행은 버린다
    if v_ref is null or v_name is null or v_phone is null or length(v_phone) < 9
       or v_name ~* 'test|테스트' then n_skip := n_skip + 1; continue; end if;

    v_hand    := (select s.name from core.staff s where s.name = nullif(btrim(d->>'handler'),'') limit 1);
    v_result  := core.f_form_result(d->>'status');
    v_content := nullif(concat_ws(' / ',
                   nullif(btrim(d->>'category'), ''),
                   nullif(left(btrim(d->>'summary'), 900), '')), '');
    v_notes   := nullif(left(btrim(coalesce(d->>'memo','')), 500), '');

    v_key := core.f_buyer_key(v_name, v_phone);
    insert into crm.customer (buyer_key, name, phone, first_seen_at, last_seen_at,
                              consent_marketing, consent_source, source_channels)
    values (v_key, v_name, v_phone, v_ts, v_ts, false, 'web', array[f.consult_source])
    on conflict (buyer_key) do update set
      last_seen_at = greatest(crm.customer.last_seen_at, excluded.last_seen_at),
      source_channels = (select array_agg(distinct x) from unnest(crm.customer.source_channels || excluded.source_channels) x);

    insert into crm.consult (source, source_ref, consult_at, handler, customer_name, phone, buyer_key,
                             inflow_route, interest_category, result, content, notes, consent_marketing, raw_payload)
    values (f.consult_source, v_ref, v_ts, v_hand, v_name, v_phone, v_key,
            f.route, left(nullif(btrim(d->>'category'),''), 120), v_result, v_content, v_notes, false, d)
    on conflict (source, source_ref) do update set
      consult_at = excluded.consult_at,
      handler    = coalesce(excluded.handler, crm.consult.handler),
      result     = excluded.result,
      content    = coalesce(excluded.content, crm.consult.content),
      notes      = coalesce(excluded.notes, crm.consult.notes),
      raw_payload = excluded.raw_payload, updated_at = now();
    n_ok := n_ok + 1;
  end loop;

  return jsonb_build_object('ok', true, 'form', p_form, 'saved', n_ok, 'skipped', n_skip);
end $$;
revoke all on function public.fn_submit_form(text, text, jsonb) from public;
grant execute on function public.fn_submit_form(text, text, jsonb) to anon, authenticated, service_role;
