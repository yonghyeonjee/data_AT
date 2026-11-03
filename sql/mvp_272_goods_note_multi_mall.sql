-- mvp_272 (2026-11-03) 상품 안내 문구 — 4몰 · 전체 몰 공통 / 몰별
-- "store에서 모든 몰을 수정할 수 있게 · s몰, at몰, p몰, sh몰 전체를 하거나 개별을 하거나 · 전체 몰에 공통 적용하거나, 각 몰 것만 적용하거나"
--   sub.mall 에 S몰(sm · www.samsungsmall.com) · AT몰(at · www.samsungat.com) 추가
--   sub.goods_note.malls text[] : 나갈 몰들 ('{*}' = 전체 몰 — 나중에 생기는 몰 포함). mall 칸은 첫 몰(옛 화면·FK 용)로 남긴다
--   권한: 문구의 몰이 모두 내 몰이어야 수정 · '전체 몰' 문구는 몰 제한이 없는 담당자만 (sub.staff_mall 이 '*' 이거나 줄이 없는 점장급)
--   목록·공개 함수·저장 함수는 이 판으로 통째로 바꾼다 (mvp_266~270 에서 만든 자기 함수들)

insert into sub.mall (code, name, domain, sort) values
  ('sm', 'S몰',  'www.samsungsmall.com', 30),
  ('at', 'AT몰', 'www.samsungat.com',    40)
on conflict (code) do nothing;

alter table sub.goods_note add column if not exists malls text[];
update sub.goods_note set malls = array[mall] where malls is null;
alter table sub.goods_note alter column malls set not null;
alter table sub.goods_note alter column malls set default '{pm}';
create index if not exists goods_note_malls_idx on sub.goods_note using gin (malls);

-- 이 몰 묶음을 이 담당자가 고칠 수 있나
create or replace function sub.f_gn_can_malls(p_name text, p_malls text[])
returns boolean language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select sub.f_gn_can(p_name)
     and case when '*' = any(p_malls)
              then not exists (select 1 from sub.staff_mall s where s.staff = p_name and not ('*' = any(s.malls)))
              else p_malls <@ sub.f_gn_malls(p_name) and cardinality(p_malls) > 0 end
$$;

create or replace function sub.f_goods_note_json(n sub.goods_note)
returns jsonb language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', n.id, 'mall', n.mall, 'malls', to_jsonb(n.malls), 'goods', to_jsonb(n.goods), 'models', to_jsonb(n.models), 'title', n.title, 'body', n.body, 'tone', n.tone,
    'btn', n.btn_label, 'url', n.btn_url, 'btnTone', n.btn_tone, 'pos', n.pos, 'scope', n.scope, 'img', n.img,
    'from', to_char(n.from_d,'YYYY-MM-DD'), 'to', to_char(n.to_d,'YYYY-MM-DD'), 'status', n.status, 'sort', n.sort, 'note', n.note))
$$;

-- 고도몰 상품상세(PC·모바일)가 부르는 공개 함수
create or replace function public.fn_goods_note(p_mall text, p_goods text default null, p_models text[] default '{}', p_test boolean default false)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', n.id, 'title', n.title, 'body', n.body, 'tone', n.tone, 'btn', n.btn_label, 'url', n.btn_url, 'btnTone', n.btn_tone, 'pos', n.pos, 'img', n.img,
           'test', case when n.status = 'test' then true end)) order by n.sort, n.id), '[]'::jsonb)
  from sub.goods_note n
  where (lower(coalesce(p_mall, 'pm')) = any(n.malls) or '*' = any(n.malls))
    and (n.status = 'on' or (n.status = 'test' and coalesce(p_test, false)))
    and (n.from_d is null or n.from_d <= (now() at time zone 'Asia/Seoul')::date)
    and (n.to_d   is null or n.to_d   >= (now() at time zone 'Asia/Seoul')::date)
    and (n.scope = 'all' or (p_goods is not null and btrim(p_goods) = any(n.goods))
      or n.models && (select coalesce(array_agg(upper(regexp_replace(x, '\s', '', 'g'))), '{}') from unnest(coalesce(p_models, '{}')) x))
