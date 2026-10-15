-- mvp_214 · 2026-10-15 · 자동 발송 설정 (DB 는 이미 적용됨 · 기록용)
-- "그걸 자동 발송 대상 -> 자동 발송 설정에서 쉽게 보고 테스트도 해볼 수 있어야지"
--
-- 관리자 › 자동 발송 대상 맨 위 [자동 발송 설정] 카드 = 규칙 6개(crm.auto_rule) 의
--   켜짐/꺼짐 · 요일 · 시각 · 조건 · 대상 수 · 대상 미리보기(5명) · 문구(템플릿 auto_*) · [테스트 받기] · [저장]
-- 실제 자동 발송 엔진(cron) 은 아직 없다 — fn_auto_rules().engine = false. 켜 둬도 보내지 않는다.
-- 테스트 받기는 화면이 fn_sms_send(p_campaign 'auto_<code>', p_kind 'test') 로 한 통 — 설정 모드를 따른다(테스트면 기록만).

-- ───────────── 1. 규칙 표 ─────────────
create table if not exists crm.auto_rule (
  code          text primary key,
  label         text not null,
  kind          text not null check (kind in ('sub_expire','quote_follow','product_cycle','product_age')),
  params        jsonb not null default '{}'::jsonb,
  template_code text references crm.sms_template(code),
  enabled       boolean not null default false,
  send_time     text not null default '10:00',
  weekday       text not null default 'daily' check (weekday in ('daily','mon','tue','wed','thu','fri','sat','sun')),
  note          text,
  sort          int  not null default 100,
  updated_at    timestamptz not null default now(),
  updated_by    text
);
alter table crm.auto_rule enable row level security;   -- 정책 없음 · RPC(security definer) 로만

-- ───────────── 2. 문구 템플릿 (scope admin · 광고 아님) ─────────────
insert into crm.sms_template (code, label, body, scope, is_ad) values
 ('auto_sub_expire',   '자동 · 구독 만료 예정',        '[삼성스토어 시흥점] {이름} 님, 구독 중인 {모델} 약정이 {기한}에 끝납니다. 재약정·기기 교체 혜택을 먼저 안내드리겠습니다. {담당자} 프로 · {매장전화}', 'admin', false),
 ('auto_quote_follow', '자동 · 견적 보낸 뒤 후속',     E'[삼성스토어 시흥점] {이름} 님, 보내드린 견적서({모델}) 유효기한이 {기한}까지입니다. 조건 변경이나 추가 상담은 {담당자} 프로 · {매장전화}\n{견적링크}', 'admin', false),
 ('auto_toner',        '자동 · 토너·잉크 교체 주기',   E'[삼성스토어 시흥점] {이름} 님, 지난 주문 기준으로 토너·잉크 교체 시기가 가까워졌습니다. 같은 제품 바로 주문 {링크}\n문의 {담당자} 프로 · {매장전화}', 'admin', false),
 ('auto_water_filter', '자동 · 정수기 필터 12개월',    E'[삼성스토어 시흥점] {이름} 님, 정수기 필터 교체 시기(12개월)가 됐습니다. {모델} 전용 필터를 준비해 두었습니다. 주문·설치 문의 {담당자} 프로 · {매장전화}\n{링크}', 'admin', false),
 ('auto_air_filter',   '자동 · 공기청정기 필터 6개월', E'[삼성스토어 시흥점] {이름} 님, 공기청정기 필터 교체 시기(6개월)가 됐습니다. 환절기 전에 바꾸시면 좋습니다. {모델} 필터 안내 {링크}\n{담당자} 프로 · {매장전화}', 'admin', false),
 ('auto_combo_care',   '자동 · AI콤보 사용 2년 케어 안내', '[삼성스토어 시흥점] {이름} 님, 비스포크 AI 콤보 사용 2년이 됐습니다. 건조 필터·세탁조 관리 방법과 점검 안내를 보내드립니다. 궁금한 점은 {담당자} 프로 · {매장전화}', 'admin', false)
on conflict (code) do nothing;

