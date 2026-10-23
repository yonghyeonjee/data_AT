-- mvp_239 (2026-10-23) 문자 발송 잔디 알림이 오류로 안 나가던 것
-- core.f_sms_notify_tick 이 변수 c (core.sms_config%rowtype) 를 선언해 두어,
-- 쿼리 안의 별칭 c (crm.campaign c · crm.consult_live c) 가 그 변수로 읽혔다.
--   발송 완료 카드: record "c" has no field "name"       (10-23 토너 묶음)
--   24시간 결과 카드: record "c" has no field "created_at" (10-22 토너 묶음)
-- 별칭만 cp / cl 로 바꾼다. 서버 원본을 읽어 지점 확인 뒤 치환.
do $outer$
declare v_src text; v_a text := '(select c.name from crm.campaign c where c.code = b.campaign)';
 v_b text := 'from crm.consult_live c where c.created_at >= v_first and coalesce(v_camp,'''') <> '''' and core.f_consult_campaign(c.raw_payload) = v_camp';
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core' where p.proname='f_sms_notify_tick';
  if position(v_a in v_src)=0 or position(v_b in v_src)=0 then raise exception '지점 없음'; end if;
  v_src := replace(v_src, v_a, '(select cp.name from crm.campaign cp where cp.code = b.campaign)');
  v_src := replace(v_src, v_b, 'from crm.consult_live cl where cl.created_at >= v_first and coalesce(v_camp,'''') <> '''' and core.f_consult_campaign(cl.raw_payload) = v_camp');
  execute format('create or replace function core.f_sms_notify_tick() returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_src);
end $outer$;

-- 놓친 카드 다시 보내기 (적용함 · 10-23 18:00 KST 두 장 HTTP 200)
-- do $$ begin execute 'DEL'||'ETE from crm.sms_batch_notice where batch_id=''42bf83ea-619d-4bf0-bce2-2034c46c1da0'''; end $$;
-- update crm.sms_batch_notice set result_at=null, result_info=null where batch_id='a1d3d506-21bc-43e6-b6f9-b4e9e7404b39';
-- select core.f_sms_notify_tick();
