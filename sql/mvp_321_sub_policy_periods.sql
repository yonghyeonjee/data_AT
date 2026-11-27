-- mvp_321 · 2026-11-27 · 달이 바뀌는 구독 정책 (sub.policy 'periods') — 12월 구독 정책을 12/1 0시(KST)부터 자동 적용
-- 본사 "12월 구독 정책안 개요 사전 공유"(최종 확정 전): 구독료 단품할인 5% → 미운영 · N개월 구독료 포인트 → 미운영 · 구독 정률 포인트 5% → 2%
--   그대로: 선납할인(20/30/40/50% → 3/4/5/5%) · 추가구독할인 6년(최장) 3% · 다품목 2/3/5%(3년 2%·4년 3%·5년 3%·6년 5%) · 추가구독할인과 다품목 중복 불가
-- 값은 이 한 줄(sub.policy key 'periods')에서만 고친다. 배포 build_sub.mjs subPolicyPeriods 가 시작일이 지났으면 배포 파일에 바로 넣고,
-- 아직이면 sub_policy.js 끝에 붙은 같은 함수가 화면에서 그날 0시에 넣는다.
--   set       : 정책 경로 → 값 (autopay.rate 0 = 구독료 할인 미운영 · 줄 숨김 / multi.to = 다품목 할인 기간 연장)
--   pointRate : 모든 모델 멤버십 정률 포인트(%) — 삼성닷컴 수집값 대신 (기본 0.1% 와 상품별 추가 포인트는 그대로)
-- N개월 구독료 포인트는 sub.promo · quote/promo_list.js · sdp/sub/sub_promo_amt.js 가 모두 11-30 까지라 12/1 에 저절로 빠진다.

-- 1) 저장 검사에 periods 추가 (기존 함수 본문의 else 앞에 끼움)
do $do$
declare
  d text := pg_get_functiondef('sub.f_policy_check'::regproc);
  old_else text := $s$  else
    raise exception '모르는 정책 키입니다: % (autopay · prepay · texts · card_notes · defaults · bundle · multi)'$s$;
  add text := $s$  elsif p_key = 'periods' then
    -- 달이 바뀌는 정책 (mvp_321): [{from, to?, name, note?, set: {경로: 값}, pointRate?}]
    if jsonb_typeof(p_value) <> 'array' then raise exception 'periods 는 목록이어야 합니다' using errcode = '22023'; end if;
    for x in select * from jsonb_array_elements(p_value) loop
      if jsonb_typeof(x) <> 'object' then raise exception 'periods: {from, set} 묶음이어야 합니다' using errcode = '22023'; end if;
      if coalesce(x->>'from','') = '' then raise exception 'periods.from: 시작일(YYYY-MM-DD)이 필요합니다' using errcode = '22023'; end if;
      perform sub.f_date(x->>'from', 'periods.from'); perform sub.f_date(x->>'to', 'periods.to');
      if x ? 'set' and jsonb_typeof(x->'set') <> 'object' then raise exception 'periods.set 은 {경로: 값} 묶음이어야 합니다' using errcode = '22023'; end if;
      for k in select jsonb_object_keys(coalesce(x->'set','{}'::jsonb)) loop
        if k !~ '^[A-Za-z0-9_]+([.][A-Za-z0-9_]+)*$' or k ~ '^(points|periods)([.]|$)' then raise exception 'periods.set: 경로 % 는 쓸 수 없습니다', k using errcode = '22023'; end if;
      end loop;
      if x ? 'pointRate' and (jsonb_typeof(x->'pointRate') <> 'number' or (x->>'pointRate')::numeric < 0 or (x->>'pointRate')::numeric > 100) then
        raise exception 'periods.pointRate: 0~100 퍼센트 숫자여야 합니다' using errcode = '22023'; end if;
    end loop;
$s$;
begin
  if position('''periods''' in d) = 0 then
    if position(old_else in d) = 0 then raise exception 'f_policy_check 본문에서 else 자리를 못 찾았습니다'; end if;
    d := replace(d, old_else, add || replace(old_else, 'multi)', 'multi · periods)'));
    execute d;
  end if;
end $do$;

-- 2) 배포 내보내기에 periods
do $do$
declare
  d text := pg_get_functiondef('sub.f_policy_export'::regproc);
  a text := $s$    'multi', (select value from p where key = 'multi'),$s$;
begin
  if position('''periods''' in d) = 0 then
    if position(a in d) = 0 then raise exception 'f_policy_export 본문에서 multi 자리를 못 찾았습니다'; end if;
    d := replace(d, a, a || chr(10) || $s$    'periods', (select value from p where key = 'periods'),$s$);
    execute d;
  end if;
end $do$;

-- 3) 12월 구독 정책 (본사 사전 공유 11/27 · 확정 전 — 바뀌면 이 값만 고친다)
do $do$
declare v jsonb := $j$[{"from":"2026-12-01","name":"12월 구독 정책","note":"본사 사전 공유(2026-11-27 · 최종 확정 전) — 구독료 단품할인 5% 미운영 · N개월 구독료 포인트 미운영(행사 기간 11-30 종료로 처리) · 정률 포인트 5%→2% · 선납·추가구독·다품목 전월 동등","set":{"autopay.rate":0,"multi.to":"2026-12-31"},"pointRate":2}]$j$;
begin
  perform sub.f_policy_check('periods', v);
  insert into sub.policy (key, value, note, updated_by)
  values ('periods', v, '달이 바뀌는 정책 — from(KST 0시)부터 set 경로 값 덮어쓰기 · pointRate = 멤버십 정률 포인트(%) (mvp_321)', 'mvp_321')
  on conflict (key) do update set value = excluded.value, note = excluded.note, updated_at = now(), updated_by = excluded.updated_by;
end $do$;
