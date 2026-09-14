-- mvp_132 · 2026-09-14
-- ① 휴가 종류(kind): 반차(오후 3시까지) · 휴무 · 교육 · 휴가 · 연차 · 매장휴무
--    매장휴무는 배정에 영향 없음(배정은 그대로 가고 휴무 뒤 순차 처리). 반차는 15:00 KST 전까지만 배정에서 빠짐.
-- ② 구독 문의 폼(GAS)이 골라 보낸 담당자가 휴가면 데이터센터가 다시 배정한다.
--    (원인: GAS 가 자기 순번으로 담당자를 정해 assignedStaff 로 보내고, fn_submit_inquiry 가 그대로 받아
--     handler 가 차 있으니 트리거 core.f_consult_assign_default 의 휴가 제외 로직이 아예 돌지 않았다 — 09/14 권혁찬 건)
--    재배정하면 notes 에 남기고 잔디(jandi_crm) 로 '휴가 재배정' 알림. 시트에서 담당자를 고쳐도 DB 담당자가 있으면 덮지 않는다.
begin;

alter table core.staff_leave add column if not exists kind text not null default '휴가';
alter table core.staff_leave drop constraint if exists staff_leave_kind_chk;
alter table core.staff_leave add constraint staff_leave_kind_chk
  check (kind in ('반차','휴무','교육','휴가','연차','매장휴무'));

create or replace function core.f_staff_on_leave(p_name text, p_on date default null)
returns boolean language sql stable set search_path to 'pg_catalog','public' as $$
  select exists (select 1 from core.staff_leave l
                  where l.staff_name = p_name
                    and coalesce(p_on, (now() at time zone 'Asia/Seoul')::date) between l.from_date and l.to_date
                    and l.kind <> '매장휴무'                                   -- 매장휴무는 배정 그대로
                    and (l.kind <> '반차' or (now() at time zone 'Asia/Seoul')::time < time '15:00'));   -- 반차 = 오후 3시까지
$$;

-- fn_store_leave_save : p_kind 추가 (옛 시그니처 drop → 새로 create → grant)
drop function if exists public.fn_store_leave_save(text, bigint, text, date, date, text);
create or replace function public.fn_store_leave_save(p_code text, p_id bigint, p_staff text, p_from date, p_to date, p_note text default null, p_kind text default '휴가')
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_id bigint; v_kind text := coalesce(nullif(btrim(p_kind),''), '휴가');
begin
  if v_me is null or not core.f_staff_is_mgr(v_me) then raise exception '점장·대표만 휴가를 넣을 수 있습니다' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_staff,'')),'') is null then raise exception '누구의 휴가인지 고르세요'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception '기간이 올바르지 않습니다'; end if;
  if v_kind not in ('반차','휴무','교육','휴가','연차','매장휴무') then raise exception '종류가 올바르지 않습니다: %', v_kind; end if;
  if p_id is null then
    insert into core.staff_leave(staff_name, from_date, to_date, note, created_by, kind) values (btrim(p_staff), p_from, p_to, nullif(btrim(p_note),''), v_me, v_kind) returning id into v_id;
  else
    update core.staff_leave set staff_name=btrim(p_staff), from_date=p_from, to_date=p_to, note=nullif(btrim(p_note),''), kind=v_kind where id=p_id returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'kind', v_kind);
end $$;
grant execute on function public.fn_store_leave_save(text, bigint, text, date, date, text, text) to anon, authenticated, service_role;

