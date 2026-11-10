-- mvp_290 · 2026-11-10 · 행운 이벤트 — 즉석뽑기(룰렛) · 행운권(즉석 확인 = 복권 긁기 / 1회 확인 = 럭키드로우 추첨)
-- 행사 목적: 총 예산 500만원 · 추가 기대 매출 1억 · 판촉 가능 고객 확보 · 매장 인지도 · 매출 확대
--   1단계 매장 방문 참여 → 2,000원 사은품(과자·키친타올)
--   2단계 멤버십 간편 가입 → 사은품 + 재방문 쿠폰 + 즉석뽑기 1회 (100% 당첨, 꽝 = 과자 + 5,000원 할인권)
--   3단계 100만원 이상 구매 또는 구독 1계약 → 위 전부 + 행운권 1장(계약당)
-- 고객 화면 /lucky/ (이름 + 휴대폰 번호로 조회) · 담당자 화면 [행운 이벤트] 탭 · 관리자 [행운 이벤트] 메뉴
-- 당첨은 전부 서버가 정한다. 즉석 확인 행운권은 발급할 때 정해 두고(남은 경품 ÷ 남은 예상 장수) 고객이 긁을 때 공개한다.
-- 행운권마다 발급 당시 방식(mode)을 적어 두므로 중간에 방식을 바꿔도 이미 나간 행운권은 그대로다.

create schema if not exists ev;
revoke all on schema ev from public, anon, authenticated;

create table if not exists ev.event (
  id serial primary key,
  name text not null default '삼성스토어 시흥 행운 이벤트',
  start_date date not null default ((now() at time zone 'Asia/Seoul')::date),
  end_date date not null default ((now() at time zone 'Asia/Seoul')::date + 30),
  draw_date date,
  mode text not null default 'draw' check (mode in ('instant','draw')),
  expect_tickets int not null default 400 check (expect_tickets > 0),
  spin_prizes jsonb not null default '[]'::jsonb,
  draw_prizes jsonb not null default '[]'::jsonb,
  goal jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  drawn_at timestamptz, drawn_by text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), updated_by text
);

create table if not exists ev.entrant (
  id bigserial primary key,
  event_id int not null references ev.event(id),
  name text not null,
  phone text not null,
  memo text,
  created_by text,
  created_at timestamptz not null default now(),
  constraint entrant_phone_ok check (phone ~ '^01[0-9]{8,9}$'),
  constraint entrant_name_len check (char_length(name) between 1 and 20)
);
create unique index if not exists ux_ev_entrant_phone on ev.entrant (event_id, phone);

create table if not exists ev.spin (
  id bigserial primary key,
  event_id int not null references ev.event(id),
  entrant_id bigint not null references ev.entrant(id),
  reason text,
  granted_by text,
  granted_at timestamptz not null default now(),
  used_at timestamptz,
  prize_rank int,
  prize_label text,
  coupon text,
  redeemed_at timestamptz, redeemed_by text,
  void_at timestamptz, void_by text, void_reason text
);
create index if not exists ix_ev_spin_entrant on ev.spin (entrant_id);
create index if not exists ix_ev_spin_rank on ev.spin (event_id, prize_rank) where used_at is not null and void_at is null;

create table if not exists ev.ticket (
  id bigserial primary key,
  event_id int not null references ev.event(id),
  entrant_id bigint not null references ev.entrant(id),
  no int not null,
  mode text not null check (mode in ('instant','draw')),
  reason text,
  ref text,
  issued_by text,
  issued_at timestamptz not null default now(),
  instant_rank int,          -- 즉석 확인: 발급 때 정함 (0 = 미당첨) · 긁기 전에는 어디에도 내보내지 않는다
  revealed_at timestamptz,
  draw_rank int,             -- 1회 확인: 추첨 결과 (null = 미당첨 · 추첨 여부는 event.drawn_at)
  redeemed_at timestamptz, redeemed_by text,
  void_at timestamptz, void_by text, void_reason text
);
create unique index if not exists ux_ev_ticket_no on ev.ticket (event_id, no);
create index if not exists ix_ev_ticket_entrant on ev.ticket (entrant_id);

create table if not exists ev.lookup_fail (ip text not null, at timestamptz not null default now());
create index if not exists ix_ev_lookup_fail on ev.lookup_fail (ip, at);

