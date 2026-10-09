-- mvp_198 · 2026-10-10 · 고객 흐름 — "고객들의 문의, 구매 흐름이 명료하게 보이게"
--
-- 한 사람의 문의·상담·견적(열람)·문자·구매·환불·DPS 구독·수신동의/거부를 한 줄 타임라인으로,
-- 그리고 기간 안 문의 고객들이 실제로 샀는지(채널 무관 주문 대조)를 한 표로.
--
-- 사람 묶기: buyer_key + 휴대폰 뒤 8자리(d8). 같은 번호에 이름이 여럿이면(가족·오타) 'people' 로 다 보여 주고
--           그 사람 키에서 온 일은 other=true 로 표시한다.
-- 상담 숨김·삭제·테스트는 뺀다. 주문은 is_test 제외. DPS 매장 전표는 core.orders(source dps)에 이미 있고,
-- 매장 밖 DPS 전표(온라인·대표 명의 등)는 dps.sale 에서 따로 — 같은 사람 원장 주문과 5일 안이면 dup=true.

create index if not exists ix_cust_d8 on crm.customer (right(phone, 8));

create or replace function core.f_cust_src_label(p text) returns text language sql immutable as $f$
  select case p
    when 'ecount' then '이카운트 거래처(VMS·렌탈)' when 'shoplinker' then '샵링커 주문' when 'dps' then 'DPS 전표'
    when 'rental' then '렌탈' when 'homepage' then '홈페이지 문의' when 'web_subscription' then '구독 문의'
    when 'store' then '매장 판매' when 'consult' then '상담 입력' when 'store_consult' then '상담 입력'
    when 'quote' then '견적서' when 'web_b2b' then 'B2B 문의' when 'web_supply' then '소모품 문의'
    else p end
$f$;

create or replace function core.f_customer_journey(p_key text, p_consult bigint default null, p_scoped boolean default false)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $f$
declare v_key text := nullif(btrim(coalesce(p_key,'')),''); v_d8 text; v_keys bpchar[]; v jsonb;
        v_today date := (now() at time zone 'Asia/Seoul')::date; v_shared boolean := false;
