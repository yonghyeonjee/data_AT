-- mvp_266 (2026-11-03) 상품 안내 문구 — 특정 상품에만 자유 문구 + 작은 버튼 · 위치 선택 · 시험 공개
-- "공통 없이 특정 제품에 특정 문구를 자유롭게 남길 수만 있으면 돼 · 작은 버튼 · 위치를 정할 수 있나? 미리보기랑?"
--   sub.goods_note : 몰(sub.mall) · 대상 상품번호/모델번호(둘 중 하나는 꼭) · 제목 · 본문 · 색 · 버튼(글자·주소·색) · 위치 · 기간 · 상태
--     상태 status : test(주소 끝 &gnote=on 인 사람만 보임) · on(모두) · off(꺼짐)
--     위치 pos    : title_below 상품명 아래 · price_below 가격 아래 · benefit_above 혜택 상자 위 · benefit_below 혜택 상자 아래
--                   buy_above 구매 버튼 위 · pay_below 네이버페이 아래 · detail_top 상세정보 맨 위
--   공개(anon) fn_goods_note(p_mall, p_goods, p_models, p_test) — 고도몰 상품상세의 sdp/note/goods_note.js 가 부른다 (개인정보 없음)
--   매장 fn_store_goods_note_list(p_code) 보기 누구나 · fn_store_goods_note_save(p_code, p_data) 점장님·대표님

create table if not exists sub.goods_note (
  id          bigint generated always as identity primary key,
  mall        text not null default 'pm' references sub.mall(code),
  goods       text[] not null default '{}',     -- 고도몰 상품번호 (그 몰 번호)
  models      text[] not null default '{}',     -- 모델번호 (대문자 · 상품명/모델번호 칸에서 찾는다)
  title       text,
  body        text not null,
  tone        text not null default 'blue' check (tone in ('blue','red','gray','yellow')),
  btn_label   text,
  btn_url     text check (btn_url is null or btn_url ~ '^(https?://|tel:|/)'),
  btn_tone    text not null default 'kakao' check (btn_tone in ('kakao','blue','line')),
  pos         text not null default 'benefit_below'
              check (pos in ('title_below','price_below','benefit_above','benefit_below','buy_above','pay_below','detail_top')),
  from_d      date,
  to_d        date,
  status      text not null default 'test' check (status in ('test','on','off')),
  sort        integer not null default 100,
  note        text,
  updated_at  timestamptz not null default now(),
  updated_by  text,
  check (cardinality(goods) + cardinality(models) > 0),
  check (from_d is null or to_d is null or to_d >= from_d)
);
create index if not exists goods_note_goods_idx  on sub.goods_note using gin (goods);
create index if not exists goods_note_models_idx on sub.goods_note using gin (models);
alter table sub.goods_note enable row level security;

create or replace function sub.f_goods_note_json(n sub.goods_note)
returns jsonb language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', n.id, 'mall', n.mall, 'goods', to_jsonb(n.goods), 'models', to_jsonb(n.models), 'title', n.title, 'body', n.body, 'tone', n.tone,
    'btn', n.btn_label, 'url', n.btn_url, 'btnTone', n.btn_tone, 'pos', n.pos,
    'from', to_char(n.from_d,'YYYY-MM-DD'), 'to', to_char(n.to_d,'YYYY-MM-DD'), 'status', n.status, 'sort', n.sort, 'note', n.note))
$$;

-- 고도몰 상품상세가 부르는 공개 함수 — 이 상품에 지금 나갈 문구만 (본문·버튼만, 메모·작성자 없음)
create or replace function public.fn_goods_note(p_mall text, p_goods text default null, p_models text[] default '{}', p_test boolean default false)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', n.id, 'title', n.title, 'body', n.body, 'tone', n.tone, 'btn', n.btn_label, 'url', n.btn_url, 'btnTone', n.btn_tone, 'pos', n.pos,
           'test', case when n.status = 'test' then true end)) order by n.sort, n.id), '[]'::jsonb)
  from sub.goods_note n
  where n.mall = lower(coalesce(p_mall, 'pm'))
    and (n.status = 'on' or (n.status = 'test' and coalesce(p_test, false)))
    and (n.from_d is null or n.from_d <= (now() at time zone 'Asia/Seoul')::date)
    and (n.to_d   is null or n.to_d   >= (now() at time zone 'Asia/Seoul')::date)
    and ((p_goods is not null and btrim(p_goods) = any(n.goods))
      or n.models && (select coalesce(array_agg(upper(regexp_replace(x, '\s', '', 'g'))), '{}') from unnest(coalesce(p_models, '{}')) x))
$$;
grant execute on function public.fn_goods_note(text, text, text[], boolean) to anon, authenticated;

