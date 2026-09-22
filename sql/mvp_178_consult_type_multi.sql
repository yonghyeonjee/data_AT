-- mvp_178 · 2026-09-22 · 상담 입력 문의 유형 — 여러 개 선택 · 혼수/입주/이사 + 날짜(결혼 예정일·입주일·이사일 · 희망 배송일) + 증빙 여부
-- 1) core.inq_type : date_label(그 유형이 요구하는 날짜 라벨) · needs_proof. '일시불 문의' 끔, 혼수·입주·이사 추가.
-- 2) crm.consult : type_codes text[] (고른 전부, type_code 는 대표 하나 = 혼수 > 입주 > 이사 > 첫 번째) · event_dates jsonb({wedding:'YYYY-MM-DD',…})
--    · delivery_at date(희망 배송일) · proof_status(가능·불가능·추후) · proof_at date(추후 가능 날짜). 추가 날짜(extra_dates[{label,date}])는 notes 에 글로.
-- 3) crm.consult_scoped 뷰에 새 열 덧붙임 · core.f_inq_type_label(codes, code) · fn_inq_codes types 에 date_label·proof
-- 4) fn_store_consult_submit 검증(유형별 날짜 필수 · 혼수는 희망 배송일 필수 · 셋 중 하나면 증빙 여부 필수 · 추후면 날짜) · fn_store_consult_detail 에 type(여러 개)·events·delivery_at·proof_*
-- 5) 목록 함수(consults_my·consults_all·status)의 문의 유형 라벨 → 여러 개 · core.f_consult_purpose 에 wedding→혼수·신혼, movein/moving→이사·입주
alter table core.inq_type add column if not exists date_label text, add column if not exists needs_proof boolean not null default false;
update core.inq_type set active=false where code='onetime';
insert into core.inq_type(code,label,sort_no,active,date_label,needs_proof) values
  ('wedding','혼수',22,true,'결혼 예정일',true),
  ('movein','입주',24,true,'입주일',true),
  ('moving','이사',26,true,'이사일',true)
on conflict (code) do update set label=excluded.label, sort_no=excluded.sort_no, active=true, date_label=excluded.date_label, needs_proof=excluded.needs_proof;

alter table crm.consult
  add column if not exists type_codes text[],
  add column if not exists event_dates jsonb,
  add column if not exists delivery_at date,
  add column if not exists proof_status text,
  add column if not exists proof_at date;
alter table crm.consult drop constraint if exists consult_proof_check;
alter table crm.consult add constraint consult_proof_check check (proof_status is null or proof_status in ('가능','불가능','추후'));
comment on column crm.consult.type_codes is '문의 유형 여러 개 (core.inq_type.code). type_code 는 대표 하나(혼수>입주>이사>첫째)';
comment on column crm.consult.event_dates is '유형별 날짜 {wedding:결혼 예정일, movein:입주일, moving:이사일}';
comment on column crm.consult.delivery_at is '희망 배송일 (혼수는 필수)';
comment on column crm.consult.proof_status is '혼수·입주·이사 증빙 여부: 가능·불가능·추후(proof_at)';

create or replace view crm.consult_scoped as
 select id, source, source_ref, consult_at, handler, customer_name, phone, buyer_key, inflow_route, interest_category, interest_model_code,
        purchase_item, membership_status, result, expected_amount, expected_purchase_date, linked_order_id, consent_marketing, content, notes,
        raw_payload, created_at, updated_at, callback_at, callback_done_at, hidden_at, hidden_by, hidden_reason, gift_name, gift_amount,
        next_category, next_model_code, next_expected_date, next_note, channel_code, channel_etc, type_code,
        next_model_code is not null or next_category is not null as has_next,
        interest_detail, method, deleted_at, deleted_by, delete_reason,
        type_codes, event_dates, delivery_at, proof_status, proof_at
   from crm.consult k
  where deleted_at is null
    and (hidden_at is null or coalesce(hidden_reason,'') like '테스트%' and core.f_staff_is_dev(current_setting('dc.me', true)))
    and (core.f_staff_sees_b2b(current_setting('dc.me', true)) or not core.f_consult_is_b2b(source, channel_code) or handler = current_setting('dc.me', true));

create or replace function core.f_inq_type_label(p_codes text[], p_code text) returns text
language sql stable as $$
  select string_agg(i.label, ' · ' order by i.sort_no) from core.inq_type i where i.code = any(coalesce(p_codes, array[p_code]))
$$;

do $o$ declare d text; begin
  select pg_get_functiondef(oid) into d from pg_proc where proname='fn_inq_codes';
  if position('jsonb_build_object(''code'',code,''label'',label) order by sort_no), ''[]''::jsonb) from core.inq_type' in d) = 0 then raise exception 'inq_codes 지점 없음'; end if;
  d := replace(d, 'jsonb_build_object(''code'',code,''label'',label) order by sort_no), ''[]''::jsonb) from core.inq_type', 'jsonb_build_object(''code'',code,''label'',label,''date_label'',date_label,''proof'',needs_proof) order by sort_no), ''[]''::jsonb) from core.inq_type');
  execute d;
