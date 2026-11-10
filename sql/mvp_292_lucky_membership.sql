-- mvp_292 · 2026-11-10 · 행운 이벤트 — 멤버십(DPS) 가입 여부 · 개인정보/마케팅/삼성멤버십 가입 동의 · DPS 등록 여부 표기
-- 사용자: "멤버십 등록 여부를 묻고 아예 등록하게 · 마케팅 및 삼성멤버십 가입 동의 여부 물으면서" · "사실 DPS 에 등록하는 거니까 DPS 등록 여부도 ·
--          기존 고객들도 DPS 등록됐는지 현재 데이터로 표기" · "둘 다(고객·담당자) 화면에서 저장"
-- DPS 등록 판단(현재 데이터): crm.customer.phone 이 같고 dps_customer_no 가 있으면 등록 → dps.customer 의 member(삼성멤버십 회원)·membership(등급)·marketing·checked_at
--   (DPS 수집기가 마지막으로 돈 날 기준. 오늘 DPS 에 새로 넣은 고객은 다음 수집 전까지 '등록 처리함(확인 대기)'으로 보인다)
-- 고객 직접 등록(fn_lucky_join)은 즉석뽑기를 주지 않는다 — 직원이 DPS 가입을 확인하고 [즉석뽑기 주기]. 매장 밖에서 가짜 번호로 뽑기만 하는 것을 막는다.
-- 마케팅 동의는 crm.customer.consent_marketing · crm.consent_history(source 'store', evidence '행운 이벤트 …') 에도 남긴다 (동의만 올리고 거부로 내리지는 않는다).

alter table ev.entrant
  add column if not exists member_answer text check (member_answer in ('member','join','no','unknown')),
  add column if not exists privacy_at timestamptz,
  add column if not exists marketing_ok boolean,
  add column if not exists member_consent boolean,
  add column if not exists consent_by text,
  add column if not exists consent_at timestamptz,
  add column if not exists self_reg boolean not null default false,
  add column if not exists dps_done_at timestamptz,
  add column if not exists dps_done_by text;

create table if not exists ev.join_log (ip text not null, at timestamptz not null default now());
create index if not exists ix_ev_join_log on ev.join_log (ip, at);
alter table ev.join_log enable row level security;
revoke all on ev.join_log from public, anon, authenticated;

-- 번호 → DPS 상태 (현재 수집 데이터)
create or replace function ev.f_dps(p_phone text) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select coalesce((
    select jsonb_build_object('reg', true, 'member', coalesce(d.member, c.dps_grade is not null), 'grade', coalesce(d.membership, c.dps_grade),
             'marketing', d.marketing, 'checked', coalesce(d.checked_at, (d.updated_at at time zone 'Asia/Seoul')::date))
      from crm.customer c left join dps.customer d on d.customer_no = c.dps_customer_no
     where c.phone = p_phone and c.dps_customer_no is not null
     order by d.updated_at desc nulls last limit 1),
    jsonb_build_object('reg', false))
  || jsonb_build_object('crm_mkt', exists (select 1 from crm.customer c where c.phone = p_phone and c.consent_marketing)) $$;

-- 마케팅 동의 → CRM 고객 (동의일 때만 부른다)
create or replace function ev.f_crm_consent(p_name text, p_phone text, p_evidence text) returns void
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_key char(16);
begin
  v_key := core.f_buyer_key(p_name, p_phone, null);
  if v_key is null then return; end if;
  insert into crm.customer (buyer_key, name, phone, first_seen_at, last_seen_at, consent_marketing, consent_updated_at, consent_source, source_channels)
  values (v_key, p_name, p_phone, now(), now(), true, now(), 'store', array['store'])
  on conflict (buyer_key) do update set
    consent_marketing = true,
    consent_updated_at = case when crm.customer.consent_marketing then crm.customer.consent_updated_at else now() end,
    consent_source = case when crm.customer.consent_marketing then crm.customer.consent_source else 'store' end,
    last_seen_at = now(),
    source_channels = (select array_agg(distinct x) from unnest(coalesce(crm.customer.source_channels,'{}'::text[]) || array['store']) x);
  insert into crm.consent_history (buyer_key, consent, source, evidence) values (v_key, true, 'store', left(p_evidence, 200));