-- 매장 화면: 목록 (보기는 담당자 누구나 · 고치기는 점장님·대표님)
create or replace function public.fn_store_goods_note_list(p_code text)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_edit', core.f_staff_is_mgr(v_me),
    'malls', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'domain', domain) order by sort, code), '[]'::jsonb) from sub.mall),
    'notes', (select coalesce(jsonb_agg(sub.f_goods_note_json(n) || jsonb_build_object(
                'state', case when n.status = 'off' then 'off'
                              when n.to_d is not null and n.to_d < (now() at time zone 'Asia/Seoul')::date then 'ended'
                              when n.from_d is not null and n.from_d > (now() at time zone 'Asia/Seoul')::date then 'soon'
                              else n.status end,
                'updated', to_char(n.updated_at at time zone 'Asia/Seoul', 'MM-DD HH24:MI'), 'by', n.updated_by)
              order by (n.status = 'off'), n.mall, n.sort, n.id desc), '[]'::jsonb) from sub.goods_note n));
end $$;
grant execute on function public.fn_store_goods_note_list(text) to anon, authenticated;

-- 매장 화면: 저장 (새로 · 고치기 · 상태만 바꾸기) — 점장님·대표님
create or replace function public.fn_store_goods_note_save(p_code text, p_data jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_id bigint := nullif(p_data->>'id','')::bigint;
  v_goods text[]; v_models text[]; v_body text; v_url text; v_label text;
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not core.f_staff_is_mgr(v_me) then raise exception '상품 안내 문구는 점장님·대표님만 고칠 수 있습니다' using errcode = '42501'; end if;
  -- 상태만 바꾸기 (켜기·시험·끄기)
  if v_id is not null and (select count(*) from jsonb_object_keys(p_data)) = 2 and p_data ? 'status' then
    update sub.goods_note set status = p_data->>'status', updated_at = now(), updated_by = v_me where id = v_id;
    if not found then raise exception '문구를 찾지 못했습니다' using errcode = '22023'; end if;
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;
  select coalesce(array_agg(distinct x order by x), '{}') into v_goods
    from (select regexp_replace(btrim(e), '[^0-9]', '', 'g') x from jsonb_array_elements_text(coalesce(p_data->'goods', '[]')) e) t where x <> '';
  select coalesce(array_agg(distinct x order by x), '{}') into v_models
    from (select upper(regexp_replace(btrim(e), '\s', '', 'g')) x from jsonb_array_elements_text(coalesce(p_data->'models', '[]')) e) t where x <> '';
  v_body  := btrim(coalesce(p_data->>'body', ''));
  v_label := nullif(btrim(coalesce(p_data->>'btn', '')), '');
  v_url   := nullif(btrim(coalesce(p_data->>'url', '')), '');
  if v_body = '' then raise exception '문구를 적어 주세요' using errcode = '22023'; end if;
  if cardinality(v_goods) + cardinality(v_models) = 0 then raise exception '대상 상품번호나 모델번호를 하나 이상 넣어 주세요' using errcode = '22023'; end if;
  if (v_label is null) <> (v_url is null) then raise exception '버튼은 글자와 주소를 둘 다 넣어야 합니다' using errcode = '22023'; end if;
  if v_url is not null and v_url !~ '^(https?://|tel:|/)' then raise exception '버튼 주소는 https:// 또는 tel: 로 시작해야 합니다' using errcode = '22023'; end if;
  if v_id is null then
    insert into sub.goods_note (mall, goods, models, title, body, tone, btn_label, btn_url, btn_tone, pos, from_d, to_d, status, sort, note, updated_by)
    values (coalesce(nullif(p_data->>'mall',''), 'pm'), v_goods, v_models, nullif(btrim(coalesce(p_data->>'title','')),''), v_body,
            coalesce(nullif(p_data->>'tone',''), 'blue'), v_label, v_url, coalesce(nullif(p_data->>'btnTone',''), 'kakao'),
            coalesce(nullif(p_data->>'pos',''), 'benefit_below'), sub.f_date(p_data->>'from', '시작일'), sub.f_date(p_data->>'to', '종료일'),
            coalesce(nullif(p_data->>'status',''), 'test'), coalesce(nullif(p_data->>'sort','')::int, 100),
            nullif(btrim(coalesce(p_data->>'note','')),''), v_me)
    returning id into v_id;
  else
    update sub.goods_note set mall = coalesce(nullif(p_data->>'mall',''), mall), goods = v_goods, models = v_models,
           title = nullif(btrim(coalesce(p_data->>'title','')),''), body = v_body, tone = coalesce(nullif(p_data->>'tone',''), tone),
           btn_label = v_label, btn_url = v_url, btn_tone = coalesce(nullif(p_data->>'btnTone',''), btn_tone),
           pos = coalesce(nullif(p_data->>'pos',''), pos), from_d = sub.f_date(p_data->>'from', '시작일'), to_d = sub.f_date(p_data->>'to', '종료일'),
           status = coalesce(nullif(p_data->>'status',''), status), sort = coalesce(nullif(p_data->>'sort','')::int, sort),
           note = nullif(btrim(coalesce(p_data->>'note','')),''), updated_at = now(), updated_by = v_me
     where id = v_id;
    if not found then raise exception '문구를 찾지 못했습니다' using errcode = '22023'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
grant execute on function public.fn_store_goods_note_save(text, jsonb) to anon, authenticated;