-- fn_store_leave_list : kind 내려주기 · '오늘 휴가' 에서 매장휴무 제외
do $outer$
declare v_src text; v_args text; v_n int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_store_leave_list';
  v_n := (length(v_src) - length(replace(v_src, $q$'note', l.note, 'by', l.created_by,$q$, ''))) / length($q$'note', l.note, 'by', l.created_by,$q$);
  if v_n <> 1 then raise exception 'leave_list 지점1 %개', v_n; end if;
  v_src := replace(v_src, $q$'note', l.note, 'by', l.created_by,$q$, $q$'note', l.note, 'kind', l.kind, 'by', l.created_by,$q$);
  v_n := (length(v_src) - length(replace(v_src, $q$where (now() at time zone 'Asia/Seoul')::date between l.from_date and l.to_date$q$, ''))) / length($q$where (now() at time zone 'Asia/Seoul')::date between l.from_date and l.to_date$q$);
  if v_n <> 1 then raise exception 'leave_list 지점2 %개', v_n; end if;
  v_src := replace(v_src, $q$where (now() at time zone 'Asia/Seoul')::date between l.from_date and l.to_date$q$,
                          $q$where (now() at time zone 'Asia/Seoul')::date between l.from_date and l.to_date and l.kind <> '매장휴무'$q$);
  execute format('create or replace function public.fn_store_leave_list(%s) returns jsonb language plpgsql stable security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;

-- fn_submit_inquiry : 휴가자면 재배정 + 기록 + 잔디 · 시트 수정으로는 DB 담당자를 덮지 않음
do $outer$
declare v_src text; v_args text; v_n int;
  a1 text := $q$v_hand := (select s.name from core.staff s where s.name = v_staff limit 1);$q$;
  b1 text := $q$v_hand := (select s.name from core.staff s where s.name = v_staff limit 1);
  /* 폼(GAS)이 고른 담당자가 휴가면 데이터센터가 다시 배정한다 (매장휴무·15시 지난 반차는 휴가로 안 봄) */
  if v_hand is not null and core.f_staff_on_leave(v_hand) then
    v_orig := v_hand;
    v_hand := core.f_assign_next('구독·렌탈', nullif(p_data->>'modelName',''));
  end if;$q$;
  a2 text := $q$handler = coalesce(excluded.handler, crm.consult.handler),$q$;
  b2 text := $q$handler = coalesce(crm.consult.handler, excluded.handler),$q$;
  a3 text := $q$returning id into v_id;$q$;
  b3 text := $q$returning id into v_id;
  if v_orig is not null then
    update crm.consult set notes = concat_ws(' / ', notes, '휴가 재배정 '||v_orig||' → '||coalesce(v_hand,'미배정')||' ('||to_char(now() at time zone 'Asia/Seoul','MM-DD HH24:MI')||')') where id = v_id;
    perform core.f_notify('consult.assign_leave', jsonb_build_object('orig', v_orig, 'handler', coalesce(v_hand,'미배정'), 'name', v_name,
      'phone', '***-'||right(v_phone,4), 'source', '구독 문의', 'ref', v_ref, 'model', coalesce(p_data->>'modelName','')));
  end if;$q$;
  a4 text := $q$v_hand text;$q$;
  b4 text := $q$v_hand text; v_orig text;$q$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_submit_inquiry';
  foreach v_n in array array[1,2,3,4] loop
    if (length(v_src)-length(replace(v_src, case v_n when 1 then a1 when 2 then a2 when 3 then a3 else a4 end, '')))
       / length(case v_n when 1 then a1 when 2 then a2 when 3 then a3 else a4 end) <> 1
    then raise exception 'submit_inquiry 지점% 이 1개가 아님', v_n; end if;
  end loop;
  v_src := replace(v_src, a1, b1); v_src := replace(v_src, a2, b2); v_src := replace(v_src, a3, b3); v_src := replace(v_src, a4, b4);
  execute format('create or replace function public.fn_submit_inquiry(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;

insert into core.notify_rule (code, label, event, channel_code, enabled, template, note, sort, color)
values ('assign_leave', '휴가 재배정', 'consult.assign_leave', 'jandi_crm', true,
  E'[휴가 재배정] {orig} 프로님이 휴가라 {handler} 프로님께 배정했습니다\n{source} · {name} ({phone}) · {model}\n[상담 열기](https://db.samsungat.co.kr/store.html)',
  '구독 문의 폼(GAS)이 고른 담당자가 휴가일 때 데이터센터가 다시 배정하고 알린다', 22, '#0F766E')
on conflict (code) do update set enabled = true, template = excluded.template, note = excluded.note, channel_code = excluded.channel_code;

commit;