begin
  if v_key is null and p_consult is not null then
    select buyer_key::text, right(regexp_replace(coalesce(phone,''),'\D','','g'),8) into v_key, v_d8 from crm.consult where id = p_consult;
  end if;
  if coalesce(v_d8,'') = '' and v_key is not null then
    select right(regexp_replace(coalesce(phone,''),'\D','','g'),8) into v_d8 from crm.customer where buyer_key = v_key::bpchar;
    if coalesce(v_d8,'') = '' then
      select right(regexp_replace(coalesce(phone,''),'\D','','g'),8) into v_d8 from crm.consult
       where buyer_key = v_key::bpchar and phone is not null order by consult_at desc limit 1;
    end if;
  end if;
  if length(coalesce(v_d8,'')) < 8 then v_d8 := null; end if;
  /* 자리표시 번호(같은 숫자 8개·12345678)나 6명 넘게 쓰는 번호는 번호로 묶지 않는다 — 다른 사람이 섞인다 */
  if v_d8 is not null and (v_d8 ~ '^(\d)\1{7}$' or v_d8 in ('12345678','87654321')
                           or (select count(*) from crm.customer where right(phone,8) = v_d8) > 5) then
    v_d8 := null; v_shared := true;
  end if;
  if v_key is null and v_d8 is null and p_consult is null then raise exception '고객을 찾을 수 없습니다'; end if;

  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select v_key::bpchar k where v_key is not null
    union select buyer_key from crm.customer where v_d8 is not null and right(phone,8) = v_d8
    union select buyer_key from crm.consult where v_d8 is not null and buyer_key is not null
                                         and right(regexp_replace(coalesce(phone,''),'\D','','g'),8) = v_d8
  ) t where k is not null;

  with ppl as (
    select c.buyer_key, c.name, c.phone, c.account_type, c.consent_marketing, c.consent_source, c.consent_dps,
           c.source_channels, c.first_seen_at, c.created_at, (c.buyer_key::text = v_key) main
      from crm.customer c where c.buyer_key = any(v_keys)),
  cons as (
    select k.* from crm.consult k
     where k.deleted_at is null and k.hidden_at is null
       and (k.buyer_key = any(v_keys) or k.id = p_consult
            or (v_d8 is not null and right(regexp_replace(coalesce(k.phone,''),'\D','','g'),8) = v_d8))
       and (not p_scoped or exists (select 1 from crm.consult_scoped s where s.id = k.id))),
  ord as (
    select o.source, o.order_no, min(o.order_at) at, max(o.channel_name) ch, max(o.channel_type) ctype,
           max(o.sale_kind) kind, left(string_agg(distinct left(coalesce(o.product_name_raw, o.model_code, ''), 48), ' · '), 160) prods,
           sum(o.qty) qty, sum(o.gross_amount) gross, sum(coalesce(o.refund_amount,0)) refund, sum(o.net_amount) net,
           max(o.status) status, max(o.handler) handler, bool_and(v_key is not null and o.buyer_key <> v_key::bpchar) other
      from core.orders o where o.buyer_key = any(v_keys) and not coalesce(o.is_test,false)
     group by o.source, o.order_no),
  subs as (
    select u.sale_no, jsonb_agg(jsonb_build_object('kind', u.kind, 'service', u.service, 'model', u.model, 'status', u.status,
             'monthly', u.monthly_fee,
             'months', case when u.kind = '올인원' and u.monthly_fee > 0 and u.total_fee > 0 then round(u.total_fee / u.monthly_fee)::int
                            when u.end_date is not null and u.start_date is not null then round((u.end_date - u.start_date) / 30.44)::int end,
             'end', case when u.kind = '올인원' and u.start_date is not null and u.monthly_fee > 0 and u.total_fee > 0
                         then (u.start_date + make_interval(months => round(u.total_fee / u.monthly_fee)::int))::date else u.end_date end)
             order by u.seq) j
      from dps.subscription u
     where u.sale_no in (select order_no from ord where source = 'dps'
                         union select s.sale_no from dps.sale s where s.buyer_key = any(v_keys) and not s.is_store)
     group by u.sale_no),
  dpx as (
    select s.sale_no, s.doc_type, s.sale_date, s.channel, s.staff_name, s.amount, s.is_subscription,
           (select string_agg(i.model, ' · ' order by i.line_no) from dps.sale_item i where i.sale_no = s.sale_no) models,
           exists (select 1 from ord where abs((ord.at at time zone 'Asia/Seoul')::date - s.sale_date) <= 5 and ord.net > 0) dup,
           (v_key is not null and s.buyer_key <> v_key::bpchar) other
      from dps.sale s where s.buyer_key = any(v_keys) and not s.is_store),
  qt as (
    select distinct on (q.quote_no) q.quote_no, q.version, q.counselor, q.models, q.final_price, q.monthly, q.quote_type,
           (select min(x.issued_at) from crm.quote x where x.quote_no = q.quote_no) first_at,
           (select count(*) from crm.quote x where x.quote_no = q.quote_no) versions,
           (select min(sh.created_at) from crm.quote_share sh where sh.quote_no = q.quote_no and not sh.revoked) sent_at,
           (select coalesce(sum(sh.views),0) from crm.quote_share sh where sh.quote_no = q.quote_no and not sh.revoked) views,
           (select max(sh.last_view_at) from crm.quote_share sh where sh.quote_no = q.quote_no and not sh.revoked) last_view
      from crm.quote q
     where (q.buyer_key = any(v_keys) or (v_d8 is not null and right(regexp_replace(coalesce(q.phone,''),'\D','','g'),8) = v_d8))
       and not core.f_quote_is_test(q.quote_no, q.customer_name, q.counselor)
     order by q.quote_no, q.version desc),
  snd as (
    select l.campaign, cp.name, l.channel, l.sent_at, l.status, l.error_msg from crm.send_log l
      left join crm.campaign cp on cp.code = l.campaign where l.buyer_key = any(v_keys)),
  ev as (
    -- 처음 확인 (명단에 들어온 날 · 고도몰 회원이면 가입일)
    select p.first_seen_at at, 'seen' k, '처음 확인' t,
           (select string_agg(core.f_cust_src_label(s), ' · ') from unnest(p.source_channels) s) s,
           null::numeric amt, null::text ref, coalesce(not p.main, false) other, null::jsonb x
      from ppl p where p.first_seen_at is not null
    union all
    select k.consult_at, case when k.source = 'store' then 'consult' else 'inq' end,
           case when k.source = 'store' then '매장 상담' else coalesce(ch.label, core.f_consult_src(k.source, k.inflow_route)) end,
           concat_ws(' · ', core.f_inq_type_label(k.type_codes, k.type_code), nullif(k.interest_category,''), nullif(k.interest_model_code,''),
                     nullif(left(regexp_replace(coalesce(k.content,''),'\s+',' ','g'), 90),'')),
           k.expected_amount, k.id::text, (v_key is not null and k.buyer_key is not null and k.buyer_key <> v_key::bpchar),
           jsonb_build_object('handler', k.handler, 'result', k.result, 'route', k.inflow_route, 'campaign', core.f_consult_campaign(k.raw_payload),
                              'channel', coalesce(ch.label, core.f_consult_src(k.source, k.inflow_route)), 'source', k.source,
                              'superseded', k.superseded_by, 'bought', k.purchase_item, 'callback', k.callback_at)
      from cons k left join core.inq_channel ch on ch.code = k.channel_code
    union all
    select coalesce(q.first_at, q.sent_at), 'quote', '견적서 ' || q.quote_no,
           concat_ws(' · ', nullif(left(coalesce(q.models,''),80),''), case when q.versions > 1 then q.versions || '판' end),
           coalesce(q.final_price, q.monthly), q.quote_no, false,
           jsonb_build_object('counselor', q.counselor, 'monthly', q.monthly, 'final', q.final_price, 'sent_at', q.sent_at,
                              'views', q.views, 'last_view', q.last_view, 'type', q.quote_type)
      from qt q
    union all
    select s.sent_at, 'send', '문자 · ' || coalesce(s.name, s.campaign), concat_ws(' · ', s.campaign, s.channel,
           case when s.status = 'failed' then '실패' || coalesce(' (' || nullif(s.error_msg,'') || ')','') end),
           null, s.campaign, false, jsonb_build_object('failed', s.status = 'failed')
      from snd s
    union all
    select o.at, case when o.gross > 0 and o.refund >= o.gross then 'cancel' else 'buy' end,
           case o.source when 'store' then '매장 구매' when 'dps' then '매장 구매 (DPS)' when 'ecount' then 'VMS 거래'
                         when 'rental' then '렌탈' else coalesce(o.ch, o.source) end
             || coalesce(' · ' || nullif(o.kind,''), ''),
           o.prods, o.net, o.order_no, o.other,
           jsonb_build_object('channel', o.ch, 'ctype', o.ctype, 'source', o.source, 'qty', o.qty, 'gross', o.gross, 'refund', o.refund,
                              'status', o.status, 'handler', o.handler, 'subs', (select j from subs where subs.sale_no = o.order_no and o.source = 'dps'))
      from ord o
    union all
    select (d.sale_date + time '12:00') at time zone 'Asia/Seoul',
           case when d.doc_type like '해약%' then 'cancel' else 'dps' end,
           'DPS ' || case when d.doc_type like '해약%' then '해약·교환' else '판매' end || coalesce(' · ' || regexp_replace(d.channel, '^DPS\s*', ''), ''),
           concat_ws(' · ', d.models, d.staff_name), d.amount, d.sale_no, d.other,
           jsonb_build_object('dup', d.dup, 'sub', d.is_subscription, 'subs', (select j from subs where subs.sale_no = d.sale_no))
      from dpx d
    union all
    select h.changed_at, 'consent', case when h.consent then '수신 동의' else '수신 동의 철회' end, h.source, null, null,
           (v_key is not null and h.buyer_key <> v_key::bpchar), null
      from crm.consent_history h where h.buyer_key = any(v_keys)
    union all
    select o.opted_at, 'optout', '문자 수신거부', concat_ws(' · ', o.source, o.note), null, null, false, null
      from crm.sms_optout o where v_d8 is not null and o.d8 = v_d8 and o.released_at is null),
  st as (
    select min(at) filter (where k = 'seen') seen,
           min(at) filter (where k in ('inq','consult')) inq,
           min(at) filter (where k = 'quote') quote,
           min(at) filter (where k in ('buy','dps') and coalesce(amt,0) > 0 and not coalesce((x->>'dup')::boolean,false)) buy1,
           max(at) filter (where k in ('buy','dps') and coalesce(amt,0) > 0) buy_last,
           count(distinct (at at time zone 'Asia/Seoul')::date) filter (where k in ('buy','dps') and coalesce(amt,0) > 0 and not coalesce((x->>'dup')::boolean,false)) buy_days
      from ev)
  select jsonb_build_object(
    'key', v_key, 'd8', v_d8 is not null, 'shared_phone', v_shared, 'today', v_today,
    'people', (select coalesce(jsonb_agg(jsonb_build_object('key', p.buyer_key, 'name', p.name, 'phone', p.phone, 'biz', p.account_type = 'business',
                 'consent', p.consent_marketing, 'consent_src', p.consent_source, 'consent_dps', p.consent_dps,
                 'srcs', (select coalesce(jsonb_agg(core.f_cust_src_label(s)), '[]'::jsonb) from unnest(p.source_channels) s),
                 'first', to_char(p.first_seen_at at time zone 'Asia/Seoul','YYYY-MM-DD'), 'main', p.main) order by p.main desc, p.first_seen_at), '[]'::jsonb) from ppl p),
    'consult_name', (select k.customer_name from cons k order by k.consult_at desc limit 1),
    'consult_phone', (select k.phone from cons k where k.phone is not null order by k.consult_at desc limit 1),
    'stages', (select jsonb_build_object(
        'seen', to_char(seen at time zone 'Asia/Seoul','YYYY-MM-DD'), 'inq', to_char(inq at time zone 'Asia/Seoul','YYYY-MM-DD'),
        'quote', to_char(quote at time zone 'Asia/Seoul','YYYY-MM-DD'), 'buy1', to_char(buy1 at time zone 'Asia/Seoul','YYYY-MM-DD'),
        'buy_last', to_char(buy_last at time zone 'Asia/Seoul','YYYY-MM-DD'), 'buy_days', buy_days,
        'buy_after_inq', (select to_char(min(e.at) at time zone 'Asia/Seoul','YYYY-MM-DD') from ev e
                           where e.k in ('buy','dps') and coalesce(e.amt,0) > 0 and st.inq is not null
                             and (e.at at time zone 'Asia/Seoul')::date >= (st.inq at time zone 'Asia/Seoul')::date),
        'days_to_buy', (select (min(e.at) at time zone 'Asia/Seoul')::date - (st.inq at time zone 'Asia/Seoul')::date from ev e
                         where e.k in ('buy','dps') and coalesce(e.amt,0) > 0 and st.inq is not null
                           and (e.at at time zone 'Asia/Seoul')::date >= (st.inq at time zone 'Asia/Seoul')::date)) from st),
    'open', (select jsonb_build_object('id', k.id, 'result', k.result, 'handler', k.handler, 'callback', k.callback_at)
               from cons k where k.result in ('진행전','진행중','보류') order by k.consult_at desc limit 1),
    'sub_end', (select min((e->>'end')::date) from ev, jsonb_array_elements(case when jsonb_typeof(ev.x->'subs') = 'array' then ev.x->'subs' else '[]'::jsonb end) e
                 where (e->>'end') is not null and (e->>'end')::date >= v_today),
    'summary', jsonb_build_object(
        'inq', (select count(*) from ev where k in ('inq','consult')),
        'quote', (select count(*) from ev where k = 'quote'),
        'quote_views', (select coalesce(sum((x->>'views')::int),0) from ev where k = 'quote'),
        'buy', (select count(*) from ev where k in ('buy','dps') and coalesce(amt,0) > 0 and not coalesce((x->>'dup')::boolean,false)),
        'net', (select coalesce(sum(amt),0) from ev where k = 'buy'),
        'dps_amt', (select coalesce(sum(amt),0) from ev where k = 'dps' and not coalesce((x->>'dup')::boolean,false)),
        'cancel', (select count(*) from ev where k = 'cancel'),
        'send', (select count(*) from ev where k = 'send'),
        'send_failed', (select count(*) from ev where k = 'send' and (x->>'failed')::boolean),
        'optout', exists (select 1 from ev where k = 'optout')),
    'events_total', (select count(*) from ev),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('k', k, 'at', to_char(at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'),
                 't', t, 's', nullif(s,''), 'amt', amt, 'ref', ref, 'other', other, 'x', x) order by at desc nulls last), '[]'::jsonb)
                 from (select * from ev order by at desc nulls last limit 400) e)
  ) into v;
  return v;
