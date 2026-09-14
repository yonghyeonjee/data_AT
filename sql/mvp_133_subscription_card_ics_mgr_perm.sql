-- mvp_133 · 2026-09-14 (세 가지, 모두 DB 에 적용 완료)
-- ① 구독 문의 접수 카드를 데이터센터가 보낸다 (규칙 inquiry_subscription · 기본 꺼짐).
--    GAS 의 sendJandiNotification 을 끈 뒤 이 규칙을 켜면 카드가 한 장만 간다. 담당자는 휴가 재배정 뒤 최종값, 재배정이면 담당자 줄에 표시.
--    assign_leave 규칙(mvp_132)은 여기에 합쳐서 껐다.
-- ② 휴가 달력 → 구글 캘린더 구독(ICS): core.api_key 'leave_ics' + public.fn_leave_ics(p_key) (service_role 만) + Edge Function leave-ics (verify_jwt=false, ?k=토큰).
--    토큰은 _secrets.local.md 에만. 구글 캘린더 › 다른 캘린더 › URL 로 추가.
-- ③ 점장 권한을 관리자 권한 표에서: core.perm_def 'mgr'(기본 꺼짐), core.f_staff_is_mgr = 옛 규칙(직함·부서) OR f_has_perm('mgr'), fn_staff_perms 에 auto_mgr.

