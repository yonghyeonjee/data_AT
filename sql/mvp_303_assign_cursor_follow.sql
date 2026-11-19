-- mvp_303 · 2026-11-19 · 문의 자동 배정 — 수동으로 넘기면 순번도 따라간다 (mvp_302 의 ③ 되돌림)
-- (적용됨 — 이 파일은 기록용)
--
-- 왜: mvp_302 뒤 첫 두 건(#1066 김규완 · #1067 송희봉 — 둘 다 휴무)을 store 에서 이수혁 · 권혁찬 프로님께 넘겼는데
--     순번(마지막 배정)이 송희봉에 그대로 남아 "다음 = 이수혁" 으로 나왔다.
--     "왜 바꾸었으니까 최태웅프로님이지" — 넘겨받은 사람이 그 차례를 받은 것이므로 다음은 그다음 사람이어야 한다.
--     mvp_302 에서 '다른 규칙은 다 꺼두는 걸로' 를 넓게 읽어 이 동작까지 끈 것이 잘못.
--
-- 바꾼 것: 트리거 함수 core.f_consult_assign_cursor 를 mvp_302 전 원문으로 되돌림
--          (core.fn_src_backup id 11 · tag 'before mvp_302' 와 pg_get_functiondef 가 같은지 확인하고 적용).
--          되돌리기 직전 판은 tag 'before mvp_302b'.
--   규칙(원래대로): 지금 '마지막 배정' 인 사람의 문의를 순번표에 있는(active) 다른 사람에게 넘기면
--                   넘겨받은 사람이 '마지막 배정' 이 된다. 그 밖의 문의를 넘기는 것은 순번에 영향 없음.
-- 그대로(mvp_302): core.f_assign_simple() = true — 휴가자 건너뛰기 · 휴가 재배정 · 품목/접수 종류 규칙은 꺼짐.
--          f_assign_simple 본문 주석만 고침(수동 재배정 따라가기는 이 스위치와 무관).
-- 순번 맞춤: fn_assign_cursor_set('default','권혁찬') — 마지막 배정 송희봉 → 권혁찬 (core.assign_pool_log 에 기록)
--          → 다음 = 최태웅.
--
-- 시험(롤백 블록): 마지막 송희봉 · #1066=김규완 · #1067=송희봉 으로 놓고
--   #1066 → 이수혁 : 마지막 배정 그대로(송희봉)   (#1066 은 마지막 배정 건이 아님)
--   #1067 → 권혁찬 : 마지막 배정 = 권혁찬 · fn_assign_pool next = 최태웅
-- crm.consult 의 UPDATE 트리거 중 바깥으로 나가는 것(http·잔디)은 없다(시험 전에 확인).

do $outer$
declare v_src text; v_new text; v_old text;
        v_anchor text := 'if not core.f_assign_simple() and new.handler is distinct from old.handler';
begin
  select p.prosrc into v_src from pg_proc p where p.oid = 'core.f_consult_assign_cursor'::regproc;
  if (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor) <> 1 then raise exception 'anchor count mismatch'; end if;
  v_new := replace(v_src, v_anchor, 'if new.handler is distinct from old.handler');
  select b.src into v_old from core.fn_src_backup b where b.id = 11 and b.tag = 'before mvp_302';
  if v_old is null then raise exception 'no backup'; end if;
  insert into core.fn_src_backup(fn, args, tag, src)
  values ('core.f_consult_assign_cursor()', '', 'before mvp_302b', pg_get_functiondef('core.f_consult_assign_cursor'::regproc));
  execute format('create or replace function core.f_consult_assign_cursor() returns trigger language plpgsql volatile set search_path to ''pg_catalog'',''public'' as %L', v_new);
  if pg_get_functiondef('core.f_consult_assign_cursor'::regproc) is distinct from v_old then raise exception 'restored def differs from original'; end if;
end $outer$;

create or replace function core.f_assign_simple() returns boolean language sql stable set search_path to 'pg_catalog','public' as $f$
  /* 문의 자동 배정 단순 순번 모드 (mvp_302 · 2026-11-19) — true 면 기본 순번표(1~6번)만 순서대로 돈다:
     휴가자 건너뛰기 · 휴가 재배정 · 품목/접수 종류 규칙을 끈다. 다시 켜려면 false 로.
     수동 재배정 시 순번 따라가기는 mvp_303 에서 다시 켰다(이 스위치와 무관). */
  select true
$f$;

-- 순번 맞춤 (관리자 세션에서)
-- select public.fn_assign_cursor_set('default', '권혁찬');