end $f$;
revoke all on function core.f_customer_journey(text, bigint, boolean) from public, anon, authenticated;

-- 관리자: 이름·번호는 가린다 · [실명·실번호] 는 관리자만, crm.access_log 'customer_journey:unmask'
create or replace function public.fn_customer_journey(p_key text, p_consult bigint default null, p_unmask boolean default false)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_role text := core.f_role(); v_un boolean; v jsonb;
begin
  if v_role not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v_un := coalesce(p_unmask,false) and v_role = 'admin';
  v := core.f_customer_journey(p_key, p_consult, false);
  if not v_un then
    v := v || jsonb_build_object(
      'people', (select coalesce(jsonb_agg(p || jsonb_build_object('name', regexp_replace(coalesce(p->>'name',''),'(?<=.).','*','g'),
                                                                 'phone', core.f_phone_show(p->>'phone', false)) order by i), '[]'::jsonb)
                   from jsonb_array_elements(v->'people') with ordinality t(p, i)),
      'consult_name', regexp_replace(coalesce(v->>'consult_name',''),'(?<=.).','*','g'),
      'consult_phone', core.f_phone_show(v->>'consult_phone', false));
  else
    v := v || jsonb_build_object('consult_phone', core.f_phone_show(v->>'consult_phone', true),
      'people', (select coalesce(jsonb_agg(p || jsonb_build_object('phone', core.f_phone_show(p->>'phone', true)) order by i), '[]'::jsonb)
                   from jsonb_array_elements(v->'people') with ordinality t(p, i)));
    insert into crm.access_log (actor, actor_email, action, row_count, reason)
    values (auth.uid(), (select pr.email from public.profiles pr where pr.id = auth.uid()), 'customer_journey:unmask', 1,
            coalesce(p_key, 'consult:' || p_consult));
  end if;
  return v || jsonb_build_object('unmask', v_un);
