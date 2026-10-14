-- mvp_211 · 2026-10-14 · 문자 보내기 화면을 센드온 [문자보내기] 양식으로 (발신번호 고르기 · 광고/정보성 · 변수 · 연락처 3가지 · 문구 · 발송시간 · 미리보기 · 발송 요약)
--            + 발송 결과를 '발송 요청별' 로 묶어 보기 (fn_sms_batches · fn_sms_batch) · 예약에 발신번호 등 옵션(opt) 저장
-- 적용: 2026-10-14 (MCP execute_sql · 호출 여러 번으로 나눠서 — 함수 패치와 롤백 테스트는 같은 호출에 넣지 않는다)

-- ① 열 추가 — 보낸 발신번호를 줄마다 남기고, 예약은 보낼 때 쓸 옵션(발신번호 등)을 함께 둔다
alter table crm.sms_message  add column if not exists sender_no text;
alter table crm.sms_schedule add column if not exists opt jsonb;

-- ② core.f_sms_send — p_opt.sender (센드온에 등록·승인된 번호만) · 줄마다 sender_no · 응답 sender. 서버 본문을 읽어 지점만 치환
do $outer$
declare v_def text; v_oid oid; n int;
  rep text[][] := array[
    ['v_max int := coalesce(nullif(p_opt->>''max'','''')::int, 500);', 'v_max int := coalesce(nullif(p_opt->>''max'','''')::int, 500); v_from text;'],
    ['v_tel    := coalesce((select value from core.app_setting where key=''store_tel''),'''');',
     'v_tel    := coalesce((select value from core.app_setting where key=''store_tel''),'''');' || E'\n' ||
     '  v_from := regexp_replace(coalesce(nullif(p_opt->>''sender'',''''), c.sender_no, ''''), ''\D'', '''', ''g'');' || E'\n' ||
     '  if nullif(p_opt->>''sender'','''') is not null and v_from <> regexp_replace(coalesce(c.sender_no,''''),''\D'','''',''g'')' || E'\n' ||
     '     and not exists (select 1 from jsonb_array_elements(coalesce(c.last_check->''numbers'',''[]''::jsonb)) x where regexp_replace(x->>''number'',''\D'','''',''g'') = v_from and x->>''status'' = ''ACTIVE'') then' || E'\n' ||
     '    raise exception ''발신번호 % 는 센드온에 등록·승인된 번호가 아닙니다 — [연결 확인] 뒤 목록에서 고르세요'', v_from using errcode=''22023''; end if;'],
    ['''from'', regexp_replace(c.sender_no,''\D'','''',''g''),', '''from'', v_from,'],
    ['provider_group_id, sent_by)' || E'\n' || '  select v_batch', 'provider_group_id, sent_by, sender_no)' || E'\n' || '  select v_batch'],
    ['x->>''gid'', p_by' || E'\n' || '    from jsonb_array_elements(v_q) x;', 'x->>''gid'', p_by, v_from' || E'\n' || '    from jsonb_array_elements(v_q) x;'],
    ['''calls'', v_calls, ''groups'', v_groups,', '''calls'', v_calls, ''groups'', v_groups, ''sender'', v_from,']
  ];
  i int;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='core' and p.proname='f_sms_send';
  v_def := pg_get_functiondef(v_oid);
  for i in 1..array_length(rep,1) loop
    n := (length(v_def) - length(replace(v_def, rep[i][1], ''))) / length(rep[i][1]);
    if n <> 1 then raise exception 'f_sms_send 지점 % 개수 % (1 이어야)', i, n; end if;
    v_def := replace(v_def, rep[i][1], rep[i][2]);
  end loop;
  execute v_def;
end $outer$;

-- ③ 예약 — opt 저장 (옛 8인자 판은 이름만 바꿔 비켰다 · SQL 편집기에서 지울 것)
alter function public.fn_sms_schedule_save(timestamptz, jsonb, text, text, text, text, boolean, text) rename to fn_sms_schedule_save_old198;
create or replace function public.fn_sms_schedule_save(p_send_at timestamptz, p_rows jsonb, p_body text, p_title text default null, p_campaign text default null, p_kind text default 'manual', p_is_ad boolean default false, p_note text default null, p_opt jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_role text := core.f_role(); v_email text := (select p.email from public.profiles p where p.id = auth.uid()); v_id bigint; c core.sms_config%rowtype; v_n int; v_from text;
begin
  if v_role not in ('admin','staff') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into c from core.sms_config where id = 1;
  if not coalesce(c.enabled, false) then raise exception '문자 기능이 꺼져 있습니다 — 설정에서 켠 뒤 예약하세요' using errcode='22023'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception '받는 사람이 없습니다' using errcode='22023'; end if;
  v_n := jsonb_array_length(p_rows);
  if v_n = 0 then raise exception '받는 사람이 없습니다' using errcode='22023'; end if;
  if v_n > 500 then raise exception '예약 한 건에 500명까지 (지금 %명)', v_n using errcode='22023'; end if;
  if btrim(coalesce(p_body,'')) = '' then raise exception '보낼 내용이 없습니다' using errcode='22023'; end if;
  if p_send_at is null or p_send_at < now() + interval '1 minute' then raise exception '예약 시각은 지금부터 1분 뒤 이후여야 합니다' using errcode='22023'; end if;
  if p_send_at > now() + interval '90 days' then raise exception '예약은 90일 안으로' using errcode='22023'; end if;
  v_from := regexp_replace(coalesce(nullif(p_opt->>'sender',''),''), '\D', '', 'g');
  if v_from <> '' and v_from <> regexp_replace(coalesce(c.sender_no,''),'\D','','g')
     and not exists (select 1 from jsonb_array_elements(coalesce(c.last_check->'numbers','[]'::jsonb)) x where regexp_replace(x->>'number','\D','','g') = v_from and x->>'status' = 'ACTIVE') then
    raise exception '발신번호 % 는 센드온에 등록·승인된 번호가 아닙니다', v_from using errcode='22023'; end if;
  insert into crm.sms_schedule (send_at, rows, n, body, title, campaign, kind, is_ad, note, created_by, opt)
  values (p_send_at, p_rows, v_n, p_body, nullif(btrim(p_title),''), nullif(btrim(p_campaign),''), coalesce(nullif(p_kind,''),'manual'), coalesce(p_is_ad,false), nullif(btrim(p_note),''), coalesce(v_email,'admin'),
          case when v_from <> '' then jsonb_build_object('sender', v_from) else null end)
  returning id into v_id;
  insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), v_email, 'sms_schedule:save', v_n, coalesce(p_campaign, p_kind));
  return jsonb_build_object('id', v_id, 'send_at', p_send_at, 'n', v_n, 'mode_now', c.mode, 'sender', nullif(v_from,''));
end $$;
revoke all on function public.fn_sms_schedule_save(timestamptz, jsonb, text, text, text, text, boolean, text, jsonb) from public, anon;
grant execute on function public.fn_sms_schedule_save(timestamptz, jsonb, text, text, text, text, boolean, text, jsonb) to authenticated, service_role;

-- ④ 예약 실행이 opt 를 넘긴다 · 목록에 sender·batch_id
do $outer$
declare v_def text; v_oid oid; n int; a text; b text;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='core' and p.proname='f_sms_schedule_run';
  v_def := pg_get_functiondef(v_oid); a := 'jsonb_build_object(''timeout_ms'', ''8000'', ''max'', 500)'; b := 'coalesce(r.opt, ''{}''::jsonb) || jsonb_build_object(''timeout_ms'', ''8000'', ''max'', 500)';
  n := (length(v_def) - length(replace(v_def, a, ''))) / length(a); if n <> 1 then raise exception 'f_sms_schedule_run 지점 %', n; end if;
  execute replace(v_def, a, b);
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='fn_sms_schedule_list';
  v_def := pg_get_functiondef(v_oid); a := '''error'', s.error, ''note'', s.note)'; b := '''error'', s.error, ''note'', s.note, ''sender'', s.opt->>''sender'', ''batch_id'', s.result->>''batch_id'')';
  n := (length(v_def) - length(replace(v_def, a, ''))) / length(a); if n <> 1 then raise exception 'fn_sms_schedule_list 지점 %', n; end if;
  execute replace(v_def, a, b);
end $outer$;

-- ⑤ 발송 결과 · 발송 요청별 — 한 번의 [발송하기] = batch 하나 (crm.sms_message.batch_id) · 아직 안 보낸 예약(대기·실행 중·취소·실패)도 같은 목록에
create or replace function public.fn_sms_batches(p_q text default null, p_from date default null, p_to date default null, p_limit int default 50, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v_role text := core.f_role(); v_q text := nullif(btrim(coalesce(p_q,'')),''); v_total int; v_rows jsonb; v_sender text;
begin
  if v_role not in ('admin','staff') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select sender_no into v_sender from core.sms_config where id = 1;
  with b as (
    select m.batch_id, min(m.created_at) at, count(*) n,
           count(*) filter (where m.status='sent') sent, count(*) filter (where m.status='failed') failed, count(*) filter (where m.status='blocked') blocked, count(*) filter (where m.status='test') test,
           max(m.mode) mode, max(m.kind) kind, max(m.campaign) campaign, max(m.title) title, bool_or(m.is_ad) is_ad, max(m.sent_by) by,
           (array_agg(m.body order by m.id))[1] body, count(*) filter (where m.msg_type='LMS') lms, count(*) filter (where m.msg_type='SMS') sms,
           max(m.sender_no) sender, count(distinct m.provider_group_id) filter (where m.provider_group_id is not null) groups
      from crm.sms_message m group by m.batch_id),
  u as (
    select 'batch' src, b.batch_id, s.id sched_id, b.at, b.n, b.sent, b.failed, b.blocked, b.test, b.mode, b.kind, b.campaign, b.title, b.is_ad, b.by, b.body, b.lms, b.sms, b.groups,
           case when b.mode='test' then 'test' else 'done' end status, s.send_at sched_at, null::text error, coalesce(b.sender, v_sender) sender
      from b left join crm.sms_schedule s on s.result->>'batch_id' = b.batch_id::text
    union all
    select 'sched', null, s.id, s.created_at, s.n, 0, 0, 0, 0, null, s.kind, s.campaign, s.title, s.is_ad, s.created_by, s.body, 0, 0, 0, s.status, s.send_at, s.error, coalesce(s.opt->>'sender', v_sender)
      from crm.sms_schedule s where s.status <> 'done'),
  f as (
    select * from u
     where (v_q is null or u.body ilike '%'||v_q||'%' or coalesce(u.campaign,'') ilike '%'||v_q||'%' or coalesce(u.by,'') ilike '%'||v_q||'%' or coalesce(u.title,'') ilike '%'||v_q||'%')
       and (p_from is null or (u.at at time zone 'Asia/Seoul')::date >= p_from)
       and (p_to   is null or (u.at at time zone 'Asia/Seoul')::date <= p_to))
  select count(*), (select coalesce(jsonb_agg(jsonb_build_object(
            'src', f.src, 'batch_id', f.batch_id, 'sched_id', f.sched_id, 'at', to_char(f.at at time zone 'Asia/Seoul','YY-MM-DD HH24:MI:SS'), 'n', f.n,
            'sent', f.sent, 'failed', f.failed, 'blocked', f.blocked, 'test', f.test, 'mode', f.mode, 'kind', f.kind, 'campaign', f.campaign, 'title', f.title, 'is_ad', f.is_ad, 'by', f.by,
            'body', left(f.body, 200), 'type', case when f.lms >= f.sms and f.lms > 0 then 'LMS' when f.sms > 0 then 'SMS' when core.f_sms_bytes(f.body) > 90 then 'LMS' else 'SMS' end,
            'groups', f.groups, 'status', f.status, 'sched_at', to_char(f.sched_at at time zone 'Asia/Seoul','YY-MM-DD HH24:MI'), 'error', f.error, 'sender', f.sender) order by f.at desc), '[]'::jsonb)
          from (select * from f order by f.at desc limit least(greatest(coalesce(p_limit,50),1),300) offset greatest(coalesce(p_offset,0),0)) f)
    into v_total, v_rows from f;
  return jsonb_build_object('total', v_total, 'rows', v_rows, 'pending', (select count(*) from crm.sms_schedule where status='pending'));
end $$;
revoke all on function public.fn_sms_batches(text, date, date, int, int) from public, anon;
grant execute on function public.fn_sms_batches(text, date, date, int, int) to authenticated, service_role;

-- ⑥ 발송 결과 보기 — 요청 하나의 요약(전체·성공·실패·차단·테스트 · 종류별 · 예상 금액) · 예약 내역 · 받는 사람(500명까지 · 실명은 관리자만 + 감사로그)
create or replace function public.fn_sms_batch(p_batch uuid default null, p_sched bigint default null, p_unmask boolean default false)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_role text := core.f_role(); v_un boolean; v_batch uuid := p_batch; s crm.sms_schedule%rowtype; c core.sms_config%rowtype; v_costs jsonb; v_info jsonb; v_sum jsonb; v_rows jsonb; v_sched jsonb;
begin
  if v_role not in ('admin','staff') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v_un := coalesce(p_unmask,false) and v_role = 'admin';
  select * into c from core.sms_config where id = 1; v_costs := coalesce(c.last_check->'costs','{}'::jsonb);
  if p_sched is not null then
    select * into s from crm.sms_schedule where id = p_sched;
    if s.id is null then raise exception '예약 #% 가 없습니다', p_sched using errcode='22023'; end if;
    if v_batch is null and s.result->>'batch_id' is not null then v_batch := (s.result->>'batch_id')::uuid; end if;
  elsif v_batch is not null then
    select * into s from crm.sms_schedule where result->>'batch_id' = v_batch::text limit 1;
  end if;
  if v_batch is null and s.id is null then raise exception '발송 요청을 찾을 수 없습니다' using errcode='22023'; end if;
  if v_un and v_batch is not null then
    insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), (select p.email from public.profiles p where p.id = auth.uid()), 'sms_batch:unmask', (select count(*) from crm.sms_message where batch_id = v_batch), v_batch::text);
  end if;
  if s.id is not null then
    v_sched := jsonb_build_object('id', s.id, 'send_at', to_char(s.send_at at time zone 'Asia/Seoul','YY-MM-DD HH24:MI:SS'), 'n', s.n, 'status', s.status, 'by', s.created_by,
                                  'created_at', to_char(s.created_at at time zone 'Asia/Seoul','YY-MM-DD HH24:MI:SS'), 'run_at', to_char(s.run_at at time zone 'Asia/Seoul','YY-MM-DD HH24:MI:SS'),
                                  'error', s.error, 'note', s.note, 'sender', s.opt->>'sender', 'body', s.body, 'title', s.title, 'campaign', s.campaign, 'is_ad', s.is_ad, 'kind', s.kind);
  end if;
  if v_batch is not null then
    select jsonb_build_object('batch_id', m.batch_id, 'at', to_char(min(m.created_at) at time zone 'Asia/Seoul','YY-MM-DD HH24:MI:SS'), 'mode', max(m.mode), 'kind', max(m.kind), 'campaign', max(m.campaign),
             'title', max(m.title), 'is_ad', bool_or(m.is_ad), 'by', max(m.sent_by), 'body', (array_agg(m.body order by m.id))[1], 'bytes', (array_agg(m.bytes order by m.id))[1],
             'type', case when count(*) filter (where m.msg_type='LMS') >= count(*) filter (where m.msg_type='SMS') then 'LMS' else 'SMS' end,
             'sender', coalesce(max(m.sender_no), c.sender_no), 'groups', (select coalesce(jsonb_agg(distinct m2.provider_group_id), '[]'::jsonb) from crm.sms_message m2 where m2.batch_id = v_batch and m2.provider_group_id is not null)),
           jsonb_build_object('total', count(*), 'sent', count(*) filter (where m.status='sent'), 'failed', count(*) filter (where m.status='failed'), 'blocked', count(*) filter (where m.status='blocked'), 'test', count(*) filter (where m.status='test'),
             'lms', count(*) filter (where m.msg_type='LMS'), 'sms', count(*) filter (where m.msg_type='SMS'),
             'cost', round(coalesce(sum(case when m.status='sent' then coalesce((v_costs->>m.msg_type)::numeric, 0) end), 0), 1),
             'cost_est', round(coalesce(sum(coalesce((v_costs->>m.msg_type)::numeric, 0)), 0), 1),
             'reasons', (select coalesce(jsonb_agg(jsonb_build_object('reason', r.reason, 'n', r.n) order by r.n desc), '[]'::jsonb)
                           from (select coalesce(m3.block_reason, m3.provider_msg) reason, count(*) n from crm.sms_message m3 where m3.batch_id = v_batch and m3.status in ('failed','blocked') group by 1) r))
      into v_info, v_sum from crm.sms_message m where m.batch_id = v_batch group by m.batch_id;
    select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'name', case when v_un then m.name else coalesce(left(m.name,1)||'*','') end, 'phone', case when v_un then m.phone else core.f_sms_mask(m.phone) end,
             'status', m.status, 'type', m.msg_type, 'bytes', m.bytes, 'reason', coalesce(m.block_reason, m.provider_msg), 'gid', m.provider_group_id, 'at', to_char(m.created_at at time zone 'Asia/Seoul','HH24:MI:SS')) order by m.id), '[]'::jsonb)
      into v_rows from (select * from crm.sms_message where batch_id = v_batch order by id limit 500) m;
  end if;
  return jsonb_build_object('info', v_info, 'summary', v_sum, 'rows', coalesce(v_rows,'[]'::jsonb), 'schedule', v_sched, 'unmasked', v_un, 'costs', v_costs);
end $$;
revoke all on function public.fn_sms_batch(uuid, bigint, boolean) from public, anon;
grant execute on function public.fn_sms_batch(uuid, bigint, boolean) to authenticated, service_role;
