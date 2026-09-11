/* ═══════════════════════════════════════════════════════════════
   mvp_108 — 샵링커 배송비(운송료) · 날짜 선택 · 이카운트 전송 규칙
   2026-09-10

   1) core.orders.shipping_fee 를 실제로 쓴다 (수집은 collect.mjs 쪽에서)
   2) 배송비는 "운송장 1개 = 1건". 한 주문에 운송장 2개면 2건.
      샵링커는 상품 줄마다 같은 배송비를 붙여 주므로 줄 단위 합계는 틀리다.
   3) 가져오기 목록에 시작일·종료일·날짜 기준(발송일/주문일/수집일)
   4) 이카운트 전송 규칙
      영업담당 00022(오픈마켓) · 판매담당자 고창재
      주문No. = 샵링커 주문번호 · 적요(줄) = 쇼핑몰 주문번호
      특이사항 = "n월 주문건 / 주문서 작성일"
      운송료는 품목 AS-00076 한 줄로 붙는다
   ═══════════════════════════════════════════════════════════════ */

-- ── 0. 설정값 ────────────────────────────────────────────────────
insert into core.app_setting(key, value) values
  ('sl_emp_code','00022'),
  ('sl_handler','고창재'),
  ('sl_fee_item','AS-00076'),
  ('sl_fee_on','on')
on conflict (key) do nothing;

-- 운송료는 재고를 빼지 않는다
update inv.item set no_stock = true where code = 'AS-00076';

-- 주문No. 자리에 샵링커 주문번호가 가도록 (쇼핑몰 주문번호는 줄 적요로 간다)
update core.app_setting
   set value = ((value::jsonb) - 'order_no' || jsonb_build_object('order_ref', coalesce((value::jsonb)->>'order_no','U_MEMO3')))::text
 where key = 'ec_field_map' and (value::jsonb) ? 'order_no';

-- ── 1. 주문 1건의 배송비 (운송장 단위) ─────────────────────────────
create or replace function core.f_sl_fee(p_order_no text)
returns jsonb language sql stable
set search_path to 'pg_catalog','public' as $fn$
  select jsonb_build_object(
           'fee',   coalesce(sum(f),0),
           'trk',   count(*) filter (where t <> '#'),
           'known', bool_or(k))
    from (select coalesce(nullif(btrim(o.tracking_no),''),'#') t,
                 max(coalesce(o.shipping_fee,0)) f,
                 bool_or(o.shipping_fee is not null) k
            from core.orders o
           where o.source = 'shoplinker'
             and o.order_no = p_order_no
             and coalesce(o.refund_amount,0) = 0
           group by 1) z;
$fn$;

comment on function core.f_sl_fee(text) is
  '샵링커 주문 1건의 배송비 — 운송장(송장번호) 하나당 한 번만 센다. {fee, trk, known}';

-- ── 2. 목록 (날짜 기준에 발송일 추가 + 배송비) ─────────────────────
create or replace function core.f_sl_range(
    p_from date, p_to date, p_basis text default 'order', p_q text default null,
    p_channel text default null, p_limit integer default 500, p_include_done boolean default false)