-- ───────────── 3. 규칙 6개 (전부 꺼짐) ─────────────
-- 주기는 원장(오픈마켓 제외 · 3년) 재구매 간격 중앙값 실측: 토너 99일 · 정수기 필터 364일 · 공기청정기 필터 188일 · 건조기 필터는 재구매 표본 없음
-- AI콤보는 소모품을 취급하지 않아 '사용 24개월 케어 안내'(product_age) — 세탁조 클리너를 취급하면 product_cycle 로
insert into crm.auto_rule (code, label, kind, params, template_code, weekday, sort, note) values
 ('sub_90',       '구독 만료 90일 전',          'sub_expire',    '{"days":90}',  'auto_sub_expire',   'mon',   10, 'DPS 구독 전표 · 만료 90일 안 · 2027-05 부터 본격'),
 ('quote_3',      '견적 보낸 뒤 3일',            'quote_follow',  '{"days":3}',   'auto_quote_follow', 'daily', 20, '보낸 날 = 공유 링크 만든 때 · 산 사람은 빼야 한다'),
 ('toner_cycle',  '토너·잉크 교체 주기',         'product_cycle', '{"consumable":"MLT-|CLT-|INK-|토너|잉크","body":null,"cycle_days":99,"lo":-30,"hi":14}', 'auto_toner', 'mon', 30, '실측 재구매 간격 중앙값 99일 · VMS 는 고객별 주기(수동 추출 재구매 주기)가 더 정확'),
 ('water_filter', '정수기 필터 12개월',          'product_cycle', '{"consumable":"HAF-|정수기.*필터|필터.*정수기","body":"정수기","cycle_days":365,"lo":-30,"hi":14}', 'auto_water_filter', 'mon', 40, '실측 재구매 간격 중앙값 364일'),
 ('air_filter',   '공기청정기 필터 6개월',       'product_cycle', '{"consumable":"CFX-|청정기.*필터|헤파","body":"공기청정기|청정기","cycle_days":180,"lo":-30,"hi":14}', 'auto_air_filter', 'mon', 50, '실측 재구매 간격 중앙값 188일'),
 ('combo_24',     'AI콤보 사용 24개월 케어 안내', 'product_age',   '{"group":"AI콤보","min_m":24,"max_m":25}', 'auto_combo_care', 'mon', 60, '소모품이 없어 케어 안내 · 세탁조 클리너를 취급하면 주기 상품으로')
on conflict (code) do nothing;

-- ───────────── 4. RPC (authenticated · service_role · anon 없음) ─────────────
CREATE OR REPLACE FUNCTION public.fn_auto_rules()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select case when core.f_role() = 'anon' then null else
    jsonb_build_object('today', (now() at time zone 'Asia/Seoul')::date, 'engine', false,
      'rules', coalesce((select jsonb_agg(jsonb_build_object('code', r.code, 'label', r.label, 'kind', r.kind, 'params', r.params, 'enabled', r.enabled,
                 'send_time', r.send_time, 'weekday', r.weekday, 'note', r.note, 'sort', r.sort, 'updated_at', r.updated_at, 'updated_by', r.updated_by,
                 'template_code', r.template_code, 'body', t.body, 'is_ad', coalesce(t.is_ad,false), 'template_label', t.label) order by r.sort, r.code)
               from crm.auto_rule r left join crm.sms_template t on t.code = r.template_code), '[]'::jsonb)) end
$function$;

