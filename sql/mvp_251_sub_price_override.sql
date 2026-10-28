-- mvp_251 (2026-10-28) 구독 요금 직접 관리 — DPS 요금표 위에 손으로 덮어쓰는 값 (상품상세 구독탭 · 구독센터)
-- "datacenter store/test에 수동으로 관리할 수 있는 메뉴도 그 구독 가격에 대해서"
--   sub.price_override : 모델 · (약정 · 케어 — 비우면 그 모델 전체) · 월/총 구독료 · 숨김 · 기간 · 켜짐
--   배포: fn_sub_policy_export 의 'overrides' 로 나가고 build_sub.mjs 가 DPS 요금표에 덧씌운다 (sub_policy.js 에는 안 쓴다)
--   판 번호: sub.f_policy_ver 에 지금 적용 중인 덮어쓰기 목록의 해시 4자리를 붙인다 — 기간이 시작·끝나도 판이 바뀌어 상세페이지가 새로 받는다
--   매장 화면(store/test 견적서 탭): fn_store_sub_price_list(보기 누구나) · fn_store_sub_price_save(점장님·대표님)

create table if not exists sub.price_override (
  id          bigint generated always as identity primary key,
  model       text not null,                       -- 대문자·공백 없음
  action      text not null default 'set' check (action in ('set','hide')),
  term_years  integer check (term_years between 1 and 10),   -- 비우면 모든 약정
  care        text,                                -- 상세페이지 요금제 이름 그대로(예: 방문케어 · 무상수리) · 비우면 모든 케어
  cat         text,                                -- DPS 에 없는 모델을 새로 넣을 때 품목(냉장고 …)
  seg         text,                                -- 새 모델의 세부유형 (선택)
  monthly_fee numeric check (monthly_fee is null or monthly_fee > 0),
  total_fee   numeric check (total_fee is null or total_fee > 0),
  from_d      date,
  to_d        date,
  active      boolean not null default true,
  note        text,
  updated_at  timestamptz not null default now(),
  updated_by  text
);
create index if not exists price_override_model_idx on sub.price_override (model);
alter table sub.price_override enable row level security;

-- 지금 상세페이지에 적용되는 덮어쓰기 (켜짐 · 기간 안 · 한국 날짜)
create or replace function sub.f_price_override_live()
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', id, 'model', model, 'action', action, 'term', term_years, 'care', care, 'cat', cat, 'seg', seg,
           'monthly', monthly_fee, 'total', total_fee)) order by model, id), '[]'::jsonb)
    from sub.price_override
   where active
     and (from_d is null or from_d <= (now() at time zone 'Asia/Seoul')::date)
     and (to_d   is null or to_d   >= (now() at time zone 'Asia/Seoul')::date);
$$;

-- 판 번호: 정책·카드·행사 마지막 수정 시각 + 적용 중인 덮어쓰기 해시
create or replace function sub.f_policy_ver()
returns text language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select to_char(coalesce(greatest((select max(updated_at) from sub.policy), (select max(updated_at) from sub.card_policy), (select max(updated_at) from sub.promo)), now())
                 at time zone 'Asia/Seoul', 'YYMMDD-HH24MI')
         || coalesce((select case when jsonb_array_length(o) > 0 then 'o' || left(md5(o::text), 4) end from (select sub.f_price_override_live() o) x), '');
$$;

-- 배포용 정책에 overrides 를 붙인다 (build_sub.mjs 가 꺼내 쓰고 sub_policy.js 에는 남기지 않는다)
create or replace function sub.f_policy_export()
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with p as (select key, value from sub.policy)
  select jsonb_strip_nulls(jsonb_build_object(
    'ver', sub.f_policy_ver(),
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

-- 목록 (매장 화면) — 전부 · 상태 붙여서
create or replace function sub.f_price_override_view()
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with t as (select (now() at time zone 'Asia/Seoul')::date d)
  select jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
              'id', o.id, 'model', o.model, 'action', o.action, 'term', o.term_years, 'care', o.care, 'cat', o.cat, 'seg', o.seg,
              'monthly', o.monthly_fee, 'total', o.total_fee,
              'from', to_char(o.from_d,'YYYY-MM-DD'), 'to', to_char(o.to_d,'YYYY-MM-DD'), 'active', o.active, 'note', o.note,
              'updated_at', to_char(o.updated_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'updated_by', o.updated_by,
              'state', case when not o.active then 'off' when o.to_d is not null and o.to_d < t.d then 'ended'
                            when o.from_d is not null and o.from_d > t.d then 'soon' else 'on' end)
              order by o.active desc, o.model, o.term_years nulls first, o.care nulls first, o.id) from sub.price_override o, t), '[]'::jsonb),
    'ver', sub.f_policy_ver(),
    'deployed', (select jsonb_build_object('at', to_char(at at time zone 'Asia/Seoul','MM-DD HH24:MI'), 'ver', ver)
                   from sdp.publish_log where kind = 'sub_deployed' order by id desc limit 1));