alter table ev.event enable row level security;
alter table ev.entrant enable row level security;
alter table ev.spin enable row level security;
alter table ev.ticket enable row level security;
alter table ev.lookup_fail enable row level security;
revoke all on all tables in schema ev from public, anon, authenticated;

-- 첫 회차 (관리자 화면에서 기간·경품·방식을 고친다)
insert into ev.event (id, name, start_date, end_date, draw_date, mode, expect_tickets, spin_prizes, draw_prizes, goal)
select 1, '삼성스토어 시흥 행운 이벤트', date '2026-11-10', date '2026-12-09', date '2026-12-10', 'draw', 400,
 '[{"rank":1,"label":"로얄 20만 포인트","sub":"삼성전자 로얄 멤버십 포인트","prob":1,"stock":null,"value":200000},
   {"rank":2,"label":"제품 50% 할인권","sub":"오디세이 G5 게이밍 모니터","prob":2,"stock":null,"value":0,"img":"img/prize2_odyssey_g5.jpg"},
   {"rank":3,"label":"커피 쿠폰 5,000원","sub":"모바일 커피 쿠폰","prob":10,"stock":null,"value":5000},
   {"rank":0,"label":"과자 + 5,000원 할인권","sub":"꽝 없이 모두 드려요","value":2000}]'::jsonb,
 '[{"rank":1,"label":"무선 청소기","sub":"100만원 상당","qty":1,"value":1000000},
   {"rank":2,"label":"공기청정기","sub":"58만원 상당","qty":1,"value":580000},
   {"rank":3,"label":"믹서기","sub":"20만원 상당","qty":1,"value":200000},
   {"rank":4,"label":"캡슐 커피머신","sub":"14만원 상당","qty":2,"value":140000},
   {"rank":5,"label":"두유 제조기","sub":"10만원 상당","qty":3,"value":100000}]'::jsonb,
 '{"budget":5000000,"sales":100000000,"visitors":200,"tickets":400,"gift_unit":2000,"sale_goal":300000000,"sub_goal":100}'::jsonb
where not exists (select 1 from ev.event);
select setval(pg_get_serial_sequence('ev.event','id'), greatest((select max(id) from ev.event),1));

-- ── 내부 도우미 ──
create or replace function ev.f_phone(p text) returns text language sql immutable as $$ select regexp_replace(coalesce(p,''),'\D','','g') $$;
create or replace function ev.f_name(p text) returns text language sql immutable as $$ select regexp_replace(btrim(coalesce(p,'')),'\s+','','g') $$;
create or replace function ev.f_mask_name(p text) returns text language sql immutable as $$
  select case when char_length(p) <= 1 then p
              when char_length(p) = 2 then left(p,1)||'*'
              else left(p,1)||repeat('*', char_length(p)-2)||right(p,1) end $$;
create or replace function ev.f_mask_phone(p text) returns text language sql immutable as $$
  select left(p,3)||'-****-'||right(p,4) $$;
create or replace function ev.f_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;

-- 지금 회차: 기간 안에 든 활성 회차 → 없으면 가장 최근 활성 회차
create or replace function ev.f_cur() returns int language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select id from ev.event where active
   order by (ev.f_today() between start_date and end_date) desc, start_date desc, id desc limit 1 $$;