-- ① fn_submit_inquiry: 새로 넣은 건(xmax=0)일 때만 접수 카드
do $outer$
declare v_src text; v_args text; v_n int;
  a1 text := $q$returning id into v_id;$q$;
  b1 text := $q$returning id, (xmax = 0) into v_id, v_new;
  /* 접수 카드 한 장 — GAS 카드 대신 데이터센터가 보낸다 (규칙 inquiry_subscription, 재배정이면 담당자 줄에 표시) */
  if v_new then
    perform core.f_notify('inquiry.subscription', jsonb_build_object(
      'name', v_name, 'phone', regexp_replace(v_phone, '^(\d{3})(\d{3,4})(\d{4})$', '\1-\2-\3'),
      'handler', coalesce(v_hand, '미배정'),
      'reassign', case when v_orig is not null then ' (' || v_orig || ' 프로님 휴가 → 재배정)' else '' end,
      'detail', concat_ws(' | ',
        nullif(concat_ws(' · ', nullif(p_data->>'modelName',''), nullif(p_data->>'inquiryType','')), ''),
        nullif(concat(coalesce(p_data->>'region',''), case when nullif(p_data->>'contactMethod','') is not null then '(' || (p_data->>'contactMethod') || ')' end), ''),
        nullif(concat_ws(' · ', nullif(p_data->>'existingSubscription',''), nullif(p_data->>'membershipStatus',''), nullif(p_data->>'prepayIntent','')), '')),
      'ref', v_ref));
  end if;$q$;
  a2 text := $q$v_hand text; v_orig text;$q$;
  b2 text := $q$v_hand text; v_orig text; v_new boolean;$q$;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_submit_inquiry';
  v_n := (length(v_src)-length(replace(v_src,a1,'')))/length(a1); if v_n <> 1 then raise exception '지점1 %개', v_n; end if;
  v_n := (length(v_src)-length(replace(v_src,a2,'')))/length(a2); if v_n <> 1 then raise exception '지점2 %개', v_n; end if;
  v_src := replace(replace(v_src, a1, b1), a2, b2);
  execute format('create or replace function public.fn_submit_inquiry(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;

insert into core.notify_rule (code, label, event, channel_code, enabled, template, connect, note, sort, color)
values ('inquiry_subscription', '구독 문의 접수', 'inquiry.subscription', 'jandi_crm', false,
  '📋 구독상담 · {name} ({phone})',
  '[{"title":"👤 배정 담당자","description":"{handler} 프로님{reassign}"},{"title":"📦 상담 정보","description":"{detail}"},{"title":"📝 상담 처리","description":"[상담 확인하러가기](https://db.samsungat.co.kr/store)"}]'::jsonb,
  '구독 문의 폼 접수 카드. GAS 의 sendJandiNotification 을 끄고 이 규칙을 켜면 카드가 한 장만 간다 (담당자는 휴가 재배정 뒤 최종값)', 6, '#0F766E')
on conflict (code) do update set template = excluded.template, connect = excluded.connect, note = excluded.note, channel_code = excluded.channel_code;
update core.notify_rule set enabled = false, note = note || ' — 2026-09-14 접수 카드(inquiry_subscription)에 합쳐서 끔' where code = 'assign_leave';

-- ② ICS
insert into core.api_key (name, key_hash, note) values ('leave_ics', '<SHA-256 of token — 실제 값은 DB 에만>', '휴가 달력 구글 캘린더 구독(ICS) 주소의 k= 값 (Edge Function leave-ics)')
on conflict (name) do nothing;
create or replace function public.fn_leave_ics(p_key text)
returns text language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v text; r record; esc_ics text;
begin
  if not core.f_api_ok('leave_ics', p_key) then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v := E'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//삼성앤텍 데이터센터//휴가//KO\r\nCALSCALE:GREGORIAN\r\nMETHOD:PUBLISH\r\n'
     || E'X-WR-CALNAME:삼성스토어 시흥 · 휴가\r\nX-WR-TIMEZONE:Asia/Seoul\r\nX-PUBLISHED-TTL:PT1H\r\nREFRESH-INTERVAL;VALUE=DURATION:PT1H\r\n';
  for r in select l.id, l.staff_name, l.from_date, l.to_date, l.kind, l.note, l.created_at
             from core.staff_leave l where l.to_date >= (now() at time zone 'Asia/Seoul')::date - 400 order by l.from_date, l.id loop
    esc_ics := regexp_replace(regexp_replace(coalesce(r.note,''), '\\', '\\\\', 'g'), '([,;])', '\\\1', 'g');
    v := v || E'BEGIN:VEVENT\r\n'
      || 'UID:leave-' || r.id || E'@db.samsungat.co.kr\r\n'
      || 'DTSTAMP:' || to_char(coalesce(r.created_at, now()) at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"') || E'\r\n'
      || 'DTSTART;VALUE=DATE:' || to_char(r.from_date, 'YYYYMMDD') || E'\r\n'
      || 'DTEND;VALUE=DATE:' || to_char(r.to_date + 1, 'YYYYMMDD') || E'\r\n'
      || 'SUMMARY:' || case when r.kind = '매장휴무' then '매장휴무' else regexp_replace(r.staff_name, '([,;])', '\\\1', 'g') || ' · ' || r.kind end
      || case when r.kind = '반차' then ' (오후 3시까지)' else '' end || E'\r\n'
      || case when esc_ics <> '' then 'DESCRIPTION:' || esc_ics || E'\r\n' else '' end
      || 'CATEGORIES:' || r.kind || E'\r\n'
      || E'TRANSP:TRANSPARENT\r\nEND:VEVENT\r\n';
  end loop;
  return v || E'END:VCALENDAR\r\n';
end $$;
revoke all on function public.fn_leave_ics(text) from public, anon, authenticated;
grant execute on function public.fn_leave_ics(text) to service_role;
-- Edge Function leave-ics (Deno) 는 tools/edge/leave-ics.ts 참고 — Supabase MCP deploy_edge_function 으로 올렸다 (verify_jwt=false)

-- ③ 점장 권한
insert into core.perm_def (code, label, note, default_on, scope, sort)
values ('mgr', '점장 권한', '배정 · 휴가 입력 · 담당자별 현황 · 남의 상담 열기. 직함이 점장·대표면 자동으로 켜져 있고 여기서는 추가로 줄 사람만 켠다', false, 'store', 5)
on conflict (code) do update set label = excluded.label, note = excluded.note, sort = excluded.sort;
create or replace function core.f_staff_is_mgr(p_name text) returns boolean
language sql stable set search_path to 'pg_catalog','public' as $$
  select exists (select 1 from core.staff s where s.name = p_name and s.active
                   and (coalesce(s.role_note,'') in ('점장','대표','전체') or coalesce(s.dept,'') in ('대표','전체') or replace(coalesce(s.dept,''),' ','') = '개발'))
      or core.f_has_perm(p_name, 'mgr');
$$;
-- fn_staff_perms: 각 직원에 auto_mgr (직함·부서로 자동인지) 추가 — 관리자 권한 표에서 잠긴 체크로 보임
