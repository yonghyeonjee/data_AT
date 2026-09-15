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

/* ─────────────────────────────────────────────────────────────
   mvp_145 — 미입금 주문 (고도몰) · 결제 안 한 고객 (2026-09-15)

   샵링커는 **결제가 끝난 주문만** 준다. 고도몰 관리자의 '가/미'(가상계좌·무통장 미입금)
   주문은 우리 DB 에 안 들어온다 (9/14 KMR85RH 710만원 · 9/12 KQ85QNH80 352만원 확인).
   그래서 고도몰에서 입금 대기 목록을 받아 따로 쌓는다.

   crm.unpaid_order 는 **스냅샷**이다 — 올릴 때마다 목록에 없는 열린 건은
   결제됐거나 취소된 것으로 보고 resolved_at 을 찍어 목록에서 내린다.
   그래서 "입금 대기 전부"를 받아 올려야 한다 (일부만 올리면 나머지가 사라진다).
   ───────────────────────────────────────────────────────────── */

create table if not exists crm.unpaid_order (
  order_no    text primary key,
  mall        text,
  ordered_at  timestamptz,
  name        text,
  phone       text,
  buyer_key   char(16),
  product     text,
  qty         int,
  amount      numeric,
  pay_method  text,
  status      text,
  memo        text,
  file_name   text,
  uploaded_at timestamptz not null default now(),
  resolved_at timestamptz,
  updated_at  timestamptz not null default now()
);
create index if not exists ix_unpaid_open on crm.unpaid_order (ordered_at desc) where resolved_at is null;
create index if not exists ix_unpaid_key  on crm.unpaid_order (buyer_key);
comment on table crm.unpaid_order is '고도몰 미입금(입금 대기) 주문 스냅샷 — 샵링커는 결제 끝난 주문만 주므로 여기로 따로 받는다';

/* fn_unpaid_upsert(p_rows, p_file) · fn_unpaid_list(p_reason, …)
   본문은 서버에 이미 올라가 있다 (pg_proc 참고). 요점만:
   - 주문일시에 표준시가 안 붙어 있으면 **KST 로 읽는다** (core.f_ts 는 UTC 로 읽어
     14:51 주문이 23:51 로 찍혔다)
   - temp table 이름을 _uw / _ur 로 나누고 drop if exists 를 앞에 둔다
     (한 트랜잭션에서 upsert 와 list 를 같이 부르면 _u 가 겹쳐 터진다)
   - fn_unpaid_list 는 p_reason 이 필수고 첫 페이지·내보내기 때 crm.access_log 에 남는다
   - 이름·번호는 기본 마스킹, admin + p_unmask 일 때만 원문 */

insert into core.data_source (key, label, owner, expect_days, how, sort_no, active, auto_plan)
values ('unpaid_order', '미입금 주문 (고도몰)', '온라인사업부', 7,
        '고도몰 관리자 › 주문 목록에서 입금 대기(가상계좌·무통장) 주문을 내려받아 올림 · 올릴 때마다 목록에 없는 건은 결제·취소로 보고 정리됩니다',
        67, true,
        '샵링커는 결제가 끝난 주문만 준다. 고도몰 OpenAPI 를 붙이면 자동으로 받을 수 있다')
on conflict (key) do update
  set label=excluded.label, owner=excluded.owner, expect_days=excluded.expect_days,
      how=excluded.how, sort_no=excluded.sort_no, active=true, auto_plan=excluded.auto_plan;

do $outer$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='core' and p.proname='f_source_last';
  if position('when ''unpaid_order''' in v_def) > 0 then return; end if;
  execute replace(v_def, 'else null end;',
    'when ''unpaid_order''  then (select max(uploaded_at) from crm.unpaid_order)
    else null end;');
end $outer$;

/* ─────────────────────────────────────────────────────────────
   mvp_146 — 재구매 주기를 2026-08-14 콜랩 방식으로 맞춘다 (2026-09-15)

   사용자가 8/14 발송의 원본(sale_search_raw_0814.csv 20,757행 · 거래처 7,739)과
   콜랩 노트북을 보여줬다. 거기서 쓴 방식이 우리 것보다 낫다:

   - 주문 = **거래처 × 날짜 합산** (같은 날 여러 전표 = 주문 1건)   ← 우리 buy_days 와 같다
   - 주기 = 간격의 **중앙값**. 평균은 한 번의 긴 공백에 끌려간다     ← 우리는 평균이었다
   - **이탈(마지막 구매 365일 초과) 제외**                          ← 우리는 2년이었다
   - 예상재구매일 = 마지막 구매 + 주기 · 대상 = **D-30 ~ D+14**     ← 우리는 '주기~주기×3'
   (콜랩은 거래처×모델 3회+ 의 모델 주기를 1순위로 쓰는 3단 폴백까지 했다.
    우리는 아직 주문 주기만 — 모델 주기는 품목명 파싱이 붙은 뒤에 넣는다.)

   8/14 콜랩 결과: 발송 타겟 266건 / 문자 가능 263건.
   2026-09-15 우리 DB 로 같은 규칙: 383명 (동의 기준은 그대로 3,741명).
   ───────────────────────────────────────────────────────────── */

alter table crm.customer_roll add column if not exists cycle_days numeric;
comment on column crm.customer_roll.cycle_days is '주문 간격 중앙값(일) — 주문 = 고객×날짜 합산. 평균이 아니라 중앙값이다 (2026-08-14 콜랩 방식)';

-- core.f_customer_roll 이 cycle_days 를 채우게 한다
do $outer$
declare v_src text; v_old text; v_new text;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='core' and p.proname='f_customer_roll';
  if position('cycle_days' in v_src) > 0 then return; end if;
  v_old := '  select count(*) into v_n from crm.customer_roll;';
  if position(v_old in v_src) = 0 then raise exception '지점 없음'; end if;
  v_new := '  with d as (
      select buyer_key, (order_at at time zone ''Asia/Seoul'')::date dt
        from core.orders where buyer_key is not null and not coalesce(is_test,false)
       group by 1,2),
    g as (select buyer_key, dt - lag(dt) over (partition by buyer_key order by dt) gap from d),
    m as (select buyer_key, percentile_cont(0.5) within group (order by gap) med
            from g where gap is not null group by 1)
  update crm.customer_roll r set cycle_days = m.med from m where m.buyer_key = r.buyer_key;

