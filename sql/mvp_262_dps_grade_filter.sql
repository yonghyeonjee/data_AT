-- mvp_262 · DPS 멤버십 등급으로 고객 고르기 (2026-11-02)
-- crm.customer.dps_grade (DPS 수집기가 넣는 삼성 멤버십 등급: 일반·스타·로열블루·프레스티지·단골직전·단골)
--   · fn_customer_list (관리자 › 고객 통합 › 고객 목록)  p_grade 추가 · 줄에 'grade'
--   · fn_crm_targets_v2 (발송 대상 추출)               p_grade 추가 · 줄에 'grade'
--   · fn_crm_segment_run · core.f_auto_rule_ext        저장 조건의 grade 를 넘김 (자동 발송 세그먼트도 같은 수)
-- p_grade = 쉼표로 여러 등급 ('로열블루,프레스티지' = 로열블루 이상) · 비우면 거르지 않음
-- 함수 본문은 지금 DB 의 정의를 고쳐 다시 만든다 (본문 중복을 피하려고). 바꿀 자리를 못 찾으면 멈춘다.
do $mig$
declare d text; o text;
begin
  -- 1) fn_customer_list
  d := pg_get_functiondef('public.fn_customer_list(text,text,text,text,text,integer,integer,boolean)'::regprocedure); o := d;
  d := replace(d, 'p_unmask boolean DEFAULT false)', 'p_unmask boolean DEFAULT false, p_grade text DEFAULT NULL::text)');
  d := replace(d, 'c.source_channels, c.first_seen_at, c.last_seen_at,', 'c.source_channels, c.first_seen_at, c.last_seen_at, c.dps_grade,');
  d := replace(d, '       and (p_consent is null', '       and (coalesce(p_grade,'''') = '''' or dps_grade = any(string_to_array(replace(p_grade,'' '',''''), '','')))' || chr(10) || '       and (p_consent is null');
  d := replace(d, '''biz'', account_type = ''business'', ''consent'', consent_marketing,', '''biz'', account_type = ''business'', ''consent'', consent_marketing, ''grade'', dps_grade,');
  if position('p_grade text' in d) = 0 or position('c.last_seen_at, c.dps_grade' in d) = 0 or position('''grade'', dps_grade' in d) = 0 or position('any(string_to_array' in d) = 0 then
    raise exception 'fn_customer_list: 바꿀 자리를 못 찾음'; end if;
  drop function public.fn_customer_list(text,text,text,text,text,integer,integer,boolean);
  execute d;
  revoke all on function public.fn_customer_list(text,text,text,text,text,integer,integer,boolean,text) from public, anon;
  grant execute on function public.fn_customer_list(text,text,text,text,text,integer,integer,boolean,text) to authenticated, service_role;

  -- 2) fn_crm_targets_v2
  d := pg_get_functiondef('public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,integer,numeric,integer,boolean,integer,text,integer,integer,boolean,boolean,text,text,date,integer,integer)'::regprocedure); o := d;
  d := replace(d, 'p_due_hi integer DEFAULT NULL::integer)', 'p_due_hi integer DEFAULT NULL::integer, p_grade text DEFAULT NULL::text)');
  d := replace(d, 'c.account_type, c.source_channels, c.first_seen_at,', 'c.account_type, c.source_channels, c.first_seen_at, c.dps_grade,');
  d := replace(d, '    and (p_kind is null or p_kind = '''' or c.account_type = p_kind)', '    and (p_kind is null or p_kind = '''' or c.account_type = p_kind)' || chr(10) || '    and (coalesce(p_grade,'''') = '''' or c.dps_grade = any(string_to_array(replace(p_grade,'' '',''''), '','')))');
  d := replace(d, '''region'', region, ''biz'', account_type=''business'',', '''region'', region, ''biz'', account_type=''business'', ''grade'', dps_grade,');
  if position('p_grade text' in d) = 0 or position('c.dps_grade = any' in d) = 0 or position('''grade'', dps_grade' in d) = 0 or position('c.first_seen_at, c.dps_grade' in d) = 0 then
    raise exception 'fn_crm_targets_v2: 바꿀 자리를 못 찾음'; end if;
  drop function public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,integer,numeric,integer,boolean,integer,text,integer,integer,boolean,boolean,text,text,date,integer,integer);
  execute d;
  revoke all on function public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,integer,numeric,integer,boolean,integer,text,integer,integer,boolean,boolean,text,text,date,integer,integer,text) from public, anon;
  grant execute on function public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,integer,numeric,integer,boolean,integer,text,integer,integer,boolean,boolean,text,text,date,integer,integer,text) to authenticated, service_role;

  -- 3) 저장 조건 실행 · 자동 발송 세그먼트 → grade 도 넘김
  d := pg_get_functiondef('public.fn_crm_segment_run(text,text,integer,integer,boolean,boolean,jsonb)'::regprocedure); o := d;
  d := replace(d, 'p_kind          => nullif(pm->>''kind'',''''),', 'p_kind          => nullif(pm->>''kind'',''''), p_grade => nullif(pm->>''grade'',''''),');
  if d = o then raise exception 'fn_crm_segment_run: 바꿀 자리를 못 찾음'; end if;
  execute d;
  d := pg_get_functiondef('core.f_auto_rule_ext(text,integer,boolean)'::regprocedure); o := d;
  d := replace(d, 'p_kind => nullif(sp->>''kind'',''''),', 'p_kind => nullif(sp->>''kind'',''''), p_grade => nullif(sp->>''grade'',''''),');
  if d = o then raise exception 'f_auto_rule_ext: 바꿀 자리를 못 찾음'; end if;
  execute d;
end $mig$;
notify pgrst, 'reload schema';
