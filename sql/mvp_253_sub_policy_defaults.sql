-- mvp_253 (2026-10-29) 구독 화면 공통 기준값을 데이터센터 정책으로 — 기본 제휴카드·실적 구간 · 상담 신청 주소 · 전화
-- 지금까지 고도몰 스킨(goods/_sub_tab.html 의 SUB_TAB_CONFIG) · 구독센터 상세(sub_view.js) · 목록(sub_shop.js) 이 제각기 들고 있던 값을 sub.policy 'defaults' 한 곳에 둔다.
--   defaults = { card: '삼성카드', tier: '30만↑', consultUrl: '/main/html.php?htmid=service/SamSungSubscription.html', tel: '031-8042-3166' }
--   화면은 CFG(스킨 설정) 값이 비어 있으면 이 값을 쓴다 → 고도몰 템플릿은 켜고 끄기·상품번호·선택자만 남긴다.
--   목록 화면의 카드 할인 표시도 이 tier 기준으로 맞춘다 (전에는 가장 낮은 실적 구간).
-- 고치는 길: 관리자(admin.html 품목 › 구독 혜택 정책 › 기본 기준·상담 연락처) fn_sub_policy_save('defaults', …). 매장(store.html)은 보기만.
-- 배포: fn_sub_policy_export() 의 'defaults' → sdp/sub/sub_policy.js (SUB_POLICY.defaults). 정책 판(sub.f_policy_ver)은 updated_at 으로 자동으로 바뀐다.

-- 1) 값 검사 — defaults 가지 추가 (나머지는 mvp_246 과 같다)
create or replace function sub.f_policy_check(p_key text, p_value jsonb) returns void
language plpgsql immutable as $$
declare x jsonb; k text;
  procedure_rate text := '0 이상 1 미만 소수여야 합니다 (5% → 0.05)';
begin
  if p_key = 'autopay' then
    if jsonb_typeof(p_value->'rate') <> 'number' or (p_value->>'rate')::numeric < 0 or (p_value->>'rate')::numeric >= 1 then
      raise exception 'autopay.rate: %', procedure_rate using errcode = '22023'; end if;
    if coalesce(p_value->>'label','') !~ '\{rate\}' then
      raise exception 'autopay.label 에는 {rate} 자리가 있어야 합니다' using errcode = '22023'; end if;
  elsif p_key = 'prepay' then
    if jsonb_typeof(p_value->'steps') <> 'array' then raise exception 'prepay.steps 는 목록이어야 합니다' using errcode = '22023'; end if;
    for x in select * from jsonb_array_elements(p_value->'steps') loop
      if jsonb_typeof(x) <> 'number' or x::text::numeric <= 0 or x::text::numeric >= 1 then
        raise exception 'prepay.steps: % — %', x, procedure_rate using errcode = '22023'; end if;
      if not (p_value->'rates') ? (x::text) then
        raise exception 'prepay.rates: 선납 % 의 할인율이 없습니다', x using errcode = '22023'; end if;
    end loop;
    for k, x in select * from jsonb_each(coalesce(p_value->'rates','{}'::jsonb)) loop
      if jsonb_typeof(x) <> 'number' or x::text::numeric < 0 or x::text::numeric >= 1 then
        raise exception 'prepay.rates.%: %', k, procedure_rate using errcode = '22023'; end if;
    end loop;
    if p_value ? 'defaultMax' and (jsonb_typeof(p_value->'defaultMax') <> 'number' or (p_value->>'defaultMax')::numeric <= 0 or (p_value->>'defaultMax')::numeric > 1) then
      raise exception 'prepay.defaultMax: %', procedure_rate using errcode = '22023'; end if;
    for k, x in select * from jsonb_each(coalesce(p_value->'maxByCat','{}'::jsonb)) loop
      if jsonb_typeof(x) <> 'number' or x::text::numeric < 0 or x::text::numeric > 1 then
        raise exception 'prepay.maxByCat.%: %', k, procedure_rate using errcode = '22023'; end if;
    end loop;
    for x in select * from jsonb_array_elements(coalesce(p_value->'maxByName','[]'::jsonb)) loop
      if coalesce(x->>'cat','') = '' or coalesce(x->>'contains','') = '' or jsonb_typeof(x->'max') <> 'number' then
        raise exception 'prepay.maxByName: cat · contains · max 가 모두 있어야 합니다 (%)', x using errcode = '22023'; end if;
    end loop;
    if p_value ? 'notes' and jsonb_typeof(p_value->'notes') <> 'array' then raise exception 'prepay.notes 는 문장 목록이어야 합니다' using errcode = '22023'; end if;
  elsif p_key = 'texts' then
    if p_value ? 'points' and jsonb_typeof(p_value->'points') <> 'array' then raise exception 'texts.points 는 문장 목록이어야 합니다' using errcode = '22023'; end if;
    if p_value ? 'notice' and jsonb_typeof(p_value->'notice') <> 'string' then raise exception 'texts.notice 는 글이어야 합니다' using errcode = '22023'; end if;
  elsif p_key = 'card_notes' then
    if jsonb_typeof(p_value) <> 'array' then raise exception 'card_notes 는 문장 목록이어야 합니다' using errcode = '22023'; end if;
  elsif p_key = 'defaults' then
    if jsonb_typeof(p_value) <> 'object' then raise exception 'defaults 는 항목 묶음이어야 합니다' using errcode = '22023'; end if;
    if coalesce(btrim(p_value->>'card'),'') = '' then raise exception 'defaults.card: 기본 제휴카드 이름이 비었습니다 (카드 금액표의 이름과 같게 · 예: 삼성카드)' using errcode = '22023'; end if;
    if p_value ? 'tier' and jsonb_typeof(p_value->'tier') <> 'string' then raise exception 'defaults.tier: 실적 구간은 글자여야 합니다 (예: 30만↑ · 비우면 가장 낮은 구간)' using errcode = '22023'; end if;
    if coalesce(p_value->>'consultUrl','') !~ '^(/|https://)' then raise exception 'defaults.consultUrl: 상담 신청 주소는 / 또는 https:// 로 시작해야 합니다' using errcode = '22023'; end if;
    if coalesce(p_value->>'tel','') !~ '^[0-9-]*$' then raise exception 'defaults.tel: 전화번호는 숫자와 - 만 (예: 031-8042-3166 · 비우면 전화 버튼 없음)' using errcode = '22023'; end if;
  else
    raise exception '모르는 정책 키입니다: % (autopay · prepay · texts · card_notes · defaults)', p_key using errcode = '22023';
  end if;
