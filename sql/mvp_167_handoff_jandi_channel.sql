-- mvp_167 (2026-09-21 · v130) — 이미 DB 에 반영됨. 기록용.
-- 담당자 화면 [상담 입력 › 문의 접수·넘기기] 로 문의를 만들어 배정하면 잔디 카드:
--   "📨 문의 접수 · {channel} → {handler} 프로님 배정 · {name} ({phone})" + 배정 담당자 / 문의 채널 / 상담 정보 / 상담 확인하러가기.
-- 본인 배정도 보낸다(전엔 넘길 때만). 일단 테스트 방(jandi_test)으로 — 확인되면 아래 마지막 문장으로 CRM 방으로.

insert into core.notify_channel (code, label, kind, endpoint, enabled, note, sort)
values ('jandi_test', '잔디 · 테스트 방', 'jandi', '<웹훅 주소는 DB 에만 — _secrets.local.md>', true,
        '문의 접수·배정 카드 테스트용 (2026-09-21). 확인되면 consult_handoff 규칙의 채널을 jandi_crm 으로 되돌린다', 15)
on conflict (code) do update set endpoint = excluded.endpoint, enabled = true, note = excluded.note;

update core.notify_rule set
  channel_code = 'jandi_test',
  template = '📨 문의 접수 · {channel} → {handler} 프로님 배정 · {name} ({phone})',
  connect = '[{"title":"👤 배정 담당자","description":"{handler} 프로님{self} · 수동입력(생성자:{by})"},
             {"title":"📣 문의 채널","description":"{channel}"},
             {"title":"📦 상담 정보","description":"{detail}"},
             {"title":"📝 상담 처리","description":"[상담 확인하러가기](https://db.samsungat.co.kr/store)"}]'::jsonb,
  note = '담당자 화면 [상담 입력 › 문의 접수·넘기기] 로 만든 건 — 본인 배정도 보낸다 (mvp_167). 지금은 테스트 방(jandi_test), 확인 뒤 jandi_crm 으로'
where code = 'consult_handoff';

-- fn_store_consult_handoff: 넘길 때만 보내던 f_notify 를 if 밖으로 · 변수 channel(라벨 · 기타)·phone·self 추가 (pg_get_functiondef 치환, 지점 1개 확인)
do $outer$
declare v_def text; v_old text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_store_consult_handoff';
  v_old := $q$  if v_to <> v_me then
    insert into crm.consult_assign (consult_id, from_handler, to_handler, by_staff, note)
    values (v_id, null, v_to, v_me, '문의 접수 · 넘김');
    select c.label into v_ch from core.inq_channel c where c.code = p_data->>'channel_code';
    v_detail := concat_ws(' · ', v_name, nullif(p_data->>'customer_phone',''), coalesce(v_ch, nullif(p_data->>'channel_code','')),
                          nullif(p_data->>'channel_etc',''), nullif(p_data->>'interest_detail',''), left(nullif(p_data->>'content',''), 140));
    perform core.f_notify('consult.handoff', jsonb_build_object('handler', v_to, 'by', v_me, 'name', v_name,
                                                                'detail', v_detail, 'ref', r->>'ref'));
  end if;
  return r || jsonb_build_object('to', v_to, 'by', v_me, 'notified', v_to <> v_me);$q$;
  v_new := $q$  if v_to <> v_me then
    insert into crm.consult_assign (consult_id, from_handler, to_handler, by_staff, note)
    values (v_id, null, v_to, v_me, '문의 접수 · 넘김');
  end if;
  /* 잔디 카드 — 어느 채널의 문의가 누구에게 배정됐는지. 본인 배정도 보낸다 (mvp_167) */
  select c.label into v_ch from core.inq_channel c where c.code = p_data->>'channel_code';
  v_ch := concat_ws(' · ', coalesce(v_ch, nullif(p_data->>'channel_code',''), '채널 미기재'), nullif(p_data->>'channel_etc',''));
  v_detail := concat_ws(' · ', v_name, nullif(p_data->>'customer_phone',''),
                        nullif(p_data->>'interest_category',''), nullif(p_data->>'interest_detail',''), left(nullif(p_data->>'content',''), 140));
  perform core.f_notify('consult.handoff', jsonb_build_object('handler', v_to, 'by', v_me, 'name', v_name,
                          'phone', coalesce(nullif(p_data->>'customer_phone',''), '번호 없음'), 'channel', v_ch,
                          'self', case when v_to = v_me then ' (본인 접수)' else '' end,
                          'detail', v_detail, 'ref', r->>'ref'));
  return r || jsonb_build_object('to', v_to, 'by', v_me, 'notified', true);$q$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'fn_store_consult_handoff 지점 %개', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $outer$;

-- 테스트 카드 1장 (core.f_notify 직접 호출) → notify_log ok · 200 확인 (2026-09-21 06:17 UTC)
-- 확인 뒤 CRM 방으로:  update core.notify_rule set channel_code='jandi_crm' where code='consult_handoff';

-- v131 (2026-09-21): 문의 접수 카드에 관심 품목 칩·상세·관심 모델 — 카드 '상담 정보' 에 관심 모델도 싣는다 (지점 1개 치환)
do $outer$
declare v_def text; v_old text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_store_consult_handoff';
  v_old := $q$nullif(p_data->>'interest_category',''), nullif(p_data->>'interest_detail',''), left(nullif(p_data->>'content',''), 140));$q$;
  v_new := $q$nullif(p_data->>'interest_category',''), nullif(p_data->>'interest_detail',''), nullif(p_data->>'interest_model_code',''), left(nullif(p_data->>'content',''), 140));$q$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception '지점 %개', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $outer$;