end $o$;

-- core.f_consult_purpose : 새 유형 코드 → 구독 폼과 같은 묶음 이름 (정의 통째 치환)
do $o$ declare d text; begin
  select pg_get_functiondef(oid) into d from pg_proc where proname='f_consult_purpose';
  if position('case p_type when ''subscribe'' then ''구독''' in d) = 0 then raise exception 'purpose 지점 없음'; end if;
  d := replace(d, 'case p_type when ''subscribe'' then ''구독''', 'case p_type when ''wedding'' then ''혼수·신혼'' when ''movein'' then ''이사·입주'' when ''moving'' then ''이사·입주'' when ''subscribe'' then ''구독''');
  execute d;
end $o$;

-- fn_store_consult_submit : 여러 유형 · 날짜 · 증빙 (원본에서 지점만 치환)
do $o$ declare v text; a text; n int; begin
  select prosrc, pg_get_function_arguments(oid) into v, a from pg_proc where proname='fn_store_consult_submit';
  -- 선언
  if position('v_dig text; v_closed text[];' in v) <> 0 then
    v := replace(v, 'v_dig text; v_closed text[];',
      'v_dig text; v_closed text[];
  v_types text[]; v_type text; v_ev jsonb; v_deliv date; v_proof text; v_proof_at date; v_extra text; v_t record;');
  else raise exception '선언 지점 없음'; end if;
  -- 검증 블록 (고객명 검사 다음)
  if position('if v_name is null then raise exception ''고객명은 필수입니다''; end if;' in v) = 0 then raise exception '검증 지점 없음'; end if;
  v := replace(v, 'if v_name is null then raise exception ''고객명은 필수입니다''; end if;',
    'if v_name is null then raise exception ''고객명은 필수입니다''; end if;
  /* 문의 유형 — 여러 개 (mvp_178). type_code 는 대표 하나: 혼수 > 입주 > 이사 > 첫째 */
  select array_agg(distinct x) into v_types from jsonb_array_elements_text(case when jsonb_typeof(p_data->''type_codes'')=''array'' then p_data->''type_codes'' else ''[]''::jsonb end) x where btrim(x) <> '''';
  if v_types is null or cardinality(v_types) = 0 then v_types := array[coalesce(nullif(p_data->>''type_code'',''''),''product'')]; end if;
  if exists (select 1 from unnest(v_types) t where not exists (select 1 from core.inq_type i where i.code = t)) then raise exception ''알 수 없는 문의 유형입니다''; end if;
  v_type := case when ''wedding'' = any(v_types) then ''wedding'' when ''movein'' = any(v_types) then ''movein'' when ''moving'' = any(v_types) then ''moving'' else v_types[1] end;
  v_ev := case when jsonb_typeof(p_data->''event_dates'')=''object'' then p_data->''event_dates'' else ''{}''::jsonb end;
  select coalesce(jsonb_object_agg(e.key, e.value), ''{}''::jsonb) into v_ev from jsonb_each_text(v_ev) e where e.key = any(v_types) and btrim(e.value) <> '''';
  v_deliv := nullif(p_data->>''delivery_at'','''')::date;
  v_proof := nullif(p_data->>''proof_status'','''');
  v_proof_at := nullif(p_data->>''proof_at'','''')::date;
  for v_t in select i.code, i.label, i.date_label from core.inq_type i where i.code = any(v_types) and i.date_label is not null loop
    if nullif(v_ev->>v_t.code,'''') is null then raise exception ''%(%)을 입력하세요'', v_t.date_label, v_t.label; end if;
    perform (v_ev->>v_t.code)::date;
  end loop;
  if exists (select 1 from core.inq_type i where i.code = any(v_types) and i.needs_proof) then
    if v_proof is null then raise exception ''증빙 여부(가능·불가능·추후 가능)를 고르세요''; end if;
    if v_proof not in (''가능'',''불가능'',''추후'') then raise exception ''알 수 없는 증빙 여부: %'', v_proof; end if;
    if v_proof = ''추후'' and v_proof_at is null then raise exception ''추후 가능이면 증빙 가능 날짜를 입력하세요''; end if;
    if v_proof <> ''추후'' then v_proof_at := null; end if;
    if ''wedding'' = any(v_types) and v_deliv is null then raise exception ''혼수는 희망 배송일이 필수입니다''; end if;
  else v_proof := null; v_proof_at := null; end if;
  if v_ev = ''{}''::jsonb then v_ev := null; end if;
  if jsonb_typeof(p_data->''extra_dates'')=''array'' then
    select string_agg(btrim(e->>''label'')||'' ''||(e->>''date''), '' · '') into v_extra
      from jsonb_array_elements(p_data->''extra_dates'') e where nullif(btrim(e->>''label''),'''') is not null and nullif(e->>''date'','''') is not null;
  end if;');
  -- insert 열 · 값
  if position('channel_code, channel_etc, type_code, method)' in v) = 0 then raise exception 'insert 열 지점 없음'; end if;
  v := replace(v, 'channel_code, channel_etc, type_code, method)', 'channel_code, channel_etc, type_code, method, type_codes, event_dates, delivery_at, proof_status, proof_at)');
  if position('coalesce(nullif(p_data->>''type_code'',''''),''product''),
    case when p_data->>''method'' in (''대면'',''전화'',''메시지'') then p_data->>''method'' end)' in v) = 0 then raise exception 'values 지점 없음'; end if;
  v := replace(v, 'coalesce(nullif(p_data->>''type_code'',''''),''product''),
    case when p_data->>''method'' in (''대면'',''전화'',''메시지'') then p_data->>''method'' end)',
    'v_type,
    case when p_data->>''method'' in (''대면'',''전화'',''메시지'') then p_data->>''method'' end,
    v_types, v_ev, v_deliv, v_proof, v_proof_at)');
  -- 추가 날짜 → notes
  n := (length(v) - length(replace(v, 'nullif(p_data->>''notes'',''''), v_cb', ''))) / length('nullif(p_data->>''notes'',''''), v_cb');
  if n <> 1 then raise exception 'notes 지점 %개', n; end if;
  v := replace(v, 'nullif(p_data->>''notes'',''''), v_cb', 'nullif(concat_ws('' / '', nullif(p_data->>''notes'',''''), case when v_extra is not null then ''추가 날짜 · ''||v_extra end),''''), v_cb');
  execute format('create or replace function public.fn_store_consult_submit(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', a, v);
end $o$;

-- fn_store_consult_detail : type(여러 개) · type_codes · events · delivery_at · proof
--   jsonb_build_object 는 인자 100개 한계라(원래 90개 남짓) 새 키는 `|| jsonb_build_object(...)` 로 뒤에 붙인다 (처음 안에 넣었다가 54023 로 막혔다)
do $o$ declare v text; a text; n int; begin
  select prosrc, pg_get_function_arguments(oid) into v, a from pg_proc where proname='fn_store_consult_detail';
  if position('''type'', (select ty.label from core.inq_type ty where ty.code = k.type_code), ''method'', k.method,' in v) = 0 then raise exception 'detail 지점 없음'; end if;
  v := replace(v, '''type'', (select ty.label from core.inq_type ty where ty.code = k.type_code), ''method'', k.method,', '''type'', core.f_inq_type_label(k.type_codes, k.type_code), ''method'', k.method,');
  n := (length(v) - length(replace(v, '= v_dig))));', ''))) / length('= v_dig))));');
  if n <> 1 then raise exception '꼬리 지점 %개', n; end if;
  v := replace(v, '= v_dig))));', '= v_dig))))
  || jsonb_build_object(''type_codes'', coalesce(k.type_codes, array[k.type_code]),
    ''events'', (select coalesce(jsonb_agg(jsonb_build_object(''code'', i.code, ''label'', i.label, ''date_label'', i.date_label, ''date'', k.event_dates->>i.code) order by i.sort_no), ''[]''::jsonb)
                  from core.inq_type i where i.code = any(coalesce(k.type_codes, array[k.type_code])) and i.date_label is not null),
    ''delivery_at'', k.delivery_at, ''proof_status'', k.proof_status, ''proof_at'', k.proof_at);');
  execute format('create or replace function public.fn_store_consult_detail(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', a, v);
end $o$;

-- 목록 3개 : 문의 유형 라벨 → 여러 개 (함수 정의 통째 치환 — 시그니처·속성 그대로)
do $o$ declare r record; d text; n int; begin
  for r in select p.oid, p.proname from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname in ('fn_store_consults_my','fn_store_consults_all','fn_store_status') loop
    d := pg_get_functiondef(r.oid);
    n := (length(d) - length(replace(d, '(select ty.label from core.inq_type ty where ty.code = k.type_code)', ''))) / length('(select ty.label from core.inq_type ty where ty.code = k.type_code)');
    if n = 0 then raise exception '% 라벨 지점 없음', r.proname; end if;
    d := replace(d, '(select ty.label from core.inq_type ty where ty.code = k.type_code)', 'core.f_inq_type_label(k.type_codes, k.type_code)');
    execute d;
  end loop;
end $o$;


-- 롤백 확인 (do 블록 끝에 raise 로 되돌림): 혼수 날짜 없음 → '결혼 예정일(혼수)을 입력하세요' · 배송일 없음 → '혼수는 희망 배송일이 필수입니다' · 이사 증빙 없음 → '증빙 여부…' · 추후 날짜 없음 → 오류
--   상품+혼수+입주 저장 → type_code=wedding · type_codes {movein,product,wedding} · event_dates 두 개(고르지 않은 moving 은 버림) · notes '추가 날짜 · 예식장 계약일 2026-09-30'(이름 없는 줄은 버림)
--   옛 방식 type_code 하나 → type_codes {subscribe} · purpose(wedding)=혼수·신혼 · consults_my src2 '상품 문의 · 혼수 · 입주'