' || v_old;
  execute format('create or replace function core.f_customer_roll() returns integer
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L',
                 replace(v_src, v_old, v_new));
end $outer$;
select core.f_customer_roll();

-- fn_crm_targets_v2 의 p_basis='repeat' 조건을 콜랩 방식으로
do $outer$
declare v_src text; v_args text; v_old text; v_new text; v_i int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_crm_targets_v2';
  if position('o.cycle_days is not null' in v_src) > 0 then return; end if;
  v_i := position('where (case when p_basis = ''repeat'' then' in v_src);
  if v_i = 0 then raise exception '지점 없음 (repeat 조건)'; end if;
  v_old := substring(v_src from v_i for
            position('    and c.phone is not null and length(c.phone) >= 10' in v_src) - v_i);
  v_new := 'where (case when p_basis = ''repeat'' then
             o.buy_days >= 2 and o.cycle_days is not null
             and ((now() at time zone ''Asia/Seoul'')::date
                  - (o.last_at at time zone ''Asia/Seoul'')::date) <= 365
             and ((((o.last_at at time zone ''Asia/Seoul'')::date
                    + (o.cycle_days || '' days'')::interval)::date)
                  - (now() at time zone ''Asia/Seoul'')::date) between -30 and 14
           else c.consent_marketing end)
';
  execute format('create or replace function public.fn_crm_targets_v2(%s) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L',
                 v_args, replace(v_src, v_old, v_new));
end $outer$;

/* ─────────────────────────────────────────────────────────────
   2026-09-15 · 8/14 발송분 적재 + 월요일(9/21) 토너·정수기 필터 교체 알림 준비

   센드온 발송내역(91f57129 … 2026-08-24.xlsx, 261줄) 을 fn_send_log_import 로 넣었다.
   캠페인 '2026-08-14 토너·잉크 교체 안내 (LMS)' · 채널 lms · 257명 매칭 · 실패 1 · 미매칭 4줄.
   이 261명은 이카운트 VMS 거래처(256/257 source=ecount) — 고도몰 회원 풀(3,741)과 다른 집단.

   fn_send_log_import 도 unpaid 와 같은 KST 버그가 있어 고쳤다 —
   '실 발송 일시' 에 표준시가 없으면 KST 로 읽는다 (전엔 16:09 가 다음 날 01:09 KST 로 들어갔다).

   숫자 (9/15): 재구매 주기 383 → 보낸 사람 전부 제외 325.
   '30일 내 제외' 로는 8/14 가 안 빠진다 (월요일이면 38일) — 화면에서 [거래 재구매 주기] 를 고르면
   '한 번이라도 보낸 사람 전부 제외' 가 자동으로 걸리게 했다.
   창이 D-30~D+14 라 날짜에 따라 움직인다: 9/21 기준 339 (새로 50 · 빠짐 36). 월요일 아침에 뽑을 것.
   ───────────────────────────────────────────────────────────── */

/* ─────────────────────────────────────────────────────────────
   mvp_147 — 대상 기준 '제품 재구매' (2026-09-15)

   정수기 필터·건조기 필터(WD-FLTR)·AI 콤보처럼 **특정 제품을 산 사람**에게
   교체·연결 판매를 보내려면 제품으로 뽑을 수 있어야 한다.
   'repeat' 은 주문 주기라 소모품에 안 맞는다 — 필터는 2회+ 구매가 30명뿐이다.

   fn_crm_targets_v2 에 p_basis='product' + p_product(정규식) 추가.
   - 조건: 그 제품을 p_from ~ p_to 사이에 산 적이 있다. **수신동의는 안 본다.**
   - product 기준일 때 p_from·p_to 는 '마지막 구매일' 이 아니라 '그 제품을 산 날' 이다
     (o.last_at 조건을 건너뛴다)
   - core.orders 에 품목명 trgm 인덱스 추가 (ix_orders_pname_trgm)

   2026-09-15 확인: 정수기 필터(HAF-) 전체 4,082 · 3~6개월 전 구매 1,067 ·
   WD-FLTR 101 · AI 콤보 248.

   samsung_pmall 은 **네이버 스마트스토어** 계정이다 (SHOP_MAP '스마트스토어|samsung_pmall'
   → 'B2B|오픈마켓'). 채널 이름이 'B2B' 라 자사몰처럼 보이지만 아니다 —
   정수기 필터 구매자 4,390명 중 3,279명이 여기서 샀고, 고도몰 자사몰은 251명뿐이다.
   고도몰 회원 명부와 맞물리는 사람은 45명(수신동의 5명).
   ───────────────────────────────────────────────────────────── */