$$;

-- 저장 (새로 · 고치기 · 끄기/켜기) — 값 검사 · 기록
create or replace function sub.f_price_override_save(p jsonb, p_by text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare
  v_id bigint := nullif(p->>'id','')::bigint;
  v_model text := upper(regexp_replace(coalesce(p->>'model',''), '\s', '', 'g'));
  v_action text := coalesce(nullif(p->>'action',''), 'set');
  v_term int := nullif(p->>'term','')::int;
  v_care text := nullif(trim(coalesce(p->>'care','')), '');
  v_mon numeric := nullif(p->>'monthly','')::numeric;
  v_tot numeric := nullif(p->>'total','')::numeric;
  v_from date := nullif(p->>'from','')::date;
  v_to date := nullif(p->>'to','')::date;
  v_before jsonb; v_row sub.price_override;
begin
  if v_model !~ '^[A-Z0-9][A-Z0-9_\-/.]{3,40}$' then raise exception '모델번호를 확인해 주세요 (%)', coalesce(p->>'model','') using errcode = '22023'; end if;
  if v_action not in ('set','hide') then raise exception '동작은 요금 바꾸기 또는 숨김입니다' using errcode = '22023'; end if;
  if v_action = 'set' and v_mon is null then raise exception '월 구독료를 적어 주세요' using errcode = '22023'; end if;
  if v_action = 'set' and v_mon < 1000 then raise exception '월 구독료가 너무 작습니다 (%원)', v_mon using errcode = '22023'; end if;
  if v_from is not null and v_to is not null and v_to < v_from then raise exception '종료일이 시작일보다 앞입니다' using errcode = '22023'; end if;
  if v_action = 'set' and v_tot is null and v_term is not null then v_tot := v_mon * v_term * 12; end if;   -- 총구독료를 비우면 월 × 개월
  if v_id is not null then
    select to_jsonb(o) into v_before from sub.price_override o where id = v_id;
    if v_before is null then raise exception '없는 항목입니다 (%)', v_id using errcode = 'P0002'; end if;
    update sub.price_override set model = v_model, action = v_action, term_years = v_term, care = v_care,
           cat = nullif(trim(coalesce(p->>'cat','')),''), seg = nullif(trim(coalesce(p->>'seg','')),''),
           monthly_fee = case when v_action = 'set' then v_mon end, total_fee = case when v_action = 'set' then v_tot end,
           from_d = v_from, to_d = v_to, active = coalesce((p->>'active')::boolean, active),
           note = nullif(trim(coalesce(p->>'note','')),''), updated_at = now(), updated_by = p_by
     where id = v_id returning * into v_row;
  else
    insert into sub.price_override (model, action, term_years, care, cat, seg, monthly_fee, total_fee, from_d, to_d, active, note, updated_by)
    values (v_model, v_action, v_term, v_care, nullif(trim(coalesce(p->>'cat','')),''), nullif(trim(coalesce(p->>'seg','')),''),
            case when v_action = 'set' then v_mon end, case when v_action = 'set' then v_tot end,
            v_from, v_to, coalesce((p->>'active')::boolean, true), nullif(trim(coalesce(p->>'note','')),''), p_by)
    returning * into v_row;
  end if;
  insert into sub.policy_log (kind, key, before, after, by_user) values ('price_override', v_row.model, v_before, to_jsonb(v_row), p_by);
  return jsonb_build_object('ok', true, 'id', v_row.id, 'ver', sub.f_policy_ver());
end $$;

-- 매장 화면 RPC — 보기는 담당자 누구나, 고치기는 점장님·대표님
create or replace function public.fn_store_sub_price_list(p_code text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  return sub.f_price_override_view() || jsonb_build_object('me', v_me, 'can_edit', core.f_staff_is_mgr(v_me));
end $$;

create or replace function public.fn_store_sub_price_save(p_code text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not core.f_staff_is_mgr(v_me) then raise exception '구독 요금은 점장님·대표님만 고칠 수 있습니다' using errcode = '42501'; end if;
  return sub.f_price_override_save(p_data, v_me);
end $$;

-- 권한: 새 public 함수는 기본으로 anon 실행이 붙는다 — 담당자 코드로 막지만 sub.* 내부 함수는 닫는다
revoke all on function sub.f_price_override_live() from public, anon, authenticated;
revoke all on function sub.f_price_override_view() from public, anon, authenticated;
revoke all on function sub.f_price_override_save(jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_store_sub_price_list(text) to anon, authenticated;
grant execute on function public.fn_store_sub_price_save(text, jsonb) to anon, authenticated;
