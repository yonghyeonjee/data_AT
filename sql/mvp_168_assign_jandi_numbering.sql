-- mvp_168 (2026-09-21 · v132) — 이미 DB 에 반영됨. 기록용.
-- ① 배정·담당 변경(fn_store_consult_assign: 배정 탭 [배정]/[담당 바꾸기] · 내 상담 [넘기기])도 잔디 카드
-- ② 모든 상담 카드에 상담 번호(#id) — 새 문의(🌐 홈페이지 · 📋 구독) / 📨 수동 접수 / 📌 배정 · 🔁 담당 변경 이 서로 헷갈리지 않게
-- ③ 6건 넘게 한 번에 옮기면 요약 카드 한 장

insert into core.notify_rule (code, label, event, channel_code, enabled, template, cond, note, sort, connect, color)
values ('consult_assign', '상담 배정 · 담당 변경', 'consult.assign', 'jandi_test', true,
  '{icon} {kind} {no} · {from} → {handler} 프로님 · {name} ({phone})', '{}'::jsonb,
  '담당자 화면 배정 탭 [배정]/[담당 바꾸기] · 내 상담 [넘기기] (fn_store_consult_assign). 이미 있던 문의를 옮기는 것이라 새 문의 카드와 색·머리말이 다르다. 6건 넘게 한 번에 옮기면 요약 카드 한 장 (mvp_168). 지금은 테스트 방, 확인 뒤 jandi_crm 으로',
  8,
  '[{"title":"👤 담당","description":"{from} → {handler} 프로님 · 바꾼 사람 {by}{note}"},
    {"title":"📣 문의","description":"{channel} · 처음 접수 {at} · 상태 {status}"},
    {"title":"📦 상담 정보","description":"{detail}"},
    {"title":"📝 상담 처리","description":"[상담 확인하러가기](https://db.samsungat.co.kr/store)"}]'::jsonb,
  '#8A5D00')
on conflict (code) do update set label=excluded.label, event=excluded.event, channel_code=excluded.channel_code, enabled=true,
  template=excluded.template, note=excluded.note, sort=excluded.sort, connect=excluded.connect, color=excluded.color;

update core.notify_rule set template = '🌐 홈페이지 문의 #{id} · {name} ({phone})' where code='inquiry_homepage';
update core.notify_rule set template = '📋 구독 문의 #{id} · {name} ({phone})' where code='inquiry_subscription';
update core.notify_rule set template = '📨 수동 접수 #{id} · {channel} → {handler} 프로님 · {name} ({phone})' where code='consult_handoff';

-- fn_inquiry_mail_ingest · fn_submit_inquiry · fn_store_consult_handoff: f_notify 변수에 'id', v_id 추가 (각 지점 1개 치환)
-- fn_store_consult_assign: declare 에 cc record · v_many(6건 초과) · v_list · v_notified · v_note,
--   loop 안 v_n := v_n + 1 뒤에 상담 조회 + f_notify('consult.assign', {id,no:'#'||id,icon,kind(배정|담당 변경),from(이전|미배정),handler,by,note,name,phone,channel,at(처음 접수),status,detail}),
--   v_many 면 loop 뒤 요약 카드 1장(no = 'N건', detail = 줄마다 '#id 이름 · 채널 · 이전 담당'), 반환에 notified.
--   loop 의 alias c → k (record 변수 c 와 충돌해 55000 "record c is not assigned yet" 이 났다).
-- 확인: 롤백 트랜잭션 안에서 테스트 상담(#392 홍길동)을 담당 변경·미배정→배정·7건 일괄로 옮겨 카드 3장 200 (DB 는 롤백, HTTP 는 나감).
-- 주의: execute_sql 한 번의 호출은 한 트랜잭션 — 끝에 rollback 을 쓰면 앞의 do 블록(함수 패치)까지 같이 되돌아간다. 패치와 롤백 테스트는 호출을 나눌 것.
-- 확인 뒤 CRM 방으로:  update core.notify_rule set channel_code='jandi_crm' where code in ('consult_assign','consult_handoff');
