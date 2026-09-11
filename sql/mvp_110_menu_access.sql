/* ═══════════════════════════════════════════════════════════════
   MVP 110 · 계정별 메뉴 노출 (per-account menu visibility)

   설계
   - core.menu_access 는 "숨김 목록"(deny list) 이다. 행이 없으면 전부 보임.
     → 나중에 메뉴를 새로 추가해도 기존 계정에 자동으로 보인다 (허용목록이면 안 보임)
   - 개발 계정(core.f_is_dev)은 항상 전부 본다 — 잠김 방지
   - 'home' 은 숨길 수 없다
   - admin 권한 계정에서는 'settings'·'option' 을 숨길 수 없다 — 되돌릴 창구가 막히므로
   - 항목이 하나도 안 남은 그룹은 통째로 사라진다
   ═══════════════════════════════════════════════════════════════ */

create table if not exists core.menu_access(
  profile_id uuid not null references public.profiles(id) on delete cascade,
  menu_code  text not null,
  created_at timestamptz not null default now(),
  primary key (profile_id, menu_code)
);
comment on table core.menu_access is '계정별 숨김 메뉴 (행 = 숨김). 행이 없으면 전부 보임';

/* 잠김 방지 — 이 코드들은 admin 계정에서 숨길 수 없다 */
/* admin 계정에서 숨길 수 없는 메뉴 코드 (잠김 방지) */
insert into core.app_setting(key, value)
values ('menu_lock_codes','settings,option')
on conflict (key) do nothing;

/* ───────── fn_menu : 로그인한 계정의 숨김 목록을 걸러서 준다 ───────── */
create or replace function public.fn_menu(p_env text default 'prod')
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog','public' as $fn$
declare v_env text := case when p_env = 'test' then 'test' else 'prod' end;
        v_uid uuid := auth.uid();
        v_dev boolean;
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v_dev := coalesce(core.f_is_dev(), false);
  return (
    select coalesce(jsonb_agg(x.obj order by x.sort), '[]'::jsonb)
      from (
        select g.sort,
               jsonb_build_object('group', g.code, 'group_label', g.label,
                                  'group_state', g.state, 'items', it.items) obj
          from core.menu_group g
          cross join lateral (
            select coalesce(jsonb_agg(jsonb_build_object(
                     'code', i.code, 'label', i.label, 'state', i.state, 'note', i.note)
                     order by i.sort, i.label), '[]'::jsonb) items,
                   count(*) n
              from core.menu_item i
             where i.group_code = g.code
               and i.state <> 'off'
               and v_env = any(i.envs)
               and ( v_dev or i.code = 'home'
                     or not exists (select 1 from core.menu_access a
                                     where a.profile_id = v_uid and a.menu_code = i.code) )
          ) it
         where g.state <> 'off' and v_env = any(g.envs) and it.n > 0
      ) x);
end $fn$;

/* ───────── fn_menu_access(p_id) : 한 계정의 메뉴 체크 상태 ─────────
   반환 : { profile:{…}, groups:[ {code,label,items:[{code,label,state,hidden,locked}]} ] } */
create or replace function public.fn_menu_access(p_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','public' as $fn$
declare v_lock text[]; v_role text; v_dev boolean;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 볼 수 있습니다' using errcode='42501'; end if;
  select array(select btrim(x) from unnest(string_to_array(
           coalesce((select value from core.app_setting where key='menu_lock_codes'),'settings,option'), ',')) x
          where btrim(x) <> '') into v_lock;
  select p.role into v_role from public.profiles p where p.id = p_id;
  if v_role is null then raise exception '없는 계정입니다' using errcode='22023'; end if;
  select exists(select 1 from public.profiles p
                 where p.id = p_id and p.active and p.role='admin'
                   and lower(p.email) = any(select btrim(lower(x)) from unnest(string_to_array(
                         coalesce((select value from core.app_setting where key='dev_users'),''), ',')) x))
    into v_dev;

  return jsonb_build_object(
    'profile', (select jsonb_build_object('id',p.id,'email',p.email,'role',p.role,
                                          'handler_name',p.handler_name,'active',p.active,'is_dev',v_dev)
                  from public.profiles p where p.id = p_id),
    'hidden_n', (select count(*) from core.menu_access a where a.profile_id = p_id),
    'groups', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', g.code, 'label', g.label,
               'items', (select coalesce(jsonb_agg(jsonb_build_object(
                            'code', i.code, 'label', i.label, 'state', i.state,
                            'hidden', exists(select 1 from core.menu_access a
                                              where a.profile_id = p_id and a.menu_code = i.code),
                            'locked', (i.code = 'home') or (v_role = 'admin' and i.code = any(v_lock))
                          ) order by i.sort, i.label), '[]'::jsonb)
                          from core.menu_item i
                         where i.group_code = g.code and i.state <> 'off')
             ) order by g.sort), '[]'::jsonb)
        from core.menu_group g where g.state <> 'off')
  );
end $fn$;

/* ───────── fn_menu_access_save(p_id, p_hidden) : 숨김 목록 통째 교체 ───────── */
create or replace function public.fn_menu_access_save(p_id uuid, p_hidden text[])
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog','public' as $fn$
declare v_lock text[]; v_role text; v_keep text[]; v_drop text[];
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 바꿀 수 있습니다' using errcode='42501'; end if;
  select p.role into v_role from public.profiles p where p.id = p_id;
  if v_role is null then raise exception '없는 계정입니다' using errcode='22023'; end if;
  select array(select btrim(x) from unnest(string_to_array(
           coalesce((select value from core.app_setting where key='menu_lock_codes'),'settings,option'), ',')) x
          where btrim(x) <> '') into v_lock;

  /* 실제로 있는 메뉴 코드만 · home 은 언제나 제외 · admin 계정은 잠김 코드 제외 */
  select array(select distinct i.code from core.menu_item i
                where i.code = any(coalesce(p_hidden, '{}'::text[]))
                  and i.code <> 'home'
                  and not (v_role = 'admin' and i.code = any(v_lock)))
    into v_keep;
  select array(select x from unnest(coalesce(p_hidden,'{}'::text[])) x
                where x = 'home' or (v_role='admin' and x = any(v_lock)))
    into v_drop;

  delete from core.menu_access a where a.profile_id = p_id and not (a.menu_code = any(v_keep));
  insert into core.menu_access(profile_id, menu_code)
  select p_id, c from unnest(v_keep) c
  on conflict (profile_id, menu_code) do nothing;

  return jsonb_build_object('hidden', coalesce(array_length(v_keep,1),0),
                            'skipped', coalesce(v_drop,'{}'::text[]));
end $fn$;

grant execute on function public.fn_menu_access(uuid) to authenticated;
grant execute on function public.fn_menu_access_save(uuid, text[]) to authenticated;