-- 대상 수 + 미리보기(최대 50명). sub_expire·quote_follow·product_age 는 fn_crm_followups(자동 발송 대상 카드와 같은 판정) 를 그대로 쓰고,
-- product_cycle 은 마지막 소모품 구매(없으면 본체 구매) + cycle_days 가 오늘 D+lo ~ D+hi 안인 사람.
-- 오픈마켓·취소·환불·자리표시(DP)·휴대폰 없음·수신거부 제외 · 같은 규칙(campaign auto_<code>)으로 주기 절반 안에 보낸 사람 제외. 번호는 가림.
CREATE OR REPLACE FUNCTION public.fn_auto_rule_preview(p_code text, p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare r crm.auto_rule; v_today date := (now() at time zone 'Asia/Seoul')::date; f jsonb; v_rows jsonb; v_total int := 0;
        v_cons text; v_body text; v_cycle int; v_lo int; v_hi int; v_lim int := least(greatest(coalesce(p_limit,5),1),50);
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into r from crm.auto_rule where code = p_code;
  if r.code is null then raise exception '규칙 없음 %', p_code; end if;

  if r.kind = 'sub_expire' then
    f := public.fn_crm_followups('sub', jsonb_build_object('days', coalesce((r.params->>'days')::int, 90), 'limit', v_lim));
    v_total := coalesce((f->>'total')::int, jsonb_array_length(coalesce(f->'rows','[]'::jsonb)));
    select coalesce(jsonb_agg(jsonb_build_object('name', x->>'name', 'phone', x->>'phone', 'item', coalesce(x->>'pname', x->>'model'), 'model', x->>'model',
             'ref_date', x->>'start_date', 'due_date', x->>'end_date', 'days', (x->>'days_left')::int, 'handler', x->>'staff', 'optout', (x->>'optout')::boolean)), '[]'::jsonb)
      into v_rows from jsonb_array_elements(coalesce(f->'rows','[]'::jsonb)) x;
  elsif r.kind = 'quote_follow' then
    f := public.fn_crm_followups('quote', jsonb_build_object('days', coalesce((r.params->>'days')::int, 3), 'limit', v_lim));
    v_total := coalesce((f->>'total')::int, jsonb_array_length(coalesce(f->'rows','[]'::jsonb)));
    select coalesce(jsonb_agg(jsonb_build_object('name', x->>'name', 'phone', x->>'phone', 'item', x->>'models', 'model', x->>'models',
             'ref_date', left(x->>'sent_at',10), 'due_date', x->>'until', 'days', (x->>'days_since')::int, 'handler', x->>'counselor', 'optout', (x->>'optout')::boolean, 'bought', (x->>'bought')::boolean)), '[]'::jsonb)
      into v_rows from jsonb_array_elements(coalesce(f->'rows','[]'::jsonb)) x;
  elsif r.kind = 'product_age' then
    f := public.fn_crm_followups('product', jsonb_build_object('group', r.params->>'group', 'min_m', r.params->'min_m', 'max_m', r.params->'max_m', 'limit', v_lim));
    v_total := coalesce((f->>'total')::int, jsonb_array_length(coalesce(f->'rows','[]'::jsonb)));
    select coalesce(jsonb_agg(jsonb_build_object('name', x->>'name', 'phone', x->>'phone', 'item', x->>'pname', 'model', x->>'model',
             'ref_date', x->>'bought_at', 'due_date', null, 'days', (x->>'months')::int, 'handler', x->>'handler', 'optout', (x->>'optout')::boolean)), '[]'::jsonb)
      into v_rows from jsonb_array_elements(coalesce(f->'rows','[]'::jsonb)) x;
  else
    /* product_cycle — 마지막 소모품 구매(없으면 본체 구매) + 주기 가 창(D+lo ~ D+hi) 안인 사람. 오픈마켓·취소·환불·수신거부·자리표시 고객 제외 · 같은 규칙으로 주기 절반 안에 보낸 사람 제외 */
    v_cons := r.params->>'consumable'; v_body := nullif(r.params->>'body',''); v_cycle := coalesce((r.params->>'cycle_days')::int, 180);
    v_lo := coalesce((r.params->>'lo')::int, -30); v_hi := coalesce((r.params->>'hi')::int, 14);
    with o as (
      select buyer_key::text bk, order_at::date d, product_name_raw pn from core.orders_live
       where net_amount > 0 and buyer_key is not null and coalesce(channel_type,'') <> '오픈마켓' and coalesce(status,'') not in ('취소','환불') and order_at > now() - interval '3 years'),
    cons as (select bk, max(d) last_d, (array_agg(pn order by d desc))[1] pn from o where pn ~* v_cons group by 1),
    body as (select bk, max(d) last_d, (array_agg(pn order by d desc))[1] pn from o where v_body is not null and pn ~* v_body and pn !~* v_cons group by 1),
    base as (select coalesce(c.bk, b.bk) bk, coalesce(c.last_d, b.last_d) ref_d, coalesce(c.pn, b.pn) pn, (c.bk is not null) has_cons from cons c full join body b on b.bk = c.bk),
    sel as (select d.bk, d.ref_d, d.pn, d.has_cons, d.ref_d + v_cycle due_d, cu.name, cu.phone, cu.buyer_key
              from base d join crm.customer cu on cu.buyer_key::text = d.bk
             where d.ref_d + v_cycle between v_today + v_lo and v_today + v_hi
               and nullif(cu.phone,'') is not null and not coalesce(cu.is_placeholder,false)
               and not exists (select 1 from crm.sms_optout oo where oo.released_at is null and oo.d8 = right(regexp_replace(cu.phone,'\D','','g'),8))
               and not exists (select 1 from crm.send_log l where l.buyer_key = cu.buyer_key and l.campaign = 'auto_'||r.code and coalesce(l.status,'') <> 'failed' and l.sent_at > now() - (v_cycle/2) * interval '1 day'))
    select count(*), coalesce((select jsonb_agg(jsonb_build_object('name', s.name, 'phone', core.f_phone_show(s.phone, false), 'item', s.pn, 'model', null,
             'ref_date', s.ref_d, 'due_date', s.due_d, 'days', (s.due_d - v_today), 'has_cons', s.has_cons, 'optout', false) order by s.due_d, s.name)
             from (select * from sel order by due_d, name limit v_lim) s), '[]'::jsonb)
      into v_total, v_rows from sel;
  end if;
  return jsonb_build_object('code', r.code, 'kind', r.kind, 'today', v_today, 'total', v_total, 'rows', coalesce(v_rows,'[]'::jsonb));
end $function$;

-- 저장(관리자만) — enabled · send_time · weekday · note · params(얕은 병합) · body/is_ad(템플릿) · 감사로그 'auto_rule:save' · 응답은 fn_auto_rules()
CREATE OR REPLACE FUNCTION public.fn_auto_rule_save(p_code text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare r crm.auto_rule; v_email text := coalesce(auth.jwt()->>'email','');
begin
  if core.f_role() <> 'admin' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into r from crm.auto_rule where code = p_code;
  if r.code is null then raise exception '규칙 없음 %', p_code; end if;
  update crm.auto_rule set
    enabled   = coalesce((p_data->>'enabled')::boolean, enabled),
    send_time = coalesce(nullif(btrim(p_data->>'send_time'),''), send_time),
    weekday   = case when p_data->>'weekday' in ('daily','mon','tue','wed','thu','fri','sat','sun') then p_data->>'weekday' else weekday end,
    note      = case when p_data ? 'note' then nullif(btrim(p_data->>'note'),'') else note end,
    params    = case when jsonb_typeof(p_data->'params') = 'object' then params || (p_data->'params') else params end,
    updated_at = now(), updated_by = v_email
  where code = p_code;
  if p_data ? 'body' and r.template_code is not null then
    update crm.sms_template set body = p_data->>'body', is_ad = coalesce((p_data->>'is_ad')::boolean, is_ad), updated_at = now() where code = r.template_code;
  end if;
  insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), v_email, 'auto_rule:save', 1, p_code||' enabled='||coalesce(p_data->>'enabled','(그대로)'));
  return public.fn_auto_rules();
