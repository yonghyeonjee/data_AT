-- mvp_259 · 2026-11-02 · 상담 입력 [판매 완료] — 판매 입력을 따로 하지 않는다
-- 담당자는 상담에서 [판매 완료] + 구분(일시불·구독·직판)만 고른다. 판매 날짜·제품·금액은 DPS 판매가
-- 고객명·전화번호로 이어 준다(core.f_consult_link_sales). 안 이어진 것만 [판매 확인 필요] 에서 고른다.
-- (DB 에는 이미 적용 — 기록용)

-- ① 판매 완료 구분
alter table crm.consult add column if not exists sale_kind text;
alter table crm.consult add constraint consult_sale_kind_check check (sale_kind is null or sale_kind in ('일시불','구독','직판'));
-- 이미 판매에 이어진 구매완료 상담은 그 판매의 구분으로 채움 (179건)
update crm.consult c set sale_kind = o.sale_kind
  from core.orders o where o.id = c.linked_order_id and c.result='구매완료' and c.sale_kind is null and o.sale_kind in ('일시불','구독','직판');

-- ② fn_store_consult_submit : p_data.sale_kind 를 받아 구매완료일 때만 저장 (서버 원본 부분 치환)
--    a) declare 에 v_kind text  b) 상태 검사 앞에 구분 검사  c) insert 열·값에 sale_kind
-- ③ fn_store_consult_update : 동작 추가 (서버 원본 부분 치환)
--    'sold'   p_memo = 구분 → result 구매완료 · sale_kind · 콜백 지움 · core.f_consult_link_sales(60)
--    'link'   p_memo = core.orders.id → 판매 확인 필요에서 고른 판매에 잇기 (다른 상담에 이어진 판매는 거절)
--    'unlink' 이어진 판매 떼기
--    판매 완료에서 다른 상태(start·pre·hold·resume·done·reject)로 바꾸면 sale_kind·linked_order_id 를 비운다
--    응답에 linked_order
-- ③-1 fn_store_consults_my : p_filter 'sold'(result 구매완료) · counts.sold·sold_need · 줄에 sale_kind·order_at·order_src (서버 원본 부분 치환)

-- ④ 판매 완료 상담 목록 — 판매 확인 필요 · 상담 현황 입력 내역 · 판매현황
create or replace function public.fn_store_sale_consults(p_code text, p_state text default 'need', p_from date default null, p_to date default null,
  p_handler text default null, p_q text default null, p_limit integer default 50, p_offset integer default 0, p_scope text default null)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare
  v_me  text := core.f_staff(p_code);
  v_mgr boolean := core.f_staff_is_mgr(v_me);
  v_who text := case when v_mgr then nullif(btrim(coalesce(p_handler,'')),'') else v_me end;
  v_st  text := lower(coalesce(nullif(btrim(p_state),''),'need'));
  v_q   text := nullif(btrim(coalesce(p_q,'')),'');
  v_dig text := nullif(regexp_replace(coalesce(p_q,''),'\D','','g'),'');
  v_lim int := least(greatest(coalesce(p_limit,50),1),200);
  v_off int := greatest(coalesce(p_offset,0),0);
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_from date := coalesce(p_from, v_today - 90);
  v_to   date := coalesce(p_to, v_today);
  v_sc  text := nullif(btrim(coalesce(p_scope,'')),'');
  v_out jsonb;