returns jsonb language plpgsql
set search_path to 'pg_catalog','public' as $fn$
declare v_rows jsonb; v_total int; v_f timestamptz; v_t timestamptz;
begin
  v_f := (coalesce(p_from, (now() at time zone 'Asia/Seoul')::date - 7)::timestamp) at time zone 'Asia/Seoul';
  v_t := ((coalesce(p_to, (now() at time zone 'Asia/Seoul')::date) + 1)::timestamp) at time zone 'Asia/Seoul';
  drop table if exists pg_temp._sll; drop table if exists pg_temp._slc; drop table if exists pg_temp._slp;
  create temp table _sll on commit drop as
    select o.order_no, o.line_no, o.product_name_raw, o.model_code, o.option_text, o.qty, o.unit_price,
           o.channel_name, o.channel_account, o.buyer_name_raw, o.order_at, o.created_at, o.net_amount, o.gross_amount, o.status,
           o.tracking_no, o.alt_order_no, o.shipping_fee,
           coalesce(o.category,'기타') category, coalesce(o.goods_kind,'기타') kind,
           (exists (select 1 from ec.order_queue q where q.order_no = o.order_no and q.status <> 'void')
              or core.f_ec_slip_of(o.order_no, o.alt_order_no) is not null) done,
           core.f_ec_slip_of(o.order_no, o.alt_order_no) ec_slip,
           (o.tracking_no is not null or o.shipped_at is not null
              or coalesce(o.status,'') in ('송장전송완료','배송중','배송완료','구매확정','구매결정','교환완료')) shipped
      from core.orders o
     where o.source = 'shoplinker'
       and (case when p_basis = 'collect' then o.created_at
                 when p_basis = 'ship'    then coalesce(o.shipped_at, o.order_at)
                 else o.order_at end) >= v_f
       and (case when p_basis = 'collect' then o.created_at
                 when p_basis = 'ship'    then coalesce(o.shipped_at, o.order_at)
                 else o.order_at end) <  v_t
       and coalesce(o.status,'') not in ('취소','반품','환불','주문취소')
       and coalesce(o.refund_amount,0) = 0
       and (p_include_done or not (exists (select 1 from ec.order_queue q where q.order_no = o.order_no and q.status <> 'void')
                                   or core.f_ec_slip_of(o.order_no, o.alt_order_no) is not null))
       and (p_channel is null or p_channel = '' or o.channel_name = p_channel)
       and (p_q is null or p_q = '' or o.order_no ilike '%'||p_q||'%' or o.alt_order_no ilike '%'||p_q||'%' or o.buyer_name_raw ilike '%'||p_q||'%'
            or o.product_name_raw ilike '%'||p_q||'%' or o.model_code ilike '%'||p_q||'%' or o.option_text ilike '%'||p_q||'%');
  create temp table _slc on commit drop as
    select d.product_name_raw, d.model_code, d.option_text,
           core.f_ec_cands_cached(d.product_name_raw, d.model_code, d.option_text) cands,
           core.f_sl_model(d.model_code, d.option_text) model_eff
      from (select distinct product_name_raw, model_code, option_text from _sll) d;
  create temp table _slp on commit drop as
    select l.order_no, max(l.channel_name) ch, max(l.channel_account) acct, max(l.buyer_name_raw) buyer,
           max(l.order_at) at, max(l.created_at) collected, bool_or(l.done) done, max(l.status) status,
           max(l.ec_slip) ec_slip, bool_or(l.shipped) shipped, max(l.tracking_no) tracking_no, max(l.alt_order_no) alt_order_no,
           (select cc.cust_code from ec.channel_cust cc where cc.channel = max(l.channel_name) limit 1) cust_code,
           mode() within group (order by l.category) category,
           case when bool_and(l.kind='소모품') then '소모품' when bool_and(l.kind='대물') then '대물' when bool_or(l.kind='대물') then '혼합' else '기타' end kind,
           jsonb_agg(jsonb_build_object(
              'line', l.line_no, 'product', l.product_name_raw, 'model', l.model_code,
              'model_eff', c.model_eff, 'option', l.option_text, 'qty', l.qty, 'price', l.unit_price,
              'category', l.category, 'kind', l.kind, 'tracking_no', l.tracking_no, 'fee_raw', l.shipping_fee,
              'item_code', c.cands->0->>'code', 'item_name', c.cands->0->>'name',
              'cands', c.cands, 'n_cand', jsonb_array_length(c.cands)) order by l.line_no) lines,
           sum(coalesce(l.net_amount, l.gross_amount, 0)) amount, sum(l.qty) qty,
           count(distinct nullif(btrim(l.tracking_no),'')) trk_n,
           bool_or(l.shipping_fee is not null) fee_known,
           (select coalesce(sum(f),0) from (
              select coalesce(nullif(btrim(l2.tracking_no),''),'#') t, max(coalesce(l2.shipping_fee,0)) f
                from _sll l2 where l2.order_no = l.order_no group by 1) z) ship_fee,
           count(*) filter (where jsonb_array_length(c.cands) > 0)::int mapped,
           count(*) filter (where jsonb_array_length(c.cands) > 1)::int ambig,
           count(*)::int total_lines
      from _sll l
      join _slc c on c.product_name_raw is not distinct from l.product_name_raw
                 and c.model_code is not distinct from l.model_code
                 and c.option_text is not distinct from l.option_text
     group by l.order_no;
  select count(*) into v_total from _slp;
  select coalesce(jsonb_agg(jsonb_build_object(
      'order_no', order_no, 'alt_order_no', alt_order_no, 'channel', ch, 'account', acct, 'buyer', buyer, 'cust_code', cust_code,
      'category', category, 'kind', kind,
      'at', to_char(at at time zone 'Asia/Seoul','MM-DD HH24:MI'),
      'collected', to_char(collected at time zone 'Asia/Seoul','MM-DD HH24:MI'),
      'io_date', (at at time zone 'Asia/Seoul')::date, 'done', done, 'status', status,
      'ec_slip', ec_slip, 'shipped', shipped, 'tracking_no', tracking_no,
      'trk_n', trk_n, 'ship_fee', ship_fee, 'fee_known', fee_known,
      'qty', qty, 'amount', amount, 'lines', lines,
      'mapped', mapped, 'ambig', ambig, 'total_lines', total_lines,
      'ready', mapped = total_lines) order by at desc), '[]'::jsonb) into v_rows
  from (select * from _slp order by at desc limit greatest(p_limit,1)) t;
  return jsonb_build_object('rows', v_rows, 'total', v_total, 'basis', coalesce(p_basis,'order'),
    'from', coalesce(p_from, (now() at time zone 'Asia/Seoul')::date - 7), 'to', coalesce(p_to, (now() at time zone 'Asia/Seoul')::date),
    'channels', (select coalesce(jsonb_agg(distinct ch),'[]'::jsonb) from _slp where ch is not null),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('c', category, 'n', n) order by n desc),'[]'::jsonb) from (select category, count(*) n from _slp where not done group by category) x),
    'kinds', (select coalesce(jsonb_agg(jsonb_build_object('k', kind, 'n', n) order by n desc),'[]'::jsonb) from (select kind, count(*) n from _slp where not done group by kind) x),
    'ready', (select count(*) from _slp where mapped = total_lines and ambig = 0 and not done),
    'ready_all', (select count(*) from _slp where mapped = total_lines and not done),
    'ambig', (select count(*) from _slp where ambig > 0 and mapped = total_lines and not done),
    'unmapped', (select count(*) from _slp where mapped < total_lines and not done),
    'done', (select count(*) from _slp where done),
    'shipped', (select count(*) from _slp where shipped and not done),
    'unshipped', (select count(*) from _slp where not shipped and not done),
    'fee_total', (select coalesce(sum(ship_fee),0) from _slp where not done),
    'fee_unknown', (select count(*) from _slp where not fee_known and not done),
    'lines', (select coalesce(sum(total_lines),0) from _slp));
