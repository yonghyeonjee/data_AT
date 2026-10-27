-- mvp_249 (2026-10-27) 상품상세 구독탭 요금표의 원본을 SDP 엑셀판 → DPS 올인원구독모델조회(dps.sub_model · 매일 수집)로
--   build_sub.mjs 가 fn_sub_dps_export() 로 DPS 전체(active)를 받아 sub_index.js · sub_plans_<키>.js 를 만든다.
--   SDP 판(fn_sdp_export)은 제휴카드표(CARD)·정수기 본사 할인값(WATER_POLICY)에만 계속 쓴다.
--   안전장치(publish.mjs): 최신 수집이 24시간 넘게 없거나 모델 수가 직전 배포판보다 10% 넘게 줄면 구독탭 파일을 안 바꾸고(이전 판 유지)
--   fn_sub_publish_log('sub_skipped', …) 로 남긴다. DPS 에서 빠진 모델(active=false)은 자연히 제외된다 (주문 불가 모델 노출 방지).
--   관리자 화면 변경 없음. 요금제 이름·품목 키 매핑은 build_sub.mjs 쪽 (DPS 판매 수집기 export_products_js.mjs 와 같은 규칙).

-- ── 배포용 내보내기 (GitHub Actions · service_role 만) ──
-- items 원소: [model, category, seg, term_months, service, visit_cycle, total_fee, monthly_fee, prepay_ok]
--   prepay_ok = 호버 표에 0% 말고 선납 비율이 하나라도 있음 (없는 모델만 모아 PREPAY_NO 가 된다)
create or replace function public.fn_sub_dps_export() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with f as (select fetch_id, finished_at, rows from dps.sub_model_fetch where finished_at is not null order by finished_at desc limit 1),
       a as (select * from dps.sub_model where active)
  select jsonb_build_object(
    'fetch_id',   (select fetch_id from f),
    'fetched_at', (select finished_at from f),
    'fetch_rows', (select rows from f),
    'rows',       (select count(*) from a),
    'models',     (select count(distinct model) from a),
    'items',      coalesce((select jsonb_agg(jsonb_build_array(model, category, seg, term_months, service, visit_cycle, total_fee, monthly_fee,
                      exists(select 1 from jsonb_array_elements(prepay) e where coalesce((e->>'ratio')::int, 0) > 0)) order by row_no, model, term_months, service, visit_cycle)
                    from a), '[]'::jsonb));
$$;

-- 배포가 건너뛰었거나 경고가 있을 때 기록 (kind: sub_skipped · sub_warn) — 관리자 [배포 기록] 과 같은 표(sdp.publish_log)
create or replace function public.fn_sub_publish_log(p_kind text, p_ver text, p_note text default null) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
begin
  if p_kind not in ('sub_skipped', 'sub_warn') then raise exception 'kind 는 sub_skipped · sub_warn 만 됩니다'; end if;
  insert into sdp.publish_log (release_id, ver, kind, by_user, note) values (null, left(coalesce(p_ver, ''), 80), p_kind, 'github-actions', left(coalesce(p_note, ''), 2000));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.fn_sub_dps_export(), public.fn_sub_publish_log(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_sub_dps_export()                     to service_role;
grant execute on function public.fn_sub_publish_log(text, text, text)    to service_role;