end $function$;

revoke all on function public.fn_auto_rules(), public.fn_auto_rule_preview(text,int), public.fn_auto_rule_save(text,jsonb) from public, anon;
grant execute on function public.fn_auto_rules(), public.fn_auto_rule_preview(text,int), public.fn_auto_rule_save(text,jsonb) to authenticated, service_role;

-- ───────────── 5. 롤백 실험 결과 (2026-10-15 · 관리자 JWT 로) ─────────────
-- fn_auto_rule_preview 대상 수: sub_90 0 · quote_3 1 · toner_cycle 557 · water_filter 3 · air_filter 1 · combo_24 37
-- fn_auto_rule_save: enabled·weekday·send_time·body 저장 → fn_auto_rules 에 그대로 · access_log 'auto_rule:save' 1줄 · anon 42501 · 없는 코드 '규칙 없음'
--
-- ───────────── 6. 다음 ─────────────
-- 자동 발송 엔진: cron 이 enabled 규칙을 요일·시각에 맞춰 fn_auto_rule_preview(p_limit 50→전체 실번호 판) 로 뽑아 core.f_sms_send(campaign 'auto_<code>', 모드 그대로) 로 보내고
-- crm.send_log 에 남기면 다음 회차에서 빠진다. 켜지면 fn_auto_rules().engine = true 로 바꿔 화면 안내 문구를 바꾼다.
