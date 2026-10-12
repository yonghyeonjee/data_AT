-- mvp_200 · DPS 수신동의 재확인 (2026-10-12 · 적용: Supabase migration dps_consent_recheck)
-- 수집기 [수신거부만 확인] 이 지금 동의 상태인 고객만 DPS 고객조회로 다시 조회 → 고객정보.json 갱신 →
-- 업로드(--consent-only)가 fn_dps_consent_upsert(동의 항목만, 조회일이 같거나 새로울 때) → fn_dps_consent_apply.
-- apply: crm.customer(dps_customer_no 로 연결)의 consent_dps 를 dps.customer.sms 에 맞추고,
--        consent_source = 'dps' 인 고객만 consent_marketing 도 따라간다(다른 채널 동의는 그 채널 기준 유지) · consent_history 'dps' 한 줄.
-- 일반 업로드도 원장 동기화 끝에 fn_dps_consent_apply 를 부른다. 바뀐 것이 없으면 아무것도 안 한다.
-- 시험(되돌림): 수신동의 고객 1명을 수신거부로 올림 → upsert updated 1 · apply changed 1 · marketing_off 1 · 다시 apply → changed 0.

create or replace function core.f_dps_consent_apply()
returns jsonb language plpgsql set search_path to 'pg_catalog', 'public' as $$
declare v_changed int := 0; v_refused int := 0; v_agreed int := 0; v_mk_off int := 0; v_mk_on int := 0;
begin
  create temp table if not exists _dps_consent_ch (id bigint, buyer_key char(16), v boolean, at timestamptz, sms text, txt text, checked date, src text) on commit drop;
  truncate _dps_consent_ch;
  insert into _dps_consent_ch
  select c.id, c.buyer_key, d.sms = '수신동의', coalesce(d.checked_at::timestamptz, now()), d.sms, d.consent_text, d.checked_at, c.consent_source
    from crm.customer c join dps.customer d on d.customer_no = c.dps_customer_no
   where d.sms in ('수신동의', '수신거부') and c.consent_dps is distinct from (d.sms = '수신동의');
  get diagnostics v_changed = row_count;
  if v_changed = 0 then return jsonb_build_object('changed', 0, 'refused', 0, 'agreed', 0, 'marketing_off', 0, 'marketing_on', 0); end if;

  update crm.customer c set consent_dps = ch.v, consent_dps_at = ch.at, updated_at = now()
    from _dps_consent_ch ch where c.id = ch.id;
  select count(*) filter (where not v), count(*) filter (where v) into v_refused, v_agreed from _dps_consent_ch;

  -- 발송 동의는 동의 출처가 DPS 인 고객만 따라간다(다른 채널에서 받은 동의는 그 채널 기준을 유지).
  update crm.customer c set consent_marketing = ch.v, consent_updated_at = ch.at
    from _dps_consent_ch ch where c.id = ch.id and c.consent_source = 'dps' and c.consent_marketing is distinct from ch.v;
  select count(*) filter (where not ch.v), count(*) filter (where ch.v) into v_mk_off, v_mk_on
    from _dps_consent_ch ch where ch.src = 'dps';

  insert into crm.consent_history (buyer_key, consent, changed_at, source, evidence)
  select ch.buyer_key, ch.v, ch.at, 'dps', 'DPS 수신동의 재확인 · SMS ' || ch.sms || ' · ' || coalesce(ch.txt, '') || ' · 조회 ' || coalesce(ch.checked::text, '')
    from _dps_consent_ch ch;

  return jsonb_build_object('changed', v_changed, 'refused', v_refused, 'agreed', v_agreed, 'marketing_off', v_mk_off, 'marketing_on', v_mk_on);
end $$;

create or replace function core.f_dps_consent_upsert(p_rows jsonb)
returns jsonb language plpgsql set search_path to 'pg_catalog', 'public' as $$
declare v_rows int := 0; v_upd int := 0; v_refused int := 0;
begin
  with src as (
    select r->>'customer_no' as customer_no, nullif(r->>'text','') as consent_text, nullif(r->>'privacy','') as privacy,
           nullif(r->>'marketing','') as marketing, nullif(r->>'ad','') as ad, nullif(r->>'sms','') as sms,
           nullif(r->>'dm','') as dm, nullif(r->>'tm','') as tm, (r->>'member')::boolean as member,
           nullif(r->>'status','') as status, nullif(r->>'grade','') as grade, nullif(r->>'membership','') as membership,
           case when r->>'checked_at' ~ '^\d{4}-\d{2}-\d{2}$' then (r->>'checked_at')::date end as checked_at
      from jsonb_array_elements(p_rows) r
     where nullif(r->>'customer_no','') is not null
  ), up as (
    insert into dps.customer as d (customer_no, consent_text, privacy, marketing, ad, sms, dm, tm, member, status, grade, membership, checked_at, updated_at)
    select customer_no, consent_text, privacy, marketing, ad, sms, dm, tm, member, status, grade, membership, checked_at, now() from src
    on conflict (customer_no) do update set consent_text = excluded.consent_text, privacy = excluded.privacy, marketing = excluded.marketing,
      ad = excluded.ad, sms = excluded.sms, dm = excluded.dm, tm = excluded.tm, member = excluded.member, status = excluded.status,
      grade = coalesce(excluded.grade, d.grade), membership = coalesce(excluded.membership, d.membership), checked_at = excluded.checked_at, updated_at = now()
    where d.checked_at is null or (excluded.checked_at is not null and excluded.checked_at >= d.checked_at)
      and (d.sms is distinct from excluded.sms or d.marketing is distinct from excluded.marketing or d.consent_text is distinct from excluded.consent_text
           or d.checked_at is distinct from excluded.checked_at)
    returning d.sms
  )
  select (select count(*) from src), count(*), count(*) filter (where sms = '수신거부') into v_rows, v_upd, v_refused from up;
  return jsonb_build_object('rows', v_rows, 'updated', v_upd, 'updated_refused', v_refused);
end $$;

revoke all on function core.f_dps_consent_apply() from public;
revoke all on function core.f_dps_consent_upsert(jsonb) from public;

create or replace function public.fn_dps_consent_upsert(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'public' as $$
begin
  if core.f_role() not in ('admin','uploader') then raise exception 'DPS 적재는 관리자만 가능합니다' using errcode = '42501'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception '올릴 행이 없습니다'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception '한 번에 2000명까지 올릴 수 있습니다'; end if;
  return core.f_dps_consent_upsert(p_rows);
end $$;

create or replace function public.fn_dps_consent_apply()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'public' as $$
begin
  if core.f_role() not in ('admin','uploader') then raise exception 'DPS 적재는 관리자만 가능합니다' using errcode = '42501'; end if;
  return core.f_dps_consent_apply();
end $$;

revoke all on function public.fn_dps_consent_upsert(jsonb) from public, anon;
revoke all on function public.fn_dps_consent_apply() from public, anon;
grant execute on function public.fn_dps_consent_upsert(jsonb) to authenticated, service_role;
grant execute on function public.fn_dps_consent_apply() to authenticated, service_role;