end $$;

-- 2) 배포용 내보내기에 defaults 를 붙인다 (mvp_251 판 + defaults)
create or replace function sub.f_policy_export()
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with p as (select key, value from sub.policy)
  select jsonb_strip_nulls(jsonb_build_object(
    'ver', sub.f_policy_ver(),
    'defaults', (select value from p where key = 'defaults'),
    'autopay', (select value from p where key = 'autopay'),
    'prepay',  (select value from p where key = 'prepay'),
    'texts',   (select value from p where key = 'texts'),
    'cardNotes', coalesce((select value from p where key = 'card_notes'), '[]'::jsonb),
    'cards', (select coalesce(jsonb_object_agg(card, jsonb_strip_nulls(jsonb_build_object(
                'notes', case when cardinality(notes) > 0 then to_jsonb(notes) end,
                'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'), 'hidden', case when hidden then true end))), '{}'::jsonb)
              from sub.card_policy),
    'promos', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                'text', text, 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                'cats', case when cardinality(cats) > 0 then to_jsonb(cats) end,
                'models', case when cardinality(models) > 0 then to_jsonb(models) end,
                'goods', case when cardinality(goods) > 0 then to_jsonb(goods) end)) order by sort, id), '[]'::jsonb)
               from sub.promo where active and (to_d is null or to_d >= (now() at time zone 'Asia/Seoul')::date - 1)),
    'overrides', sub.f_price_override_live()));
$$;

-- 3) 처음 값 = 지금까지 고도몰 스킨 SUB_TAB_CONFIG 에 있던 값 · 이미 있으면 건드리지 않는다
insert into sub.policy (key, value, note, updated_by) values
('defaults', '{"card":"삼성카드","tier":"30만↑","consultUrl":"/main/html.php?htmid=service/SamSungSubscription.html","tel":"031-8042-3166"}',
 '구독탭·구독센터 공통 기준 — 처음 선택되는 제휴카드·실적 구간, 상담 신청 주소, 전화', 'mvp_253')
on conflict (key) do nothing;

-- 확인: select key, value from sub.policy where key = 'defaults';  select sub.f_policy_export()->'defaults';
