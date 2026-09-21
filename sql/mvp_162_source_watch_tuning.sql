-- mvp_162 · 2026-09-21 · 수집 미도착 알림 5건 정리 (09-21 09:10 잔디)
-- ① 샵링커: 수집기는 하루 5번 정상 동작(Actions 성공 · sl_log DONE fetched 86~168)인데 "2.6일째 안 들어옴".
--    원인 = 샵링커 API 는 발주확인(002)·송장등록(015)·송장전송완료(003)·취소/교환/반품(999) 넷만 받는다(탐색 --flags 로 확인, 001·004~014·016~020 거부).
--    주말엔 아무도 발주확인을 안 하니 금요일 17:43 주문이 마지막이고, 월요일 09:10 알림이 매주 헛도는 구조.
--    → f_source_last('shoplinker') = greatest(마지막 주문 적재, 마지막 성공 수집(sl_log DONE · fetched>0)). '수집기가 돌고 샵링커가 응답했는가'로 본다.
-- ② 이카운트 주문서 현황: "API 로 가져온 걸로 적재" → f_source_last('ec_slip') = greatest(엑셀 업로드, ec.order_queue sent_at). 9/17 전송이 있어 정상.
-- ③ 미입금 주문: "필수 아님, 주기 1주일" → alert=false (화면 데이터 상태엔 남고 잔디 알림에서만 빠짐).
-- ④ 온라인 채널 일매출: how 에 원천 시트 주소 명시(온라인은 시트, 매장은 일 마감). 알림은 그대로(10일).
-- ⑤ 소모품·렌탈 문의: 손대지 않음 — 12.7일은 실제로 문의가 없었을 가능성(GAS 는 살아 있음). 14일로 늘리지 않았다.
do $outer$
declare v_src text; v_args text; v_lang text; v_vol text; v_ret text; a text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid), l.lanname, case p.provolatile when 'i' then 'immutable' when 's' then 'stable' else 'volatile' end, pg_get_function_result(p.oid)
    into v_src, v_args, v_lang, v_vol, v_ret
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname='core' and p.proname='f_source_last';
  a := $a$    when 'ec_slip'         then (select max(uploaded_at) from ec.slip_ref)$a$;
  if (length(v_src)-length(replace(v_src,a,'')))/length(a) <> 1 then raise exception 'ec_slip 지점'; end if;
  v_src := replace(v_src, a, $n$    when 'ec_slip'         then greatest((select max(uploaded_at) from ec.slip_ref), (select max(sent_at) from ec.order_queue where status = 'sent'))   /* 2026-09-21: 주문서는 데이터센터가 API 로 보낸 전표가 원천. 엑셀 업로드는 보조 */$n$);
  a := $a$    when 'shoplinker'      then (select max(created_at) from core.orders where source='shoplinker')$a$;
  if (length(v_src)-length(replace(v_src,a,'')))/length(a) <> 1 then raise exception 'shoplinker 지점'; end if;
  v_src := replace(v_src, a, $n$    when 'shoplinker'      then greatest((select max(created_at) from core.orders where source='shoplinker'),
                                          (select max(ran_at) from core.sl_log where status = 'DONE' and fetched > 0))   /* 2026-09-21: 자동 수집은 '수집기가 돌아서 샵링커가 주문을 돌려줬는가'로 본다. 주말·연휴엔 발주확인이 없어 새 주문이 0이라 월요일 아침마다 헛알림이 났다 */$n$);
  execute format('create or replace function core.f_source_last(%s) returns %s language %s %s as %L', v_args, v_ret, v_lang, v_vol, v_src);
end $outer$;
update core.data_source set
  how = '구글 시트 「온라인 채널 일매출」(docs.google.com/spreadsheets/d/12L7yBInxWC4ChDWT6PmRoRqJGiIviTG2W49_yoW77XA · gid 1654024467)에서 내려받아 관리자 → 데이터 가져오기에 올림. 매장 수기 입력은 여기가 아니라 담당자 화면 일 마감으로 들어온다',
  auto_plan = '시트를 Google Sheets API(GAS 15분 트리거 → fn_channel_daily_upsert) 로 읽어오면 자동 — GAS 한 장이면 된다'
 where key='channel_daily';
update core.data_source set alert = false,
  how = how || ' · 필수 아님 — 결제 안 한 고객 발송이 필요할 때 주 1회 올린다 (2026-09-21 알림에서 제외)'
 where key='unpaid_order';
update core.data_source set
  how = '주문서는 데이터센터가 API 로 보낸 전표(주문서 · 전송 화면)를 원천으로 본다. 이카운트 → 주문서 현황 엑셀 업로드는 중복 전송 차단 보조용',
  auto_plan = '전송 전표는 ec.order_queue(sent) 로 자동 기록. 이카운트에서 직접 넣은 주문서는 조회 API 가 없어 엑셀로만'
 where key='ec_slip';
