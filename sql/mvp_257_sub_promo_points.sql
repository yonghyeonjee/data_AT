-- mvp_257 · 구독 행사에 "N개월 구독료 상당 포인트 지원" 금액을 싣는다 (2026-11-02)
-- 왜: 삼성 11월 가이드 — AI 구독 페스티벌: 대상 모델 3/6개월 구독료 상당 포인트 지원 (최장 계약기간 기준). 구독탭·구독센터가 결제 예상액에서 차감해 "실제 구독료" 를 보여줘야 한다
-- 무엇: sub.promo 에 months(개월) · amount(모델 공통 금액) · amounts(모델별 금액 {"WD90H25AHW":540000}) · max_term_only(최장 약정에서만 · 기본 true)
--       금액 우선순위(화면 sub_tab.js): amounts[모델] → amount → months × 선택 요금제 월 구독료
--       저장 함수는 보내지 않은 항목을 지우지 않는다 (매장 화면 store.html 은 문구·기간·대상만 보낸다)
-- 적용 뒤: 행사 저장 → 트리거(mvp_255)가 배포 → sub_policy.js promos[] 에 months/amount/amounts/maxTerm 이 실린다

alter table sub.promo add column if not exists months        int,
                      add column if not exists amount        int,
                      add column if not exists amounts       jsonb,
                      add column if not exists max_term_only boolean not null default true;

