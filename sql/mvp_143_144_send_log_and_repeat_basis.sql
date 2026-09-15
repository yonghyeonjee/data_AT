/* mvp_143 — 이미 보낸 고객(발송 이력) 가져오기 + CRM 발송 대상에서 제외
   2026-09-15

   왜: 지난 캠페인에서 한 번 보낸 사람에게 또 보내면 안 된다. 그런데 crm.send_log 는 0건이라
       [발송 대상 추출] 의 '최근 발송 제외' 가 아무것도 걸러내지 못했다.
       보낸 목록(휴대폰·이름·발송일)을 데이터 가져오기로 올려 send_log 에 쌓고,
       추출에서 '이미 보낸 사람 전부 제외' 로 뺀다.

   핵심: 매칭은 buyer_key 를 다시 계산하지 않고 **휴대폰 뒤 8자리**로 한다.
         core.f_buyer_key 는 이름+번호를 같이 해싱하므로, 이름이 없거나 다르게 적힌
         발송 목록으로는 같은 키가 안 나온다. 번호만 있는 목록도 받아야 한다. */

-- 같은 캠페인·같은 사람을 두 번 올려도 한 줄만 남는다 (파일을 다시 올려도 안전)
create unique index if not exists ux_send_camp_buyer
  on crm.send_log (campaign, buyer_key);

