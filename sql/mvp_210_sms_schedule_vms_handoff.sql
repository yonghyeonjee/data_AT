-- mvp_210 (2026-10-14) ① VMS 대시보드 타일 → 발송 대상 추출 · 수동 (예상재구매일 창 인자) ② 관리자 문자 보내기·테스트·예약
-- 적용됨 (MCP · 2026-10-14). 아래는 기록용.

-- ① fn_crm_targets_v2 에 p_due_lo / p_due_hi (재구매 주기 기준의 예상재구매일 창 · 기본 -30 ~ +14 그대로)
--    옛 판은 DROP 대신 이름만 바꿔 비켰다(MCP 는 drop 에서 60초로 끊긴다) → SQL 편집기에서 drop function public.fn_crm_targets_v2_old196(...);
alter function public.fn_crm_targets_v2(p_reason text, p_q text, p_channel text, p_category text, p_region text, p_kind text, p_from date, p_to date, p_min_cnt integer, p_min_net numeric, p_dormant_days integer, p_next_only boolean, p_no_send_days integer, p_sort text, p_limit integer, p_offset integer, p_unmask boolean, p_export boolean, p_basis text, p_product text, p_asof date) rename to fn_crm_targets_v2_old196;
do $outer$
declare v_src text; v_args text; v_n int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p where p.proname='fn_crm_targets_v2_old196' and p.pronamespace='public'::regnamespace;
  v_n := (length(v_src) - length(replace(v_src, 'between -30 and 14', ''))) / length('between -30 and 14');
  if v_n <> 1 then raise exception '지점 %개', v_n; end if;
  v_src := replace(v_src, 'between -30 and 14', 'between coalesce(p_due_lo, -30) and coalesce(p_due_hi, 14)');
  execute format('create function public.fn_crm_targets_v2(%s, p_due_lo integer default null, p_due_hi integer default null) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
revoke all on function public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,integer,numeric,integer,boolean,integer,text,integer,integer,boolean,boolean,text,text,date,integer,integer) from public, anon;
grant execute on function public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,integer,numeric,integer,boolean,integer,text,integer,integer,boolean,boolean,text,text,date,integer,integer) to authenticated, service_role;
revoke all on function public.fn_crm_targets_v2_old196(text,text,text,text,text,text,date,date,integer,numeric,integer,boolean,integer,text,integer,integer,boolean,boolean,text,text,date) from public, anon, authenticated;

-- ② 예약 문자 — 매분 cron 이 시각이 된 pending 을 core.f_sms_send 로 (보낼 때의 sms_config 모드를 따른다)
create table if not exists crm.sms_schedule (
  id bigserial primary key,
  send_at timestamptz not null,
  rows jsonb not null,
  n int not null,
  body text not null,
  title text,
  campaign text,
  kind text not null default 'manual',
  is_ad boolean not null default false,
  status text not null default 'pending' check (status in ('pending','running','done','failed','cancelled')),
  note text,
  created_by text,
  created_at timestamptz not null default now(),
  run_at timestamptz,
  result jsonb,
  error text,
  cancelled_at timestamptz,
  cancelled_by text);
alter table crm.sms_schedule enable row level security;
create index if not exists ix_sms_schedule_due on crm.sms_schedule (send_at) where status = 'pending';

create or replace function core.f_sms_schedule_run() returns jsonb
language plpgsql volatile set search_path to 'pg_catalog','public' as $f$
declare r record; v jsonb; v_en boolean; v_done int := 0; v_fail int := 0; v_ids bigint[] := '{}';
begin
  select enabled into v_en from core.sms_config where id = 1;
  for r in select * from crm.sms_schedule where status = 'pending' and send_at <= now() order by send_at for update skip locked limit 5 loop
    update crm.sms_schedule set status = 'running', run_at = now() where id = r.id;
    begin
      if not coalesce(v_en, false) then raise exception '문자 기능이 꺼져 있어 보내지 않았습니다 — 설정에서 켠 뒤 다시 예약하세요' using errcode = '22023'; end if;
      v := core.f_sms_send(r.rows, r.body, r.title, r.campaign, r.kind, r.is_ad, coalesce(r.created_by, 'schedule'),
                           jsonb_build_object('timeout_ms', '8000', 'max', 500));
      update crm.sms_schedule set status = 'done', result = v where id = r.id;
      v_done := v_done + 1;
    exception when others then
      update crm.sms_schedule set status = 'failed', error = left(sqlerrm, 300) where id = r.id;
      v_fail := v_fail + 1;
    end;
    v_ids := v_ids || r.id;
  end loop;
  return jsonb_build_object('done', v_done, 'failed', v_fail, 'ids', v_ids);
