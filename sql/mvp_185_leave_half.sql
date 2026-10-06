-- mvp_185 · 2026-10-06 · 반차를 오전·오후로 나눈다 — 배정·알림 제외도 그 시간만
-- "휴무에 반차 오후인지, 오전인지 결정할 수 있게 · 오전 반차는 오후 2시까지 없는 거고 오후 반차는 오후 2시부터 없는 거야"
--
-- 전엔 반차 = 오후 3시 전까지 빠짐 하나뿐이었다.
-- 배정·잔디 알림의 휴가 제외는 전부 core.f_staff_on_leave 한 곳을 거친다
--   (core.f_assign_next 순번 · fn_submit_inquiry 휴가 재배정 · fn_store_leave_list '휴가 중').
-- 옛 반차 10건은 'am'(오전)으로 채웠다 — 전 규칙(오후까지 빠짐)과 가장 가깝다.

alter table core.staff_leave add column if not exists half text;
alter table core.staff_leave add constraint staff_leave_half_chk check (half is null or (kind='반차' and half in ('am','pm')));
update core.staff_leave set half='am' where kind='반차' and half is null;

create or replace function core.f_staff_on_leave(p_name text, p_on date default null::date)
 returns boolean language sql stable set search_path to 'pg_catalog','public'
as $function$
  /* 반차: 오전(am) = 오후 2시 전까지 없음 · 오후(pm) = 오후 2시부터 없음. 매장휴무는 배정 그대로 */
  select exists (select 1 from core.staff_leave l
                  where l.staff_name = p_name
                    and coalesce(p_on, (now() at time zone 'Asia/Seoul')::date) between l.from_date and l.to_date
                    and l.kind <> '매장휴무'
                    and (l.kind <> '반차'
                         or (coalesce(l.half,'am') = 'am' and (now() at time zone 'Asia/Seoul')::time <  time '14:00')
                         or (l.half = 'pm'                and (now() at time zone 'Asia/Seoul')::time >= time '14:00')));
$function$;

-- fn_store_leave_save 에 p_half 추가. MCP 는 DROP 에서 60초로 끊기므로(전부 롤백) 옛 판은 이름만 바꿔 비켜 두었다.
-- 지울 것 (SQL 편집기에서): drop function public.fn_store_leave_save_old184(text,bigint,text,date,date,text,text);
alter function public.fn_store_leave_save(text,bigint,text,date,date,text,text) rename to fn_store_leave_save_old184;
revoke all on function public.fn_store_leave_save_old184(text,bigint,text,date,date,text,text) from public, anon, authenticated;

create function public.fn_store_leave_save(p_code text, p_id bigint, p_staff text, p_from date, p_to date, p_note text default null::text, p_kind text default '휴가'::text, p_half text default null::text)
 returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public'
as $function$
declare v_me text := core.f_staff(p_code); v_id bigint; v_kind text := coalesce(nullif(btrim(p_kind),''), '휴가');
        v_half text := case when coalesce(nullif(btrim(p_kind),''),'휴가') = '반차' then coalesce(nullif(btrim(p_half),''),'am') end;
begin
  if v_me is null or not core.f_staff_is_mgr(v_me) then raise exception '점장·대표만 휴가를 넣을 수 있습니다' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_staff,'')),'') is null then raise exception '누구의 휴가인지 고르세요'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception '기간이 올바르지 않습니다'; end if;
  if v_kind not in ('반차','휴무','교육','휴가','연차','매장휴무') then raise exception '종류가 올바르지 않습니다: %', v_kind; end if;
  if v_half is not null and v_half not in ('am','pm') then raise exception '반차는 오전·오후 중 하나입니다'; end if;
  if p_id is null then
    insert into core.staff_leave(staff_name, from_date, to_date, note, created_by, kind, half) values (btrim(p_staff), p_from, p_to, nullif(btrim(p_note),''), v_me, v_kind, v_half) returning id into v_id;
  else
    update core.staff_leave set staff_name=btrim(p_staff), from_date=p_from, to_date=p_to, note=nullif(btrim(p_note),''), kind=v_kind, half=v_half where id=p_id returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'kind', v_kind, 'half', v_half);
end $function$;
revoke all on function public.fn_store_leave_save(text,bigint,text,date,date,text,text,text) from public;
grant execute on function public.fn_store_leave_save(text,bigint,text,date,date,text,text,text) to anon, authenticated, service_role;

-- 목록·캘린더 피드에 half · ICS 는 오전 09:00~14:00 · 오후 14:00~20:00 (제목 '이름 · 오전 반차/오후 반차')
do $o$ declare v text;
begin
  v := pg_get_functiondef('public.fn_store_leave_list(text)'::regprocedure);
  execute replace(v, '''kind'', l.kind, ''by''', '''kind'', l.kind, ''half'', l.half, ''by''');
  v := pg_get_functiondef('public.fn_leave_feed(text)'::regprocedure);
  execute replace(v, '''kind'', l.kind,', '''kind'', l.kind, ''half'', l.half,');
  v := pg_get_functiondef('public.fn_leave_ics(text)'::regprocedure);
  v := replace(v, 'select l.id, l.staff_name, l.from_date, l.to_date, l.kind,', 'select l.id, l.staff_name, l.from_date, l.to_date, l.kind, l.half,');
  v := replace(v, 'E''T000000Z', 'case when r.half=''pm'' then ''T050000Z'' else ''T000000Z'' end || E''');
  v := replace(v, 'E''T060000Z', 'case when r.half=''pm'' then ''T110000Z'' else ''T050000Z'' end || E''');
  v := replace(v, 'E'' · 반차', 'case when r.half=''pm'' then '' · 오후 반차'' else '' · 오전 반차'' end || E''');
  execute v;
end $o$;

-- 검증(롤백 블록, 14:21 KST): 오전 반차 → 배정 받음(on=f) · 오후 반차 → 빠짐(on=t) · 휴가에 p_half 를 줘도 null · 반차에 p_half 없으면 am