begin
  perform set_config('dc.me', coalesce(v_me,''), true);
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if v_to - v_from > 400 then raise exception '조회 기간은 400일 이내로 해주세요'; end if;
  /* 다른 담당자 고객까지 보면(점장님 전체) 고객 정보 재확인 · 접근 기록 (mvp_258 규칙) */
  if v_who is distinct from v_me then perform core.f_store_pii(v_me, 'sale_consults'); end if;
  with base as (
    select k.*, (k.consult_at at time zone 'Asia/Seoul')::date d,
           case when k.result <> '구매완료' then 'other'
                when k.linked_order_id is not null then 'linked'
                when (k.consult_at at time zone 'Asia/Seoul')::date >= v_today - 2 then 'wait'   /* DPS 는 아침에 전날까지 들어온다 */
                else 'need' end st
      from crm.consult k
     where (v_who is null or k.handler = v_who)
       and (k.hidden_at is null or (coalesce(k.hidden_reason,'') like '테스트%' and core.f_staff_is_dev(v_me)))
       and k.deleted_at is null
       and k.consult_at >= core.f_kst(v_from) and k.consult_at < core.f_kst(v_to + 1)
       and (v_sc is null or core.f_consult_scope(k.channel_code, k.source) = v_sc)
       and (v_q is null or k.customer_name ilike '%'||v_q||'%' or k.source_ref ilike '%'||v_q||'%'
            or coalesce(k.interest_category,'') ilike '%'||v_q||'%' or coalesce(k.purchase_item,'') ilike '%'||v_q||'%'
            or coalesce(k.interest_model_code,'') ilike '%'||v_q||'%'
            or (v_dig is not null and length(v_dig) >= 3 and regexp_replace(coalesce(k.phone,''),'\D','','g') like '%'||v_dig||'%'))
  ), cnt as (
    select jsonb_build_object('all', count(*), 'sold', count(*) filter (where st <> 'other'),
             'linked', count(*) filter (where st='linked'), 'wait', count(*) filter (where st='wait'), 'need', count(*) filter (where st='need'),
             '일시불', count(*) filter (where st <> 'other' and sale_kind='일시불'), '구독', count(*) filter (where st <> 'other' and sale_kind='구독'),
             '직판', count(*) filter (where st <> 'other' and sale_kind='직판')) c,
           count(*) filter (where v_st = 'all' or (v_st = 'sold' and st <> 'other') or st = v_st) tot
      from base
  ), pg as (
    select * from base b where v_st = 'all' or (v_st = 'sold' and st <> 'other') or st = v_st
     order by b.consult_at desc, b.id desc limit v_lim offset v_off
  ), rws as (
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'ref', k.source_ref, 'at', k.consult_at, 'handler', k.handler, 'name', k.customer_name,
        'tel', regexp_replace(coalesce(k.phone,''),'\D','','g'),
        'phone', case when length(regexp_replace(coalesce(k.phone,''),'\D','','g')) >= 10
                      then left(regexp_replace(k.phone,'\D','','g'),3)||'-****-'||right(regexp_replace(k.phone,'\D','','g'),4) end,
        'result', k.result, 'st', k.st, 'kind', k.sale_kind, 'source', k.source,
        'src', coalesce((select ch.label from core.inq_channel ch where ch.code = k.channel_code), core.f_consult_src(k.source, k.inflow_route)),
        'type', core.f_inq_type_label(k.type_codes, k.type_code),
        'interest', k.interest_category, 'model', k.interest_model_code, 'bought', k.purchase_item, 'content', left(k.content, 100),
        'order', (select jsonb_build_object('id', o1.id, 'at', o1.order_at, 'src', o1.source, 'no', o1.order_no,
                    'kind', o1.sale_kind, 'handler', o1.handler,
                    'product', (select string_agg(distinct coalesce(nullif(o2.model_key,''), o2.product_name_raw), ', ') from core.orders o2 where o2.source = o1.source and o2.order_no = o1.order_no),
                    'amount', (select sum(o2.gross_amount - o2.refund_amount) from core.orders o2 where o2.source = o1.source and o2.order_no = o1.order_no))
                    from core.orders o1 where o1.id = k.linked_order_id))
        order by k.consult_at desc, k.id desc), '[]'::jsonb) r from pg k)
  select jsonb_build_object('ok', true, 'me', v_me, 'is_mgr', v_mgr, 'who', v_who, 'state', v_st, 'from', v_from, 'to', v_to,
           'total', cnt.tot, 'limit', v_lim, 'offset', v_off, 'counts', cnt.c, 'rows', rws.r)
    into v_out from cnt, rws;
  return v_out;
