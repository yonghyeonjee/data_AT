-- mvp_134 · 2026-09-14 — 구독 문의 배정을 데이터센터가 한다 (홈페이지 문의와 같은 순번표)
-- fn_submit_inquiry:
--   · assignedStaff 가 비면 트리거 core.f_consult_assign_default → core.f_assign_next('구독·렌탈' → 풀 없으면 'default') 가 배정.
--     홈페이지 문의(fn_inquiry_mail_ingest)도 f_assign_next('default') 를 쓰므로 두 채널이 한 순번표를 번갈아 쓴다. 휴가자는 f_staff_on_leave 로 건너뜀.
--   · 새 접수인데 GAS 가 담당자를 보냈고 그 사람이 휴가면 다시 배정 (기존 건의 시트 수정은 그대로 — 순번표를 안 돌린다).
--   · 시트 수정(onMgmtEdit)으로 온 담당자는 다시 DB 를 덮는다 (mvp_132 의 'DB 우선' 되돌림 — GAS v15 가 시트 H열에 DB 값을 적으므로 어긋나지 않는다).
--   · returning 에서 실제 handler 를 받아 응답 'handler' 와 접수 카드에 쓴다.
-- GAS: tools/gas/inquiry_forward.gs v15 (dcAssignInquiry_). 적용은 위 do 블록 (지점 4곳 치환).
do $outer$
declare v_src text; v_args text; v_n int;
  a1 text := $q$  /* 폼(GAS)이 고른 담당자가 휴가면 데이터센터가 다시 배정한다 (매장휴무·15시 지난 반차는 휴가로 안 봄) */
  if v_hand is not null and core.f_staff_on_leave(v_hand) then
    v_orig := v_hand;
    v_hand := core.f_assign_next('구독·렌탈', nullif(p_data->>'modelName',''));
  end if;$q$;
  b1 text := $q$$q$;
  a2 text := $q$v_ref := to_char(v_ts at time zone 'Asia/Seoul', 'YYYYMMDDHH24MISS') || '-' || right(v_phone, 4);$q$;
  b2 text := $q$v_ref := to_char(v_ts at time zone 'Asia/Seoul', 'YYYYMMDDHH24MISS') || '-' || right(v_phone, 4);
  if not exists (select 1 from crm.consult c where c.source = 'web_subscription' and c.source_ref = v_ref)
     and v_hand is not null and core.f_staff_on_leave(v_hand) then
    v_orig := v_hand;
    v_hand := core.f_assign_next('구독·렌탈', nullif(p_data->>'modelName',''));
  end if;$q$;
  a3 text := $q$handler = coalesce(crm.consult.handler, excluded.handler),$q$;
  b3 text := $q$handler = coalesce(excluded.handler, crm.consult.handler),$q$;
  a4 text := $q$returning id, (xmax = 0) into v_id, v_new;$q$;
  b4 text := $q$returning id, handler, (xmax = 0) into v_id, v_hand, v_new;$q$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_submit_inquiry';
  foreach v_n in array array[1,2,3,4] loop
    if (length(v_src)-length(replace(v_src, case v_n when 1 then a1 when 2 then a2 when 3 then a3 else a4 end, '')))
       / length(case v_n when 1 then a1 when 2 then a2 when 3 then a3 else a4 end) <> 1
    then raise exception '지점% 이 1개가 아님', v_n; end if;
  end loop;
  v_src := replace(v_src, a1, b1); v_src := replace(v_src, a2, b2); v_src := replace(v_src, a3, b3); v_src := replace(v_src, a4, b4);
  execute format('create or replace function public.fn_submit_inquiry(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