-- 공개 정보 (고객 화면 · 추첨 화면)
create or replace function ev.f_pub(p_ev int) returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object(
    'id', e.id, 'name', e.name, 'start_date', e.start_date, 'end_date', e.end_date, 'draw_date', e.draw_date,
    'mode', e.mode, 'today', ev.f_today(), 'open', ev.f_today() between e.start_date and e.end_date,
    'spin_prizes', (select coalesce(jsonb_agg(jsonb_build_object('rank',(x->>'rank')::int,'label',x->>'label','sub',x->>'sub','img',x->>'img','prob',x->'prob')
                                              order by case when (x->>'rank')::int=0 then 99 else (x->>'rank')::int end),'[]'::jsonb)
                      from jsonb_array_elements(e.spin_prizes) x),
    'draw_prizes', (select coalesce(jsonb_agg(jsonb_build_object('rank',(x->>'rank')::int,'label',x->>'label','sub',x->>'sub','img',x->>'img','qty',coalesce((x->>'qty')::int,1))
                                              order by (x->>'rank')::int),'[]'::jsonb)
                      from jsonb_array_elements(e.draw_prizes) x),
    'drawn', e.drawn_at is not null, 'drawn_at', e.drawn_at,
    'tickets', (select count(*) from ev.ticket t where t.event_id=e.id and t.void_at is null and t.mode='draw'),
    'tickets_all', (select count(*) from ev.ticket t where t.event_id=e.id and t.void_at is null),
    'entrants', (select count(*) from ev.entrant n where n.event_id=e.id),
    'winners', case when e.drawn_at is null then '[]'::jsonb else (
        select coalesce(jsonb_agg(jsonb_build_object('rank',t.draw_rank,'no',t.no,'name',ev.f_mask_name(n.name),'phone4',right(n.phone,4),
                  'label',(select x->>'label' from jsonb_array_elements(e.draw_prizes) x where (x->>'rank')::int=t.draw_rank limit 1))
                  order by t.draw_rank, t.no),'[]'::jsonb)
          from ev.ticket t join ev.entrant n on n.id=t.entrant_id
         where t.event_id=e.id and t.draw_rank is not null and t.void_at is null) end,
    'instant_winners', (
        select coalesce(jsonb_agg(jsonb_build_object('rank',t.instant_rank,'no',t.no,'name',ev.f_mask_name(n.name),'at',t.revealed_at) order by t.revealed_at desc),'[]'::jsonb)
          from ev.ticket t join ev.entrant n on n.id=t.entrant_id
         where t.event_id=e.id and t.mode='instant' and t.revealed_at is not null and t.instant_rank > 0 and t.void_at is null)
  ) from ev.event e where e.id = p_ev $$;