$$;
grant execute on function public.fn_goods_note(text, text, text[], boolean) to anon, authenticated;

-- 매장: 목록 — 내 몰이 걸린 문구 + 전체 몰 문구 · 문구마다 고칠 수 있는지(can)
create or replace function public.fn_store_goods_note_list(p_code text)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_my text[];
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  v_my := sub.f_gn_malls(v_me);
  return jsonb_build_object(
    'can_edit', sub.f_gn_can(v_me),
    'can_all',  sub.f_gn_can_malls(v_me, '{*}'),
    'malls', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'domain', domain) order by sort, code), '[]'::jsonb) from sub.mall where code = any(v_my)),
    'notes', (select coalesce(jsonb_agg(sub.f_goods_note_json(n) || jsonb_build_object(
                'state', case when n.status = 'off' then 'off'
                              when n.to_d is not null and n.to_d < (now() at time zone 'Asia/Seoul')::date then 'ended'
                              when n.from_d is not null and n.from_d > (now() at time zone 'Asia/Seoul')::date then 'soon'
                              else n.status end,
                'can', sub.f_gn_can_malls(v_me, n.malls),
                'updated', to_char(n.updated_at at time zone 'Asia/Seoul', 'MM-DD HH24:MI'), 'by', n.updated_by)
              order by (n.status = 'off'), ('*' = any(n.malls)) desc, n.mall, n.sort, n.id desc), '[]'::jsonb)
              from sub.goods_note n
              where n.status <> 'gone' and ('*' = any(n.malls) or n.malls && v_my)));
end $$;
grant execute on function public.fn_store_goods_note_list(text) to anon, authenticated;

