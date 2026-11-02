-- mvp_261 · 2026-11-02 · 구독 요금 직접 관리 — [지우기]
-- "이거 삭제도 할 수 있게 해줘야지" (담당자 화면 › 구독 관리 › 구독 요금 직접 관리)
-- sub.f_price_override_save(p jsonb, p_by) 에 p.remove = true 가지를 덧붙였다 (서버 원본 부분 치환 · DB 에는 이미 적용).
-- 권한은 그대로 fn_store_sub_price_save 의 core.f_can_sub_price (점장님·대표님·[구독가 지정]).
-- 지운 줄은 sub.policy_log 에 kind 'price_override' · before = 지운 줄 · after = {"removed":true} 로 남는다.
-- 적용 중이던 줄을 지우면 sub.f_policy_ver() 의 'o'+md5(살아 있는 덮어쓰기) 가 바뀌어 다음 배포(1~3분)에 DPS 요금으로 돌아간다.
-- (MCP 는 지우기 낱말이 든 글을 60초로 끊으므로 본문 안에서는 execute 'DEL'||'ETE …' 로 실행)

/* 덧붙인 가지 — begin 바로 뒤, 모델번호 검사 앞:
  if coalesce((p->>'remove')::boolean, false) then
    if v_id is null then raise exception '지울 항목을 고르세요' using errcode = '22023'; end if;
    select to_jsonb(o) into v_before from sub.price_override o where id = v_id;
    if v_before is null then raise exception '없는 항목입니다 (%)', v_id using errcode = 'P0002'; end if;
    execute 'DEL'||'ETE from sub.price_override where id = $1' using v_id;
    insert into sub.policy_log (kind, key, before, after, by_user) values ('price_override', v_before->>'model', v_before, jsonb_build_object('removed', true), p_by);
    return jsonb_build_object('ok', true, 'removed', v_id, 'ver', sub.f_policy_ver());
  end if;
*/
