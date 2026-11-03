-- mvp_271 (2026-11-03) 스마트 패키지 안내 카드 — 매장에서 몰 담당자가 문구·버튼·켜기/끄기 관리
-- "시흥몰 관리자가 이거 관리할 수 있게 해주라니까"
--   포인트표(판 · 대상 모델)는 그대로 관리자 /admin/spkg/ → sdp/spkg/data.js
--   카드 문구 · 상담 버튼 · 전화 · 켜기/끄기 · 숨길 상품 · 더할 상품은 sub.spkg_conf (몰마다 한 줄) → sdp/spkg/spkg.js 가 fn_spkg_conf 로 읽는다
--   빈 칸(null)은 원래 문구 그대로. 문구 안 {min} = '2품목 10만P' 같은 첫 단계 · {max} = 최대 포인트 · **굵게** · !!빨강!!
--   보기·저장 권한은 상품 안내 문구와 같다 (sub.f_gn_malls / sub.f_gn_can)

create table if not exists sub.spkg_conf (
  mall        text primary key references sub.mall(code),
  is_on       boolean not null default true,
  tag         text,
  msg         text,
  sub         text,
  btn         text,
  ask_url     text check (ask_url is null or ask_url ~ '^(https?://|/)'),
  tel         text,
  hide_goods  text[] not null default '{}',
  extra_goods text[] not null default '{}',
  updated_at  timestamptz not null default now(),
  updated_by  text
);
alter table sub.spkg_conf enable row level security;
insert into sub.spkg_conf (mall, updated_by) values ('sh', 'mvp_271') on conflict (mall) do nothing;

create or replace function sub.f_spkg_conf_json(c sub.spkg_conf)
returns jsonb language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object('mall', c.mall, 'on', c.is_on, 'tag', c.tag, 'msg', c.msg, 'sub', c.sub, 'btn', c.btn,
    'ask', c.ask_url, 'tel', c.tel, 'hide', to_jsonb(c.hide_goods), 'extra', to_jsonb(c.extra_goods)))
$$;

-- 고도몰 상품상세 spkg.js 가 부르는 공개 함수 (개인정보 없음)
create or replace function public.fn_spkg_conf(p_mall text default 'sh')
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce((select sub.f_spkg_conf_json(c) from sub.spkg_conf c where c.mall = lower(coalesce(p_mall, 'sh'))), '{}'::jsonb)
$$;
grant execute on function public.fn_spkg_conf(text) to anon, authenticated;

-- 매장: 내 몰의 카드 설정 목록
create or replace function public.fn_store_spkg_conf_list(p_code text)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  return jsonb_build_object('can_edit', sub.f_gn_can(v_me),
    'items', (select coalesce(jsonb_agg(sub.f_spkg_conf_json(c) || jsonb_build_object(
                'name', m.name, 'domain', m.domain, 'updated', to_char(c.updated_at at time zone 'Asia/Seoul', 'MM-DD HH24:MI'), 'by', c.updated_by)
              order by m.sort, m.code), '[]'::jsonb)
              from sub.spkg_conf c join sub.mall m on m.code = c.mall
              where c.mall = any(sub.f_gn_malls(v_me))));
end $$;
grant execute on function public.fn_store_spkg_conf_list(text) to anon, authenticated;

-- 매장: 저장 ({mall, on} 만 오면 켜기/끄기만)
create or replace function public.fn_store_spkg_conf_save(p_code text, p_data jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_mall text := lower(coalesce(nullif(p_data->>'mall',''), 'sh'));
  v_hide text[]; v_extra text[]; v_ask text;
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not sub.f_gn_can(v_me, v_mall) then raise exception '이 몰의 스마트 패키지 안내는 수정할 수 없습니다' using errcode = '42501'; end if;
  if not exists (select 1 from sub.spkg_conf where mall = v_mall) then raise exception '이 몰에는 스마트 패키지 안내가 없습니다' using errcode = '22023'; end if;
  if (select count(*) from jsonb_object_keys(p_data)) = 2 and p_data ? 'on' then
    update sub.spkg_conf set is_on = (p_data->>'on')::boolean, updated_at = now(), updated_by = v_me where mall = v_mall;
    return jsonb_build_object('ok', true);
  end if;
  select coalesce(array_agg(distinct x order by x), '{}') into v_hide
    from (select regexp_replace(e, '[^0-9]', '', 'g') x from jsonb_array_elements_text(coalesce(p_data->'hide', '[]')) e) t where x <> '';
  select coalesce(array_agg(distinct x order by x), '{}') into v_extra
    from (select regexp_replace(e, '[^0-9]', '', 'g') x from jsonb_array_elements_text(coalesce(p_data->'extra', '[]')) e) t where x <> '';
  v_ask := nullif(btrim(coalesce(p_data->>'ask','')), '');
  if v_ask is not null and v_ask !~ '^(https?://|/)' then raise exception '상담 버튼 주소는 https:// 또는 / 로 시작해야 합니다' using errcode = '22023'; end if;
  update sub.spkg_conf set
    is_on = coalesce((p_data->>'on')::boolean, is_on),
    tag = nullif(btrim(coalesce(p_data->>'tag','')), ''), msg = nullif(btrim(coalesce(p_data->>'msg','')), ''),
    sub = nullif(btrim(coalesce(p_data->>'sub','')), ''), btn = nullif(btrim(coalesce(p_data->>'btn','')), ''),
    ask_url = v_ask, tel = nullif(btrim(coalesce(p_data->>'tel','')), ''),
    hide_goods = v_hide, extra_goods = v_extra, updated_at = now(), updated_by = v_me
  where mall = v_mall;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.fn_store_spkg_conf_save(text, jsonb) to anon, authenticated;
