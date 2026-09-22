-- mvp_179 · 2026-09-22 · 구독 폼 문의가 들어올 때 고객이 고른 것(구매 목적)으로 문의 유형을 자동 선택
-- core.f_inq_types_from_form(raw_payload) : 늘 subscribe + 혼수·신혼 → wedding + 이사·입주 → moving (pageUrl evt=movein|newhome 면 movein)
-- core.f_inq_type_main(codes) : 대표 유형(혼수 > 입주 > 이사 > 첫째). fn_submit_inquiry 가 type_code·type_codes 에 넣고,
-- 시트 수정 재전송(on conflict)은 이미 있는 type_codes 를 덮지 않는다. 옛 web_subscription 65건 backfill (subscribe 43 · +moving 17 · +wedding 5). 구매 목적(f_consult_purpose)은 폼 값이 우선이라 그대로.
-- 화면: 담당자 화면 csLoadFromConsult(＋ 새 상담) 가 detail 의 type_codes·events·delivery_at·proof 를 폼에 미리 채운다.
create or replace function core.f_inq_types_from_form(p jsonb) returns text[] language sql immutable as $$
  select array_remove(array[
    'subscribe',
    case when p->>'purchasePurpose' = '혼수·신혼' then 'wedding' end,
    case when p->>'purchasePurpose' = '이사·입주' then case when coalesce(p->>'pageUrl','') ~ 'evt=(movein|newhome)' then 'movein' else 'moving' end end
  ], null)
$$;
create or replace function core.f_inq_type_main(p_codes text[]) returns text language sql immutable as $$
  select case when 'wedding' = any(p_codes) then 'wedding' when 'movein' = any(p_codes) then 'movein' when 'moving' = any(p_codes) then 'moving' else p_codes[1] end
$$;
do $o$ declare v text; a text; begin
  select prosrc, pg_get_function_arguments(oid) into v, a from pg_proc where proname='fn_submit_inquiry';
  if position('raw_payload, channel_code, type_code)
  values (''web_subscription''' in v) = 0 then raise exception '열 지점 없음'; end if;
  v := replace(v, 'raw_payload, channel_code, type_code)
  values (''web_subscription''', 'raw_payload, channel_code, type_code, type_codes)
  values (''web_subscription''');
  if position('    case when coalesce(p_data->>''inquiryType'','''') = ''구독'' then ''subscribe'' else ''product'' end)
  on conflict' in v) = 0 then raise exception '값 지점 없음'; end if;
  v := replace(v, '    case when coalesce(p_data->>''inquiryType'','''') = ''구독'' then ''subscribe'' else ''product'' end)
  on conflict', '    core.f_inq_type_main(core.f_inq_types_from_form(p_data)), core.f_inq_types_from_form(p_data))
  on conflict');
  if position('raw_payload = excluded.raw_payload, updated_at = now()' in v) = 0 then raise exception 'update 지점 없음'; end if;
  v := replace(v, 'raw_payload = excluded.raw_payload, updated_at = now()', 'raw_payload = excluded.raw_payload, updated_at = now(),
    type_codes = coalesce(crm.consult.type_codes, excluded.type_codes),
    type_code = case when crm.consult.type_codes is null then excluded.type_code else crm.consult.type_code end');
  execute format('create or replace function public.fn_submit_inquiry(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', a, v);
end $o$;
update crm.consult set type_codes = core.f_inq_types_from_form(raw_payload), type_code = core.f_inq_type_main(core.f_inq_types_from_form(raw_payload))
 where source='web_subscription' and type_codes is null;
-- 롤백 확인(트랜잭션 안에서 gas_forward 해시를 임시 값으로 바꿔 호출, raise 로 되돌림): 혼수·신혼 → subscribe+wedding/wedding · 이사·입주+evt=movein → subscribe+movein · 신규구독 → subscribe
--   같은 ref 재전송은 손으로 바꾼 type_codes(subscribe+wedding+movein)를 유지하면서 result 만 갱신. 키 해시·테스트 줄 모두 안 남음.
