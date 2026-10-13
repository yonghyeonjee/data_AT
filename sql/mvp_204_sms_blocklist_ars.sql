-- mvp_204 · 센드온 수신거부 받아오기 고침 — 100개 상한 · 080(ARS) 목록 · 이어 받기 (2026-10-13 · v191)
-- 사건: [센드온 수신거부 받아오기] → "최소 1개 이상, 최대 100개 이하로 조회해주세요". 허용 IP(43.201.156.141) 등록 뒤 처음 닿은 호출이었다.
--   ① limit=200 → 센드온 상한 100. ② 기본 경로가 /v2/contacts/blocklist/unified 인데 비어 있고(totalCount 0),
--      실제 080 수신거부(blockType ARS)는 /v2/contacts/blocklist 에 있었다(8건 · 2026-09-18 ~ 10-12).
--   cursor 는 오프셋(0,2,4…) · 끝이면 null. 목록은 최신순.
-- 고침(fn_sms_blocklist_pull · 서버 원본 치환): 두 경로를 차례로 다 받는다(p_unified 는 무시 — 화면은 그대로 true 를 보낸다) ·
--   limit 100 · 한 번에 5초·50쪽(약 5,000개)까지 · 다 못 받으면 멈춘 곳(경로|cursor)을 core.sms_config.blocklist_resume 에 두고
--   다음 호출이 거기서 이어 받는다(core.app_setting 은 대시보드 dirty 트리거가 걸려 있어 쓰지 않는다) · totalCount 는 두 경로 중 큰 값.
-- 연결 확인(fn_sms_check) 첫 성공: 포인트 135,549.99 · 단가 SMS 7.4 · LMS 24.5 · MMS 59.2 · 발신번호 0221093500(대표·ACTIVE)·휴대폰 1개.
-- 받아오기: 8건 · 새 번호 8 · 고객 찾음 8 · 수신동의 끔 8 (raw.upload 864 — 데이터 가져오기 › 적재 기록에서 되돌리기).
-- 이어 받기 확인(롤백 실험): resume '/v2/contacts/blocklist|4' → 4건 받고 unified 0 → resume 비움.

alter table core.sms_config add column if not exists blocklist_resume text;

do $outer$
declare v_def text; i int; n int;
  olds text[] := array[
    $o$'?limit=200&cursor=' || v_cursor$o$,
    $o$v_t timestamptz := clock_timestamp();$o$,
    $o$v_path := case when coalesce(p_unified, true) then '/v2/contacts/blocklist/unified' else '/v2/contacts/blocklist' end;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '5000');
  loop$o$,
    $o$v_total := coalesce(nullif(v_json#>>'{data,totalCount}','')::int, v_total);$o$,
    $o$exit when jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0;$o$,
    $o$exit when v_cursor is null or v_page >= 40 or clock_timestamp() - v_t > interval '6 seconds';
  end loop;
  perform extensions.http_reset_curlopt();$o$ ];
  news text[] := array[
    $n$'?limit=100&cursor=' || v_cursor$n$,
    $n$v_t timestamptz := clock_timestamp(); v_resume text;$n$,
    $n$/* 080 수신거부(ARS)는 /blocklist · 통합은 /unified → 둘 다. 멈춘 곳(경로|cursor)부터 이어 받기 */
  v_resume := coalesce(c.blocklist_resume, '');
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '5000');
  foreach v_path in array array['/v2/contacts/blocklist', '/v2/contacts/blocklist/unified'] loop
  if v_resume <> '' then
    if split_part(v_resume, '|', 1) <> v_path then continue; end if;
    v_cursor := coalesce(nullif(split_part(v_resume, '|', 2), ''), '0'); v_resume := '';
  else v_cursor := '0'; end if;
  loop$n$,
    $n$v_total := greatest(coalesce(v_total, 0), coalesce(nullif(v_json#>>'{data,totalCount}','')::int, 0));$n$,
    $n$if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then v_cursor := null; exit; end if;$n$,
    $n$exit when v_cursor is null or v_page >= 50 or clock_timestamp() - v_t > interval '5 seconds';
  end loop;
  exit when v_code <> 200 or v_cursor is not null;
  end loop;
  perform extensions.http_reset_curlopt();
  if v_code = 200 then
    update core.sms_config set blocklist_resume = case when v_cursor is not null then v_path || '|' || v_cursor end where id = 1;
  end if;$n$ ];
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='fn_sms_blocklist_pull';
  for i in 1..array_length(olds,1) loop
    n := (length(v_def) - length(replace(v_def, olds[i], ''))) / length(olds[i]);
    if n <> 1 then raise exception '지점 % 가 %개', i, n; end if;
    v_def := replace(v_def, olds[i], news[i]);
  end loop;
  execute v_def;
end $outer$;
-- (실제 적용은 세 번에 나눠 했다: limit·쪽 수 → 경로·이어 받기 → totalCount. 위 블록은 한 번에 같은 결과)
