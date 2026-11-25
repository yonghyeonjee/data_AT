-- mvp_319 · 2026-11-25 · 문의 자동 배정 — 같은 고객(전화번호)이 연달아 접수하면 같은 담당자에게, 순번은 안 씀
-- DB 에는 이미 적용됨 (이 파일은 기록). 함수 원본은 core.fn_src_backup tag = 'before mvp_319'.
--
-- 왜: 11-12 같은 고객이 3분 간격으로 두 번 접수(#1022 · #1023) → 순번 두 칸을 쓰고 담당자가 둘로 갈렸다.
-- 규칙: 같은 전화번호(숫자만 · 10자리 이상)로 7일 안에 받은, 아직 안 끝난(진행전·진행중·보류) 자동 배정 대상 문의가 있으면
--       그 담당자(재직 중)에게 주고 f_assign_next 를 부르지 않는다. 숨김/지운 건은 기준이 안 된다.
--       같은 접수를 다시 받는 경우(source + source_ref 가 이미 있음 · 시트 수정)는 예전 그대로.

do $$
declare v_def text; v_new text; v_n int;
  a1 text := 'declare v_scope text;';
  b1 text := 'declare v_scope text; v_dig text; v_prev text; v_prev_id bigint;';
  a2 text := '  new.handler := core.f_assign_next(v_scope, nullif(new.interest_category,''''));';
  b2 text := '  /* mvp_319: 같은 고객(전화번호)이 연달아 접수하면 같은 담당자에게 — 7일 안에 받은, 아직 안 끝난(새 문의·상담중·보류) 문의가 있으면
     그 담당자에게 주고 순번은 쓰지 않는다. 이미 있는 접수를 다시 받는 경우(시트 수정)는 예전 그대로 */
  v_dig := regexp_replace(coalesce(new.phone,''''),''\D'','''',''g'');
  if length(v_dig) >= 10
     and not exists (select 1 from crm.consult e where e.source = new.source and e.source_ref = new.source_ref) then
    select c.handler, c.id into v_prev, v_prev_id
      from crm.consult c
     where c.created_at > now() - interval ''7 days''
       and regexp_replace(coalesce(c.phone,''''),''\D'','''',''g'') = v_dig
       and c.hidden_at is null and c.deleted_at is null
       and c.source in (''web_subscription'',''web_supply'',''quote'',''portal_form'',''web'')
       and c.result in (''진행전'',''진행중'',''보류'')
       and c.handler is not null
       and exists (select 1 from core.staff s where s.name = c.handler and s.active)
     order by c.id desc limit 1;
    if v_prev is not null then
      new.handler := v_prev;
      new.notes := concat_ws('' / '', nullif(new.notes,''''), ''같은 고객의 문의 #''||v_prev_id||'' 와 같은 담당자에게 배정 (순번 안 씀)'');
      return new;
    end if;
  end if;
' || a2;
begin
  insert into core.fn_src_backup(fn,args,tag,src) values ('core.f_consult_assign_default()','','before mvp_319', pg_get_functiondef('core.f_consult_assign_default()'::regprocedure));
  v_def := pg_get_functiondef('core.f_consult_assign_default()'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a1,'')))/length(a1); if v_n <> 1 then raise exception 'a1 hits %', v_n; end if;
  v_new := replace(v_def,a1,b1);
  v_n := (length(v_new)-length(replace(v_new,a2,'')))/length(a2); if v_n <> 1 then raise exception 'a2 hits %', v_n; end if;
  execute replace(v_new,a2,b2);
end $$;

-- 되돌림 테스트 (2026-11-25 · 순서 권혁찬 > 이수혁 > 송희봉 > 김규완 > 최태웅 > 차효범 · 시작 마지막 = 김규완 · 다음 = 권혁찬):
--   A 열린 #1133(김규완)과 같은 번호 → 담당 김규완 · 마지막 그대로 · notes 에 기록
--   B 처음 보는 번호                 → 담당 권혁찬(순번대로) · 마지막 = 권혁찬
--   C 끝난 #1124 와 같은 번호        → 순번대로 (같은 담당자에게 가지 않음)
