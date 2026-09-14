-- mvp_139 (2026-09-15) 받은 문의 접수 · 담당자 넘기기 (수기 상담 배정)
-- 최지영 프로가 네이버톡으로 받은 문의를 지용현에게 말로만 넘겨 상담에 없던 건.
-- 담당자 화면 [상담 입력] › [문의 접수·넘기기] 가 fn_store_consult_handoff 를 부른다:
--   fn_store_consult_submit(handler=받는 사람, result='진행전') + crm.consult_assign 기록 + 잔디 카드(consult.handoff, 본인이면 안 보냄)
begin;

update core.inq_channel set label = '네이버톡', active = true, sort_no = 61,
       note = '네이버 톡톡·스마트스토어 문의로 직접 온 것 (2026-09-15 켬)'
 where code = 'naver';

insert into core.notify_rule (code, label, event, channel_code, enabled, template, cond, note, sort, connect, color)
values ('consult_handoff', '문의 접수 · 담당자 넘김', 'consult.handoff', 'jandi_crm', true,
        '📨 {by} 프로님이 받은 문의를 {handler} 프로님에게 넘겼습니다 — {name} ({ref})', '{}'::jsonb,
        '담당자 화면 [상담 입력 › 문의 접수·넘기기] 로 넘긴 건. 넘긴 사람 = 받는 사람이면 보내지 않는다', 7,
        '[{"title":"👤 받는 담당자","description":"{handler} 프로님 (넘긴 사람 {by} 프로님)"},{"title":"📦 상담 정보","description":"{detail}"},{"title":"📝 상담 처리","description":"[상담 확인하러가기](https://db.samsungat.co.kr/store)"}]'::jsonb,
        '#0F766E')
on conflict (code) do nothing;

create or replace function public.fn_store_consult_handoff(p_code text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
        v_to text := nullif(btrim(coalesce(p_data->>'to','')),'');
        v_stamp text := to_char(now() at time zone 'Asia/Seoul','MM-DD HH24:MI');
        r jsonb; v_id bigint; v_ch text; v_detail text; v_name text;
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode='42501'; end if;
  if v_to is null then v_to := v_me; end if;
  if not exists (select 1 from core.staff s where s.name = v_to and s.active)
    then raise exception '넘길 담당자를 찾을 수 없습니다: %', v_to; end if;
  v_name := coalesce(nullif(btrim(coalesce(p_data->>'customer_name','')),''), '(이름 없음)');
  r := public.fn_store_consult_submit(p_code, (p_data - 'to') || jsonb_build_object(
         'handler', v_to, 'result', '진행전', 'consult_at', coalesce(nullif(p_data->>'consult_at',''), now()::text),
         'customer_name', v_name,
         'interest_category', coalesce(nullif(p_data->>'interest_category',''), '알 수 없음'),
         'type_code', coalesce(nullif(p_data->>'type_code',''), 'product'),
         'notes', concat_ws(' / ', nullif(p_data->>'notes',''),
                   '문의 접수 '||v_stamp||' '||v_me||' → '||v_to||case when v_to = v_me then ' (본인)' else ' 넘김' end)));
  v_id := (r->>'id')::bigint;
  if v_to <> v_me then
    insert into crm.consult_assign (consult_id, from_handler, to_handler, by_staff, note)
    values (v_id, null, v_to, v_me, '문의 접수 · 넘김');
    select c.label into v_ch from core.inq_channel c where c.code = p_data->>'channel_code';
    v_detail := concat_ws(' · ', v_name, nullif(p_data->>'customer_phone',''), coalesce(v_ch, nullif(p_data->>'channel_code','')),
                          nullif(p_data->>'channel_etc',''), nullif(p_data->>'interest_detail',''), left(nullif(p_data->>'content',''), 140));
    perform core.f_notify('consult.handoff', jsonb_build_object('handler', v_to, 'by', v_me, 'name', v_name,
                                                                'detail', v_detail, 'ref', r->>'ref'));
  end if;
  return r || jsonb_build_object('to', v_to, 'by', v_me, 'notified', v_to <> v_me);
end $$;
revoke all on function public.fn_store_consult_handoff(text, jsonb) from public;
grant execute on function public.fn_store_consult_handoff(text, jsonb) to anon, authenticated, service_role;

commit;