end $$;

-- 동의 저장 (고객·담당자 공통). privacy 는 처음 한 번 꼭 받는다
create or replace function ev.f_consent_save(p_ent bigint, p_data jsonb, p_by text) returns void
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare n ev.entrant; v_mkt boolean := (p_data->>'marketing')::boolean; v_mem boolean := (p_data->>'member_consent')::boolean;
  v_ans text := nullif(p_data->>'member_answer','');
begin
  select * into n from ev.entrant where id = p_ent for update;
  if n.privacy_at is null and coalesce((p_data->>'privacy')::boolean,false) = false then
    raise exception '개인정보 수집·이용 동의(필수)를 받아 주세요' using errcode='22023'; end if;
  if v_ans is not null and v_ans not in ('member','join','no','unknown') then raise exception '멤버십 답이 잘못됐습니다' using errcode='22023'; end if;
  update ev.entrant set
    privacy_at = coalesce(privacy_at, case when (p_data->>'privacy')::boolean then now() end),
    marketing_ok = coalesce(v_mkt, marketing_ok),
    member_consent = coalesce(v_mem, member_consent),
    member_answer = coalesce(v_ans, member_answer),
    consent_by = p_by, consent_at = now()
   where id = p_ent;
  if v_mkt and not coalesce(n.marketing_ok,false) then
    perform ev.f_crm_consent(n.name, n.phone, '행운 이벤트 마케팅 수신 동의 · ' || p_by);
  end if;
end $$;
revoke all on function ev.f_dps(text), ev.f_crm_consent(text,text,text), ev.f_consent_save(bigint,jsonb,text) from public, anon, authenticated;

-- 고객 한 명 (멤버십·동의·DPS 칸 더함)
create or replace function ev.f_me(p_ent bigint, p_staff boolean default false, p_full boolean default false) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object(
    'id', n.id, 'name', n.name,
    'phone', case when p_full then n.phone when p_staff then ev.f_mask_phone(n.phone) else null end,
    'phone4', right(n.phone,4), 'memo', case when p_staff then n.memo end,
    'created_at', n.created_at, 'created_by', case when p_staff then n.created_by end,
    'member_answer', n.member_answer, 'privacy', n.privacy_at is not null, 'marketing_ok', n.marketing_ok, 'member_consent', n.member_consent,
    'self_reg', n.self_reg, 'consent_by', case when p_staff then n.consent_by end, 'consent_at', n.consent_at,
    'dps', case when p_staff then ev.f_dps(n.phone) end,
    'dps_done_at', n.dps_done_at, 'dps_done_by', case when p_staff then n.dps_done_by end,
    'spins_left', (select count(*) from ev.spin s where s.entrant_id=n.id and s.used_at is null and s.void_at is null),
    'spins', (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'reason',s.reason,'granted_at',s.granted_at,'granted_by',case when p_staff then s.granted_by end,
                       'used_at',s.used_at,'rank',s.prize_rank,'label',s.prize_label,'coupon',s.coupon,'redeemed_at',s.redeemed_at,
                       'void',s.void_at is not null) order by s.id),'[]'::jsonb)
                from ev.spin s where s.entrant_id=n.id and (p_staff or s.void_at is null)),
    'tickets', (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'no',t.no,'mode',t.mode,'reason',t.reason,'ref',case when p_staff then t.ref end,
                       'issued_at',t.issued_at,'issued_by',case when p_staff then t.issued_by end,
                       'revealed', t.revealed_at is not null, 'revealed_at', t.revealed_at,
                       'rank', case when t.mode='instant' then (case when t.revealed_at is not null or p_full then t.instant_rank end)
                                    when e.drawn_at is not null then coalesce(t.draw_rank,0) end,
                       'label', (select x->>'label' from jsonb_array_elements(e.draw_prizes) x
                                  where (x->>'rank')::int = case when t.mode='instant' then (case when t.revealed_at is not null or p_full then t.instant_rank end)
                                                                 when e.drawn_at is not null then t.draw_rank end limit 1),
                       'redeemed_at',t.redeemed_at,'void',t.void_at is not null) order by t.no),'[]'::jsonb)
                  from ev.ticket t where t.entrant_id=n.id and (p_staff or t.void_at is null))
  ) from ev.entrant n join ev.event e on e.id=n.event_id where n.id=p_ent $$;

