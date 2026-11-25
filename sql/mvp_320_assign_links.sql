-- mvp_320 · 2026-11-25 · 문의 자동 배정 — 연동 점검 (홈페이지 문의 · 잔디 카드)
-- DB 에는 이미 적용됨 (이 파일은 기록). 함수 원본은 core.fn_src_backup tag = 'before mvp_320'.
--
-- 1) core.f_assign_sources() — 자동 배정 순번에 들어가는 접수 종류를 한 곳에. homepage_api · gmail_homepage 추가.
--    f_consult_assign_default(같은 고객 찾기) · f_consult_assign_cursor(담당 변경 시 순번 따라가기)가 이 목록을 쓴다.
-- 2) core.f_assign_same_customer(전화번호) — mvp_319 규칙으로 찾은 담당자. 트리거를 안 거치는 홈페이지 문의
--    (core.f_homepage_inquiry · fn_inquiry_mail_ingest)가 순번을 돌리기 전에 먼저 본다.
-- 3) fn_submit_inquiry 잔디 카드 담당자 줄 — 같은 고객 재문의면 " (같은 고객이 다시 문의 · 앞 문의 담당자에게 · 순번 그대로)".

do $$
declare v_def text; v_n int; r record;
  a1 text := 'and c.source in (''web_subscription'',''web_supply'',''quote'',''portal_form'',''web'')';
  b1 text := 'and c.source = any(core.f_assign_sources())';
  a2 text := 'and new.source in (''web_subscription'',''web_supply'',''quote'',''portal_form'',''web'')';
  b2 text := 'and new.source = any(core.f_assign_sources())   /* mvp_320: 홈페이지 문의(API·메일)도 */';
  a3 text := 'v_hand := core.f_assign_next(''default'')';
  b3 text := 'v_hand := coalesce(core.f_assign_same_customer(v_phone), core.f_assign_next(''default''))   /* mvp_320: 같은 고객의 열린 문의가 있으면 그 담당자 · 순번 안 씀 */';
  a4 text := '''reassign'', case when v_orig is not null then '' ('' || v_orig || '' 프로님 휴가 → 재배정)'' else '''' end,';
  b4 text := '''reassign'', case when v_orig is not null then '' ('' || v_orig || '' 프로님 휴가 → 재배정)''
                       else coalesce((select '' (같은 고객이 다시 문의 · 앞 문의 담당자에게 · 순번 그대로)'' from crm.consult k where k.id = v_id and k.notes like ''%같은 담당자에게 배정%''), '''') end,   /* mvp_320 */';
begin
  for r in select p.oid, p.oid::regprocedure::text fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where (n.nspname='core' and p.proname in ('f_consult_assign_default','f_consult_assign_cursor','f_homepage_inquiry')) or (n.nspname='public' and p.proname in ('fn_inquiry_mail_ingest','fn_submit_inquiry')) loop
    insert into core.fn_src_backup(fn,args,tag,src) values (r.fn, '', 'before mvp_320', pg_get_functiondef(r.oid));
  end loop;

  execute $f$
    create or replace function core.f_assign_sources() returns text[] language sql immutable set search_path to 'pg_catalog','public' as $s$
      /* 자동 배정 순번에 들어가는 접수 종류 (mvp_320) — 구독 폼 · 소모품 · 견적 · 고객센터 폼 · 홈페이지(API·메일) */
      select array['web_subscription','web_supply','quote','portal_form','web','homepage_api','gmail_homepage']
    $s$
  $f$;
  execute $f$
    create or replace function core.f_assign_same_customer(p_phone text) returns text language sql stable security definer set search_path to 'pg_catalog','public' as $s$
      /* 같은 전화번호로 7일 안에 받은, 아직 안 끝난(새 문의·상담중·보류) 자동 배정 대상 문의의 담당자 — 없으면 null (mvp_319 규칙 · mvp_320 에서 함수로) */
      select c.handler from crm.consult c
       where length(regexp_replace(coalesce(p_phone,''),'\D','','g')) >= 10
         and c.created_at > now() - interval '7 days'
         and regexp_replace(coalesce(c.phone,''),'\D','','g') = regexp_replace(p_phone,'\D','','g')
         and c.hidden_at is null and c.deleted_at is null
         and c.source = any(core.f_assign_sources())
         and c.result in ('진행전','진행중','보류')
         and c.handler is not null
         and exists (select 1 from core.staff s where s.name = c.handler and s.active)
       order by c.id desc limit 1
    $s$
  $f$;
  revoke all on function core.f_assign_same_customer(text) from public, anon, authenticated;

  v_def := pg_get_functiondef('core.f_consult_assign_default()'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a1,'')))/length(a1); if v_n <> 1 then raise exception 'default a1 hits %', v_n; end if;
  execute replace(v_def,a1,b1);

  v_def := pg_get_functiondef('core.f_consult_assign_cursor()'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a2,'')))/length(a2); if v_n <> 1 then raise exception 'cursor a2 hits %', v_n; end if;
  execute replace(v_def,a2,b2);

  v_def := pg_get_functiondef('core.f_homepage_inquiry(jsonb)'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a3,'')))/length(a3); if v_n <> 1 then raise exception 'homepage a3 hits %', v_n; end if;
  execute replace(v_def,a3,b3);

  v_def := pg_get_functiondef('public.fn_inquiry_mail_ingest(text,jsonb)'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a3,'')))/length(a3); if v_n <> 1 then raise exception 'mail a3 hits %', v_n; end if;
  execute replace(v_def,a3,b3);

  v_def := pg_get_functiondef('public.fn_submit_inquiry(text,jsonb)'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a4,'')))/length(a4); if v_n <> 1 then raise exception 'submit a4 hits %', v_n; end if;
  execute replace(v_def,a4,b4);
end $$;

-- 되돌림 테스트 (2026-11-25 · 시작 마지막 = 김규완):
--   f_assign_same_customer(열린 #1133 의 번호) = 김규완 · 처음 보는 번호 = null
--   같은 번호로 새 접수 → 담당 김규완 · 카드 문구 " (같은 고객이 다시 문의 · 앞 문의 담당자에게 · 순번 그대로)"
--   홈페이지 문의 #980(차효범)을 권혁찬에게 → 마지막 배정 = 권혁찬 (전엔 그대로였다)
