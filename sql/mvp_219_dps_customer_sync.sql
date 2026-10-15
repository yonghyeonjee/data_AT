-- mvp_219 · 원장 밖 DPS 고객도 고객 목록에 저장 (2026-10-15 · 적용: Supabase migration dps_customer_sync_non_ledger)
-- 사용자: "원장이 없어도 저장은 되게" (온라인·대표 명의·소모품 전표 고객 = DPS 에만 있고 core.orders 에 없음)
-- core.f_dps_customer_sync():
--   새 고객(crm.customer 에 없는 DPS 판매 buyer_key): 마지막 판매 전표의 이름·전화(숫자만)·주소 · source_channels {dps}
--     · dps_customer_no·등급 · consent_dps(SMS) · 발송 동의 consent_marketing = SMS 수신동의, consent_source 'dps' · consent_history 'DPS 고객정보 · 원장 밖 DPS 고객 등록'
--   기존 고객(dps_customer_no 없음): DPS 고객번호·등급·consent_dps·source_channels+dps 만 연결, 발송 동의는 그대로(보류 중인 A안과 구분).
-- public.fn_dps_consent_apply 가 sync → apply 순으로 함께 돌린다(수집기 업로드 마지막 단계).
-- 첫 실행 2026-10-15: 새로 2,385명(SMS 동의 1,006) · 연결 1,096명 · 다시 실행 0/0. DPS 구매 고객 7,344명 전원이 고객 목록에 있음.
-- 구매 요약(crm.customer_roll)은 core.orders 기준이라 이들은 '구매 0건'으로 보이고, DPS 전표는 고객 흐름 타임라인(매장 밖 DPS 전표)에 보인다.

create or replace function core.f_dps_customer_sync()
returns jsonb language plpgsql set search_path to 'pg_catalog', 'public' as $$
declare v_new int := 0; v_new_ok int := 0; v_link int := 0;
begin
  with last_sale as (
    select distinct on (s.buyer_key) s.buyer_key, s.customer_no, s.buyer_name, s.buyer_phone, s.buyer_address, s.sale_date
      from dps.sale s where s.doc_type = '판매' and s.buyer_key is not null
     order by s.buyer_key, s.sale_date desc, s.sale_no desc),
  first_sale as (select buyer_key, min(sale_date) first_dt from dps.sale where doc_type = '판매' and buyer_key is not null group by 1),
  src as (
    select l.*, f.first_dt, coalesce(d.membership, d.grade) grade, d.checked_at,
           case when d.sms = '수신동의' then true when d.sms = '수신거부' then false end v
      from last_sale l join first_sale f using (buyer_key) left join dps.customer d on d.customer_no = l.customer_no),
  ins as (
    insert into crm.customer (buyer_key, name, phone, address, account_type, first_seen_at, last_seen_at, source_channels,
                              dps_customer_no, dps_grade, consent_dps, consent_dps_at, consent_marketing, consent_source, consent_updated_at)
    select src.buyer_key, coalesce(nullif(trim(src.buyer_name), ''), '(미상)'), nullif(regexp_replace(coalesce(src.buyer_phone, ''), '\D', '', 'g'), ''),
           nullif(src.buyer_address, ''), 'personal', src.first_dt::timestamptz, src.sale_date::timestamptz, array['dps'],
           src.customer_no, src.grade, src.v, case when src.v is not null then coalesce(src.checked_at::timestamptz, now()) end,
           coalesce(src.v, false), case when src.v is not null then 'dps' end, case when src.v is not null then coalesce(src.checked_at::timestamptz, now()) end
      from src where not exists (select 1 from crm.customer c where c.buyer_key = src.buyer_key)
    on conflict (buyer_key) do nothing
    returning buyer_key, consent_dps, consent_dps_at),
  hist as (
    insert into crm.consent_history (buyer_key, consent, changed_at, source, evidence)
    select ins.buyer_key, ins.consent_dps, ins.consent_dps_at, 'dps', 'DPS 고객정보 · 원장 밖 DPS 고객 등록 · SMS ' || case when ins.consent_dps then '수신동의' else '수신거부' end
      from ins where ins.consent_dps is not null
    returning 1)
  select count(*), count(*) filter (where consent_dps) into v_new, v_new_ok from ins;

  with last_sale as (
    select distinct on (s.buyer_key) s.buyer_key, s.customer_no
      from dps.sale s where s.doc_type = '판매' and s.buyer_key is not null and s.customer_no is not null
     order by s.buyer_key, s.sale_date desc, s.sale_no desc),
  src as (
    select l.buyer_key, l.customer_no, coalesce(d.membership, d.grade) grade, d.checked_at,
           case when d.sms = '수신동의' then true when d.sms = '수신거부' then false end v
      from last_sale l left join dps.customer d on d.customer_no = l.customer_no),
  up as (
    update crm.customer c set dps_customer_no = src.customer_no, dps_grade = coalesce(src.grade, c.dps_grade),
           consent_dps = coalesce(src.v, c.consent_dps),
           consent_dps_at = case when src.v is not null then coalesce(src.checked_at::timestamptz, now()) else c.consent_dps_at end,
           source_channels = (select array_agg(distinct x) from unnest(coalesce(c.source_channels, '{}') || array['dps']) x),
           updated_at = now()
      from src where c.buyer_key = src.buyer_key and c.dps_customer_no is null
    returning 1)
  select count(*) into v_link from up;

  return jsonb_build_object('dps_new', v_new, 'dps_new_consent', v_new_ok, 'dps_linked', v_link);
end $$;
revoke all on function core.f_dps_customer_sync() from public;

create or replace function public.fn_dps_consent_apply()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'public' as $$
declare a jsonb;
begin
  if core.f_role() not in ('admin','uploader') then raise exception 'DPS 적재는 관리자만 가능합니다' using errcode = '42501'; end if;
  a := core.f_dps_customer_sync();
  return core.f_dps_consent_apply() || a;
end $$;
