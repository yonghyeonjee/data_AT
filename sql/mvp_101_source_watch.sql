-- mvp_101 · 수집 미도착 감시 (2026-09-09)
--
-- 문제 : core.data_source 에 소스 9개와 expect_days 가 등록돼 있지만
--        (a) 밀렸는지 확인하는 것이 아무것도 없고
--        (b) 알림 채널 3개가 전부 주소 없이 꺼져 있어
--        자료가 안 들어와도 관리자 화면에 들어가 본 사람만 안다.
--        수동 수집 9건 중 5건이 한 사람(온라인사업부)에게 몰려 있어
--        그 사람이 자리를 비우면 수집이 조용히 멈춘다.
--
-- 해결 : 매일 아침 밀린 소스를 찾아 알림을 보낸다. 웹훅 주소가 아직 없어도
--        core.notify_log 에는 남으므로, 주소만 넣으면 그때부터 바로 배달된다.
--        대체 담당(backup_owner)을 함께 실어 "누가 대신 하는지"까지 알린다.

-- ── 1. 대체 담당 · 자동화 계획 · 마지막 알림 시각 ─────────────────────────
alter table core.data_source add column if not exists backup_owner   text;
alter table core.data_source add column if not exists auto_plan      text;
alter table core.data_source add column if not exists last_alert_at  timestamptz;
comment on column core.data_source.backup_owner is '담당자가 없을 때 대신 하는 사람. 비어 있으면 알림에 "대체 담당 미지정" 으로 뜬다';
comment on column core.data_source.auto_plan    is '이 수동 항목을 자동으로 옮길 방법. 비어 있으면 당분간 사람이 계속 한다는 뜻';

-- ── 2. 아직 등록 안 된 수동 소스 3건 추가 ────────────────────────────────
insert into core.data_source (key, label, owner, expect_days, how, sort_no, active, alert) values
  ('channel_daily','온라인 채널 일매출','온라인사업부', 10,
   '원장 시트를 관리자 → 데이터 가져오기에 올림', 65, true, true),
  ('ec_slip','이카운트 주문서 현황','온라인사업부', 10,
   '이카운트 → 주문서 현황 엑셀을 데이터 가져오기에 올림 (중복 전송 차단에 쓰임)', 70, true, true),
  ('ec_customer','이카운트 거래처','온라인사업부', 180,
   '거래처 코드 CSV 를 데이터 가져오기에 올림 (거래처가 늘면)', 75, true, false)
on conflict (key) do nothing;

-- ── 3. 소스별 마지막 도착 시각 ───────────────────────────────────────────
create or replace function core.f_source_last(p_key text)
returns timestamptz language sql stable security definer
set search_path to 'pg_catalog','public' as $$
  select case p_key
    when 'shoplinker'      then (select max(created_at) from core.orders where source='shoplinker')
    when 'store'           then (select max(created_at) from core.orders where source='store')
    when 'store_manual'    then (select max(updated_at) from core.store_daily)
    when 'ecount_sales'    then (select max(created_at) from core.orders where source='ecount')
    when 'rental'          then (select max(created_at) from core.orders where source='rental')
    when 'ecount_prospect' then (select max(created_at) from crm.consult where source='ecount_prospect')
    when 'web_inquiry'     then (select max(created_at) from crm.web_inquiry)
    when 'godo_member'     then (select max(uploaded_at) from raw.upload where source in ('P몰','S몰','AT몰','시흥몰'))
    when 'channel_daily'   then (select max(updated_at) from core.channel_daily)
    when 'ec_slip'         then (select max(uploaded_at) from ec.slip_ref)
    when 'ec_customer'     then (select max(uploaded_at) from raw.upload where source='ecount_customer')
    when 'sub_plan'        then (select max(updated_at) from core.app_setting where key like 'sub_plan%')
    else null end;
$$;

-- ── 4. 밀린 소스 목록 (화면·알림 공용) ───────────────────────────────────
create or replace function core.f_source_overdue()
returns table(key text, label text, owner text, backup_owner text, how text,
              last_at timestamptz, days_late numeric, expect_days int)
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select d.key, d.label, d.owner, d.backup_owner, d.how, l.last_at,
         round(extract(epoch from (now() - coalesce(l.last_at, now() - (d.expect_days+1) * interval '1 day')))/86400.0, 1),
         d.expect_days
    from core.data_source d
    cross join lateral (select core.f_source_last(d.key) as last_at) l
   where d.active and d.alert
     and (l.last_at is null or l.last_at < now() - d.expect_days * interval '1 day')
   order by d.sort_no;
