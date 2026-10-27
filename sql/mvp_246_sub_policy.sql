-- mvp_246 (2026-10-27) 구독 혜택 정책을 데이터센터에서 관리 — 상품상세 구독탭(goods_view)·계산기가 읽는 sub_policy.js 의 원본
-- 지금까지 코드에 고정돼 있던 자동납부 할인율 · 선납 할인율 · 품목별 선납 한도 · 카드 유의사항 · 행사 문구 · 안내 문구를 sub 스키마 표 3개에 둔다.
--   sub.policy       key → value(jsonb)   autopay · prepay · texts · card_notes
--   sub.card_policy  카드별 유의사항 · 노출 기간 · 숨김            (카드 금액표 자체는 SDP 판의 CARD — 여기서는 문구·기간만)
--   sub.promo        행사 문구 · 기간 · 대상(품목/모델/고도몰 상품번호)
--   sub.policy_log   누가 언제 무엇을 바꿨나 (앞·뒤 값)
-- 고치는 길
--   관리자(admin.html 품목 › 구독 혜택 정책)  fn_sub_policy · fn_sub_policy_save(수치·문구 전부) · fn_sub_card_policy_save · fn_sub_promo_save · fn_sub_promo_remove
--   매장(store.html 점장님·대표님)             fn_store_sub_policy(p_code) · fn_store_sub_promo_save · fn_store_sub_card_policy_save · fn_store_sub_text_save(card_notes·texts 만)
--   배포(GitHub Actions sdp-publish.yml)       fn_sub_policy_export() → sdp/sub/sub_policy.js  (publish.mjs · 10분마다 · 바뀐 것만 커밋) · fn_sub_policy_deployed
-- 검사 규칙은 tools/sub/build_sub.mjs(=고도몰 패키지 build_sub_index.py)와 같다 — 비율은 0 이상 1 미만 소수, 날짜는 YYYY-MM-DD, steps 마다 rates 가 있어야 한다.
-- 공개 파일이므로 제품가·인센티브·포인트 표 같은 내부 정보는 여기 넣지 않는다.

