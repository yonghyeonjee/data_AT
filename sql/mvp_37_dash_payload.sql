-- mvp_37: GAS 매출 대시보드 v4 payload 를 Datacenter 데이터로 생성 (dash/ 자체 모드 · admin 대시보드 이식용)
-- 출처 매핑 (GAS 와 동일 원천):
--   온라인 채널  → core.channel_daily (담당자 수기 = GAS _raw)      · 주문수/상품 → core.orders(shoplinker)
--   매장(시흥)/매장구독(시흥)/직판 → core.store_daily              · 직판 담당자별 → subs
--   통신판매(VMS) → core.orders(source ecount)  · 렌탈 → core.orders(source rental)

create or replace function core.f_dash_payload(p_from date, p_to date) returns jsonb
language plpgsql set search_path = pg_catalog, public as $$
declare v_days int := (p_to - p_from) + 1; v_out jsonb;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception '기간이 올바르지 않습니다'; end if;
  if v_days > 800 then raise exception '기간은 최대 800일입니다'; end if;

  -- 채널 목록 (GAS 순서) · 기간 내 데이터가 있는 채널만
  create temp table if not exists _ch (ci int, name text, grp text, norefund bool) on commit drop;
  delete from _ch;
  insert into _ch (ci, name, grp, norefund)
  select row_number() over (order by o) - 1, name, grp, norefund from (
    select name, grp, norefund, o from (values
      ('P몰','고도몰',false,1),('S몰','고도몰',false,2),('AT몰','고도몰',false,3),('시흥','고도몰',false,4),
      ('E스토어','오픈마켓',false,5),('B2B','오픈마켓',false,6),('가전시장','오픈마켓',false,7),('쿠팡','오픈마켓',false,8),('11번가','오픈마켓',false,9),
      ('지마켓','오픈마켓',false,10),('옥션','오픈마켓',false,11),('SSG','오픈마켓',false,12),('현대홈쇼핑','오픈마켓',false,13),('쿠팡이츠','오픈마켓',false,14),
      ('SK스토아','오픈마켓',false,15),('토스쇼핑','오픈마켓',false,16),('롯데온','오픈마켓',false,17),('카카오-관악','오픈마켓',false,18),('카카오-시흥','오픈마켓',false,19),
      ('한퓨어','오픈마켓',false,20),('삼성AT스토어','오픈마켓',false,21),
      ('통신판매(VMS)','오프라인',true,30),('매장(시흥)','오프라인',false,31),('매장구독(시흥)','오프라인',false,32),('직판','오프라인',false,33),('렌탈','오프라인',true,34)
    ) t(name, grp, norefund, o)
    where name in (select channel from core.channel_daily where biz_date between p_from and p_to and (sales <> 0 or refund <> 0))
       or (name = '통신판매(VMS)' and exists (select 1 from core.orders where source in ('ecount','ecount_sales') and (order_at at time zone 'Asia/Seoul')::date between p_from and p_to))
       or (name = '렌탈' and exists (select 1 from core.orders where source = 'rental' and (order_at at time zone 'Asia/Seoul')::date between p_from and p_to))
       or (name = '매장(시흥)' and exists (select 1 from core.store_daily where sale_kind = '일시불' and biz_date between p_from and p_to))
       or (name = '매장구독(시흥)' and exists (select 1 from core.store_daily where sale_kind = '구독' and biz_date between p_from and p_to))
       or (name = '직판' and exists (select 1 from core.store_daily where sale_kind = '직판' and biz_date between p_from and p_to))
  ) x;

  -- 일별 셀
  create temp table if not exists _cells (di int, ci int, g numeric, r numeric) on commit drop;
  delete from _cells;
  insert into _cells
  select (cd.biz_date - p_from), c.ci, sum(cd.sales), sum(cd.refund)
    from core.channel_daily cd join _ch c on c.name = cd.channel
   where cd.biz_date between p_from and p_to group by 1, 2
  union all
  select (sd.biz_date - p_from), c.ci, sum(sd.sales), sum(sd.refund)
    from core.store_daily sd join _ch c on c.name = case sd.sale_kind when '일시불' then '매장(시흥)' when '구독' then '매장구독(시흥)' else '직판' end
   where sd.biz_date between p_from and p_to group by 1, 2
  union all
  select ((o.order_at at time zone 'Asia/Seoul')::date - p_from), c.ci, sum(o.gross_amount), sum(o.refund_amount)
    from core.orders o join _ch c on c.name = case when o.source = 'rental' then '렌탈' else '통신판매(VMS)' end
   where o.source in ('ecount','ecount_sales','rental') and (o.order_at at time zone 'Asia/Seoul')::date between p_from and p_to group by 1, 2;

  -- 주문 수 (원장 기준)
  create temp table if not exists _oc (di int, ci int, n int) on commit drop;
  delete from _oc;
  insert into _oc
  select ((o.order_at at time zone 'Asia/Seoul')::date - p_from), c.ci, count(distinct o.order_no)
    from core.orders o
    join _ch c on c.name = case when o.source = 'rental' then '렌탈' when o.source in ('ecount','ecount_sales') then '통신판매(VMS)'
                                when o.source = 'store' then case when o.sale_kind = '구독' then '매장구독(시흥)' when o.sale_kind = '직판' then '직판' else '매장(시흥)' end
                                else core.f_channel_norm(o.channel_name) end
   where (o.order_at at time zone 'Asia/Seoul')::date between p_from and p_to group by 1, 2;

  -- 상품 (월 × 채널 × 모델) · 기간 내 총매출 상위 400 모델
  create temp table if not exists _pm (mi int, ym text) on commit drop;
  delete from _pm;
  insert into _pm select row_number() over (order by ym) - 1, ym from (
    select distinct to_char(gs, 'YYYY-MM') ym from generate_series(p_from, p_to, '1 day') gs) t;
  create temp table if not exists _pr (pi int, model text, name text, cat text, tot numeric) on commit drop;
  delete from _pr;
  insert into _pr
  select row_number() over (order by tot desc) - 1, model, name, cat, tot from (
    select coalesce(nullif(o.model_key,''), nullif(o.model_code,''), left(o.product_name_raw, 40)) model,
           (array_agg(o.product_name_raw order by o.gross_amount desc))[1] name,
           coalesce((array_agg(o.category order by o.gross_amount desc) filter (where o.category is not null))[1], '기타') cat,
           sum(o.gross_amount) tot
      from core.orders o
     where (o.order_at at time zone 'Asia/Seoul')::date between p_from and p_to and o.product_name_raw is not null
     group by 1 order by 4 desc limit 400) t;

  v_out := jsonb_build_object(
    'days', (select jsonb_agg(to_char(gs, 'YYYY-MM-DD') order by gs) from generate_series(p_from, p_to, '1 day') gs),
    'channels', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'group', grp, 'norefund', norefund) order by ci), '[]'::jsonb) from _ch),
    'cells', (select coalesce(jsonb_agg(jsonb_build_array(di, ci, round(g), round(r)) order by di, ci), '[]'::jsonb) from _cells),
    'ocells', (select coalesce(jsonb_agg(jsonb_build_array(di, ci, n) order by di, ci), '[]'::jsonb) from _oc),
    'products', (select coalesce(jsonb_agg(jsonb_build_array(model, name, cat) order by pi), '[]'::jsonb) from _pr),
    'pmonths', (select coalesce(jsonb_agg(ym order by mi), '[]'::jsonb) from _pm),
    'pcells', (select coalesce(jsonb_agg(jsonb_build_array(mi, ci, pi, q, round(g), round(r)) order by mi, ci, pi), '[]'::jsonb) from (
        select m.mi, c.ci, p.pi, sum(o.qty) q, sum(o.gross_amount) g, sum(o.refund_amount) r
          from core.orders o
          join _pm m on m.ym = to_char(o.order_at at time zone 'Asia/Seoul', 'YYYY-MM')
          join _pr p on p.model = coalesce(nullif(o.model_key,''), nullif(o.model_code,''), left(o.product_name_raw, 40))
          join _ch c on c.name = case when o.source = 'rental' then '렌탈' when o.source in ('ecount','ecount_sales') then '통신판매(VMS)'
                                      when o.source = 'store' then case when o.sale_kind = '구독' then '매장구독(시흥)' when o.sale_kind = '직판' then '직판' else '매장(시흥)' end
                                      else core.f_channel_norm(o.channel_name) end
         where (o.order_at at time zone 'Asia/Seoul')::date between p_from and p_to
         group by 1, 2, 3) t),
    'rental', (select jsonb_build_object(
        'rows', coalesce(jsonb_agg(jsonb_build_array(di, ii, ti, cu, amt) order by di), '[]'::jsonb),
        'items', (select coalesce(jsonb_agg(v order by i), '[]'::jsonb) from (select distinct coalesce(product_name_raw,'-') v, dense_rank() over (order by coalesce(product_name_raw,'-')) - 1 i from core.orders where source='rental' and (order_at at time zone 'Asia/Seoul')::date between p_from and p_to) x),
        'types', (select coalesce(jsonb_agg(v order by i), '[]'::jsonb) from (select distinct coalesce(payment_method,'-') v, dense_rank() over (order by coalesce(payment_method,'-')) - 1 i from core.orders where source='rental' and (order_at at time zone 'Asia/Seoul')::date between p_from and p_to) x),
        'custs', (select coalesce(jsonb_agg(v order by i), '[]'::jsonb) from (select distinct coalesce(buyer_name_raw,'-') v, dense_rank() over (order by coalesce(buyer_name_raw,'-')) - 1 i from core.orders where source='rental' and (order_at at time zone 'Asia/Seoul')::date between p_from and p_to) x))
      from (select ((order_at at time zone 'Asia/Seoul')::date - p_from) di,
                   dense_rank() over (order by coalesce(product_name_raw,'-')) - 1 ii,
                   dense_rank() over (order by coalesce(payment_method,'-')) - 1 ti,
                   dense_rank() over (order by coalesce(buyer_name_raw,'-')) - 1 cu,
                   round(gross_amount - refund_amount) amt
              from core.orders where source='rental' and (order_at at time zone 'Asia/Seoul')::date between p_from and p_to) r),
    'subs', (select jsonb_build_object(
        'names', coalesce((select jsonb_agg(h order by i) from (select distinct h, dense_rank() over (order by h) - 1 i from (
                    select handler h from core.store_daily where sale_kind='직판' and biz_date between p_from and p_to and handler <> ''
                    union select handler from core.orders where source in ('ecount','ecount_sales') and handler is not null and (order_at at time zone 'Asia/Seoul')::date between p_from and p_to) u) n), '[]'::jsonb),
        'rows', coalesce((select jsonb_agg(jsonb_build_array(di, ci, ni, round(g), round(r)) order by di) from (
                    select s.di, s.ci, dense_rank() over (order by s.h) - 1 ni, s.g, s.r from (
                      select (sd.biz_date - p_from) di, c.ci, sd.handler h, sum(sd.sales) g, sum(sd.refund) r
                        from core.store_daily sd join _ch c on c.name = '직판'
                       where sd.sale_kind='직판' and sd.handler <> '' and sd.biz_date between p_from and p_to group by 1,2,3
                      union all
                      select ((o.order_at at time zone 'Asia/Seoul')::date - p_from), c.ci, o.handler, sum(o.gross_amount), sum(o.refund_amount)
                        from core.orders o join _ch c on c.name = '통신판매(VMS)'
                       where o.source in ('ecount','ecount_sales') and o.handler is not null and (o.order_at at time zone 'Asia/Seoul')::date between p_from and p_to group by 1,2,3
                    ) s) q), '[]'::jsonb))),
    'events', coalesce((select value::jsonb from core.app_setting where key = 'dash_events'), '[]'::jsonb),
    'updated', to_char(now() at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI'),
    'source', 'datacenter', 'from', p_from, 'to', p_to);
  return v_out;
end $$;

-- 로그인 사용자용
create or replace function public.fn_dash_payload(p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_dash_payload(p_from, p_to);
end $$;
revoke all on function public.fn_dash_payload(date, date) from public;
grant execute on function public.fn_dash_payload(date, date) to authenticated;

-- 외부 공유(dash/) 용: 비밀번호 확인 (해시는 core.api_key 'dash_share')
insert into core.api_key(name, key_hash, note) values ('dash_share', encode(extensions.digest('3166','sha256'),'hex'), '외부 공유 대시보드 비밀번호')
on conflict (name) do nothing;
create or replace function public.fn_dash_payload_pub(p_pw text, p_from date default null, p_to date default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if not core.f_api_ok('dash_share', p_pw) then raise exception 'unauthorized' using errcode='42501'; end if;
  return core.f_dash_payload(coalesce(p_from, (date_trunc('year', current_date) - interval '1 day')::date), coalesce(p_to, current_date));
end $$;
revoke all on function public.fn_dash_payload_pub(text, date, date) from public;
grant execute on function public.fn_dash_payload_pub(text, date, date) to anon, authenticated;
