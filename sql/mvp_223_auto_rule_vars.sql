-- mvp_223 · 2026-10-19 · 자동 발송 문구에 지난 구매 제품 정보 (제품·모델·구매일·기한) — 적용 기록
-- "앞서 구매했던 제품 모델명도 함께 나갔으면 · 재구매 주기 도달했을 때는 앞서 구매한 제품 정보를 담아서"
-- 1) 자리 글자 묶음: 미리보기 한 줄(item·model·ref_date·due_date) → {제품,모델,구매일,기한}
create or replace function core.f_auto_rule_vars(x jsonb) returns jsonb language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    '제품', left(nullif(btrim(x->>'item'),''), 60),
    '모델', coalesce(nullif(btrim(x->>'model'),''), left(nullif(btrim(x->>'item'),''), 60)),
    '구매일', case when (x->>'ref_date') ~ '^\d{4}-\d{2}-\d{2}' then to_char((x->>'ref_date')::date, 'YYYY.MM.DD') else nullif(x->>'ref_date','') end,
    '기한', case when (x->>'due_date') ~ '^\d{4}-\d{2}-\d{2}' then to_char((x->>'due_date')::date, 'YYYY.MM.DD') else nullif(x->>'due_date','') end))
$$;
-- 2) fn_auto_rule_preview 부분 치환 (pg_get_functiondef → replace → execute · 지점 수 검증)
--    product_cycle: 원장 o 에 nullif(model_key,'') mk · cons/body 가 최근 줄의 mk(널 아닌 것) · base·sel 에 mk · rows 'model' s.mk (전엔 null)
--    공통: return 직전에 rows 마다 'vars' = core.f_auto_rule_vars(row) 를 붙인다
--    (치환 문구는 세션 기록 참고 — 바꿀 문구 6개 · 지점 1·2·1·1·1·1)
-- 3) 문구 4개 (crm.sms_template) — {구매일}에 구매하신 {제품} …
--    auto_toner · auto_water_filter · auto_air_filter · auto_combo_care({모델})
-- 확인: 사람별 렌더 205·225·256·201 바이트(LMS) · 토너 'CLT-K515S/TND [1,500매]' 2026.06.12 · 정수기 'HAF-HIN' · 콤보 'WD25DB8995BZ'
