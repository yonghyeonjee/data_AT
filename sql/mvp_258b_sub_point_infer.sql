-- mvp_258b (2026-11-02) · 구독 멤버십 포인트를 활성 구독 모델 전부에 — 삼성닷컴에 없는 모델은 같은 품목의 가장 가까운 모델에서 물려받는다
--
-- 왜: 수집기(tools/subpoint/collect.mjs)는 삼성닷컴에 구독 상품이 있는 모델만 받아 온다(2026-11-02 1,131개 중 765개).
--     나머지 366개는 삼성닷컴에 없는 매장 전용 변형(같은 제품의 다른 색상·설치형·번들 코드 — TV 205 · 에어컨 89 · 세탁기/건조기 28 · 정수기 9 …)이라
--     구독센터(/data/gudok)·구독탭의 결제 내역에 "적립 예정 멤버십 포인트" 줄이 빠져 있었다.
--     수집된 765개는 전부 정률 6.0% + 기본 0.1% 로 같고, 상품별 추가 포인트(300,000P)만 시스템에어컨 AJ/AN/AS 계열에 붙는다.
--
-- 어떻게: 배포용 points 를 sub.f_point_export() 로 뺀다 = 수집·손 입력 행(sub.model_point) + 추정 행(est).
--   추정 행 = 활성 모델 중 sub.model_point 에 없는 모델마다
--     · 정률·기본률 : 같은 품목(dps.sub_model.category)에서 모델번호 앞부분이 가장 길게 같은 수집 모델의 값. 품목에 수집 모델이 없으면(정수기) 수집값의 최빈값(6.0 · 0.1).
--     · 추가 포인트 : 그 가장 가까운 모델과 앞 5자 이상 같을 때만 물려받는다 (AN40BSU5P44ISY ← AN40BSU5P40ISY 300,000P · AF70F17D11BT ← AF70F17D11WT 0).
--     · total 은 없다(기준 총액이 없다) · "est": 1 과 기준 모델 "ref" 를 같이 내보낸다 — 화면(sub_tab.js · sub_view.js)은 rate/base/add 만 쓰고, 검사기(build_sub.mjs checkPolicy)도 그 키만 본다.
--   sub.model_point 에는 넣지 않는다 — 다음 수집이 실제 값을 받아 오면 추정은 저절로 빠진다. 관리자 › 구독 혜택 정책 › 모델 포인트의 '못 찾음' 수는 그대로다(요약에 n_est 추가).
--
-- 적용: MCP apply_migration (mvp_258b_sub_point_infer). 적용 뒤 sub.model_point 에 빈 update 한 번으로 배포 트리거(sub.f_deploy_kick)를 울려 sub_policy.js 를 새 판으로.
-- 검증: select jsonb_object_keys(sub.f_point_export()) 수 = 활성 모델 수(1,131) · est 366 · 정수기 RWP… 6/0.1 · AN40BSU5P44ISY add 300000.

-- ── 두 글자열의 앞부분이 몇 자 같은가 ──
create or replace function sub.f_lcp(a text, b text) returns int
language sql immutable strict as $$
  select coalesce((select min(i) - 1 from generate_series(1, least(length(a), length(b))) i where substr(a, i, 1) <> substr(b, i, 1)),
                  least(length(a), length(b)));
$$;