end $f$;
revoke all on function core.f_sms_schedule_run() from public, anon, authenticated;

create or replace function public.fn_sms_schedule_save(p_send_at timestamptz, p_rows jsonb, p_body text, p_title text default null, p_campaign text default null, p_kind text default 'manual', p_is_ad boolean default false, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_role text := core.f_role(); v_email text := (select p.email from public.profiles p where p.id = auth.uid()); v_id bigint; c core.sms_config%rowtype; v_n int;
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
  insert into crm.sms_schedule (send_at, rows, n, body, title, campaign, kind, is_ad, note, created_by)
  values (p_send_at, p_rows, v_n, p_body, nullif(btrim(p_title),''), nullif(btrim(p_campaign),''), coalesce(nullif(p_kind,''),'manual'), coalesce(p_is_ad,false), nullif(btrim(p_note),''), coalesce(v_email,'admin'))
  returning id into v_id;
  insert into crm.access_log (actor, actor_email, action, row_count, reason) values (auth.uid(), v_email, 'sms_schedule:save', v_n, coalesce(p_campaign, p_kind));
  return jsonb_build_object('id', v_id, 'send_at', p_send_at, 'n', v_n, 'mode_now', c.mode);
end $f$;

create or replace function public.fn_sms_schedule_cancel(p_id bigint) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_role text := core.f_role(); v_email text := (select p.email from public.profiles p where p.id = auth.uid()); v_st text;
begin
  if v_role not in ('admin','staff') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select status into v_st from crm.sms_schedule where id = p_id for update;
  if v_st is null then raise exception '예약이 없습니다' using errcode='22023'; end if;
  if v_st <> 'pending' then raise exception '이미 % 상태라 취소할 수 없습니다', v_st using errcode='22023'; end if;
  update crm.sms_schedule set status = 'cancelled', cancelled_at = now(), cancelled_by = coalesce(v_email,'admin') where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $f$;

create or replace function public.fn_sms_schedule_list(p_limit int default 60) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $f$
  select case when core.f_role() not in ('admin','staff') then null else
    jsonb_build_object(
      'pending', (select count(*) from crm.sms_schedule where status = 'pending'),
      'rows', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', s.id, 'send_at', to_char(s.send_at at time zone 'Asia/Seoul', 'MM-DD HH24:MI'), 'send_at_iso', s.send_at,
          'n', s.n, 'status', s.status, 'body', left(s.body, 160), 'campaign', s.campaign, 'kind', s.kind, 'is_ad', s.is_ad,
          'first', core.f_sms_mask(s.rows->0->>'phone'), 'first_name', s.rows->0->>'name',
          'by', s.created_by, 'created_at', to_char(s.created_at at time zone 'Asia/Seoul', 'MM-DD HH24:MI'),
          'run_at', to_char(s.run_at at time zone 'Asia/Seoul', 'MM-DD HH24:MI'),
          'result', case when s.result is null then null else jsonb_build_object('mode', s.result->>'mode', 'sent', s.result->'sent', 'test', s.result->'test', 'blocked', s.result->'blocked', 'failed', s.result->'failed') end,
          'error', s.error, 'note', s.note) order by (s.status = 'pending') desc, s.send_at desc), '[]'::jsonb)
        from (select * from crm.sms_schedule order by (status = 'pending') desc, send_at desc limit greatest(1, least(coalesce(p_limit, 60), 300))) s)) end
$f$;
revoke all on function public.fn_sms_schedule_save(timestamptz,jsonb,text,text,text,text,boolean,text) from public, anon;
grant execute on function public.fn_sms_schedule_save(timestamptz,jsonb,text,text,text,text,boolean,text) to authenticated, service_role;
revoke all on function public.fn_sms_schedule_cancel(bigint) from public, anon;
grant execute on function public.fn_sms_schedule_cancel(bigint) to authenticated, service_role;
revoke all on function public.fn_sms_schedule_list(int) from public, anon;
grant execute on function public.fn_sms_schedule_list(int) to authenticated, service_role;
select cron.schedule('sms-schedule', '* * * * *', 'select core.f_sms_schedule_run();');   -- job 19

-- 롤백 실험(2026-10-14): 재구매 주기 · VMS · 기준일 오늘 → 창 0~30 = 258명 · 기본(-30~14) 304 · -60~-1 312 /
-- 예약 저장(중복 번호 2줄) → list pending 1 → send_at 을 지나게 하고 f_sms_schedule_run → done · 테스트 1(중복 1 차단) → done 은 취소 거절.
