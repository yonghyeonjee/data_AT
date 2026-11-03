-- mvp_273 (2026-11-03) 다품목 구독 할인 — 정책 키 multi (삼성 "11월 SDP AI 구독 상담 에이전트" 계산 기준)
--
-- 신규 고객이 2품목 이상 동시 구독하면 대마다 약정 기간별로 월 구독료를 추가 할인한다: 6년 5% (로봇청소기 5년 5%) · 4~5년 3% · 3년 2%.
-- 금액 식은 자동납부 할인과 같다 (ROUNDUP(총 구독금액 × 비율 / 1.1 / 개월, -2) × 개월 × 1.1 → 월 환산). 제휴카드 청구할인은 그 뒤에 다시 상한.
-- 정수기는 본사가 세부유형·약정·케어별 표(WATER_POLICY.multi)로 따로 정해 두어 우리 표가 없다 → exclude 로 빼고 상담 안내.
-- 기존 bundle(11월 스마트 패키지 품목 수별 정액 포인트 · mvp_264)과는 별도 키로 두어 둘을 같이 계산한다. 화면: sdp/sub/sub_bundle.js (applyMulti).
--   1) sub.f_policy_check : multi 검증 분기  2) sub.f_policy_export : 'multi' 항목  3) 정책 저장 (f_policy_save → policy_log · 배포 트리거)
-- 적용: MCP apply_migration. 긴 함수는 pg_get_functiondef 를 읽어 확인한 조각만 바꾼다 (조각이 정확히 1번 있어야 하고, 아니면 멈춘다).

do $$
declare d text; old text; new text; c int;
begin
  -- 1) 검증
  d := pg_get_functiondef('sub.f_policy_check(text,jsonb)'::regprocedure);
  old := $o$  else
    raise exception '모르는 정책 키입니다: % (autopay · prepay · texts · card_notes · defaults · bundle)', p_key using errcode = '22023';$o$;
  new := $n$  elsif p_key = 'multi' then
    -- 다품목 구독 할인 (mvp_273): {rates: {"3": 0.02, "4": 0.03, "5": 0.03, "6": 0.05}, robot5(로봇청소기 5년), min, exclude: [품목], from, to, name, text}
    if jsonb_typeof(p_value) <> 'object' then raise exception 'multi 는 항목 묶음이어야 합니다' using errcode = '22023'; end if;
    if jsonb_typeof(p_value->'rates') <> 'object' or p_value->'rates' = '{}'::jsonb then raise exception 'multi.rates: 약정 연수별 할인율이 비었습니다 ({"3": 0.02, "4": 0.03, "5": 0.03, "6": 0.05})' using errcode = '22023'; end if;
    for k, x in select * from jsonb_each(p_value->'rates') loop
      if k !~ '^\d+$' or k::int < 1 then raise exception 'multi.rates: 약정 연수는 1 이상 정수여야 합니다 (현재 %)', k using errcode = '22023'; end if;
      if jsonb_typeof(x) <> 'number' or x::text::numeric < 0 or x::text::numeric >= 1 then raise exception 'multi.rates.%: %', k, procedure_rate using errcode = '22023'; end if;
    end loop;
    if p_value ? 'robot5' and (jsonb_typeof(p_value->'robot5') <> 'number' or (p_value->>'robot5')::numeric < 0 or (p_value->>'robot5')::numeric >= 1) then raise exception 'multi.robot5: %', procedure_rate using errcode = '22023'; end if;
    if p_value ? 'min' and (jsonb_typeof(p_value->'min') <> 'number' or (p_value->>'min')::numeric < 2) then raise exception 'multi.min: 최소 품목 수는 2 이상 정수여야 합니다' using errcode = '22023'; end if;
    if p_value ? 'exclude' and jsonb_typeof(p_value->'exclude') <> 'array' then raise exception 'multi.exclude 는 품목 이름 목록이어야 합니다 (예: ["정수기"])' using errcode = '22023'; end if;
    perform sub.f_date(p_value->>'from', 'multi.from'); perform sub.f_date(p_value->>'to', 'multi.to');
    if coalesce(p_value->>'from','') <> '' and coalesce(p_value->>'to','') <> '' and (p_value->>'to')::date < (p_value->>'from')::date then raise exception 'multi: 종료일이 시작일보다 앞입니다' using errcode = '22023'; end if;
  else
    raise exception '모르는 정책 키입니다: % (autopay · prepay · texts · card_notes · defaults · bundle · multi)', p_key using errcode = '22023';$n$;
  c := (length(d) - length(replace(d, old, ''))) / length(old);
  if c <> 1 then raise exception 'f_policy_check: 바꿀 조각이 % 번 있습니다 (1이어야 함)', c; end if;
  execute replace(d, old, new);

  -- 2) 배포 JSON
  d := pg_get_functiondef('sub.f_policy_export()'::regprocedure);
  old := $o$    'bundle', sub.f_bundle_export(),$o$;
  new := $n$    'multi', (select value from p where key = 'multi'),
    'bundle', sub.f_bundle_export(),$n$;
  c := (length(d) - length(replace(d, old, ''))) / length(old);
  if c <> 1 then raise exception 'f_policy_export: 바꿀 조각이 % 번 있습니다 (1이어야 함)', c; end if;
  execute replace(d, old, new);
end $$;

-- 3) 11월 정책 (기간이 지나면 화면은 자동으로 빼고, 다음 달 표는 이 키만 다시 저장)
select sub.f_policy_save('multi', $j${"rates": {"3": 0.02, "4": 0.03, "5": 0.03, "6": 0.05}, "robot5": 0.05, "min": 2, "exclude": ["정수기"],
  "from": "2026-11-01", "to": "2026-11-30", "name": "다품목 구독 할인",
  "text": "신규 고객이 2품목 이상 동시 구독하면 대마다 약정 기간에 따라 월 구독료를 추가 할인합니다. 정수기는 본사 표가 따로 있어 상담 때 안내해 드립니다."}$j$::jsonb, 'mvp_273');
update sub.policy set note = '다품목 구독 할인 — 삼성 11월 SDP 상담 기준 (6년 5% · 로봇청소기 5년 5% · 4~5년 3% · 3년 2% · 신규 고객 2품목↑ · 정수기 제외)' where key = 'multi';