-- 고객 한 명의 즉석뽑기·행운권 (p_full = 관리자: 즉석 확인 결과를 미리 본다)
create or replace function ev.f_me(p_ent bigint, p_staff boolean default false, p_full boolean default false) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object(
    'id', n.id, 'name', n.name,
    'phone', case when p_full then n.phone when p_staff then ev.f_mask_phone(n.phone) else null end,
    'phone4', right(n.phone,4), 'memo', case when p_staff then n.memo end,
    'created_at', n.created_at, 'created_by', case when p_staff then n.created_by end,
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

-- 고객 확인 (이름 + 번호) · 같은 접속에서 10분에 15번 틀리면 잠시 막는다. 예외를 던지면 실패 기록도 롤백되므로 오류는 jsonb 로 돌려준다
create or replace function ev.f_who(p_name text, p_phone text, out ent bigint, out err text)
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_ip text; v_ev int := ev.f_cur(); v_ph text := ev.f_phone(p_phone); v_nm text := ev.f_name(p_name);
begin
  select coalesce(nullif(r.ip,''), r.key) into v_ip from core.f_req_ident() r;
  if (select count(*) from ev.lookup_fail f where f.ip = v_ip and f.at > now() - interval '10 minutes') >= 15 then
    err := '조회를 너무 많이 시도했습니다. 10분 뒤 다시 해 주세요'; return; end if;
  if v_ev is null then err := '진행 중인 이벤트가 없습니다'; return; end if;
  if v_nm = '' or v_ph !~ '^01[0-9]{8,9}$' then err := '이름과 휴대폰 번호를 정확히 적어 주세요'; return; end if;
  select n.id into ent from ev.entrant n where n.event_id = v_ev and n.phone = v_ph and ev.f_name(n.name) = v_nm;
  if ent is null then
    insert into ev.lookup_fail(ip) values (v_ip);
    err := '참여 내역이 없습니다. 매장에서 등록한 이름·번호로 조회해 주세요'; end if;
end $$;

revoke all on all functions in schema ev from public, anon, authenticated;

-- ── 고객 화면 (anon) ──
create or replace function public.fn_lucky_info(p_event int default null) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v int := coalesce(p_event, ev.f_cur());
begin
  if v is null then return jsonb_build_object('ok',false,'error','진행 중인 이벤트가 없습니다'); end if;
  return jsonb_build_object('ok',true,'event',ev.f_pub(v));
end $$;

create or replace function public.fn_lucky_me(p_name text, p_phone text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare w record;
begin
  select * into w from ev.f_who(p_name, p_phone);
  if w.err is not null then return jsonb_build_object('ok',false,'error',w.err); end if;
  return jsonb_build_object('ok',true,'event',ev.f_pub(ev.f_cur()),'me',ev.f_me(w.ent));
end $$;

-- 즉석뽑기 (룰렛) — 남은 1회를 쓰고 경품을 정한다. 회차 줄을 잠가 재고 계산이 겹치지 않게
create or replace function public.fn_lucky_spin(p_name text, p_phone text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare w record; e ev.event; v_sid bigint; r numeric; acc numeric := 0; v_rank int := 0; v_p jsonb; p jsonb; v_cp text; n_used int;
begin
  select * into w from ev.f_who(p_name, p_phone);
  if w.err is not null then return jsonb_build_object('ok',false,'error',w.err); end if;
  select * into e from ev.event where id = (select event_id from ev.entrant where id = w.ent) for update;
  if ev.f_today() > e.end_date then return jsonb_build_object('ok',false,'error','이벤트 기간이 끝났습니다'); end if;
  select id into v_sid from ev.spin where entrant_id = w.ent and used_at is null and void_at is null order by id limit 1 for update;
  if v_sid is null then return jsonb_build_object('ok',false,'error','남은 즉석뽑기가 없습니다','me',ev.f_me(w.ent)); end if;
  r := random() * 100;
  for p in select x from jsonb_array_elements(e.spin_prizes) x where coalesce((x->>'rank')::int,0) > 0 order by (x->>'rank')::int loop
    if nullif(p->>'stock','') is not null then
      select count(*) into n_used from ev.spin s where s.event_id = e.id and s.prize_rank = (p->>'rank')::int and s.used_at is not null and s.void_at is null;
      if n_used >= (p->>'stock')::int then continue; end if;
    end if;
    acc := acc + coalesce(nullif(p->>'prob','')::numeric, 0);
    if r < acc then v_rank := (p->>'rank')::int; v_p := p; exit; end if;
  end loop;
  if v_p is null then select x into v_p from jsonb_array_elements(e.spin_prizes) x where coalesce((x->>'rank')::int,0) = 0 limit 1; v_rank := 0; end if;
  v_cp := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  update ev.spin set used_at = now(), prize_rank = v_rank, prize_label = coalesce(v_p->>'label','참여 경품'), coupon = v_cp where id = v_sid;
  return jsonb_build_object('ok',true,'spin_id',v_sid,'rank',v_rank,'label',coalesce(v_p->>'label','참여 경품'),'sub',v_p->>'sub','img',v_p->>'img','coupon',v_cp,
                            'me',ev.f_me(w.ent));
end $$;

-- 즉석 확인 행운권 긁기 — 발급 때 정해 둔 결과를 공개
create or replace function public.fn_lucky_reveal(p_name text, p_phone text, p_no int) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare w record; t ev.ticket; e ev.event; v_p jsonb;
begin
  select * into w from ev.f_who(p_name, p_phone);
  if w.err is not null then return jsonb_build_object('ok',false,'error',w.err); end if;
  select * into t from ev.ticket where entrant_id = w.ent and no = p_no and void_at is null for update;
  if t.id is null then return jsonb_build_object('ok',false,'error','행운권을 찾지 못했습니다'); end if;
  if t.mode <> 'instant' then return jsonb_build_object('ok',false,'error','이 행운권은 추첨일에 결과가 나옵니다'); end if;
  if t.revealed_at is null then update ev.ticket set revealed_at = now() where id = t.id; end if;
  select * into e from ev.event where id = t.event_id;
  select x into v_p from jsonb_array_elements(e.draw_prizes) x where (x->>'rank')::int = t.instant_rank limit 1;
  return jsonb_build_object('ok',true,'no',t.no,'rank',coalesce(t.instant_rank,0),'label',v_p->>'label','sub',v_p->>'sub','img',v_p->>'img','me',ev.f_me(w.ent));
end $$;

-- ── 담당자 화면 ──
create or replace function ev.f_staff_rows(p_ev int, p_q text) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with q as (select nullif(btrim(coalesce(p_q,'')),'') s, nullif(ev.f_phone(p_q),'') d),
  hit as (
    select n.id, greatest(n.created_at,
             coalesce((select max(greatest(s.granted_at, coalesce(s.used_at, s.granted_at))) from ev.spin s where s.entrant_id=n.id), n.created_at),
             coalesce((select max(t.issued_at) from ev.ticket t where t.entrant_id=n.id), n.created_at)) last_at
      from ev.entrant n, q
     where n.event_id = p_ev
       and (q.s is null or n.name ilike '%'||q.s||'%' or (q.d is not null and char_length(q.d) >= 4 and n.phone like '%'||q.d||'%')
            or exists (select 1 from ev.ticket t where t.entrant_id=n.id and q.s ~ '^\d{1,6}$' and t.no = q.s::int))
  )
  select coalesce(jsonb_agg(ev.f_me(h.id, true) order by h.last_at desc), '[]'::jsonb)
    from (select * from hit order by last_at desc limit 40) h $$;

create or replace function ev.f_stats(p_ev int) returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select jsonb_build_object(
    'entrants', (select count(*) from ev.entrant where event_id=p_ev),
    'entrants_today', (select count(*) from ev.entrant where event_id=p_ev and (created_at at time zone 'Asia/Seoul')::date = ev.f_today()),
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
revoke all on function ev.f_staff_rows(int,text), ev.f_stats(int) from public, anon, authenticated;

create or replace function public.fn_store_lucky(p_code text, p_q text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_ev int := ev.f_cur();
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_ev is null then return jsonb_build_object('event',null,'rows','[]'::jsonb); end if;
  return jsonb_build_object('event', ev.f_pub(v_ev) || jsonb_build_object('expect_tickets',(select expect_tickets from ev.event where id=v_ev)),
                            'stats', ev.f_stats(v_ev), 'rows', ev.f_staff_rows(v_ev, p_q), 'me', v_me);
end $$;

-- 발급: 즉석뽑기 n회 · 행운권 n장 (처음 오는 번호면 고객을 만든다)
create or replace function public.fn_store_lucky_issue(p_code text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); e ev.event; v_ent bigint; v_old text;
  v_nm text := btrim(regexp_replace(coalesce(p_data->>'name',''),'\s+',' ','g'));
  v_ph text := ev.f_phone(p_data->>'phone');
  n_sp int := coalesce(nullif(p_data->>'spins','')::int, 0);
  n_tk int := coalesce(nullif(p_data->>'tickets','')::int, 0);
  v_reason text := left(btrim(coalesce(p_data->>'reason','')), 40);
  v_ref text := left(btrim(coalesce(p_data->>'ref','')), 80);
  v_no int; v_left int; r numeric; acc numeric; v_rank int; rem int; p jsonb; nos int[] := '{}';
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into e from ev.event where id = ev.f_cur() for update;
  if e.id is null then raise exception '진행 중인 이벤트가 없습니다' using errcode='22023'; end if;
  if ev.f_today() > e.end_date then raise exception '이벤트 기간(%까지)이 끝났습니다', e.end_date using errcode='22023'; end if;
  if v_nm = '' or char_length(v_nm) > 20 then raise exception '고객 이름을 적어 주세요 (20자까지)' using errcode='22023'; end if;
  if v_ph !~ '^01[0-9]{8,9}$' then raise exception '휴대폰 번호를 확인해 주세요 (010 으로 시작하는 10~11자리)' using errcode='22023'; end if;
  if n_sp < 0 or n_sp > 3 then raise exception '즉석뽑기는 한 번에 3회까지 줄 수 있습니다' using errcode='22023'; end if;
  if n_tk < 0 or n_tk > 30 then raise exception '행운권은 한 번에 30장까지 줄 수 있습니다' using errcode='22023'; end if;
  if n_sp = 0 and n_tk = 0 and coalesce((p_data->>'register_only')::boolean,false) = false then
    raise exception '줄 것(즉석뽑기 또는 행운권)을 골라 주세요' using errcode='22023'; end if;
  if n_tk > 0 and v_reason = '' then raise exception '행운권 사유(100만원 이상 구매 · 구독 계약)를 골라 주세요' using errcode='22023'; end if;

  select id, name into v_ent, v_old from ev.entrant where event_id = e.id and phone = v_ph;
  if v_ent is null then
    insert into ev.entrant(event_id, name, phone, memo, created_by) values (e.id, v_nm, v_ph, nullif(left(btrim(coalesce(p_data->>'memo','')),100),''), v_me)
    returning id into v_ent;
  elsif ev.f_name(v_old) <> ev.f_name(v_nm) then
    raise exception '이 번호는 다른 이름(%)으로 등록돼 있습니다. 이름을 확인해 주세요', ev.f_mask_name(v_old) using errcode='22023';
  end if;

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

-- 지급 완료 표시 · 되돌리기 · 잘못 준 것 취소
create or replace function public.fn_store_lucky_mark(p_code text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); v_kind text := p_data->>'kind'; v_op text := p_data->>'op'; v_id bigint := nullif(p_data->>'id','')::bigint;
  v_ent bigint; s ev.spin; t ev.ticket; e ev.event; v_rs text := left(btrim(coalesce(p_data->>'reason','')),60);
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_kind = 'spin' then
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

-- ── 관리자 화면 ──
create or replace function public.fn_lucky_admin(p_event int default null, p_q text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v int := coalesce(p_event, ev.f_cur()); v_full boolean := core.f_role() = 'admin';
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  insert into crm.access_log (action, row_count, reason, actor_email) values ('lucky:admin', null, null, coalesce(auth.jwt()->>'email',''));
  return jsonb_build_object(
    'events', (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'start_date',start_date,'end_date',end_date,'active',active) order by id desc),'[]'::jsonb) from ev.event),
    'event', (select to_jsonb(e) from ev.event e where e.id = v),
    'pub', case when v is null then null else ev.f_pub(v) end,
    'stats', case when v is null then null else ev.f_stats(v) end,
    'can_edit', v_full,
    'rows', (select coalesce(jsonb_agg(ev.f_me(n.id, true, v_full) order by n.created_at desc),'[]'::jsonb)
               from ev.entrant n
              where n.event_id = v
                and (nullif(btrim(coalesce(p_q,'')),'') is null or n.name ilike '%'||btrim(p_q)||'%'
                     or (char_length(ev.f_phone(p_q)) >= 4 and n.phone like '%'||ev.f_phone(p_q)||'%')))
  );
end $$;

create or replace function public.fn_lucky_admin_save(p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_id int := nullif(p_data->>'id','')::int; v_by text := coalesce(auth.jwt()->>'email','admin'); v_mode text := coalesce(p_data->>'mode','draw');
begin
  if core.f_role() <> 'admin' then raise exception '이벤트 설정은 관리자만 바꿀 수 있습니다' using errcode='42501'; end if;
  if v_mode not in ('instant','draw') then raise exception '확인 방식이 잘못됐습니다' using errcode='22023'; end if;
  if jsonb_typeof(p_data->'spin_prizes') <> 'array' or jsonb_typeof(p_data->'draw_prizes') <> 'array' then raise exception '경품 표가 비어 있습니다' using errcode='22023'; end if;
  if (select coalesce(sum(nullif(x->>'prob','')::numeric),0) from jsonb_array_elements(p_data->'spin_prizes') x where coalesce((x->>'rank')::int,0) > 0) > 100 then
    raise exception '즉석뽑기 확률 합이 100%%를 넘습니다' using errcode='22023'; end if;
  if not exists (select 1 from jsonb_array_elements(p_data->'spin_prizes') x where coalesce((x->>'rank')::int,0) = 0) then
    raise exception '즉석뽑기에 기본 경품(꽝 대신)이 있어야 합니다' using errcode='22023'; end if;
  if v_id is null then
    insert into ev.event(name, start_date, end_date, draw_date, mode, expect_tickets, spin_prizes, draw_prizes, goal, active, updated_by)
    values (coalesce(nullif(btrim(p_data->>'name'),''),'행운 이벤트'), (p_data->>'start_date')::date, (p_data->>'end_date')::date, nullif(p_data->>'draw_date','')::date,
            v_mode, coalesce(nullif(p_data->>'expect_tickets','')::int,400), p_data->'spin_prizes', p_data->'draw_prizes', coalesce(p_data->'goal','{}'::jsonb),
            coalesce((p_data->>'active')::boolean,true), v_by) returning id into v_id;
  else
    update ev.event set name = coalesce(nullif(btrim(p_data->>'name'),''), name),
      start_date = coalesce((p_data->>'start_date')::date, start_date), end_date = coalesce((p_data->>'end_date')::date, end_date),
      draw_date = nullif(p_data->>'draw_date','')::date, mode = v_mode,
      expect_tickets = coalesce(nullif(p_data->>'expect_tickets','')::int, expect_tickets),
      spin_prizes = p_data->'spin_prizes', draw_prizes = p_data->'draw_prizes', goal = coalesce(p_data->'goal', goal),
      active = coalesce((p_data->>'active')::boolean, active), updated_at = now(), updated_by = v_by
     where id = v_id;
  end if;
  return public.fn_lucky_admin(v_id, null);
end $$;

-- 1회 확인 추첨 (럭키드로우) — 1회 확인 방식으로 나간 행운권만, 높은 등수부터. 기본 1인 1당첨
create or replace function public.fn_lucky_draw_run(p_event int, p_one_per_person boolean default true) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare e ev.event; p jsonb; v_t bigint; n int := 0;
begin
  if core.f_role() <> 'admin' then raise exception '추첨은 관리자만 할 수 있습니다' using errcode='42501'; end if;
  select * into e from ev.event where id = p_event for update;
  if e.id is null then raise exception '회차를 찾지 못했습니다' using errcode='22023'; end if;
  if e.drawn_at is not null then raise exception '이미 추첨했습니다 (%)', to_char(e.drawn_at at time zone 'Asia/Seoul','MM-DD HH24:MI') using errcode='22023'; end if;
  for p in select x from jsonb_array_elements(e.draw_prizes) x order by (x->>'rank')::int loop
    for k in 1..coalesce((p->>'qty')::int,1) loop
      select t.id into v_t from ev.ticket t
       where t.event_id = e.id and t.mode = 'draw' and t.void_at is null and t.draw_rank is null
         and (not p_one_per_person or not exists (select 1 from ev.ticket w where w.event_id = e.id and w.entrant_id = t.entrant_id and w.draw_rank is not null))
       order by random() limit 1;
      exit when v_t is null;
      update ev.ticket set draw_rank = (p->>'rank')::int where id = v_t; n := n + 1;
    end loop;
  end loop;
  if n = 0 then raise exception '추첨할 행운권(1회 확인 방식)이 없습니다' using errcode='22023'; end if;
  update ev.event set drawn_at = now(), drawn_by = coalesce(auth.jwt()->>'email','admin') where id = e.id;
  return public.fn_lucky_admin(e.id, null);
end $$;

create or replace function public.fn_lucky_draw_reset(p_event int, p_confirm text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 되돌릴 수 있습니다' using errcode='42501'; end if;
  if coalesce(p_confirm,'') <> '다시 추첨' then raise exception '확인 글자가 맞지 않습니다' using errcode='22023'; end if;
  if exists (select 1 from ev.ticket where event_id = p_event and draw_rank is not null and redeemed_at is not null) then
    raise exception '이미 경품을 드린 당첨이 있어 되돌릴 수 없습니다' using errcode='22023'; end if;
  update ev.ticket set draw_rank = null where event_id = p_event and draw_rank is not null;
  update ev.event set drawn_at = null, drawn_by = null, updated_at = now() where id = p_event;
  return public.fn_lucky_admin(p_event, null);
end $$;

-- 관리자 메뉴 (테스트 화면부터) — 승격할 때 envs 에 'prod' 를 더한다
insert into core.menu_item(code, group_code, label, sort, state, note, envs)
values ('lucky','crm','행운 이벤트',90,'on','즉석뽑기·행운권·럭키드로우 (mvp_290)', array['test'])
on conflict (code) do update set label=excluded.label, group_code=excluded.group_code, note=excluded.note;

-- 보안 점검(search_path) 경고 막기 — 단순 도우미 함수도 search_path 고정
alter function ev.f_phone(text) set search_path to 'pg_catalog';
alter function ev.f_name(text) set search_path to 'pg_catalog';
alter function ev.f_mask_name(text) set search_path to 'pg_catalog';
alter function ev.f_mask_phone(text) set search_path to 'pg_catalog';
alter function ev.f_today() set search_path to 'pg_catalog';
-- 적용: 2026-11-10 운영 DB (apply_migration mvp_290_lucky_event) · 시험은 롤백 블록으로만 (실데이터 없음)