create or replace function ev.f_stats(p_ev int) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object(
    'entrants', (select count(*) from ev.entrant where event_id=p_ev),
    'entrants_today', (select count(*) from ev.entrant where event_id=p_ev and (created_at at time zone 'Asia/Seoul')::date = ev.f_today()),
    'self_reg', (select count(*) from ev.entrant where event_id=p_ev and self_reg),
    'marketing_ok', (select count(*) from ev.entrant where event_id=p_ev and marketing_ok),
    'member_consent', (select count(*) from ev.entrant where event_id=p_ev and member_consent),
    'dps_reg', (select count(*) from ev.entrant n where event_id=p_ev and (ev.f_dps(n.phone)->>'reg')::boolean),
    'dps_need', (select count(*) from ev.entrant n where event_id=p_ev and (n.member_consent or n.member_answer='join') and n.dps_done_at is null
                    and not (ev.f_dps(n.phone)->>'reg')::boolean),
    'dps_done', (select count(*) from ev.entrant where event_id=p_ev and dps_done_at is not null),
    'spins', (select count(*) from ev.spin where event_id=p_ev and void_at is null),
    'spins_used', (select count(*) from ev.spin where event_id=p_ev and void_at is null and used_at is not null),
    'spin_ranks', (select coalesce(jsonb_object_agg(prize_rank, c),'{}'::jsonb) from (select prize_rank, count(*) c from ev.spin where event_id=p_ev and void_at is null and used_at is not null group by 1) z),
    'spin_redeemed', (select count(*) from ev.spin where event_id=p_ev and void_at is null and redeemed_at is not null),
    'tickets', (select count(*) from ev.ticket where event_id=p_ev and void_at is null),
    'tickets_today', (select count(*) from ev.ticket where event_id=p_ev and void_at is null and (issued_at at time zone 'Asia/Seoul')::date = ev.f_today()),
    'tickets_instant', (select count(*) from ev.ticket where event_id=p_ev and void_at is null and mode='instant'),
    'tickets_draw', (select count(*) from ev.ticket where event_id=p_ev and void_at is null and mode='draw'),
    'revealed', (select count(*) from ev.ticket where event_id=p_ev and void_at is null and mode='instant' and revealed_at is not null),
    'instant_ranks_shown', (select coalesce(jsonb_object_agg(instant_rank, c),'{}'::jsonb) from (select instant_rank, count(*) c from ev.ticket where event_id=p_ev and void_at is null and mode='instant' and revealed_at is not null group by 1) z)
  ) $$;
revoke all on function ev.f_me(bigint,boolean,boolean), ev.f_stats(int) from public, anon, authenticated;

