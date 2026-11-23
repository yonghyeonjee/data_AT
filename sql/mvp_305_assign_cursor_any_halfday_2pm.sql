-- mvp_305 · 2026-11-19 · 문의 자동 배정 — 손으로 바꾼 담당자 다음 순번으로 · 오후 반차 기준 오후 2시
-- DB 에는 이미 적용됨 (이 파일은 기록). 함수 원본은 core.fn_src_backup tag = 'before mvp_305'.
--
-- 1) core.f_consult_assign_cursor(): 담당자를 손으로 바꾸면 (가장 최근에 배정된 건이 아니어도)
--    받은 사람이 "마지막 배정" 이 된다 → 다음 = 그 사람 다음 순번.
--    자동 배정 대상 접수만 · 숨김/지운 건 제외 · 받은 사람이 기본 순번표에 있을 때만.
-- 2) core.f_staff_on_leave(): 오후 반차는 오후 2시부터 없는 사람 (전엔 3시). 오전 반차·하루 휴무는 그대로.

do $$
declare v_def text; v_new text; v_n int;
  a1 text := '(l.half = ''pm''                and (now() at time zone ''Asia/Seoul'')::time >= time ''15:00'')';
  b1 text := '(l.half = ''pm''                and (now() at time zone ''Asia/Seoul'')::time >= time ''14:00'')';
  a2 text := '오후(pm) = 오후 3시부터 없음';
  b2 text := '오후(pm) = 오후 2시부터 없음(오후 2시까지만 배정 · mvp_305)';
  a3 text := 'and old.handler is not null and new.handler is not null';
  b3 text := 'and new.handler is not null and new.hidden_at is null and new.deleted_at is null' || E'\n' || '     and new.source in (''web_subscription'',''web_supply'',''quote'',''portal_form'',''web'')';
  a4 text := '     and old.handler = (select last_staff from core.assign_state where scope = ''default'')' || E'\n';
  a5 text := E'\nbegin\n  if new.handler is distinct';
  b5 text := E'\nbegin\n  /* mvp_305: 담당자를 손으로 바꾸면(가장 최근 건이 아니어도) 받은 사람이 "마지막 배정" 이 된다 → 다음 = 그 사람 다음 순번.\n     자동 배정 대상 접수(구독 폼·견적·홈페이지)만 · 숨김/지운 건 제외 · 받은 사람이 기본 순번표에 있을 때만 */\n  if new.handler is distinct';
begin
  insert into core.fn_src_backup(fn,args,tag,src) values
    ('core.f_staff_on_leave(text,date)','p_name text, p_on date','before mvp_305', pg_get_functiondef('core.f_staff_on_leave(text,date)'::regprocedure)),
    ('core.f_consult_assign_cursor()','','before mvp_305', pg_get_functiondef('core.f_consult_assign_cursor()'::regprocedure));

  v_def := pg_get_functiondef('core.f_staff_on_leave(text,date)'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a1,'')))/length(a1); if v_n <> 1 then raise exception 'leave a1 hits %', v_n; end if;
  v_new := replace(v_def,a1,b1);
  v_n := (length(v_new)-length(replace(v_new,a2,'')))/length(a2); if v_n <> 1 then raise exception 'leave a2 hits %', v_n; end if;
  execute replace(v_new,a2,b2);

  v_def := pg_get_functiondef('core.f_consult_assign_cursor()'::regprocedure);
  v_n := (length(v_def)-length(replace(v_def,a3,'')))/length(a3); if v_n <> 1 then raise exception 'cursor a3 hits %', v_n; end if;
  v_new := replace(v_def,a3,b3);
  v_n := (length(v_new)-length(replace(v_new,a4,'')))/length(a4); if v_n <> 1 then raise exception 'cursor a4 hits %', v_n; end if;
  v_new := replace(v_new,a4,'');
  v_n := (length(v_new)-length(replace(v_new,a5,'')))/length(a5); if v_n <> 1 then raise exception 'cursor a5 hits %', v_n; end if;
  execute replace(v_new,a5,b5);
end $$;

-- 되돌림 테스트 (2026-11-19 · 순서 권혁찬 > 이수혁 > 송희봉 > 김규완 > 최태웅 > 차효범 · 휴무 이수혁/송희봉/김규완 · 시작 마지막 = 차효범):
--   #1060(옛 문의) 을 권혁찬에게  → 마지막 = 권혁찬 · 다음 = 최태웅
--   #1060 을 송희봉(휴무)에게     → 마지막 = 송희봉 · 다음 = 최태웅
--   매장 입력 건을 권혁찬에게     → 마지막 그대로
--   #1060 을 박은지(순번표 밖)에게 → 마지막 그대로