end $fn$;

-- 발송일 기준 최근 N일 (기존 화면 호환)
create or replace function core.f_sl_pending(p_days integer default 7, p_q text default null,
                                             p_channel text default null, p_limit integer default 60)
returns jsonb language sql
set search_path to 'pg_catalog','public' as $fn$
  select core.f_sl_range((now() at time zone 'Asia/Seoul')::date - greatest(coalesce(p_days,7),1),
                         (now() at time zone 'Asia/Seoul')::date,
                         'ship', p_q, p_channel, p_limit, false) || jsonb_build_object('basis','ship');
$fn$;

-- 담당자 화면용 : 기간을 직접 고를 수 있는 목록
create or replace function public.fn_store_sl_list(
    p_code text, p_from date default null, p_to date default null, p_basis text default 'ship',
    p_q text default null, p_channel text default null, p_limit integer default 1000)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public' as $fn$
declare v_me text := core.f_staff(p_code);
begin
  if not core.f_has_perm(v_me, 'order') then raise exception '주문서 권한이 없습니다' using errcode='42501'; end if;
  return core.f_sl_range(coalesce(p_from, (now() at time zone 'Asia/Seoul')::date - 7),
                         coalesce(p_to,   (now() at time zone 'Asia/Seoul')::date),
                         coalesce(nullif(p_basis,''),'ship'), p_q, p_channel, p_limit, false);