-- 매장: 저장 (새로 · 수정 · 상태만) — malls: ["*"] 또는 ["sh","pm",…] (옛 화면의 mall 하나도 받는다)
create or replace function public.fn_store_goods_note_save(p_code text, p_data jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_id bigint := nullif(p_data->>'id','')::bigint;
  v_goods text[]; v_models text[]; v_body text; v_scope text := case when p_data->>'scope' = 'all' then 'all' else 'goods' end;
  v_url text; v_label text; v_img text; v_malls text[]; v_old text[]; v_bad text;
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not sub.f_gn_can(v_me) then raise exception '상품 안내 문구를 수정할 권한이 없습니다' using errcode = '42501'; end if;
  if v_id is not null then
    select malls into v_old from sub.goods_note where id = v_id;
    if v_old is null then raise exception '문구를 찾지 못했습니다' using errcode = '22023'; end if;
    if not sub.f_gn_can_malls(v_me, v_old) then raise exception '이 문구가 걸린 몰을 모두 맡고 있지 않아 수정할 수 없습니다' using errcode = '42501'; end if;
  end if;
  -- 상태만 바꾸기 (공개 · test · 끄기 · 삭제)
  if v_id is not null and (select count(*) from jsonb_object_keys(p_data)) = 2 and p_data ? 'status' then
    update sub.goods_note set status = p_data->>'status', updated_at = now(), updated_by = v_me where id = v_id;
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;
  -- 몰
  if jsonb_typeof(p_data->'malls') = 'array' then
    select coalesce(array_agg(distinct lower(btrim(e)) order by lower(btrim(e))), '{}') into v_malls
      from jsonb_array_elements_text(p_data->'malls') e where btrim(e) <> '';
  elsif nullif(p_data->>'mall','') is not null then
    v_malls := array[lower(p_data->>'mall')];
  else
    v_malls := coalesce(v_old, '{}');
  end if;
  if '*' = any(v_malls) then v_malls := '{*}'; end if;
  if cardinality(v_malls) = 0 then raise exception '나갈 몰을 하나 이상 고르세요' using errcode = '22023'; end if;
  select string_agg(x, ', ') into v_bad from unnest(v_malls) x where x <> '*' and not exists (select 1 from sub.mall m where m.code = x);
  if v_bad is not null then raise exception '모르는 몰 코드: %', v_bad using errcode = '22023'; end if;
  if not sub.f_gn_can_malls(v_me, v_malls) then
    raise exception '%', case when v_malls = '{*}' then '전체 몰 문구는 모든 몰을 맡은 담당자만 저장할 수 있습니다' else '맡지 않은 몰이 들어 있습니다' end using errcode = '42501';
  end if;
  -- 대상 · 내용
  select coalesce(array_agg(distinct x order by x), '{}') into v_goods
    from (select regexp_replace(btrim(e), '[^0-9]', '', 'g') x from jsonb_array_elements_text(coalesce(p_data->'goods', '[]')) e) t where x <> '';
  select coalesce(array_agg(distinct x order by x), '{}') into v_models
    from (select upper(regexp_replace(btrim(e), '\s', '', 'g')) x from jsonb_array_elements_text(coalesce(p_data->'models', '[]')) e) t where x <> '';
  if v_scope = 'all' then v_goods := '{}'; v_models := '{}'; end if;
  v_body  := btrim(coalesce(p_data->>'body', ''));
  v_label := nullif(btrim(coalesce(p_data->>'btn', '')), '');
  v_url   := nullif(btrim(coalesce(p_data->>'url', '')), '');
  v_img   := nullif(btrim(coalesce(p_data->>'img', '')), '');
  if v_body = '' and v_img is null then raise exception '문구나 이미지 주소를 넣어 주세요' using errcode = '22023'; end if;
  if v_img is not null and v_img !~ '^https://' then raise exception '이미지 주소는 https:// 로 시작해야 합니다' using errcode = '22023'; end if;
  if v_scope <> 'all' and cardinality(v_goods) + cardinality(v_models) = 0 then raise exception '대상 상품번호나 모델번호를 하나 이상 넣어 주세요' using errcode = '22023'; end if;
  if (v_label is null) <> (v_url is null) then raise exception '버튼은 글자와 주소를 둘 다 넣어야 합니다' using errcode = '22023'; end if;
  if v_url is not null and v_url !~ '^(https?://|tel:|/)' then raise exception '버튼 주소는 https:// 또는 tel: 로 시작해야 합니다' using errcode = '22023'; end if;
  if v_id is null then
    insert into sub.goods_note (malls, mall, img, scope, goods, models, title, body, tone, btn_label, btn_url, btn_tone, pos, from_d, to_d, status, sort, note, updated_by)
    values (v_malls, case when v_malls = '{*}' then 'pm' else v_malls[1] end, v_img, v_scope, v_goods, v_models,
            nullif(btrim(coalesce(p_data->>'title','')),''), v_body,
            coalesce(nullif(p_data->>'tone',''), 'blue'), v_label, v_url, coalesce(nullif(p_data->>'btnTone',''), 'kakao'),
            coalesce(nullif(p_data->>'pos',''), 'price_below'), sub.f_date(p_data->>'from', '시작일'), sub.f_date(p_data->>'to', '종료일'),
            coalesce(nullif(p_data->>'status',''), 'test'), coalesce(nullif(p_data->>'sort','')::int, 100),
            nullif(btrim(coalesce(p_data->>'note','')),''), v_me)
    returning id into v_id;
  else
    update sub.goods_note set malls = v_malls, mall = case when v_malls = '{*}' then mall else v_malls[1] end,
           img = v_img, scope = v_scope, goods = v_goods, models = v_models,
           title = nullif(btrim(coalesce(p_data->>'title','')),''), body = v_body, tone = coalesce(nullif(p_data->>'tone',''), tone),
           btn_label = v_label, btn_url = v_url, btn_tone = coalesce(nullif(p_data->>'btnTone',''), btn_tone),
           pos = coalesce(nullif(p_data->>'pos',''), pos), from_d = sub.f_date(p_data->>'from', '시작일'), to_d = sub.f_date(p_data->>'to', '종료일'),
           status = coalesce(nullif(p_data->>'status',''), status), sort = coalesce(nullif(p_data->>'sort','')::int, sort),
           note = nullif(btrim(coalesce(p_data->>'note','')),''), updated_at = now(), updated_by = v_me
     where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
grant execute on function public.fn_store_goods_note_save(text, jsonb) to anon, authenticated;
