-- mvp_217 · 2026-10-15 · 데이터 가져오기 [미입금 주문 (고도몰)] 카드 가림 (사용자 결정 "일단 이거 가려줘")
-- 화면은 fn_data_status → core.f_data_status_build 가 core.data_source where active 만 주므로 active=false 로 끄면 카드가 빠진다.
-- 적재 함수(fn_unpaid_upsert)·발송 대상 추출의 [결제 안 한 고객] 카드·붙여넣기 종류는 그대로 — 올릴 일이 생기면 active=true.
update core.data_source
   set active=false,
       how='(가림 2026-10-15 · 사용자 결정 — 다시 보이려면 active=true) '||coalesce(how,'')
 where key='unpaid_order' and active;

-- 30분 캐시를 바로 다시 구워 화면에서 즉시 사라지게
with b as (select core.f_data_status_build() v)
update core.rpc_cache c set payload=b.v, built_at=now() from b where c.cache_key='data_status';