end $f$;
revoke all on function public.fn_customer_journey(text, bigint, boolean) from public, anon;
grant execute on function public.fn_customer_journey(text, bigint, boolean) to authenticated, service_role;

-- 담당자 화면: 4자리 코드 · 상담은 consult_scoped 규칙(VMS·B2B 는 볼 수 있는 사람만) · 번호는 담당자 화면 규칙대로 그대로
create or replace function public.fn_store_customer_journey(p_code text, p_key text, p_consult bigint default null)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_me text := core.f_staff(p_code);
begin
  perform set_config('dc.me', coalesce(v_me,''), true);
  return core.f_customer_journey(p_key, p_consult, true);
end $f$;
revoke all on function public.fn_store_customer_journey(text, text, bigint) from public;
grant execute on function public.fn_store_customer_journey(text, text, bigint) to anon, authenticated, service_role;

-- 기간 안 문의한 사람들이 실제로 샀나 — 상담 상태가 아니라 주문(원장·DPS)으로 대조
--   사람 = 휴대폰 뒤 8자리(자리표시·6명 넘게 쓰는 번호는 제외) 또는 고객키 · 기간 안 첫 문의가 기준
--   구매 = 첫 문의 날부터 p_window 일 안의 순매출 > 0 주문(테스트 제외) 또는 매장 밖 DPS 판매 전표
--   기존 구매 = 첫 문의 날 이전 주문이 있던 사람
create or replace function public.fn_inquiry_flow(p_from date, p_to date, p_scope text default null, p_window int default 90, p_unmask boolean default false)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_role text := core.f_role(); v_un boolean; v jsonb; v_win int := least(greatest(coalesce(p_window,90),1),365);
begin
  if v_role not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v_un := coalesce(p_unmask,false) and v_role = 'admin';
  with inq as (
    select k.id, k.consult_at, (k.consult_at at time zone 'Asia/Seoul')::date d, k.source, k.channel_code, k.buyer_key, k.customer_name, k.phone,
           k.handler, k.result, k.type_codes, k.type_code, k.interest_category, k.inflow_route,
           right(regexp_replace(coalesce(k.phone,''),'\D','','g'),8) d8,
           coalesce(ch.label, core.f_consult_src(k.source, k.inflow_route)) chan
      from crm.consult k left join core.inq_channel ch on ch.code = k.channel_code
     where k.deleted_at is null and k.hidden_at is null
       and (k.consult_at at time zone 'Asia/Seoul')::date between p_from and p_to
       and (coalesce(p_scope,'') = '' or core.f_consult_scope(k.channel_code, k.source) = p_scope)),
  dc as (select right(c.phone,8) d8, count(*) n from crm.customer c where right(c.phone,8) in (select d8 from inq) group by 1),
  inq2 as (
    select i.*, (length(i.d8) = 8 and i.d8 !~ '^(\d)\1{7}$' and i.d8 not in ('12345678','87654321')
                 and coalesce((select n from dc where dc.d8 = i.d8),0) <= 5) d8ok from inq i),
  inq3 as (select i.*, case when i.d8ok then 'p' || i.d8 when i.buyer_key is not null then 'k' || i.buyer_key else 'c' || i.id end pk from inq2 i),
  person as (select distinct on (pk) * from inq3 order by pk, consult_at),
  ninq as (select pk, count(*) n from inq3 group by pk),
  pkeys as (
    select p.pk, array_agg(distinct x.k) keys from person p
      cross join lateral (
        select k2.buyer_key k from inq3 k2 where k2.pk = p.pk and k2.buyer_key is not null
        union select c.buyer_key from crm.customer c where p.d8ok and right(c.phone,8) = p.d8) x
     group by p.pk),
  res as (
    select p.*, coalesce(n.n,1) n_inq, coalesce(pk.keys, '{}') keys,
      (select count(distinct o.order_no) from core.orders o where o.buyer_key = any(pk.keys) and not coalesce(o.is_test,false)
          and o.net_amount > 0 and (o.order_at at time zone 'Asia/Seoul')::date < p.d) before_n,
      (select count(distinct q.quote_no) from crm.quote q
         where (q.buyer_key = any(pk.keys) or (p.d8ok and right(regexp_replace(coalesce(q.phone,''),'\D','','g'),8) = p.d8))
           and q.issued_at >= p.consult_at - interval '1 day' and not core.f_quote_is_test(q.quote_no, q.customer_name, q.counselor)) quote_n,
      b.at buy_at, b.amt buy_amt, b.wh buy_where, b.n buy_n
      from person p left join ninq n on n.pk = p.pk left join pkeys pk on pk.pk = p.pk
      left join lateral (
        select min(z.d) at, sum(z.amt) amt, count(distinct z.ref) n, (array_agg(z.wh order by z.d))[1] wh from (
          select (o.order_at at time zone 'Asia/Seoul')::date d, o.net_amount amt, o.source || ':' || o.order_no ref,
                 case when o.source in ('store','dps') then '매장' when o.source = 'ecount' then 'VMS' when o.source = 'rental' then '렌탈'
                      else coalesce(o.channel_name, '온라인') end wh
            from core.orders o where o.buyer_key = any(pk.keys) and not coalesce(o.is_test,false) and o.net_amount > 0
             and (o.order_at at time zone 'Asia/Seoul')::date between p.d and p.d + v_win
          union all
          select s.sale_date, s.amount, 'dps:' || s.sale_no, case when s.channel ~ '^DPS' then s.channel else 'DPS ' || coalesce(s.channel,'') end from dps.sale s
           where s.buyer_key = any(pk.keys) and not s.is_store and s.doc_type = '판매' and s.amount > 0
             and s.sale_date between p.d and p.d + v_win) z) b on true),
  agg as (select * from res)
  select jsonb_build_object(
    'from', p_from, 'to', p_to, 'window', v_win, 'scope', coalesce(p_scope,''), 'unmask', v_un,
    'summary', jsonb_build_object(
       'inquiries', (select count(*) from inq), 'people', (select count(*) from agg),
       'known_buyer', (select count(*) from agg where before_n > 0),
       'quoted', (select count(*) from agg where quote_n > 0),
       'bought', (select count(*) from agg where buy_at is not null),
       'bought_new', (select count(*) from agg where buy_at is not null and before_n = 0),
       'amount', (select coalesce(sum(buy_amt),0) from agg),
       'median_days', (select percentile_disc(0.5) within group (order by buy_at - d) from agg where buy_at is not null),
       'same_day', (select count(*) from agg where buy_at = d),
       'open', (select count(*) from agg where result in ('진행전','진행중','보류') and buy_at is null),
       'mark_no_order', (select count(*) from agg where result = '구매완료' and buy_at is null),
       'open_but_bought', (select count(*) from agg where result in ('진행전','진행중','보류') and buy_at is not null)),
    'by_where', (select coalesce(jsonb_object_agg(w, n), '{}'::jsonb) from (select buy_where w, count(*) n from agg where buy_at is not null group by 1) t),
    'by_channel', (select coalesce(jsonb_agg(jsonb_build_object('channel', chan, 'people', n, 'known', kn, 'quoted', qn, 'bought', bn,
                     'amount', amt, 'median_days', md) order by n desc), '[]'::jsonb) from (
        select chan, count(*) n, count(*) filter (where before_n > 0) kn, count(*) filter (where quote_n > 0) qn,
               count(*) filter (where buy_at is not null) bn, coalesce(sum(buy_amt),0) amt,
               percentile_disc(0.5) within group (order by buy_at - d) filter (where buy_at is not null) md
          from agg group by chan) t),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object(
        'consult', id, 'key', case when cardinality(keys) = 1 then keys[1]::text when buyer_key is not null then buyer_key::text end,
        'at', to_char(consult_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'),
        'name', case when v_un then customer_name else regexp_replace(coalesce(customer_name,''),'(?<=.).','*','g') end,
        'phone', core.f_phone_show(phone, v_un), 'channel', chan, 'route', inflow_route,
        'type', core.f_inq_type_label(type_codes, type_code), 'interest', interest_category, 'handler', handler, 'result', result,
        'n_inq', n_inq, 'before_n', before_n, 'quote_n', quote_n,
        'buy_at', buy_at, 'days', buy_at - d, 'buy_amt', buy_amt, 'buy_where', buy_where, 'buy_n', buy_n) order by consult_at desc), '[]'::jsonb)
        from (select * from agg order by consult_at desc limit 1000) r)
  ) into v;
  if v_un then
    insert into crm.access_log (actor, actor_email, action, row_count, reason)
    values (auth.uid(), (select pr.email from public.profiles pr where pr.id = auth.uid()), 'inquiry_flow:unmask',
            (v->'summary'->>'people')::int, p_from || '~' || p_to);
  end if;
  return v;
end $f$;
revoke all on function public.fn_inquiry_flow(date, date, text, int, boolean) from public, anon;
grant execute on function public.fn_inquiry_flow(date, date, text, int, boolean) to authenticated, service_role;
