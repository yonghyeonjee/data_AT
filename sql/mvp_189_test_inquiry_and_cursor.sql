-- mvp_189 · 2026-10-07 · ① 테스트 문의는 잔디 카드만 — 순번·통계·고객 표에 영향 없음  ② 배정 순번 '마지막 배정' 지정(되돌리기)  ③ '다음 배정' 표시
-- 배경: "잔디 알림이 가는지 테스트해 보려는데 기존 담당자 순서에 영향이 없게 하는 방법" → B안.
-- ① fn_submit_inquiry (부분 치환 8지점): 이름·담당에 test·테스트 가 있으면 전엔 저장 없이 skipped 였다(잔디도 안 감).
--    이제 v_test=true → 담당 '지용현'(개발 계정) 고정 → 트리거 trg_consult_dev_is_test 가 '테스트 (개발 계정 담당)' 숨김 ·
--    f_assign_next 를 안 부르니 순번 커서 그대로 · 휴가 재배정 건너뜀 · crm.customer 에 안 넣음(buyer_key null) ·
--    잔디 카드는 그대로(이름 '🧪 테스트 · 홍길동', 담당자 줄 '지용현 (테스트 — 순번 안 돌림 · 통계 제외)') · 응답 test:true.
--    GAS onMgmtEdit/backfill 의 test 건너뜀은 그대로(시트 수정은 안 올라온다). GAS 테스트 모드(noNotify)는 카드를 안 보내는 다른 것.
--    롤백 확인: '테스트 홍길동' → handler 지용현 · hidden '테스트 (개발 계정 담당)' · buyer_key null · cursor 권혁찬→권혁찬 · customer +0.
-- ② fn_assign_cursor_set(p_scope, p_staff) — admin/dev. p_staff null = 처음부터. core.assign_pool_log 에 kind='cursor' 로 기록(before=[이전], after=[새]).
--    core.assign_pool_log.kind text default 'order' 추가.
-- ③ fn_assign_pool 응답 'next' {scope: 다음 사람} — 순번표·휴가(f_staff_on_leave)·커서로 f_assign_next 와 같은 규칙, 부작용 없음.
-- 화면(admin/test → admin.html, v173): 상태 줄 '다음 차효범' · 칩 아래 [마지막 배정 ▾][이 사람으로 지정][처음부터](confirm). 테스트 ptest/pool_probe.mjs A2·A2b (17/17 × 1280·390).
alter table core.assign_pool_log add column if not exists kind text not null default 'order';
create or replace function public.fn_assign_cursor_set(p_scope text, p_staff text)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_old text; v_new text := nullif(btrim(coalesce(p_staff,'')),'');
begin
  if core.f_role() not in ('admin','dev') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_new is not null and not exists (select 1 from core.assign_pool where scope = p_scope and staff_name = v_new and active) then
    raise exception '% 은(는) 이 순번표에 없습니다', v_new; end if;
  select last_staff into v_old from core.assign_state where scope = p_scope;
  if v_new is null then delete from core.assign_state where scope = p_scope;
  else insert into core.assign_state (scope, last_staff, last_at) values (p_scope, v_new, now())
       on conflict (scope) do update set last_staff = excluded.last_staff, last_at = excluded.last_at; end if;
  insert into core.assign_pool_log (by_user, by_role, scope, before_names, after_names, kind)
  values (coalesce(auth.jwt()->>'email', current_setting('request.jwt.claims', true)::jsonb->>'role'), core.f_role(), p_scope,
          array[coalesce(v_old,'(없음)')], array[coalesce(v_new,'(처음부터)')], 'cursor');
  return jsonb_build_object('ok', true, 'scope', p_scope, 'from', v_old, 'to', v_new);
end $$;
revoke all on function public.fn_assign_cursor_set(text,text) from public, anon;
grant execute on function public.fn_assign_cursor_set(text,text) to authenticated, service_role;
-- fn_assign_pool 'next' · fn_submit_inquiry 테스트 분기 치환 본문은 세션 기록(위 설명)과 같다 — 재적용할 일이 있으면 prosrc 를 읽어 같은 지점을 치환할 것.