end $f$;

-- ⑤ 판매 확인 필요 — 이 상담에 이을 만한 판매 후보 (아직 어느 상담에도 안 이어진 DPS·매장 판매)
create or replace function public.fn_store_sale_candidates(p_code text, p_id bigint, p_any boolean default false)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare
  v_me text := core.f_staff(p_code);
  k crm.consult%rowtype;
  v_d8 text; v_out jsonb;
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select * into k from crm.consult where id = p_id and deleted_at is null;
  if not found then raise exception '상담을 찾을 수 없습니다'; end if;
  if k.handler is distinct from v_me and not core.f_staff_is_mgr(v_me) then raise exception '내 상담만 볼 수 있습니다' using errcode='42501'; end if;
  if p_any or k.handler is distinct from v_me then perform core.f_store_pii(v_me, 'sale_candidates'); end if;
  v_d8 := nullif(right(regexp_replace(coalesce(k.phone,''),'\D','','g'),8),'');
  with o as (
    select o.source, o.order_no, min(o.id) id, min(o.order_at) at, max(o.handler) handler, max(o.sale_kind) kind,
           string_agg(distinct coalesce(nullif(o.model_key,''), o.product_name_raw), ', ') product,
           sum(o.gross_amount - o.refund_amount) amount, max(o.buyer_name_raw) bname, max(o.buyer_key) bkey
      from core.orders o
     where o.source in ('dps','store') and not coalesce(o.is_test,false) and o.net_amount > 0
       and o.order_at between k.consult_at - interval '14 days' and k.consult_at + interval '60 days'
       and (p_any or o.handler = k.handler)
       and not exists (select 1 from crm.consult x where x.linked_order_id = o.id and x.deleted_at is null)
     group by o.source, o.order_no
  ), m as (
    select o.*, cu.phone cphone,
           (v_d8 is not null and right(regexp_replace(coalesce(cu.phone,''),'\D','','g'),8) = v_d8) same_phone,
           (o.bkey is not null and o.bkey = k.buyer_key) same_key,
           (k.customer_name is not null and coalesce(o.bname, cu.name) = k.customer_name) same_name
      from o left join crm.customer cu on cu.buyer_key = o.bkey
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'src', source, 'no', order_no, 'at', at, 'handler', handler, 'kind', kind,
           'product', product, 'amount', amount,
           'name', case when coalesce(bname,'') = '' then null when length(bname) <= 2 then left(bname,1)||'*' else left(bname,1)||repeat('*', length(bname)-2)||right(bname,1) end,
           'tail', nullif(right(regexp_replace(coalesce(cphone,''),'\D','','g'),4),''),
           'same_phone', same_phone or same_key, 'same_name', same_name,
           'days', round(extract(epoch from at - k.consult_at)/86400))
           order by (same_phone or same_key) desc, same_name desc, abs(extract(epoch from at - k.consult_at)), id), '[]'::jsonb)
    into v_out from (select * from m order by (same_phone or same_key) desc, same_name desc, abs(extract(epoch from at - k.consult_at)) limit 30) t;
  return jsonb_build_object('ok', true, 'id', p_id, 'handler', k.handler, 'any', p_any, 'rows', v_out);
end $f$;

revoke all on function public.fn_store_sale_consults(text,text,date,date,text,text,integer,integer,text) from public;
revoke all on function public.fn_store_sale_candidates(text,bigint,boolean) from public;
grant execute on function public.fn_store_sale_consults(text,text,date,date,text,text,integer,integer,text) to anon, authenticated, service_role;
grant execute on function public.fn_store_sale_candidates(text,bigint,boolean) to anon, authenticated, service_role;