$$;

-- 화면용 RPC (관리자 · 담당자 화면에서 배지로 쓴다)
create or replace function public.fn_source_overdue()
returns jsonb language sql stable security definer
set search_path to 'pg_catalog','public' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', key, 'label', label, 'owner', owner, 'backup', backup_owner,
           'how', how, 'days_late', days_late, 'expect_days', expect_days,
           'last_at', to_char(last_at at time zone 'Asia/Seoul','MM-DD HH24:MI')
         ) order by days_late desc), '[]'::jsonb)
    from core.f_source_overdue();
$$;
grant execute on function public.fn_source_overdue() to anon, authenticated;

-- ── 5. 매일 확인해서 알림 ────────────────────────────────────────────────
-- 같은 소스로 하루에 한 번만 부른다. 웹훅이 없으면 f_notify 가 notify_log 에만 남긴다.
create or replace function core.f_source_check()
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public' as $$
declare r record; n int := 0; lines text := ''; keys text[] := '{}';
begin
  for r in select * from core.f_source_overdue() loop
    -- 하루 한 번
    if exists (select 1 from core.data_source d
                where d.key = r.key and d.last_alert_at > now() - interval '20 hours') then
      continue;
    end if;
    lines := lines || format(E'· %s — %s일째 안 들어옴 (기준 %s일)\n  담당 %s%s\n  %s\n',
               r.label, r.days_late, r.expect_days, coalesce(r.owner,'미지정'),
               case when coalesce(r.backup_owner,'') = '' then ' · 대체 담당 미지정'
                    else ' · 대체 ' || r.backup_owner end,
               coalesce(r.how,''));
    keys := keys || r.key; n := n + 1;
  end loop;

  if n > 0 then
    perform core.f_notify('source.stale', jsonb_build_object(
      'count', n::text,
      'list',  lines,
      'at',    to_char(now() at time zone 'Asia/Seoul','MM-DD HH24:MI')));
    update core.data_source set last_alert_at = now() where key = any(keys);
  end if;
  return jsonb_build_object('overdue', n, 'keys', to_jsonb(keys));
end $$;

-- ── 6. 알림 규칙 ─────────────────────────────────────────────────────────
insert into core.notify_rule (code, label, event, channel_code, enabled, template, note, sort)
values ('source_stale','수집 미도착','source.stale','jandi_ops', true,
  E'[수집 미도착] {count}건이 예정보다 늦습니다  ({at})\n\n{list}\n관리자 화면 → 데이터 상태 에서 올릴 수 있습니다.',
  '매일 아침 09:10 자동 확인. 담당자가 자리를 비워도 누군가는 알게 하려는 규칙', 15)
on conflict (code) do update
  set enabled = true, template = excluded.template, note = excluded.note;

-- ── 7. 매일 09:10 KST (= 00:10 UTC) ─────────────────────────────────────
do $$ declare j int; begin
  select jobid into j from cron.job where jobname = 'source-check';
  if j is not null then perform cron.unschedule(j); end if;
  perform cron.schedule('source-check', '10 0 * * *', 'select core.f_source_check();');
end $$;

-- ── 8. 자동화 계획 기록 (수동을 자동으로 옮길 방법) ──────────────────────
update core.data_source set auto_plan = v.plan from (values
  ('godo_member',  '고도몰 OpenAPI 로 회원·주문 직접 수집 (검토 문서 있음) → 자동으로 이동 가능'),
  ('channel_daily','원장 시트를 Google Sheets API 로 읽어오기 → GitHub Actions 에 추가하면 자동'),
  ('web_inquiry',  '고도몰 게시판 API 또는 지메일 파싱 → 자동으로 이동 가능'),
  ('ecount_sales', '이카운트에 판매현황 조회 API 가 없음(404 확인). 정기 메일 발송 → 파싱이 대안'),
  ('ec_slip',      '이카운트 조회 API 없음. 당분간 사람이 올림'),
  ('rental',       '이카운트 입력분이라 판매현황과 같은 제약'),
  ('store',        '매장에서 파는 즉시 입력하는 것이 원본. 자동화 대상이 아님'),
  ('store_manual', '매장 마감은 사람이 확인해야 하는 절차. 자동화 대상이 아님')
) as v(key, plan) where core.data_source.key = v.key;
