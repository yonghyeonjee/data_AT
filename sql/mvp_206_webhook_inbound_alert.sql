-- mvp_206 (2026-10-13) 홈페이지 웹훅에 바깥 요청이 오면 잔디 '웹훅 확인 방' 으로 알림 (테스트·실패만)
-- "테스트 오면 알림 오게" — 맑음이 &dry=1 로 시험 문의를 보내는 순간 확인하려고.
-- 잔디 웹훅 주소는 DB(core.notify_channel 'jandi_hook')에만 있다. 저장소에 적지 말 것.
--   insert into core.notify_channel (code,label,kind,endpoint,enabled,note,sort)
--   values ('jandi_hook','잔디 · 웹훅 확인 방','jandi','<사용자가 준 잔디 웹훅 주소>',true,'…',40);
-- 규칙 core.notify_rule 'webhook_inbound' (event webhook.inbound · 카드: 읽은 내용 / 받은 항목 이름 / 결과 / 보낸 곳)
-- 트리거: raw.webhook_log 의 ok 가 처음 채워질 때(fn_homepage_hook 의 마지막 update) 한 번
--   · 우리 DB(43.201.156.141)·회사(14.35.57.228) IP 는 알리지 않음
--   · 실제 저장 성공은 CRM 방 문의 카드가 대신하므로 빼고, 테스트(dry)·키 오류·저장 실패만
--   · 알림이 실패해도 웹훅 기록·응답은 그대로 (exception 무시)
create or replace function core.f_webhook_log_alert() returns trigger
language plpgsql security definer set search_path to 'pg_catalog','public' as $f$
declare v_p jsonb := coalesce(new.parsed, '{}'::jsonb); v_det text; v_keys text; v_kind text; v_icon text; v_res text;
begin
  if coalesce(new.ip,'') in ('', '43.201.156.141', '14.35.57.228') then return new; end if;
  if coalesce(new.ok, false) and not coalesce(new.dry, false) then return new; end if;
  select string_agg(l || ': ' || left(v_p->>k, 120), E'\n' order by o) into v_det
    from (values (1,'name','이름'),(2,'phone','연락처'),(3,'kind','구분'),(4,'route','방문경로'),(5,'option','구매옵션'),
                 (6,'apt','아파트명'),(7,'items','희망품목'),(8,'model','모델명'),(9,'method','상담방법'),(10,'attach','첨부'),
                 (11,'memo','문의내용'),(12,'email','이메일'),(13,'ref','글번호'),(14,'received_at','접수일시')) t(o,k,l)
   where coalesce(v_p->>k,'') <> '';
  select string_agg(k, ', ' order by k) into v_keys from jsonb_object_keys(coalesce(new.body,'{}'::jsonb)) k;
  v_kind := case when new.error = 'key' then '키 오류' when coalesce(new.dry,false) and coalesce(new.ok,false) then '테스트 수신'
                 when coalesce(new.ok,false) then '수신' else '실패' end;
  v_icon := case when coalesce(new.ok,false) then '🧪' else '❗' end;
  v_res := case when new.error = 'key' then '키가 틀렸습니다 (403) — 주소의 k= 값 확인'
                when coalesce(new.dry,false) and coalesce(new.ok,false) then '테스트(dry) — 저장·배정·잔디 없음. 항목 확인 뒤 &dry=1 빼고 실제 연결'
                when coalesce(new.ok,false) then '저장됨 #' || coalesce(new.consult_id::text,'')
                else '저장 실패 — ' || coalesce(new.error, new.result->>'reason', '원인 미상') end;
  begin
    perform core.f_notify('webhook.inbound', jsonb_build_object(
      'icon', v_icon, 'kind', v_kind, 'log', new.id::text,
      'detail', coalesce(v_det, '(읽은 항목 없음 — 받은 항목 이름을 보고 이름표를 맞춰야 함)'),
      'keys', coalesce(v_keys, '(본문 없음)'), 'result', v_res,
      'src', coalesce(new.ip,'') || ' · ' || coalesce(new.ctype,'') || case when coalesce(new.ua,'') <> '' then ' · ' || left(new.ua, 80) else '' end));
  exception when others then null;
  end;
  return new;
end $f$;
create trigger trg_webhook_log_alert after update of ok on raw.webhook_log
for each row when (old.ok is null and new.ok is not null) execute function core.f_webhook_log_alert();
-- 확인: 가짜 바깥 IP 줄(raw.webhook_log #17 '0.0.0.0 (연결 확인)')로 카드 1장 발송 → notify_log ok http 200.
--   #17 은 지우려다 MCP 가 60초로 끊겨 남아 있다(해 없음 · SQL 편집기에서 지워도 됨).
