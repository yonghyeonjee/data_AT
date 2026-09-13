-- mvp_129 · 이어진 상담은 통계에서 한 건 (2026-09-13)
-- 문제 : mvp_128 자동 정리로 '상담완료'가 된 이전 건이 처리현황·관리자 통계(core.f_consult_stats)에 문의 +1 · 완료(구매 없음) +1 로 잡혔다.
--        원본 시트(가전·구독 상담 성과 대시보드)는 문의 1건 = 줄 1개, 상담결과를 제자리에서 바꾸므로 한 고객의 이어진 상담이 한 건이다.
alter table crm.consult add column if not exists superseded_by bigint references crm.consult(id);
comment on column crm.consult.superseded_by is '＋ 새 상담으로 이어져 자동 정리된 이전 건 → 잇는 상담 id. 통계는 이어진 체인을 한 건으로 센다 (mvp_129)';
create index if not exists consult_superseded_by_idx on crm.consult(superseded_by) where superseded_by is not null;
update crm.consult set superseded_by = 154 where id = 149;   -- 최유정 SC260909-000148 → -000153

-- fn_store_consult_submit : 자동 정리 update 에 "superseded_by = v_id" 추가 (pg_get_functiondef 치환, 지점 1)
-- core.f_consult_stats : 첫 CTE 를 아래로 치환 (지점 1). 체인 = superseded_by 로 이어진 줄들.
--   root = 아무도 잇지 않는 줄(처음 문의) → 날짜·채널·유입경로·기간 귀속
--   final = superseded_by 가 null 인 마지막 줄 → 결과(bucket)·구매·상담 방법·담당 필터
--   with recursive chain as (
--     select r.id root_id, r.id cur_id, r.superseded_by nxt, 1 depth from crm.consult r
--      where not exists (select 1 from crm.consult x where x.superseded_by = r.id)
--     union all
--     select c0.root_id, n.id, n.superseded_by, c0.depth + 1 from chain c0 join crm.consult n on n.id = c0.nxt where c0.depth < 20
--   ), lead as (select root_id, cur_id final_id from chain where nxt is null)
--   , c as (select k.id, r.consult_at, k.result, core.f_consult_bucket(k.result) bucket, (k.result='구매완료' or k.linked_order_id is not null) bought,
--             coalesce(ch.label(r.channel_code), core.f_consult_src(r.source, r.inflow_route), '기타') ch, coalesce(k.method, r.method, '미기록') method,
--             coalesce(nullif(btrim(r.inflow_route),''),'(경로 없음)') route, to_char(r.consult_at at time zone 'Asia/Seoul', v_fmt) p
--       from lead l join crm.consult r on r.id=l.root_id join crm.consult k on k.id=l.final_id
--      where r.hidden_at is null and k.hidden_at is null and (p_include_deleted or (r.deleted_at is null and k.deleted_at is null))
--        and (p_handler is null or p_handler='' or k.handler=p_handler) and r.consult_at >= … and r.consult_at < …)
-- fn_store_consult_detail : 'superseded_by' · 'superseded_ref' 추가 → 팝업 [언제·누가] 에 "SC… 으로 이어짐".
-- 검증 : 차효범 2026-09 total 4 → 3. 2026-08 구독 문의 27건(보류 9·완료 11·구매 4) vs 원본 시트 26건(계약 5·실패 19·미처리 2).