end $fn$;
grant execute on function public.fn_store_sl_list(text,date,date,text,text,text,integer) to anon, authenticated;

-- ── 3. 미리보기 : 운송료 줄과 이카운트 값이 그대로 보이게 ────────────
create or replace function core.f_sl_preview(p_order_nos text[], p_wh text default '00001', p_picks jsonb default '{}'::jsonb)
returns jsonb language plpgsql
set search_path to 'pg_catalog','public' as $fn$
declare v jsonb; v_fee_on boolean; v_fee_item text; v_emp text; v_handler text;
begin
  v_fee_on   := coalesce((select value from core.app_setting where key='sl_fee_on'),'on') = 'on';
  v_fee_item := coalesce((select value from core.app_setting where key='sl_fee_item'),'AS-00076');
  v_emp      := nullif((select value from core.app_setting where key='sl_emp_code'),'');
  v_handler  := nullif((select value from core.app_setting where key='sl_handler'),'');
  drop table if exists pg_temp._pvl;
  create temp table _pvl on commit drop as
    select o.order_no, o.line_no, o.product_name_raw, o.model_code, o.option_text,
           o.qty, o.unit_price, o.gross_amount, o.channel_name, o.buyer_name_raw, o.order_at, o.alt_order_no,
           core.f_sl_model(o.model_code, o.option_text) model_eff,
           core.f_ec_cands_cached(o.product_name_raw, o.model_code, o.option_text) cands
      from core.orders o
     where o.source='shoplinker' and o.order_no = any(p_order_nos) and coalesce(o.refund_amount,0)=0;
  with l as (
    select p.*, coalesce(nullif(p_picks->>(p.order_no||'#'||p.line_no),''), p.cands->0->>'code') code from _pvl p
  ), x as (
    select l.*, i.name item_name,
           coalesce((select sum(v.qty_signed) from inv.v_ledger v where v.item_code = l.code and v.warehouse = p_wh), 0) have
      from l left join inv.item i on i.code = l.code
  )
  select jsonb_build_object(
    'wh', p_wh, 'wh_name', (select name from ec.warehouse where code = p_wh),
    'emp_code', v_emp, 'handler', v_handler, 'fee_item', case when v_fee_on then v_fee_item end,
    'slips', (select coalesce(jsonb_agg(s order by s->>'order_no'), '[]'::jsonb) from (
       select jsonb_build_object(
         'order_no', order_no, 'io_date', (max(order_at) at time zone 'Asia/Seoul')::date,
         'channel', max(channel_name), 'cust_name', max(buyer_name_raw),
         'order_ref', max(alt_order_no),
         'cust_code', (select cc.cust_code from ec.channel_cust cc where cc.channel = max(x.channel_name) limit 1),
         'emp_code', v_emp, 'handler', v_handler,
         'remark', to_char(max(order_at) at time zone 'Asia/Seoul','FMMM')||'월 주문건 / '
                   || to_char((now() at time zone 'Asia/Seoul')::date,'YYYY-MM-DD'),
         'ship_fee', (core.f_sl_fee(x.order_no)->>'fee')::numeric,
         'trk_n',    (core.f_sl_fee(x.order_no)->>'trk')::int,
         'fee_known',(core.f_sl_fee(x.order_no)->>'known')::boolean,
         'already', exists (select 1 from ec.order_queue q where q.order_no = x.order_no and q.status <> 'void'),
         'amount', sum(coalesce(gross_amount, coalesce(qty,0) * coalesce(unit_price,0)))
                   + case when v_fee_on then (core.f_sl_fee(x.order_no)->>'fee')::numeric else 0 end,
         'lines', jsonb_agg(jsonb_build_object(
             'line', line_no, 'product', product_name_raw, 'option', option_text,
             'model', model_code, 'model_eff', model_eff, 'item_code', code, 'item_name', item_name,
             'qty', qty, 'unit_price', unit_price, 'amount', coalesce(gross_amount, coalesce(qty,0)*coalesce(unit_price,0)),
             'have', have, 'short', (code is not null and have < qty),
             'remark', order_no,
             'cands', cands, 'n_cand', jsonb_array_length(cands),
             'picked', p_picks ? (order_no||'#'||line_no)) order by line_no)
           || case when v_fee_on and (core.f_sl_fee(x.order_no)->>'fee')::numeric > 0
                   then jsonb_build_array(jsonb_build_object(
                          'line', 99, 'product', '배송비 (운송장 '||(core.f_sl_fee(x.order_no)->>'trk')||'건)',
                          'option', null, 'item_code', v_fee_item,
                          'item_name', (select name from inv.item where code = v_fee_item),
                          'qty', 1, 'unit_price', (core.f_sl_fee(x.order_no)->>'fee')::numeric,
                          'amount', (core.f_sl_fee(x.order_no)->>'fee')::numeric,
                          'have', 0, 'short', false, 'remark', x.order_no, 'n_cand', 1, 'fee', true))
                   else '[]'::jsonb end,
         'n_lines', count(*), 'n_miss', count(*) filter (where code is null),
         'n_ambig', count(*) filter (where jsonb_array_length(cands) > 1 and not (p_picks ? (order_no||'#'||line_no))),
         'n_short', count(*) filter (where code is not null and have < qty)) s
       from x group by order_no) q),
    'n_slips', (select count(distinct order_no) from x), 'n_lines', (select count(*) from x),
    'n_miss',  (select count(*) from x where code is null),
    'n_ambig', (select count(*) from x where jsonb_array_length(cands) > 1 and not (p_picks ? (order_no||'#'||line_no))),
    'n_short', (select count(*) from x where code is not null and have < qty)) into v;
  return v;
