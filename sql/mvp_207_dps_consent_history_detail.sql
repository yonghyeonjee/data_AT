-- mvp_207 · DPS 수신거부 재확인 이력을 화면에서 (2026-10-13 · 적용: Supabase migrations dps_consent_apply_prev_date, journey_consent_evidence)
-- 1) core.f_dps_consent_apply: consent_history.evidence 에 이전 확인일·이전 값·발송 동의 처리를 함께 남긴다.
--    DPS 는 고객이 수신거부한 날짜를 주지 않는다 → '이전 확인 YYYY-MM-DD 수신동의 → 그 사이에 바뀜'.
--    changed_at 은 이번 확인일(dps.customer.checked_at).
-- 2) core.f_customer_journey: '수신 동의 / 철회' 줄의 s(작은 글씨)에 재확인 근거를 보인다(관리자·담당자 고객 흐름 공통 cjHtml).
-- 3) 2026-10-13 16:29 업로드로 먼저 쌓인 14줄은 같은 고객의 앞선 'dps' 이력으로 이전 확인일을 채워 넣었다(일회성 UPDATE).
--    결과: 원장 고객 14명 DPS 동의 꺼짐 · 그중 발송 동의 출처가 DPS 인 11명 발송 동의 꺼짐 · 3명은 store·P몰·시흥몰 동의 유지.

create or replace function core.f_dps_consent_apply()
returns jsonb language plpgsql set search_path to 'pg_catalog', 'public' as $$
declare v_changed int := 0; v_refused int := 0; v_agreed int := 0; v_mk_off int := 0; v_mk_on int := 0;
begin
  create temp table if not exists _dps_consent_ch (id bigint, buyer_key char(16), v boolean, at timestamptz, sms text, txt text, checked date, src text, prev_at timestamptz, prev boolean) on commit drop;
  truncate _dps_consent_ch;
  insert into _dps_consent_ch
  select c.id, c.buyer_key, d.sms = '수신동의', coalesce(d.checked_at::timestamptz, now()), d.sms, d.consent_text, d.checked_at, c.consent_source, c.consent_dps_at, c.consent_dps
    from crm.customer c join dps.customer d on d.customer_no = c.dps_customer_no
   where d.sms in ('수신동의', '수신거부') and c.consent_dps is distinct from (d.sms = '수신동의');
  get diagnostics v_changed = row_count;
  if v_changed = 0 then return jsonb_build_object('changed', 0, 'refused', 0, 'agreed', 0, 'marketing_off', 0, 'marketing_on', 0); end if;
  update crm.customer c set consent_dps = ch.v, consent_dps_at = ch.at, updated_at = now() from _dps_consent_ch ch where c.id = ch.id;
  select count(*) filter (where not v), count(*) filter (where v) into v_refused, v_agreed from _dps_consent_ch;
  update crm.customer c set consent_marketing = ch.v, consent_updated_at = ch.at
    from _dps_consent_ch ch where c.id = ch.id and c.consent_source = 'dps' and c.consent_marketing is distinct from ch.v;
  select count(*) filter (where not ch.v), count(*) filter (where ch.v) into v_mk_off, v_mk_on from _dps_consent_ch ch where ch.src = 'dps';
  insert into crm.consent_history (buyer_key, consent, changed_at, source, evidence)
  select ch.buyer_key, ch.v, ch.at, 'dps',
         'DPS 수신동의 재확인 · SMS ' || ch.sms || ' · ' || coalesce(ch.txt, '') || ' · 조회 ' || coalesce(ch.checked::text, '')
         || case when ch.prev is not null and ch.prev_at is not null
                 then ' · 이전 확인 ' || to_char(ch.prev_at at time zone 'Asia/Seoul', 'YYYY-MM-DD') || ' ' || case when ch.prev then '수신동의' else '수신거부' end
                      || ' → 그 사이에 바뀜' else '' end
         || case when ch.src = 'dps' then ' · 발송 동의도 ' || case when ch.v then '켬' else '끔' end
                 else ' · 발송 동의는 ' || coalesce(ch.src, '-') || ' 기준 유지' end
    from _dps_consent_ch ch;
  return jsonb_build_object('changed', v_changed, 'refused', v_refused, 'agreed', v_agreed, 'marketing_off', v_mk_off, 'marketing_on', v_mk_on);
end $$;
revoke all on function core.f_dps_consent_apply() from public;

-- 고객 흐름: 서버 본문에서 consent 줄 하나만 바꾼다(본문 전체는 mvp_198).
do $mig$
declare
  d text := pg_get_functiondef('core.f_customer_journey(text,bigint,boolean)'::regprocedure);
  old text := $o$select h.changed_at, 'consent', case when h.consent then '수신 동의' else '수신 동의 철회' end, h.source, null, null,$o$;
  new text := $n$select h.changed_at, 'consent', case when h.consent then '수신 동의' else '수신 동의 철회' end,
           case when h.evidence like 'DPS 수신동의 재확인%' then 'DPS 재확인 · ' || substr(h.evidence, length('DPS 수신동의 재확인 · ') + 1) else h.source end, null, null,$n$;
begin
  if (length(d) - length(replace(d, old, ''))) / length(old) <> 1 then raise exception 'consent 줄을 정확히 하나 찾지 못했습니다'; end if;
  execute replace(d, old, new);
end $mig$;