-- ── 배포 파일의 points: 수집·손 입력 + 추정 ──
create or replace function sub.f_point_export() returns jsonb
language sql stable security definer set search_path to 'pg_catalog', 'public' as $$
  with mp as (select model, aisc_rate, basic_rate, mdl_add_point, total_point
                from sub.model_point where coalesce(aisc_rate, 0) > 0 or coalesce(mdl_add_point, 0) > 0),
       act as (select model, min(category) category from dps.sub_model where active group by model),
       miss as (select a.model, a.category from act a where not exists (select 1 from sub.model_point p where p.model = a.model)),
       near as (select distinct on (m.model) m.model, p.model ref, p.aisc_rate, p.basic_rate, p.mdl_add_point,
                       sub.f_lcp(upper(m.model), upper(p.model)) lcp
                  from miss m join act a2 on a2.category = m.category join mp p on p.model = a2.model
                 order by m.model, sub.f_lcp(upper(m.model), upper(p.model)) desc, p.model),
       dflt as (select mode() within group (order by aisc_rate) rate, mode() within group (order by basic_rate) base from mp),
       est as (select m.model, coalesce(n.aisc_rate, d.rate) rate, coalesce(n.basic_rate, d.base) base,
                      case when n.lcp >= 5 then coalesce(n.mdl_add_point, 0) else 0 end add_pt,
                      case when n.lcp >= 5 then n.ref end ref
                 from miss m left join near n on n.model = m.model cross join dflt d)
  select coalesce(jsonb_object_agg(model, body), '{}'::jsonb) from (
    select model, jsonb_strip_nulls(jsonb_build_object(
             'rate', case when coalesce(aisc_rate, 0) > 0 then aisc_rate end,
             'base', case when coalesce(basic_rate, 0) > 0 then basic_rate end,
             'add', case when coalesce(mdl_add_point, 0) > 0 then mdl_add_point end,
             'total', case when coalesce(total_point, 0) > 0 then total_point end)) body
      from mp
    union all
    select model, jsonb_strip_nulls(jsonb_build_object(
             'rate', case when coalesce(rate, 0) > 0 then rate end,
             'base', case when coalesce(base, 0) > 0 then base end,
             'add', case when add_pt > 0 then add_pt end,
             'est', 1, 'ref', ref))
      from est where coalesce(rate, 0) > 0 or add_pt > 0
  ) x;
$$;
revoke all on function sub.f_lcp(text, text), sub.f_point_export() from public, anon, authenticated;

-- ── f_policy_export 의 points 블록(mvp_258)을 sub.f_point_export() 호출로 (본문 치환 · CLAUDE.md 규칙) ──
do $outer$
declare v_src text; v_a int; v_b int;
        v_head text := $q$'points', (select coalesce(jsonb_object_agg(model$q$;
        v_tail text := $q$'overrides', sub.f_price_override_live()$q$;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'sub' where p.proname = 'f_policy_export';
  if v_src is null then raise exception 'sub.f_policy_export 없음'; end if;
  if position('sub.f_point_export()' in v_src) > 0 then raise notice 'f_policy_export: 이미 반영 — 건너뜀'; return; end if;
  v_a := position(v_head in v_src); v_b := position(v_tail in v_src);
  if v_a = 0 or v_b = 0 or v_b < v_a then raise exception 'f_policy_export 치환 지점을 못 찾음 (%, %)', v_a, v_b; end if;
  if (length(v_src) - length(replace(v_src, v_head, ''))) / length(v_head) <> 1 then raise exception 'f_policy_export points 블록이 1개가 아님'; end if;
  execute format('create or replace function sub.f_policy_export() returns jsonb language sql stable security definer set search_path to ''pg_catalog'',''public'' as %L',
                 left(v_src, v_a - 1) || $q$'points', sub.f_point_export(),
    $q$ || substr(v_src, v_b));
end $outer$;

-- ── 관리자 화면 요약(f_policy_view › points)에 추정 모델 수 n_est ──
do $outer$
declare v_src text; v_n int;
        v_old text := $q$'n_active', (select count(distinct model) from dps.sub_model where active),$q$;
        v_new text := $q$'n_active', (select count(distinct model) from dps.sub_model where active),
                 'n_est', (select count(*) from jsonb_each(sub.f_point_export()) e where (e.value->>'est') = '1'),$q$;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'sub' where p.proname = 'f_policy_view';
  if v_src is null then raise exception 'sub.f_policy_view 없음'; end if;
  if position('''n_est''' in v_src) > 0 then raise notice 'f_policy_view: 이미 반영 — 건너뜀'; return; end if;
  v_n := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'f_policy_view 치환 지점 %개 (1개여야 함)', v_n; end if;
  execute format('create or replace function sub.f_policy_view() returns jsonb language sql stable security definer set search_path to ''pg_catalog'',''public'' as %L',
                 replace(v_src, v_old, v_new));
end $outer$;

-- 확인
-- select count(*) from jsonb_each(sub.f_point_export());                                   -- 1131 (활성 모델 수)
-- select count(*) from jsonb_each(sub.f_point_export()) e where e.value->>'est' = '1';     -- 366
-- select sub.f_point_export()->'AN40BSU5P44ISY', sub.f_point_export()->'RWP70F15ANB', sub.f_point_export()->'KQ65SH90AFXKR';
