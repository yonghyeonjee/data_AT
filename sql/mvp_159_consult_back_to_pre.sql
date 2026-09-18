-- mvp_159 · 2026-09-18 · 상담을 [연락 전]으로 되돌리기 + 콜백이 연락 전을 상담중으로 바꾸지 않게
-- 배경: 이수혁 프로가 안현지 건(id 390)에 콜백 09-19 14:00 을 잡자 result 가 진행전→진행중으로 바뀌어
--       "연락전으로 돌리려면 어떻게 해" — 화면의 [연락 전] 버튼은 act:null 이라 눌리지 않았다.
-- 적용: fn_store_consult_update 원본 prosrc 를 읽어 두 지점만 치환 (ACL 그대로).
--   ① p_action = 'pre'  → result='진행전', notes '연락 전으로 되돌림 MM-DD HH:MI 이름'. callback_at 은 손대지 않는다.
--   ② p_action = 'callback' 의 result 승격 case 에서 '진행전' 을 뺀다 — 연락 전에 콜백을 잡아도 연락 전 그대로 (종료·거절 → 진행중은 유지).
-- 화면: store.html STATE_STEPS[진행전].act='pre' (버튼 활성), 힌트 문구, mcAct 토스트는 t.msg.
-- 데이터: id 390 을 수동으로 진행전으로 되돌림 (notes 에 '연락 전으로 되돌림 09-18 09:07 지용현 (요청)').
do $outer$
declare v_src text; v_args text; a text; b text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_store_consult_update';
  a := $a$  elsif p_action = 'hold' then$a$;
  b := $b$      result = case when result in ('종료','거절','진행전') then '진행중' else result end,$b$;
  if (length(v_src)-length(replace(v_src,a,'')))/length(a) <> 1 then raise exception 'hold 지점'; end if;
  if (length(v_src)-length(replace(v_src,b,'')))/length(b) <> 1 then raise exception 'callback 지점'; end if;
  v_src := replace(v_src, a,
$n$  elsif p_action = 'pre' then   -- 연락 전으로 되돌림 (잘못 눌렀거나 아직 통화 못 한 건). 콜백 약속은 그대로 둔다
    update crm.consult set result = '진행전', updated_at = now(),
      notes = concat_ws(' / ', notes, '연락 전으로 되돌림 '||v_stamp||' '||v_me||coalesce(' · '||v_memo,''))
     where id = p_id;
$n$ || a);
  v_src := replace(v_src, b,
$m$      result = case when result in ('종료','거절') then '진행중' else result end,   -- 진행전(연락 전)은 콜백을 잡아도 연락 전 그대로 (mvp_159)$m$);
  execute format('create or replace function public.fn_store_consult_update(%s) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
-- 검증(롤백되는 do 블록으로 확인함): pre → 진행전 · 진행전에서 callback → 진행전 유지 · 거절에서 callback → 진행중

-- ── 2026-09-18 두 번째 (v119) ── "내일 오후 02:00 이 그대로 나와있어"
-- ① 'pre' 가 callback_at·callback_done_at 도 null 로 (notes 에 '(콜백 MM-DD HH:MI 지움)')
-- ② p_action = 'callback_clear' — 콜백 약속만 지움(상태 그대로). 화면 콜백 창 [콜백 지우기].
do $outer$
declare v_src text; v_args text; a text; b text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_store_consult_update';
  a := $a$    update crm.consult set result = '진행전', updated_at = now(),
      notes = concat_ws(' / ', notes, '연락 전으로 되돌림 '||v_stamp||' '||v_me||coalesce(' · '||v_memo,''))$a$;
  if (length(v_src)-length(replace(v_src,a,'')))/length(a) <> 1 then raise exception 'pre 지점'; end if;
  v_src := replace(v_src, a,
$n$    update crm.consult set result = '진행전', callback_at = null, callback_done_at = null, updated_at = now(),
      notes = concat_ws(' / ', notes, '연락 전으로 되돌림'||case when callback_at is not null then ' (콜백 '||to_char(callback_at at time zone 'Asia/Seoul','MM-DD HH24:MI')||' 지움)' else '' end||' '||v_stamp||' '||v_me||coalesce(' · '||v_memo,''))$n$);
  b := $b$  elsif p_action = 'hold' then$b$;
  if (length(v_src)-length(replace(v_src,b,'')))/length(b) <> 1 then raise exception 'hold 지점'; end if;
  v_src := replace(v_src, b,
$m$  elsif p_action = 'callback_clear' then   -- 콜백 약속만 지운다 (상태는 그대로)
    update crm.consult set callback_at = null, callback_done_at = null, updated_at = now(),
      notes = concat_ws(' / ', notes, '콜백 '||coalesce(to_char(callback_at at time zone 'Asia/Seoul','MM-DD HH24:MI'),'')||' 지움 '||v_stamp||' '||v_me||coalesce(' · '||v_memo,''))
     where id = p_id;
$m$ || b);
  execute format('create or replace function public.fn_store_consult_update(%s) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
-- id 390 콜백 09-19 14:00 을 손으로 지움. 검증(롤백 블록): callback_clear → 상태 유지·콜백 null / pre → 진행전·콜백 null