create table if not exists sub.policy (
  key        text primary key,                 -- autopay · prepay · texts · card_notes
  value      jsonb not null,
  note       text,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table if not exists sub.card_policy (
  card       text primary key,                 -- SDP CARD 의 카드 이름과 같아야 한다 (삼성카드 · 우리카드 …)
  notes      text[] not null default '{}',
  from_d     date,
  to_d       date,
  hidden     boolean not null default false,
  note       text,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table if not exists sub.promo (
  id         bigserial primary key,
  text       text not null,
  from_d     date,
  to_d       date,
  cats       text[] not null default '{}',     -- 비우면 전체 품목 (값은 sub_index.js cats 와 같은 이름: TV · 김치냉장고 …)
  models     text[] not null default '{}',     -- 비우면 전체 모델
  goods      text[] not null default '{}',     -- 비우면 전체 고도몰 상품번호
  active     boolean not null default true,    -- 끄면 화면에서 빠진다 (기록은 남긴다)
  sort       int  not null default 100,
  note       text,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table if not exists sub.policy_log (
  id      bigserial primary key,
  kind    text not null,                       -- policy · card · promo
  key     text not null,
  before  jsonb,
  after   jsonb,
  at      timestamptz not null default now(),
  by_user text
);
alter table sub.policy      enable row level security;
alter table sub.card_policy enable row level security;
alter table sub.promo       enable row level security;
alter table sub.policy_log  enable row level security;
revoke all on sub.policy, sub.card_policy, sub.promo, sub.policy_log from public, anon, authenticated;

-- 값 검사 — 틀리면 어디가 틀렸는지 한국어로 멈춘다 (화면이 그대로 보여준다)
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
  else
    raise exception '모르는 정책 키입니다: % (autopay · prepay · texts · card_notes)', p_key using errcode = '22023';
  end if;
end $$;

create or replace function sub.f_date(p text, p_where text) returns date
language plpgsql immutable as $$
begin
  if coalesce(p,'') = '' then return null; end if;
  if p !~ '^\d{4}-\d{2}-\d{2}$' then raise exception '%: 날짜는 YYYY-MM-DD 로 적어 주세요 (%)', p_where, p using errcode = '22023'; end if;
  return p::date;
end $$;

-- 저장 본체 (관리자·매장 둘 다 여기로)
create or replace function sub.f_policy_save(p_key text, p_value jsonb, p_by text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_old jsonb;
begin
  perform sub.f_policy_check(p_key, p_value);
  select value into v_old from sub.policy where key = p_key;
  insert into sub.policy (key, value, updated_by) values (p_key, p_value, p_by)
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  if v_old is distinct from p_value then
    insert into sub.policy_log (kind, key, before, after, by_user) values ('policy', p_key, v_old, p_value, p_by); end if;
  return jsonb_build_object('ok', true, 'key', p_key, 'changed', v_old is distinct from p_value);
end $$;

create or replace function sub.f_card_save(p_data jsonb, p_by text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_card text := btrim(coalesce(p_data->>'card','')); v_old jsonb; v_new jsonb;
        v_from date := sub.f_date(p_data->>'from', '카드 '||v_card||' 시작일'); v_to date := sub.f_date(p_data->>'to', '카드 '||v_card||' 종료일');
begin
  if v_card = '' then raise exception '카드 이름이 비었습니다' using errcode = '22023'; end if;
  if v_from is not null and v_to is not null and v_to < v_from then raise exception '카드 % 의 종료일이 시작일보다 앞입니다', v_card using errcode = '22023'; end if;
  select to_jsonb(c) - 'updated_at' - 'updated_by' into v_old from sub.card_policy c where c.card = v_card;
  insert into sub.card_policy (card, notes, from_d, to_d, hidden, note, updated_by)
  values (v_card,
          coalesce((select array_agg(btrim(x) order by o) from jsonb_array_elements_text(coalesce(p_data->'notes','[]'::jsonb)) with ordinality t(x, o) where btrim(x) <> ''), '{}'),
          v_from, v_to, coalesce((p_data->>'hidden')::boolean, false), nullif(btrim(coalesce(p_data->>'note','')),''), p_by)
  on conflict (card) do update set notes = excluded.notes, from_d = excluded.from_d, to_d = excluded.to_d, hidden = excluded.hidden,
                                  note = excluded.note, updated_by = excluded.updated_by, updated_at = now();
  select to_jsonb(c) - 'updated_at' - 'updated_by' into v_new from sub.card_policy c where c.card = v_card;
  if v_old is distinct from v_new then
    insert into sub.policy_log (kind, key, before, after, by_user) values ('card', v_card, v_old, v_new, p_by); end if;
  return jsonb_build_object('ok', true, 'card', v_card);
end $$;

-- 문장 목록(jsonb 배열) → 빈 줄을 뺀 text[]
create or replace function sub.f_arr(j jsonb) returns text[]
language sql immutable as $$
  select coalesce((select array_agg(btrim(x)) from jsonb_array_elements_text(case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end) x where btrim(x) <> ''), '{}');
$$;

create or replace function sub.f_promo_save(p_data jsonb, p_by text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_id bigint := nullif(p_data->>'id','')::bigint; v_old jsonb; v_new jsonb;
        v_text text := btrim(coalesce(p_data->>'text','')); v_from date := sub.f_date(p_data->>'from', '행사 시작일'); v_to date := sub.f_date(p_data->>'to', '행사 종료일');
        v_models text[] := coalesce((select array_agg(upper(x)) from unnest(sub.f_arr(p_data->'models')) x), '{}');
begin
  if v_text = '' then raise exception '행사 문구가 비었습니다' using errcode = '22023'; end if;
  if v_from is not null and v_to is not null and v_to < v_from then raise exception '행사 종료일이 시작일보다 앞입니다' using errcode = '22023'; end if;
  if v_id is not null then select to_jsonb(p) - 'updated_at' - 'updated_by' into v_old from sub.promo p where p.id = v_id; end if;
  if v_old is null then
    insert into sub.promo (text, from_d, to_d, cats, models, goods, active, sort, note, updated_by)
    values (v_text, v_from, v_to, sub.f_arr(p_data->'cats'), v_models, sub.f_arr(p_data->'goods'),
            coalesce((p_data->>'active')::boolean, true), coalesce((p_data->>'sort')::int, 100), nullif(btrim(coalesce(p_data->>'note','')),''), p_by)
    returning id into v_id;
  else
    update sub.promo set text = v_text, from_d = v_from, to_d = v_to, cats = sub.f_arr(p_data->'cats'),
           models = v_models, goods = sub.f_arr(p_data->'goods'),
           active = coalesce((p_data->>'active')::boolean, active), sort = coalesce((p_data->>'sort')::int, sort),
           note = nullif(btrim(coalesce(p_data->>'note','')),''), updated_by = p_by, updated_at = now()
     where id = v_id;
  end if;
  select to_jsonb(p) - 'updated_at' - 'updated_by' into v_new from sub.promo p where p.id = v_id;
  if v_old is distinct from v_new then
    insert into sub.policy_log (kind, key, before, after, by_user) values ('promo', v_id::text, v_old, v_new, p_by); end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- 정책 판 이름 = 마지막으로 바뀐 시각 (YYMMDD-HHMM · 서울) — 배포 파일 version.js 와 캐시 무효화에 쓴다 (f_policy_view 보다 먼저 있어야 한다)
create or replace function sub.f_policy_ver() returns text
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select to_char(coalesce(greatest((select max(updated_at) from sub.policy), (select max(updated_at) from sub.card_policy), (select max(updated_at) from sub.promo)), now())
                 at time zone 'Asia/Seoul', 'YYMMDD-HH24MI');
$$;

-- 화면용 읽기 (관리자·매장 공용 본체) — 지금 값 + 최근 바뀐 기록 + 배포 상태
create or replace function sub.f_policy_view() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object(
    'policy', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from sub.policy),
    'updated', (select coalesce(jsonb_object_agg(key, jsonb_build_object('at', to_char(updated_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'by', updated_by)), '{}'::jsonb) from sub.policy),
    'cards', (select coalesce(jsonb_agg(jsonb_build_object('card', card, 'notes', to_jsonb(notes), 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                 'hidden', hidden, 'note', note, 'updated', to_char(updated_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'by', updated_by) order by card), '[]'::jsonb) from sub.card_policy),
    'promos', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'text', text, 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                 'cats', to_jsonb(cats), 'models', to_jsonb(models), 'goods', to_jsonb(goods), 'active', active, 'sort', sort, 'note', note,
                 'state', case when not active then 'off' when from_d is not null and from_d > (now() at time zone 'Asia/Seoul')::date then 'soon'
                               when to_d is not null and to_d < (now() at time zone 'Asia/Seoul')::date then 'ended' else 'on' end,
                 'updated', to_char(updated_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'), 'by', updated_by) order by active desc, sort, id), '[]'::jsonb) from sub.promo),
    -- 행사 대상으로 고를 품목 = 반영된 SDP 판 DATA 의 품목 이름 (sub_index.js 의 cats 와 같다 · TV · 김치냉장고 …)
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

-- 행사 한 건을 f_promo_save 가 받는 모양으로 (부분만 보내면 나머지가 비워지므로, 끄기·되살리기는 이걸로 전체를 보낸다)
create or replace function sub.f_promo_json(p_id bigint) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object('id', id, 'text', text, 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                            'cats', to_jsonb(cats), 'models', to_jsonb(models), 'goods', to_jsonb(goods), 'active', active, 'sort', sort, 'note', note)
    from sub.promo where id = p_id;
$$;

-- 배포 파일 내용 = sub_tab.js 가 읽는 SUB_POLICY 그대로 (publish.mjs 가 service_role 로 부른다)
create or replace function sub.f_policy_export() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
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
               from sub.promo where active and (to_d is null or to_d >= (now() at time zone 'Asia/Seoul')::date - 1))));
$$;

-- ── 관리자 (아이디 로그인 · admin) ──
create or replace function public.fn_sub_policy() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select case when core.f_role() = 'anon' then null else sub.f_policy_view() end;
$$;
create or replace function public.fn_sub_policy_save(p_key text, p_value jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '정책 변경은 관리자만 할 수 있습니다' using errcode = '42501'; end if;
  return sub.f_policy_save(p_key, p_value, core.f_sdp_actor());
end $$;
create or replace function public.fn_sub_card_policy_save(p_data jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '카드 정책 변경은 관리자만 할 수 있습니다' using errcode = '42501'; end if;
  return sub.f_card_save(p_data, core.f_sdp_actor());
end $$;
create or replace function public.fn_sub_promo_save(p_data jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '행사 문구 변경은 관리자만 할 수 있습니다' using errcode = '42501'; end if;
  return sub.f_promo_save(p_data, core.f_sdp_actor());
end $$;
-- 행사는 지우지 않고 끈다 (active=false) — 기록이 남고 되살릴 수 있다
create or replace function public.fn_sub_promo_remove(p_id bigint) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '행사 문구 변경은 관리자만 할 수 있습니다' using errcode = '42501'; end if;
  return sub.f_promo_save(sub.f_promo_json(p_id) || jsonb_build_object('active', false), core.f_sdp_actor());
end $$;

-- ── 배포 (GitHub Actions · service_role) ──
create or replace function public.fn_sub_policy_export() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select case when core.f_role() <> 'admin' then null else sub.f_policy_export() end;
$$;
create or replace function public.fn_sub_policy_deployed(p_ver text, p_note text default null) returns jsonb
language sql security definer set search_path to 'pg_catalog','public' as $$
  insert into sdp.publish_log (release_id, ver, kind, by_user, note) values (null, p_ver, 'sub_deployed', 'github-actions', p_note)
  returning jsonb_build_object('ok', true, 'id', id);
$$;

-- ── 매장 (4자리 코드 · anon) — 보기는 누구나, 고치기는 점장님·대표님만 · 수치(할인율·선납 한도)는 관리자 전용 ──
create or replace function public.fn_store_sub_policy(p_code text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  return sub.f_policy_view() || jsonb_build_object('me', v_me, 'can_edit', core.f_staff_is_mgr(v_me));
end $$;
create or replace function public.fn_store_sub_promo_save(p_code text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not core.f_staff_is_mgr(v_me) then raise exception '행사 문구는 점장님·대표님만 고칠 수 있습니다' using errcode = '42501'; end if;
  return sub.f_promo_save(p_data, v_me);
end $$;
create or replace function public.fn_store_sub_card_policy_save(p_code text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not core.f_staff_is_mgr(v_me) then raise exception '카드 유의사항은 점장님·대표님만 고칠 수 있습니다' using errcode = '42501'; end if;
  return sub.f_card_save(p_data, v_me);
end $$;
create or replace function public.fn_store_sub_text_save(p_code text, p_key text, p_value jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not core.f_staff_is_mgr(v_me) then raise exception '안내 문구는 점장님·대표님만 고칠 수 있습니다' using errcode = '42501'; end if;
  if p_key not in ('card_notes', 'texts') then raise exception '매장에서는 문구(card_notes · texts)만 고칠 수 있습니다. 할인율·선납 한도는 관리자에게 요청해 주세요' using errcode = '42501'; end if;
  return sub.f_policy_save(p_key, p_value, v_me);
end $$;

revoke all on function public.fn_sub_policy(), public.fn_sub_policy_save(text, jsonb), public.fn_sub_card_policy_save(jsonb), public.fn_sub_promo_save(jsonb), public.fn_sub_promo_remove(bigint),
              public.fn_sub_policy_export(), public.fn_sub_policy_deployed(text, text),
              public.fn_store_sub_policy(text), public.fn_store_sub_promo_save(text, jsonb), public.fn_store_sub_card_policy_save(text, jsonb), public.fn_store_sub_text_save(text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.fn_sub_policy()                            to authenticated, service_role;
grant execute on function public.fn_sub_policy_save(text, jsonb)            to authenticated, service_role;
grant execute on function public.fn_sub_card_policy_save(jsonb)             to authenticated, service_role;
grant execute on function public.fn_sub_promo_save(jsonb)                   to authenticated, service_role;
grant execute on function public.fn_sub_promo_remove(bigint)                to authenticated, service_role;
grant execute on function public.fn_sub_policy_export()                     to service_role;
grant execute on function public.fn_sub_policy_deployed(text, text)         to service_role;
grant execute on function public.fn_store_sub_policy(text)                  to anon, authenticated, service_role;
grant execute on function public.fn_store_sub_promo_save(text, jsonb)       to anon, authenticated, service_role;
grant execute on function public.fn_store_sub_card_policy_save(text, jsonb) to anon, authenticated, service_role;
grant execute on function public.fn_store_sub_text_save(text, text, jsonb)  to anon, authenticated, service_role;

-- ── 처음 값 = 지금까지 코드에 고정돼 있던 정책 (고도몰 패키지 tools/sub_policy.json 과 같음) · 이미 있으면 건드리지 않는다 ──
insert into sub.policy (key, value, note, updated_by) values
('autopay', '{"rate":0.05,"label":"구독료 {rate} 할인 (자동납부)"}', '자동납부(자동이체) 등록 시 구독료 할인', 'mvp_246'),
('prepay',  '{"steps":[0.2,0.3,0.4,0.5],"rates":{"0.2":0.03,"0.3":0.04,"0.4":0.05,"0.5":0.05},"defaultMax":0.5,
             "maxByCat":{"에어컨":0.5,"시스템에어컨":0.5,"TV":0.5,"모니터":0.5,"냉장고":0.4,"김치냉장고":0.4,"청소기":0.4,"공기청정기":0.3,"정수기":0.3,"오디오":0.3,"의류케어":0.4,"조리기기":0.5},
             "maxByName":[{"cat":"의류케어","contains":"에어드레서","max":0.5},{"cat":"조리기기","contains":"후드","max":0.3}],
             "notes":["선납금은 구독 신청 시에만 선택할 수 있으며, 구독 기간 중에는 변경이 어렵습니다."]}', '선납 비율별 할인율 · 품목별 최대 선납 비율 (calc_subscribe 와 같음)', 'mvp_246'),
('texts',   '{"points":["목돈 없이 월 납부 · 약정 기간 동안 무상수리"],
             "notice":"* 월 구독료는 VAT 포함 기준이며, 카드 혜택은 카드사 조건(전월 실적·정기결제 등)에 따라 달라질 수 있습니다. 결제 예상액은 위 혜택을 모두 받았을 때의 예상 금액으로 실제 청구 금액과 다를 수 있습니다. 정확한 금액은 상담 시 안내해 드립니다."}', '혜택 목록 기본 문구 · 맨 아래 안내문', 'mvp_246'),
('card_notes', '["전월 이용실적 산정 기준과 제외 항목은 카드사 기준을 따릅니다.","카드 혜택은 카드사 사정에 따라 변경되거나 조기 종료될 수 있습니다."]', '모든 카드 공통 유의사항 (예시 문구 — 카드사 원문으로 바꿀 것)', 'mvp_246')
on conflict (key) do nothing;
insert into sub.card_policy (card, notes, note, updated_by) values
('삼성카드', array['구독료를 삼성카드로 자동결제 등록해야 청구할인이 적용됩니다.','70만원 이상 구간의 추가 캐시백은 월 구독료 7만원 이상일 때 적용됩니다.'], '예시 문구 — 카드사 원문으로 바꿀 것', 'mvp_246')
on conflict (card) do nothing;

-- 확인(롤백): 아래 적용 기록 참고. 본문은 서버에 있다 (이 파일은 기록).
