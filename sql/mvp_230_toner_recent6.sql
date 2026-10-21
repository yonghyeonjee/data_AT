-- mvp_230 · 2026-10-21 · 토너 자동 발송은 마지막 구매 6개월 안 고객에게만
-- "그냥 6개월 이내 고객에게만 보내자" — 수신 동의만 있고 거래가 6개월 넘은 고객·오래 밀린 고객은 뺀다.
-- fn_auto_rule_preview product_cycle 에 params.recent_months (비우면 제한 없음) · 응답 recent_months·recent_blocked.
do $outer$
declare v_def text; n int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_auto_rule_preview';
  n := (length(v_def) - length(replace(v_def, 'v_ad boolean;', ''))) / length('v_ad boolean;');
  if n <> 1 then raise exception 'decl %', n; end if;
  n := (length(v_def) - length(replace(v_def, 'where ad_ok', ''))) / length('where ad_ok');
  if n <> 4 then raise exception 'where ad_ok %', n; end if;
  n := (length(v_def) - length(replace(v_def, 'where not ad_ok', ''))) / length('where not ad_ok');
  if n <> 1 then raise exception 'not ad_ok %', n; end if;
  n := (length(v_def) - length(replace(v_def, ') ad_ok, cu.name', ''))) / length(') ad_ok, cu.name');
  if n <> 1 then raise exception 'sel %', n; end if;
  n := (length(v_def) - length(replace(v_def, '''lo'', v_lo, ''hi'', v_hi)', ''))) / length('''lo'', v_lo, ''hi'', v_hi)');
  if n <> 1 then raise exception 'extra %', n; end if;
  v_def := replace(v_def, 'v_ad boolean;', 'v_ad boolean; v_recent int;');
  v_def := replace(v_def, 'v_ad := coalesce((select t.is_ad', 'v_recent := nullif(r.params->>''recent_months'','''')::int;' || E'\n    ' || 'v_ad := coalesce((select t.is_ad');
  v_def := replace(v_def, ') ad_ok, cu.name', ') ad_ok, (v_recent is null or d.ref_d >= (v_today - make_interval(months => v_recent))::date) rec_ok, cu.name');
  v_def := replace(v_def, 'where ad_ok', 'where rec_ok and ad_ok');
  v_def := replace(v_def, 'where not ad_ok', 'where rec_ok and not ad_ok');
  v_def := replace(v_def, '''lo'', v_lo, ''hi'', v_hi)', '''lo'', v_lo, ''hi'', v_hi, ''recent_months'', v_recent, ''recent_blocked'', count(*) filter (where not rec_ok))');
  execute v_def;
end $outer$;

update crm.auto_rule set params = params || '{"recent_months":6}'::jsonb where code = 'toner_cycle';

-- 결과(10-21): 첫 회 358명(이미 지난 221 + 14일 안 137) · 9,648원 · 6개월 넘은 1,263명 제외
-- 그 뒤 새로 드는 사람 하루 3~19명(평균 약 10) · 월 235~343명 6.3~9.2천원
-- 고객별 주기가 196일을 넘는 814명은 예정일 무렵 마지막 구매가 6개월을 넘겨 이 규칙으로는 안 받는다