create or replace function public.fn_send_log_import(
  p_rows      jsonb,
  p_campaign  text,
  p_channel   text default 'sms',
  p_sent_at   date default null,     -- 줄마다 발송일이 없으면 이 날짜로
  p_file      text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog','public'
as $fn$
declare
  v_matched int := 0; v_unmatched int := 0; v_dup int := 0; v_rows int := 0;
  v_sample  jsonb;
begin
  if not core.f_is_service() and core.f_role() not in ('admin','staff') then
    raise exception '권한이 없습니다' using errcode='42501';
  end if;
  if coalesce(p_campaign,'') = '' then
    raise exception '캠페인명을 적어 주세요' using errcode='22023';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('rows',0,'matched',0,'unmatched',0,'dup',0);
  end if;

  create temp table _in on commit drop as
  select right(regexp_replace(coalesce(r->>'phone',''), '\D', '', 'g'), 8) as d8,
         nullif(trim(coalesce(r->>'name','')), '')                         as name,
         coalesce(core.f_ts(r->>'sent_at'),
                  case when p_sent_at is not null then p_sent_at::timestamptz end,
                  now())                                                   as sent_at,
         coalesce(nullif(r->>'status',''), 'sent')                         as status
    from jsonb_array_elements(p_rows) r;

  delete from _in where length(d8) < 8;          -- 번호가 없거나 마스킹된 줄은 버린다
  select count(*) into v_rows from _in;

  /* 번호 뒤 8자리로 고객 마스터와 맞춘다. 한 번호에 여러 고객이 있으면 (동명이인·중복 등록)
     이름이 같은 쪽을 먼저, 없으면 아무나 하나 — 어차피 같은 번호라 보내는 사람은 한 명이다 */
  create temp table _m on commit drop as
  select distinct on (i.d8) i.d8, c.buyer_key, i.sent_at, i.status
    from _in i
    join crm.customer c
      on right(regexp_replace(coalesce(c.phone,''), '\D', '', 'g'), 8) = i.d8
     and c.buyer_key is not null
   order by i.d8, (i.name is not null and c.name = i.name) desc, c.id;

  select count(*) into v_matched from _m;
  v_unmatched := v_rows - v_matched;

  with ins as (
    insert into crm.send_log (buyer_key, channel, campaign, sent_at, status)
    select m.buyer_key, coalesce(nullif(p_channel,''),'sms'), p_campaign, m.sent_at, m.status
      from _m m
    on conflict (campaign, buyer_key) do nothing
    returning 1
  ) select v_matched - count(*) into v_dup from ins;

  select jsonb_agg(x) into v_sample from (
    select i.name, '···'||right(i.d8,4) as phone from _in i
     where not exists (select 1 from _m m where m.d8 = i.d8) limit 5) x;

  insert into raw.upload (source, file_name, row_count, error_count, note)
  values ('send_log', p_file, v_rows, v_unmatched,
          p_campaign || ' · 매칭 ' || v_matched || ' · 미매칭 ' || v_unmatched);

  return jsonb_build_object('rows', v_rows, 'matched', v_matched,
                            'unmatched', v_unmatched, 'dup', v_dup,
                            'campaign', p_campaign, 'sample', coalesce(v_sample,'[]'::jsonb));
end $fn$;

revoke all on function public.fn_send_log_import(jsonb,text,text,date,text) from public, anon;
grant execute on function public.fn_send_log_import(jsonb,text,text,date,text) to authenticated, service_role;

-- 데이터 소스 카드 (관리자 › 데이터 가져오기)
insert into core.data_source (key, label, owner, expect_days, how, sort_no, active, auto_plan)
values ('send_log', '이미 보낸 고객 (발송 이력)', '온라인사업부', 365,
        '지난 캠페인에서 보낸 목록(휴대폰·이름·발송일)을 파일 올리기 또는 붙여넣기 · [발송 대상 추출]에서 제외됩니다',
        66, true,
        '센드온이 붙으면 발송할 때마다 자동으로 쌓인다 — 그때 이 카드는 수동 업로드용으로만 남는다')
on conflict (key) do update
  set label=excluded.label, owner=excluded.owner, expect_days=excluded.expect_days,
      how=excluded.how, sort_no=excluded.sort_no, active=true, auto_plan=excluded.auto_plan;

-- '마지막 적재' 에 send_log 를 태운다 (발송일이 아니라 올린 시각을 본다)
do $outer$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='core' and p.proname='f_source_last';
  if position('when ''send_log''' in v_def) > 0 then return; end if;
  if position('else null end;' in v_def) = 0 then raise exception '지점 없음'; end if;
  execute replace(v_def, 'else null end;',
    'when ''send_log''      then (select max(uploaded_at) from raw.upload where source=''send_log'')
    else null end;');
end $outer$;

/* ─────────────────────────────────────────────────────────────
   mvp_144 — 대상 기준 두 가지 · 센드온 파일 그대로 받기 (2026-09-15)

   2026-08-14 센드온 발송 내역(261줄)을 맞춰 보니 259개 번호 중 257명이 고객 마스터에 있는데
   **수신동의 표시는 3명뿐**이었다. 이 사람들은 이카운트 거래처(소모품·VMS)라서
   동의는 거래 관계에서 나오고 crm.customer.consent_marketing 은 false 다.
   → [발송 대상 추출] 이 동의 고객만 보므로 이 3만여 명을 아예 못 뽑는다.

   1) crm.customer_roll 에 first_at · buy_days (산 날 수) 를 materialize
   2) fn_crm_targets_v2 에 p_basis
      'consent' (기본) — 지금까지와 같다
      'repeat'        — 재구매 주기를 넘긴 거래처. 주기 = (마지막-처음)/(산 날 수-1),
                        주기를 넘겼고 주기의 3배 안, 마지막 거래 2년 안.
                        **동의 여부를 안 본다** — 보낼 수 있는지는 사람이 판단한다.
   3) last_sent 는 status <> 'failed' 만 센다 (발송 실패 = 고객이 못 받음)
   ───────────────────────────────────────────────────────────── */

alter table crm.customer_roll add column if not exists first_at timestamptz;
alter table crm.customer_roll add column if not exists buy_days int;

-- core.f_customer_roll 에 first_at · buy_days 채우기 (원본 prosrc 치환)
do $outer$
declare v_src text; v_new text;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='core' and p.proname='f_customer_roll';
  if position('first_at' in v_src) > 0 then return; end if;
  v_new := replace(v_src,
    'select buyer_key, count(*)::int cnt, sum(net_amount) net, max(order_at) last_at,',
    'select buyer_key, count(*)::int cnt, sum(net_amount) net, max(order_at) last_at,
           min(order_at) first_at, count(distinct (order_at at time zone ''Asia/Seoul'')::date)::int buy_days,');
  v_new := replace(v_new,
    'insert into crm.customer_roll(buyer_key,cnt,net,last_at,chans,cats,last_product,last_category,handler,updated_at)
    select buyer_key,cnt,coalesce(net,0),last_at,chans,cats,last_product,last_category,handler,now() from _cr',
    'insert into crm.customer_roll(buyer_key,cnt,net,last_at,first_at,buy_days,chans,cats,last_product,last_category,handler,updated_at)
    select buyer_key,cnt,coalesce(net,0),last_at,first_at,buy_days,chans,cats,last_product,last_category,handler,now() from _cr');
  v_new := replace(v_new,
    'on conflict (buyer_key) do update set cnt=excluded.cnt, net=excluded.net, last_at=excluded.last_at,',
    'on conflict (buyer_key) do update set cnt=excluded.cnt, net=excluded.net, last_at=excluded.last_at,
    first_at=excluded.first_at, buy_days=excluded.buy_days,');
  if v_new = v_src then raise exception '지점 없음'; end if;
  execute format('create or replace function core.f_customer_roll() returns integer
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_new);
end $outer$;
select core.f_customer_roll();

-- 발송 실패 건은 '보낸 사람' 으로 치지 않는다
do $outer$
declare v_src text; v_args text; v_old text; v_new text;
begin
  v_old := '(select max(l.sent_at) from crm.send_log l where l.buyer_key = c.buyer_key) last_sent';
  v_new := '(select max(l.sent_at) from crm.send_log l where l.buyer_key = c.buyer_key and coalesce(l.status,'''') <> ''failed'') last_sent';
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_crm_targets_v2';
  if position(v_new in v_src) > 0 then return; end if;
  if position(v_old in v_src) = 0 then raise exception '지점 없음'; end if;
  execute format('create or replace function public.fn_crm_targets_v2(%s) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L',
                 v_args, replace(v_src, v_old, v_new));
end $outer$;

-- p_basis 추가 (옛 시그니처는 drop — 기본값 있는 인자를 더하면 호출이 모호해진다)
do $outer$
declare v_src text; v_args text; v_ident text; v_old text; v_new text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid), pg_get_function_identity_arguments(p.oid)
    into v_src, v_args, v_ident
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_crm_targets_v2';
  if position('p_basis' in v_args) > 0 then return; end if;

  v_old := 'where c.consent_marketing
    and c.phone is not null and length(c.phone) >= 10';
  if position(v_old in v_src) = 0 then raise exception '지점 없음 (동의 조건)'; end if;

  v_new := 'where (case when p_basis = ''repeat'' then
             o.buy_days >= 2 and o.first_at is not null
             and o.last_at > now() - interval ''730 days''
             and (((now() at time zone ''Asia/Seoul'')::date - (o.last_at at time zone ''Asia/Seoul'')::date))
                 between
                   ((((o.last_at at time zone ''Asia/Seoul'')::date - (o.first_at at time zone ''Asia/Seoul'')::date)::numeric
                     / greatest(o.buy_days - 1, 1)) + 1)::int
                 and
                   ((((o.last_at at time zone ''Asia/Seoul'')::date - (o.first_at at time zone ''Asia/Seoul'')::date)::numeric
                     / greatest(o.buy_days - 1, 1)) * 3)::int
           else c.consent_marketing end)
    and c.phone is not null and length(c.phone) >= 10';

  execute format('drop function if exists public.fn_crm_targets_v2(%s)', v_ident);
  execute format('create function public.fn_crm_targets_v2(%s, p_basis text default ''consent'') returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L',
                 v_args, replace(v_src, v_old, v_new));
end $outer$;

do $g$
declare v_ident text;
begin
  select pg_get_function_identity_arguments(p.oid) into v_ident
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_crm_targets_v2';
  execute format('revoke all on function public.fn_crm_targets_v2(%s) from public, anon', v_ident);
  execute format('grant execute on function public.fn_crm_targets_v2(%s) to authenticated, service_role', v_ident);
end $g$;

/* 2026-09-15 확인
   동의 기준 3,741 · 재구매 주기 1,267 (그중 채널 VMS 1,231)
   8/14 발송분(259명) 을 올려 빼면 1,123명이 남는다.
   그 1,123명의 마지막 거래는 6개월 이내 130 · 6개월 초과 993 (평균 경과 390일, 평균 주기 243일). */
