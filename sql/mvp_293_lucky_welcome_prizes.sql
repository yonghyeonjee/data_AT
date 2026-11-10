-- mvp_293 · 2026-11-10 · 행운 이벤트 — 경품 교체 · 참여 등록 = 누구나 즉석뽑기 1회 · 멤버십 가입 = 행운권 1장
-- 사용자: "1등 로열 20만원 말고 20만원 포인트(자유 사용) · 2등 제품 50% 할인 · 3등 스타벅스 아메리카노 · 누구나 1회 ·
--          회원가입하면 행운권 1권도 · 행운권 경품은 삼성 제품 이미지로 · 4등에 (필수 소모품 등)"
-- 멤버십 가입 = 고객이 '삼성멤버십 가입 동의' 체크(member_consent) · 담당자 '오늘 가입'(member_answer='join') · 담당자 [DPS 등록 완료].
--   '이미 회원'이라고만 답한 고객은 새로 가입한 게 아니라 행운권을 자동으로 주지 않는다 (담당자가 [주기]로 줄 수 있음).
-- 행운권 경품 이미지 = 시흥몰(고도몰) 상품 대표 이미지 (core.godo_goods.main_image).

-- 1) 경품표
update ev.event set
  spin_prizes = '[{"rank":1,"label":"20만원 포인트","sub":"자유 사용","prob":1,"stock":null,"value":200000},
                  {"rank":2,"label":"제품 50% 할인권","sub":"오디세이 G5 게이밍 모니터","prob":2,"stock":null,"value":0,"img":"img/prize2_odyssey_g5.jpg"},
                  {"rank":3,"label":"스타벅스 아메리카노","sub":"모바일 쿠폰","prob":10,"stock":null,"value":4700},
                  {"rank":0,"label":"과자 + 5,000원 할인권","sub":"꽝 없이 모두 드려요","value":2000}]'::jsonb,
  draw_prizes = '[{"rank":1,"label":"비스포크 AI 제트 Lite 무선청소기","sub":"VS28D950ACB · 95만원 상당","qty":1,"value":950000,"img":"https://godomall-storage.cdn-nhncommerce.com/bbfe079be9069f71afe7ad9a5bf9cee9/goods/1000000811/image/main/1000000811_main_028.png"},
                  {"rank":2,"label":"Infinite AI 공기청정기","sub":"AP90H03163EGD · 72.9만원 상당","qty":1,"value":729000,"img":"https://godomall-storage.cdn-nhncommerce.com/bbfe079be9069f71afe7ad9a5bf9cee9/goods/1000000652/image/main/1000000652_main_012.jpg"},
                  {"rank":3,"label":"갤럭시 버즈4","sub":"SM-R540N · 22만원 상당","qty":1,"value":220200,"img":"https://godomall-storage.cdn-nhncommerce.com/bbfe079be9069f71afe7ad9a5bf9cee9/goods/1000000674/image/main/1000000674_main_017.jpg"},
                  {"rank":4,"label":"비스포크 정수기 필터 (필수 소모품 등)","sub":"HAF-HIN · 14.9만원 상당","qty":2,"value":149000,"img":"https://godomall-storage.cdn-nhncommerce.com/bbfe079be9069f71afe7ad9a5bf9cee9/goods/1000000076/image/main/1000000076_main_099.png"},
                  {"rank":5,"label":"스마트싱스 스테이션 무선충전","sub":"EP-P9500 · 9.9만원 상당","qty":3,"value":99000,"img":"https://godomall-storage.cdn-nhncommerce.com/bbfe079be9069f71afe7ad9a5bf9cee9/goods/1000000121/image/main/1000000121_main_066.png"}]'::jsonb,
  updated_at = now(), updated_by = 'mvp_293'
 where id = 1;

