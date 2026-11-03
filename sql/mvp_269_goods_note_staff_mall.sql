-- mvp_269 (2026-11-03) 상품 안내 문구 — 담당자별로 보이는 몰
-- "store에서 최지영 프로는 시흥몰만 보이고 박은지 프로는 전체 몰이 다 보여야해"
--   sub.staff_mall(staff, malls) : 줄이 있으면 그 몰만 보이고 그 몰 문구를 고칠 수 있다 ('*' = 모든 몰)
--   줄이 없으면 전과 같다 — 모든 몰이 보이고, 고치기는 점장님·대표님(core.f_staff_is_mgr)만

create table if not exists sub.staff_mall (
  staff      text primary key,
  malls      text[] not null,
  note       text,
  updated_at timestamptz not null default now()
);
alter table sub.staff_mall enable row level security;

insert into sub.staff_mall (staff, malls, note) values
  ('최지영', '{sh}', '시흥몰만'),
  ('박은지', '{*}',  '모든 몰')
on conflict (staff) do update set malls = excluded.malls, note = excluded.note, updated_at = now();

-- 이 담당자에게 보이는 몰 코드
create or replace function sub.f_gn_malls(p_name text)
returns text[] language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce(array_agg(m.code order by m.sort, m.code), '{}')
  from sub.mall m
  where not exists (select 1 from sub.staff_mall s where s.staff = p_name)
     or exists (select 1 from sub.staff_mall s where s.staff = p_name and ('*' = any(s.malls) or m.code = any(s.malls)))
$$;
-- 고칠 수 있나 (p_mall 을 주면 그 몰까지)
create or replace function sub.f_gn_can(p_name text, p_mall text default null)
returns boolean language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select (core.f_staff_is_mgr(p_name) or exists (select 1 from sub.staff_mall s where s.staff = p_name))
     and (p_mall is null or p_mall = any(sub.f_gn_malls(p_name)))
$$;

-- 목록·저장 함수 점 고치기 — 고칠 곳이 정확히 1곳일 때만
do $$
declare v_src text; v_new text; a text[]; i int;
begin
  select pg_get_functiondef('public.fn_store_goods_note_list(text)'::regprocedure) into v_src;
  v_new := v_src;
  a := array[
    $q$'can_edit', core.f_staff_is_mgr(v_me),$q$, $q$'can_edit', sub.f_gn_can(v_me),$q$,
    $q$order by sort, code), '[]'::jsonb) from sub.mall),$q$, $q$order by sort, code), '[]'::jsonb) from sub.mall where code = any(sub.f_gn_malls(v_me))),$q$,
    $q$'[]'::jsonb) from sub.goods_note n));$q$, $q$'[]'::jsonb) from sub.goods_note n where n.mall = any(sub.f_gn_malls(v_me))));$q$];
  for i in 1..array_length(a,1) by 2 loop
    if (length(v_new) - length(replace(v_new, a[i], ''))) / length(a[i]) <> 1 then raise exception 'list 고칠 곳 %', a[i]; end if;
    v_new := replace(v_new, a[i], a[i+1]);
  end loop;
  execute v_new;

  select pg_get_functiondef('public.fn_store_goods_note_save(text, jsonb)'::regprocedure) into v_src;
  a := array[
    $q$if not core.f_staff_is_mgr(v_me) then raise exception '상품 안내 문구는 점장님·대표님만 고칠 수 있습니다' using errcode = '42501'; end if;$q$,
    $q$if not sub.f_gn_can(v_me) then raise exception '상품 안내 문구를 고칠 권한이 없습니다' using errcode = '42501'; end if;
  if (v_id is not null and not sub.f_gn_can(v_me, (select n.mall from sub.goods_note n where n.id = v_id)))
     or (p_data ? 'mall' and not sub.f_gn_can(v_me, coalesce(nullif(p_data->>'mall',''), 'pm')))
     or (v_id is null and not sub.f_gn_can(v_me, coalesce(nullif(p_data->>'mall',''), 'pm'))) then
    raise exception '이 몰의 상품 안내 문구는 고칠 수 없습니다' using errcode = '42501';
  end if;$q$];
  if (length(v_src) - length(replace(v_src, a[1], ''))) / length(a[1]) <> 1 then raise exception 'save 고칠 곳'; end if;
  execute replace(v_src, a[1], a[2]);
end $$;