end $fn$;

-- ── 4. 주문서 생성 : 이카운트 규칙 반영 + 운송료 줄 ──────────────────
create or replace function core.f_sl_to_order(p_order_nos text[], p_wh text, p_by text,
                                              p_allow_neg boolean default false, p_picks jsonb default '{}'::jsonb)
returns jsonb language plpgsql
set search_path to 'pg_catalog','public' as $fn$
declare r record; v_res jsonb; ok int := 0; skip jsonb := '[]'::jsonb; made bigint[] := '{}';
        v_batch text := 'SL-' || to_char(now() at time zone 'Asia/Seoul','YYMMDD-HH24MISS') || '-' || left(coalesce(p_by,'?'),6);
        v_fee_on boolean; v_fee_item text; v_emp text; v_handler text; v_today date;
        v_fee jsonb; v_lines jsonb;
begin
  v_fee_on   := coalesce((select value from core.app_setting where key='sl_fee_on'),'on') = 'on';
  v_fee_item := coalesce((select value from core.app_setting where key='sl_fee_item'),'AS-00076');
  v_emp      := nullif((select value from core.app_setting where key='sl_emp_code'),'');
  v_handler  := nullif((select value from core.app_setting where key='sl_handler'),'');
  v_today    := (now() at time zone 'Asia/Seoul')::date;
  if v_fee_on and not exists (select 1 from inv.item where code = v_fee_item and active) then
    raise exception '운송료 품목(%)이 없습니다. 관리자 품목에서 등록하거나 sl_fee_on 을 끄세요', v_fee_item;
  end if;

  for r in
    with l as (
      select o.order_no, o.line_no, o.qty, o.unit_price, o.gross_amount, o.option_text, o.channel_name,
             o.buyer_name_raw, o.order_at, o.shipped_at, o.goods_kind, o.alt_order_no, o.source_ref,
             (o.shipped_at is not null or o.tracking_no is not null or coalesce(o.status,'') in ('송장전송완료','배송중','배송완료','구매확정','구매결정','교환완료')) shipped,
             coalesce(nullif(p_picks->>(o.order_no||'#'||o.line_no),''),
                      core.f_ec_cands_cached(o.product_name_raw, o.model_code, o.option_text)->0->>'code') code
        from core.orders o
       where o.source='shoplinker' and o.order_no = any(p_order_nos) and coalesce(o.refund_amount,0)=0
    )
    select l.order_no, max(l.channel_name) ch, max(l.buyer_name_raw) buyer, bool_or(l.shipped) shipped,
           max(coalesce(l.alt_order_no, l.source_ref)) alt,
           (coalesce(max(l.shipped_at), max(l.order_at)) at time zone 'Asia/Seoul')::date io_date,
           (max(l.order_at) at time zone 'Asia/Seoul')::date ord_date,
           jsonb_agg(jsonb_build_object('item_code', l.code, 'qty', l.qty,
                                        'unit_price', case when coalesce(l.gross_amount,0) > 0 then round(l.gross_amount / greatest(l.qty,1)) else l.unit_price end,
                                        'line_total', case when coalesce(l.gross_amount,0) > 0 then l.gross_amount end,
                                        'no_stock', (l.goods_kind = '대물'),
                                        'remark', left(l.order_no,100)) order by l.line_no) lines,
           count(*) filter (where l.code is null) miss
      from l group by l.order_no
  loop
    if r.miss > 0 then skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '품목을 못 정한 줄 '||r.miss||'개'); continue; end if;
    if not r.shipped and coalesce((select value from core.app_setting where key='sl_require_ship'),'on') = 'on' then
      skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '미발송 (송장 없음) — 발송 후에 올립니다'); continue; end if;
    if exists (select 1 from ec.order_queue q where q.order_no = r.order_no and q.status <> 'void') then
      skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '이미 주문서로 만들었습니다'); continue; end if;
    if core.f_ec_slip_of(r.order_no, r.alt) is not null then
      skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '이카운트에 이미 등록된 주문 (주문서 현황 업로드 기준)'); continue; end if;

    v_fee   := core.f_sl_fee(r.order_no);
    v_lines := r.lines;
    if v_fee_on and coalesce((v_fee->>'fee')::numeric,0) > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'item_code', v_fee_item, 'qty', 1,
        'line_total', (v_fee->>'fee')::numeric,
        'unit_price', (v_fee->>'fee')::numeric,
        'no_stock', true,
        'remark', left(r.order_no,100)));
    end if;

    v_res := core.f_order_submit(jsonb_build_object(
      'origin','online', 'io_date', r.io_date, 'wh_code', p_wh, 'channel', r.ch,
      'order_no', r.order_no,          -- 쇼핑몰 주문번호
      'order_ref', r.alt,              -- 샵링커 주문번호 → 이카운트 주문No.
      'cust_name', r.buyer,
      'cust_code', (select cust_code from ec.channel_cust cc where cc.channel = r.ch limit 1),
      'deal_type', (select c.deal_type from ec.customer c join ec.channel_cust cc on cc.cust_code = c.code where cc.channel = r.ch limit 1),
      'emp_code', coalesce(v_emp, (select c.handler from ec.customer c join ec.channel_cust cc on cc.cust_code = c.code where cc.channel = r.ch limit 1)),
      'handler', v_handler,
      'remark', to_char(r.ord_date,'FMMM')||'월 주문건 / '||to_char(v_today,'YYYY-MM-DD'),
      'allow_negative', p_allow_neg, 'lines', v_lines), p_by);
    if coalesce((v_res->>'ok')::boolean,false) then
      ok := ok + 1; made := made || (v_res->>'id')::bigint;
      update ec.order_queue set batch_id = v_batch where id = (v_res->>'id')::bigint;
    else skip := skip || jsonb_build_object('order_no', r.order_no, 'reason', '재고 부족', 'shortage', v_res->'shortage'); end if;
  end loop;
  return jsonb_build_object('ok', ok > 0, 'made', ok, 'ids', to_jsonb(made), 'skipped', skip, 'batch_id', case when ok > 0 then v_batch end);
end $fn$;
