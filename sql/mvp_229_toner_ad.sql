-- mvp_229 · 2026-10-21 · 토너 자동 발송을 광고로 · 광고 규칙은 수신 동의 또는 6개월 안 거래 고객만
-- "그래 광고로 보내자" — 센드온 API 는 isAd 여도 '(광고)'·080 수신거부를 자동으로 안 붙인다(API 안내: 추후 지원 예정)
--  ① core.sms_config.ad_footer = 센드온 콘솔이 붙이던 080 문구 그대로 → core.f_sms_send 가 광고 발송 끝에 붙인다('(광고) ' 머리말은 원래 붙음)
--  ② crm.sms_template auto_toner is_ad = true
--  ③ fn_auto_rule_preview product_cycle: 규칙 문구가 광고면 수신 동의(consent_marketing) 또는 마지막 소모품 구매가 6개월 안인 고객만
--     (정보통신망법 제50조 — 거래 관계로 받은 연락처는 거래 후 6개월 안 같은 종류 상품 안내만 동의 없이) · 빠진 인원은 ad_blocked
--  MCP execute_sql 은 WHERE 없는 UPDATE 도 60초로 끊긴다 → where id = … 로 보냈다.
update core.sms_config set ad_footer = E'무료거부 0808811293\n인증 5016' where id = (select min(id) from core.sms_config);
update crm.sms_template set is_ad = true, updated_at = now() where code = 'auto_toner';

do $outer$
declare d text;
begin
  d := pg_get_functiondef('public.fn_auto_rule_preview'::regproc);
  if (length(d)-length(replace(d,'v_personal boolean; v_extra jsonb;','')))/length('v_personal boolean; v_extra jsonb;') <> 1 then raise exception 'a 지점'; end if;
  d := replace(d, 'v_personal boolean; v_extra jsonb;', 'v_personal boolean; v_extra jsonb; v_ad boolean;');
  if position('    v_personal := coalesce(r.params->>''cycle_mode'','''') = ''personal'';' in d) = 0 then raise exception 'b 지점'; end if;
  d := replace(d, '    v_personal := coalesce(r.params->>''cycle_mode'','''') = ''personal'';',
                  '    v_personal := coalesce(r.params->>''cycle_mode'','''') = ''personal'';
    v_ad := coalesce((select t.is_ad from crm.sms_template t where t.code = r.template_code), false);');
  if position('(d.pc is not null) cyc_own, d.ref_d + coalesce(d.pc, v_cycle) due_d,' in d) = 0 then raise exception 'c 지점'; end if;
  d := replace(d, '(d.pc is not null) cyc_own, d.ref_d + coalesce(d.pc, v_cycle) due_d,',
                  '(d.pc is not null) cyc_own, d.ref_d + coalesce(d.pc, v_cycle) due_d, (not v_ad or coalesce(cu.consent_marketing,false) or d.ref_d >= (v_today - interval ''6 months'')::date) ad_ok,');
  if position('    select count(*), coalesce((select jsonb_agg(jsonb_build_object(''name'', s.name' in d) = 0 then raise exception 'd 지점'; end if;
  d := replace(d, '    select count(*), coalesce((select jsonb_agg(jsonb_build_object(''name'', s.name',
                  '    select count(*) filter (where ad_ok), coalesce((select jsonb_agg(jsonb_build_object(''name'', s.name');
  if position('from (select * from sel order by due_d, name limit v_lim) s)' in d) = 0 then raise exception 'e 지점'; end if;
  d := replace(d, 'from (select * from sel order by due_d, name limit v_lim) s)', 'from (select * from sel where ad_ok order by due_d, name limit v_lim) s)');
  if position('jsonb_build_object(''backlog'', count(*) filter (where due_d < v_today), ''own_cycle'', count(*) filter (where cyc_own),' in d) = 0 then raise exception 'f 지점'; end if;
  d := replace(d, 'jsonb_build_object(''backlog'', count(*) filter (where due_d < v_today), ''own_cycle'', count(*) filter (where cyc_own),',
                  'jsonb_build_object(''backlog'', count(*) filter (where ad_ok and due_d < v_today), ''own_cycle'', count(*) filter (where ad_ok and cyc_own), ''ad'', v_ad, ''ad_blocked'', count(*) filter (where not ad_ok),');
  execute d;
end $outer$;