-- ── 고객 화면: 직접 참여 등록 (즉석뽑기는 직원이 확인 후) · 같은 접속에서 1시간 10번까지 ──
create or replace function public.fn_lucky_join(p_name text, p_phone text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare e ev.event; v_ip text; v_nm text := btrim(regexp_replace(coalesce(p_name,''),'\s+',' ','g')); v_ph text := ev.f_phone(p_phone);
  v_ent bigint; v_old text;
begin
  select coalesce(nullif(r.ip,''), r.key) into v_ip from core.f_req_ident() r;
  if (select count(*) from ev.join_log j where j.ip = v_ip and j.at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('ok',false,'error','등록을 너무 많이 시도했습니다. 직원에게 말씀해 주세요'); end if;
  select * into e from ev.event where id = ev.f_cur();
  if e.id is null then return jsonb_build_object('ok',false,'error','진행 중인 이벤트가 없습니다'); end if;
  if ev.f_today() > e.end_date and not e.keep_open then return jsonb_build_object('ok',false,'error','이벤트 기간이 끝났습니다'); end if;
  if v_nm = '' or char_length(v_nm) > 20 then return jsonb_build_object('ok',false,'error','이름을 적어 주세요'); end if;
  if v_ph !~ '^01[0-9]{8,9}$' then return jsonb_build_object('ok',false,'error','휴대폰 번호를 확인해 주세요'); end if;
  if coalesce((p_data->>'privacy')::boolean,false) = false then return jsonb_build_object('ok',false,'error','개인정보 수집·이용 동의(필수)에 체크해 주세요'); end if;
  insert into ev.join_log(ip) values (v_ip);
  select id, name into v_ent, v_old from ev.entrant where event_id = e.id and phone = v_ph;
  if v_ent is null then
    insert into ev.entrant(event_id, name, phone, created_by, self_reg) values (e.id, v_nm, v_ph, '고객 직접', true) returning id into v_ent;
  elsif ev.f_name(v_old) <> ev.f_name(v_nm) then
    return jsonb_build_object('ok',false,'error','이 번호는 다른 이름으로 등록돼 있습니다. 직원에게 말씀해 주세요');
  end if;
  perform ev.f_consent_save(v_ent, p_data, '고객 화면');
  return jsonb_build_object('ok',true,'event',ev.f_pub(e.id),'me',ev.f_me(v_ent));
end $$;

-- ── 담당자 화면 ──
-- 번호를 적으면 DPS 상태 · 이 회차 등록 여부(고객이 직접 등록했으면 동의 내용)를 미리 보여 준다
create or replace function public.fn_store_lucky_check(p_code text, p_phone text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_ph text := ev.f_phone(p_phone); v_ent bigint;
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_ph !~ '^01[0-9]{8,9}$' then return jsonb_build_object('ok',false); end if;
  select id into v_ent from ev.entrant where event_id = ev.f_cur() and phone = v_ph;
  return jsonb_build_object('ok',true,'dps',ev.f_dps(v_ph),
    'entrant', case when v_ent is null then null else (select jsonb_build_object('id',n.id,'name',ev.f_mask_name(n.name),'name_len',char_length(n.name),
                 'member_answer',n.member_answer,'privacy',n.privacy_at is not null,'marketing_ok',n.marketing_ok,'member_consent',n.member_consent,
                 'self_reg',n.self_reg,'spins',(select count(*) from ev.spin s where s.entrant_id=n.id and s.void_at is null),
                 'tickets',(select count(*) from ev.ticket t where t.entrant_id=n.id and t.void_at is null)) from ev.entrant n where n.id=v_ent) end);
end $$;

create or replace function public.fn_store_lucky_issue(p_code text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); e ev.event; v_ent bigint; v_old text;
  v_nm text := btrim(regexp_replace(coalesce(p_data->>'name',''),'\s+',' ','g'));
  v_ph text := ev.f_phone(p_data->>'phone');
  n_sp int := coalesce(nullif(p_data->>'spins','')::int, 0);
  n_tk int := coalesce(nullif(p_data->>'tickets','')::int, 0);
  v_reason text := left(btrim(coalesce(p_data->>'reason','')), 40);
  v_ref text := left(btrim(coalesce(p_data->>'ref','')), 80);
  v_has_consent boolean := p_data ? 'privacy';
  v_no int; v_left int; r numeric; acc numeric; v_rank int; rem int; p jsonb; nos int[] := '{}';
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into e from ev.event where id = ev.f_cur() for update;
  if e.id is null then raise exception '진행 중인 이벤트가 없습니다' using errcode='22023'; end if;
  if ev.f_today() > e.end_date and not e.keep_open then raise exception '이벤트 기간(%까지)이 끝났습니다', e.end_date using errcode='22023'; end if;
  if v_nm = '' or char_length(v_nm) > 20 then raise exception '고객 이름을 적어 주세요 (20자까지)' using errcode='22023'; end if;
  if v_ph !~ '^01[0-9]{8,9}$' then raise exception '휴대폰 번호를 확인해 주세요 (010 으로 시작하는 10~11자리)' using errcode='22023'; end if;
  if n_sp < 0 or n_sp > 3 then raise exception '즉석뽑기는 한 번에 3회까지 줄 수 있습니다' using errcode='22023'; end if;
  if n_tk < 0 or n_tk > 30 then raise exception '행운권은 한 번에 30장까지 줄 수 있습니다' using errcode='22023'; end if;
  if n_sp = 0 and n_tk = 0 and not v_has_consent and coalesce((p_data->>'register_only')::boolean,false) = false then
    raise exception '줄 것(즉석뽑기 또는 행운권)을 골라 주세요' using errcode='22023'; end if;
  if n_tk > 0 and v_reason = '' then raise exception '행운권 사유(100만원 이상 구매 · 구독 계약)를 골라 주세요' using errcode='22023'; end if;

  select id, name into v_ent, v_old from ev.entrant where event_id = e.id and phone = v_ph;
  if v_ent is null then
    if v_has_consent and coalesce((p_data->>'privacy')::boolean,false) = false then
      raise exception '개인정보 수집·이용 동의(필수)를 받아 주세요' using errcode='22023'; end if;
    insert into ev.entrant(event_id, name, phone, memo, created_by) values (e.id, v_nm, v_ph, nullif(left(btrim(coalesce(p_data->>'memo','')),100),''), v_me)
    returning id into v_ent;
  elsif ev.f_name(v_old) <> ev.f_name(v_nm) then
    raise exception '이 번호는 다른 이름(%)으로 등록돼 있습니다. 이름을 확인해 주세요', ev.f_mask_name(v_old) using errcode='22023';
  end if;
  if v_has_consent then perform ev.f_consent_save(v_ent, p_data, '담당자 ' || v_me); end if;

  for i in 1..n_sp loop
    insert into ev.spin(event_id, entrant_id, reason, granted_by) values (e.id, v_ent, coalesce(nullif(p_data->>'spin_reason',''),'멤버십 가입'), v_me);
  end loop;

  for i in 1..n_tk loop
    select coalesce(max(no),0)+1 into v_no from ev.ticket where event_id = e.id;
    v_rank := null;
    if e.mode = 'instant' then
      v_left := greatest(e.expect_tickets - (select count(*) from ev.ticket where event_id=e.id and mode='instant' and void_at is null), 1);
      r := random(); acc := 0; v_rank := 0;
      for p in select x from jsonb_array_elements(e.draw_prizes) x order by (x->>'rank')::int loop
        select coalesce((p->>'qty')::int,1) - count(*) into rem from ev.ticket
         where event_id=e.id and mode='instant' and void_at is null and instant_rank = (p->>'rank')::int;
        if rem <= 0 then continue; end if;
        acc := acc + rem::numeric / v_left;
        if r < acc then v_rank := (p->>'rank')::int; exit; end if;
      end loop;
    end if;
    insert into ev.ticket(event_id, entrant_id, no, mode, reason, ref, issued_by, instant_rank)
    values (e.id, v_ent, v_no, e.mode, v_reason, nullif(v_ref,''), v_me, v_rank);
    nos := nos || v_no;
  end loop;

  return jsonb_build_object('ok',true,'new_tickets',to_jsonb(nos),'new_spins',n_sp,'row',ev.f_me(v_ent, true),'stats',ev.f_stats(e.id));
end $$;

-- 지급 완료 · 되돌리기 · 취소 + 참여 고객: DPS 등록 완료 / 되돌리기 / 즉석뽑기 1회 주기
create or replace function public.fn_store_lucky_mark(p_code text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_kind text := p_data->>'kind'; v_op text := p_data->>'op'; v_id bigint := nullif(p_data->>'id','')::bigint;
  v_ent bigint; s ev.spin; t ev.ticket; e ev.event; n ev.entrant; v_rs text := left(btrim(coalesce(p_data->>'reason','')),60);
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_kind = 'entrant' then
    select * into n from ev.entrant where id = v_id for update;
    if n.id is null then raise exception '참여 고객을 찾지 못했습니다' using errcode='22023'; end if;
    v_ent := n.id;
    if v_op = 'dps_done' then update ev.entrant set dps_done_at = now(), dps_done_by = v_me where id = v_id;
    elsif v_op = 'dps_undo' then update ev.entrant set dps_done_at = null, dps_done_by = null where id = v_id;
    elsif v_op = 'give_spin' then
      select * into e from ev.event where id = n.event_id;
      if ev.f_today() > e.end_date and not e.keep_open then raise exception '이벤트 기간이 끝났습니다' using errcode='22023'; end if;
      insert into ev.spin(event_id, entrant_id, reason, granted_by) values (n.event_id, n.id, coalesce(nullif(v_rs,''),'멤버십 가입'), v_me);
    else raise exception '알 수 없는 동작' using errcode='22023'; end if;
  elsif v_kind = 'spin' then
    select * into s from ev.spin where id = v_id for update;
    if s.id is null then raise exception '즉석뽑기를 찾지 못했습니다' using errcode='22023'; end if;
    v_ent := s.entrant_id;
    if v_op = 'redeem' then
      if s.used_at is null then raise exception '아직 뽑지 않았습니다' using errcode='22023'; end if;
      update ev.spin set redeemed_at = now(), redeemed_by = v_me where id = v_id;
    elsif v_op = 'unredeem' then update ev.spin set redeemed_at = null, redeemed_by = null where id = v_id;
    elsif v_op = 'void' then
      if s.used_at is not null then raise exception '이미 뽑은 즉석뽑기는 취소할 수 없습니다' using errcode='22023'; end if;
      update ev.spin set void_at = now(), void_by = v_me, void_reason = nullif(v_rs,'') where id = v_id;
    else raise exception '알 수 없는 동작' using errcode='22023'; end if;
  elsif v_kind = 'ticket' then
    select * into t from ev.ticket where id = v_id for update;
    if t.id is null then raise exception '행운권을 찾지 못했습니다' using errcode='22023'; end if;
    select * into e from ev.event where id = t.event_id;
    v_ent := t.entrant_id;
    if v_op = 'redeem' then
      if not ((t.mode='instant' and t.revealed_at is not null and t.instant_rank > 0) or (t.mode='draw' and t.draw_rank is not null)) then
        raise exception '당첨된 행운권만 지급 완료로 표시합니다' using errcode='22023'; end if;
      update ev.ticket set redeemed_at = now(), redeemed_by = v_me where id = v_id;
    elsif v_op = 'unredeem' then update ev.ticket set redeemed_at = null, redeemed_by = null where id = v_id;
    elsif v_op = 'void' then
      if t.revealed_at is not null then raise exception '고객이 이미 긁은 행운권은 취소할 수 없습니다' using errcode='22023'; end if;
      if t.mode = 'draw' and e.drawn_at is not null then raise exception '추첨이 끝난 뒤에는 취소할 수 없습니다' using errcode='22023'; end if;
      update ev.ticket set void_at = now(), void_by = v_me, void_reason = nullif(v_rs,'') where id = v_id;
    else raise exception '알 수 없는 동작' using errcode='22023'; end if;
  else raise exception '알 수 없는 종류' using errcode='22023'; end if;
  return jsonb_build_object('ok',true,'row',ev.f_me(v_ent, true));
end $$;

-- 고객 조회 실패 문구 — 직접 등록이 생겼으니 [참여 등록]으로 안내 (ev.f_who 원본에서 그 줄만 치환)
--   '참여 내역이 없습니다. 매장에서 등록한 이름·번호로 조회해 주세요' → '참여 내역이 없습니다. 처음이시면 위의 [참여 등록]을 눌러 주세요'
-- 적용: 2026-11-10 운영 DB (apply_migration mvp_292_lucky_membership + f_who 문구 치환) · 시험은 롤백 블록으로만