create or replace function sub.f_promo_save(p_data jsonb, p_by text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_id bigint := nullif(p_data->>'id','')::bigint; v_old jsonb; v_new jsonb;
        v_text text := btrim(coalesce(p_data->>'text','')); v_from date := sub.f_date(p_data->>'from', '행사 시작일'); v_to date := sub.f_date(p_data->>'to', '행사 종료일');
        v_models text[] := coalesce((select array_agg(upper(x)) from unnest(sub.f_arr(p_data->'models')) x), '{}');
        v_months int; v_amount int; v_amounts jsonb; v_maxonly boolean;
begin
  if v_text = '' then raise exception '행사 문구가 비었습니다' using errcode = '22023'; end if;
  if v_from is not null and v_to is not null and v_to < v_from then raise exception '행사 종료일이 시작일보다 앞입니다' using errcode = '22023'; end if;
  if p_data ? 'months' then
    v_months := nullif(btrim(coalesce(p_data->>'months','')),'')::int;
    if v_months is not null and (v_months < 1 or v_months > 72) then raise exception '포인트 지원 개월 수는 1~72 사이여야 합니다' using errcode = '22023'; end if;
  end if;
  if p_data ? 'amount' then
    v_amount := nullif(regexp_replace(coalesce(p_data->>'amount',''), '[^0-9]', '', 'g'),'')::int;
  end if;
  if p_data ? 'amounts' then
    -- {"모델":금액} · 모델은 대문자·공백 제거, 금액은 숫자만. 빈 객체면 null
    select nullif(jsonb_object_agg(upper(regexp_replace(k, '\s', '', 'g')), nullif(regexp_replace(v, '[^0-9]', '', 'g'),'')::int), '{}'::jsonb) into v_amounts
      from jsonb_each_text(coalesce(nullif(p_data->'amounts', 'null'::jsonb), '{}'::jsonb)) t(k, v) where btrim(k) <> '';
  end if;
  if p_data ? 'maxTerm' then v_maxonly := coalesce((p_data->>'maxTerm')::boolean, true); end if;
  if v_id is not null then select to_jsonb(p) - 'updated_at' - 'updated_by' into v_old from sub.promo p where p.id = v_id; end if;
  if v_old is null then
    insert into sub.promo (text, from_d, to_d, cats, models, goods, active, sort, note, months, amount, amounts, max_term_only, updated_by)
    values (v_text, v_from, v_to, sub.f_arr(p_data->'cats'), v_models, sub.f_arr(p_data->'goods'),
            coalesce((p_data->>'active')::boolean, true), coalesce((p_data->>'sort')::int, 100), nullif(btrim(coalesce(p_data->>'note','')),''),
            v_months, v_amount, v_amounts, coalesce(v_maxonly, true), p_by)
    returning id into v_id;
  else
    update sub.promo set text = v_text, from_d = v_from, to_d = v_to, cats = sub.f_arr(p_data->'cats'),
           models = v_models, goods = sub.f_arr(p_data->'goods'),
           active = coalesce((p_data->>'active')::boolean, active), sort = coalesce((p_data->>'sort')::int, sort),
           note = nullif(btrim(coalesce(p_data->>'note','')),''),
           months        = case when p_data ? 'months'  then v_months  else months  end,
           amount        = case when p_data ? 'amount'  then v_amount  else amount  end,
           amounts       = case when p_data ? 'amounts' then v_amounts else amounts end,
           max_term_only = case when p_data ? 'maxTerm' then coalesce(v_maxonly, true) else max_term_only end,
           updated_by = p_by, updated_at = now()
     where id = v_id;
  end if;
  select to_jsonb(p) - 'updated_at' - 'updated_by' into v_new from sub.promo p where p.id = v_id;
  if v_old is distinct from v_new then
    insert into sub.policy_log (kind, key, before, after, by_user) values ('promo', v_id::text, v_old, v_new, p_by); end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- 화면용 읽기 (mvp_246 본체 + 포인트 항목)
create or replace function sub.f_policy_view() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object(
    'policy', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from sub.policy),
    'updated', (select coalesce(jsonb_object_agg(key, jsonb_build_object('at', to_char(updated_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'by', updated_by)), '{}'::jsonb) from sub.policy),
    'cards', (select coalesce(jsonb_agg(jsonb_build_object('card', card, 'notes', to_jsonb(notes), 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                 'hidden', hidden, 'note', note, 'updated', to_char(updated_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'by', updated_by) order by card), '[]'::jsonb) from sub.card_policy),
    'promos', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'text', text, 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                 'cats', to_jsonb(cats), 'models', to_jsonb(models), 'goods', to_jsonb(goods), 'active', active, 'sort', sort, 'note', note,
                 'months', months, 'amount', amount, 'amounts', amounts, 'maxTerm', max_term_only,
                 'state', case when not active then 'off' when from_d is not null and from_d > (now() at time zone 'Asia/Seoul')::date then 'soon'
                               when to_d is not null and to_d < (now() at time zone 'Asia/Seoul')::date then 'ended' else 'on' end,
                 'updated', to_char(updated_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'by', updated_by) order by active desc, sort, id), '[]'::jsonb) from sub.promo),
    'cats', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from (
               select jsonb_object_keys(v.body::jsonb) k from sdp.release_var v
                where v.name = 'DATA' and v.release_id = (select id from sdp.release where published_at is not null order by published_at desc limit 1)) t),
    'card_names', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from (
                     select jsonb_object_keys(v.body::jsonb) k from sdp.release_var v
                      where v.name = 'CARD' and v.release_id = (select id from sdp.release where published_at is not null order by published_at desc limit 1)) t),
    'ver', sub.f_policy_ver(),
    'deployed', (select jsonb_build_object('ver', ver, 'at', to_char(at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'note', note)
                   from sdp.publish_log where kind = 'sub_deployed' order by id desc limit 1),
    'log', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'key', key, 'at', to_char(at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'by', by_user) order by id desc), '[]'::jsonb)
              from (select * from sub.policy_log order by id desc limit 20) l));
$$;

create or replace function sub.f_promo_json(p_id bigint) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object('id', id, 'text', text, 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                            'cats', to_jsonb(cats), 'models', to_jsonb(models), 'goods', to_jsonb(goods), 'active', active, 'sort', sort, 'note', note,
                            'months', months, 'amount', amount, 'amounts', amounts, 'maxTerm', max_term_only)
    from sub.promo where id = p_id;
$$;

-- 배포 파일 (mvp_253 본체 + 포인트 항목) — jsonb_strip_nulls 라 없는 항목은 빠진다
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
                'goods', case when cardinality(goods) > 0 then to_jsonb(goods) end,
                'months', months, 'amount', amount, 'amounts', amounts,
                'maxTerm', case when (months is not null or amount is not null or amounts is not null) and not max_term_only then false end)) order by sort, id), '[]'::jsonb)
               from sub.promo where active and (to_d is null or to_d >= (now() at time zone 'Asia/Seoul')::date - 1)),
    'overrides', sub.f_price_override_live()));
$$;

-- 확인: select id, text, months, amount, amounts, max_term_only from sub.promo;  select sub.f_policy_export()->'promos';
