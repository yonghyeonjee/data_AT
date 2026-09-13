-- mvp_114 · 상태 '확인완료' 추가 + 2026-09-01 이전 미완료 일괄 정리 (2026-09-13)
--
-- 8월 이전 '진행전·진행중' 46건은 실제로 처리됐는지 알 수 없다. 그대로 두면 미완료가 너무 많고,
-- 상담완료로 돌리면 성공률 통계가 흐려진다. 그래서 세 번째 상태 '확인완료' 를 만든다.
--   버킷 'closed' — 미완료(open)도 완료(done)도 아니다. 처리현황의 문의 수에는 들어가고 완료·전환에는 안 들어간다.
--   담당자 화면 필터에서는 [전체] 에만 보인다. 회색 칩.
-- 되돌리기: crm.consult_result_backup_20260913 (id, result, notes, updated_at)
--   update crm.consult c set result=b.result, notes=b.notes, updated_at=b.updated_at
--     from crm.consult_result_backup_20260913 b where b.id=c.id;

do $outer$
declare v_src text; v_args text; v_hits int; n int;
begin
  create table if not exists crm.consult_result_backup_20260913 as
    select id, result, notes, updated_at from crm.consult
     where consult_at < '2026-09-01' and result in ('진행전','진행중') and hidden_at is null and deleted_at is null;
  alter table crm.consult drop constraint consult_result_check;
  alter table crm.consult add constraint consult_result_check
    check (result = any (array['진행전','진행중','보류','상담완료','구매완료','거절','종료','확인완료']));
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core' where p.proname='f_consult_bucket';
  /* 원본은 줄바꿈·공백이 섞여 있어 정규식으로 잡는다 (문자열 그대로 찾으면 0개가 나와 롤백된다) */
  select count(*) into v_hits from regexp_matches(v_src, $r$when\s+'거절'\s+then\s+'reject'$r$, 'g');
  if v_hits <> 1 then raise exception 'bucket 치환 지점 %개', v_hits; end if;
  execute format('create or replace function core.f_consult_bucket(%s) returns text language sql immutable as %L',
    v_args, regexp_replace(v_src, $r$(when\s+'거절'\s+then\s+'reject')$r$, $e$\1 when '확인완료' then 'closed'$e$));
  update crm.consult
     set result='확인완료',
         notes = coalesce(nullif(btrim(notes),'')||E'\n','') || '[2026-09-13 일괄] 9월 이전 미완료 정리 → 확인완료 · 실제 처리 여부 미확인 · 이전 상태 '||result,
         updated_at = now()
   where consult_at < '2026-09-01' and result in ('진행전','진행중') and hidden_at is null and deleted_at is null;
  get diagnostics n = row_count; raise notice '확인완료 처리 %건', n;
end $outer$;