-- 2) 행운권 1장 발급 (즉석 확인이면 이때 당첨을 정함) — 회차 줄을 잠가 번호·재고가 겹치지 않게
create or replace function ev.f_ticket_issue(p_ev int, p_ent bigint, p_reason text, p_ref text, p_by text) returns int
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare e ev.event; v_no int; v_left int; r numeric; acc numeric := 0; v_rank int; rem int; p jsonb;
begin
  select * into e from ev.event where id = p_ev for update;
  select coalesce(max(no),0)+1 into v_no from ev.ticket where event_id = e.id;
  if e.mode = 'instant' then
    v_left := greatest(e.expect_tickets - (select count(*) from ev.ticket where event_id=e.id and mode='instant' and void_at is null), 1);
    r := random(); v_rank := 0;
    for p in select x from jsonb_array_elements(e.draw_prizes) x order by (x->>'rank')::int loop
      select coalesce((p->>'qty')::int,1) - count(*) into rem from ev.ticket
       where event_id=e.id and mode='instant' and void_at is null and instant_rank = (p->>'rank')::int;
      if rem <= 0 then continue; end if;
      acc := acc + rem::numeric / v_left;
      if r < acc then v_rank := (p->>'rank')::int; exit; end if;
    end loop;
  end if;
  insert into ev.ticket(event_id, entrant_id, no, mode, reason, ref, issued_by, instant_rank)
  values (e.id, p_ent, v_no, e.mode, p_reason, nullif(p_ref,''), p_by, v_rank);
  return v_no;
end $$;

-- 3) 참여 기본 혜택: 누구나 즉석뽑기 1회(받은 적 없으면) · 멤버십 가입이면 행운권 1장(멤버십 가입 행운권을 받은 적 없으면)
--    p_member: null = 동의·답으로 판단 · true = [DPS 등록 완료]처럼 가입이 확인된 경우
create or replace function ev.f_welcome(p_ent bigint, p_by text, p_member boolean default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare n ev.entrant; v_sp int := 0; v_no int;
begin
  select * into n from ev.entrant where id = p_ent;
  if n.id is null then return '{}'::jsonb; end if;
  if not exists (select 1 from ev.spin s where s.entrant_id = n.id and s.void_at is null) then
    insert into ev.spin(event_id, entrant_id, reason, granted_by) values (n.event_id, n.id, '참여 등록', p_by); v_sp := 1;
  end if;
  if coalesce(p_member, coalesce(n.member_consent,false) or n.member_answer = 'join')
     and not exists (select 1 from ev.ticket t where t.entrant_id = n.id and t.void_at is null and t.reason = '멤버십 가입') then
    v_no := ev.f_ticket_issue(n.event_id, n.id, '멤버십 가입', null, p_by);
  end if;
  return jsonb_build_object('spin', v_sp, 'ticket', v_no);
end $$;
revoke all on function ev.f_ticket_issue(int,bigint,text,text,text), ev.f_welcome(bigint,text,boolean) from public, anon, authenticated;

-- 4) 고객 직접 등록 · 담당자 주기(동의 포함) · [DPS 등록 완료] 에 기본 혜택 연결 — 서버 원본에서 그 줄만 치환
do $outer$
declare v_src text; v_args text; r record; n int;
begin
  for r in select * from (values
      ('fn_lucky_join', 'perform ev.f_consent_save(v_ent, p_data, ''고객 화면'');',
                        'perform ev.f_consent_save(v_ent, p_data, ''고객 화면''); perform ev.f_welcome(v_ent, ''고객 화면'', null);'),
      ('fn_store_lucky_issue', 'if v_has_consent then perform ev.f_consent_save(v_ent, p_data, ''담당자 '' || v_me); end if;',
                        'if v_has_consent then perform ev.f_consent_save(v_ent, p_data, ''담당자 '' || v_me); perform ev.f_welcome(v_ent, v_me, null); end if;'),
      ('fn_store_lucky_mark', 'if v_op = ''dps_done'' then update ev.entrant set dps_done_at = now(), dps_done_by = v_me where id = v_id;',
                        'if v_op = ''dps_done'' then update ev.entrant set dps_done_at = now(), dps_done_by = v_me where id = v_id; perform ev.f_welcome(v_id, v_me, true);')
  ) t(fn, a, b) loop
    select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
      from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname='public' where p.proname=r.fn;
    n := (length(v_src) - length(replace(v_src, r.a, ''))) / length(r.a);
    if n <> 1 then raise exception '% 지점 % 개', r.fn, n; end if;
    execute format('create or replace function public.%I(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L',
                   r.fn, v_args, replace(v_src, r.a, r.b));
  end loop;
end $outer$;
