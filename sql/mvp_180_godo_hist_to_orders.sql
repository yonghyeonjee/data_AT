-- mvp_180 · 2026-09-22 · 고도몰 과거 주문(raw.godo_order_hist 2021~2025 · 4몰) → 통합 원장 core.orders (source='godo_hist')
-- 요청서(2026-09-22 지용현) 그대로: 새 출처 godo_hist · idempotent(전부 지우고 다시 넣기) · upload_id 로 되돌리기 · dry-run ·
--   제외(엑셀 결제실패·고객결제중단·자동취소 / API f1·f2·f3·o1) · 겹침은 같은 몰·같은 주문번호가 샵링커 원장에 있으면 넣지 않음 ·
--   샵링커 시작일 이후의 불일치 건은 기본 보류(p_include_unmatched_after=true 로 넣음) · 취소·환불 줄은 refund=gross ·
--   줄 금액 = 주문의 '총 품목 금액'(API 총상품금액)을 (판매가+옵션 추가금)×수량 비율로 나눔 — 판매가에는 옵션 추가금(+75,000 …)이 빠져 있고
--   상품수량이 1 로 찍힌 다량 주문(67,500 × 36 = 2,430,000)도 있어 주문 단위 총액이 유일하게 믿을 값이다. 주문 단위 값을 줄마다 더하지 않는다.
-- core.orders 의 net_amount·model_key·category·goods_kind 는 generated 열이라 insert 에 넣지 않는다. source_ref 는 (source, source_ref) unique 라 '몰:상품주문번호'(겹치면 :주문번호:줄).
-- '상세설명참조' 같은 모델명 글은 null 로 — model_key 가 상품명에서 모델을 뽑는다.
-- 주문번호가 몰 사이에 겹치는 8건(다른 고객·다른 주문)은 두 번째 몰의 order_no 에 '#몰' 을 붙인다(unique (source,order_no,line_no)).
-- API 상태·결제수단 코드표는 core.godo_code 에 두었다 — 고도몰 문서를 컨테이너에서 못 열어(egress 차단) godomall5 매뉴얼 기억으로 넣었으니 틀리면 표만 고치고 다시 돌리면 된다.

alter table core.orders drop constraint if exists orders_source_check;
alter table core.orders add constraint orders_source_check check (source = any (array['shoplinker','godo','godo_hist','ecount','store','rental','manual','form']));

create table if not exists core.godo_code (kind text not null, code text not null, label text not null, sale boolean not null default true, refund boolean not null default false, note text, primary key (kind, code));
insert into core.godo_code (kind, code, label, sale, refund, note) values
  ('status','o1','입금대기',false,false,'결제 전'), ('status','o2','결제중',false,false,'결제 전'),
  ('status','p1','결제완료',true,false,null), ('status','g1','상품준비중',true,false,null),
  ('status','d1','배송중',true,false,null), ('status','d2','배송완료',true,false,null), ('status','s1','구매확정',true,false,null),
  ('status','c1','취소요청',true,true,'취소'), ('status','c2','취소(고객)',true,true,'취소'), ('status','c3','취소(관리자)',true,true,'취소'), ('status','c4','취소완료',true,true,'취소'),
  ('status','b1','반품접수',true,true,'반품'), ('status','b2','반품승인',true,true,'반품'), ('status','b3','반품보류',true,true,'반품'), ('status','b4','반품완료',true,true,'반품'),
  ('status','e1','교환접수',true,false,'교환'), ('status','e2','교환승인',true,false,'교환'), ('status','e3','교환보류',true,false,'교환'), ('status','e4','교환완료',true,false,'교환'), ('status','e5','교환배송',true,false,'교환'),
  ('status','r1','환불접수',true,true,'환불'), ('status','r2','환불승인',true,true,'환불'), ('status','r3','환불완료',true,true,'환불'),
  ('status','f1','결제시도',false,false,'결제 안 됨'), ('status','f2','결제실패',false,false,'결제 안 됨'), ('status','f3','결제중단',false,false,'결제 안 됨'),
  ('pay','gb','무통장입금',true,false,null), ('pay','pb','계좌이체',true,false,null), ('pay','pc','신용카드',true,false,null), ('pay','ph','휴대폰',true,false,null),
  ('pay','pv','가상계좌',true,false,null), ('pay','pt','포인트',true,false,'확인 필요'), ('pay','eb','예치금',true,false,null), ('pay','em','마일리지',true,false,null), ('pay','ev','전액할인',true,false,null),
  ('pay','fp','간편결제(fp)',true,false,'확인 필요'), ('pay','fc','간편결제(fc)',true,false,'확인 필요'), ('pay','fa','간편결제(fa)',true,false,'확인 필요'), ('pay','fb','간편결제(fb)',true,false,'확인 필요'), ('pay','fh','간편결제(fh)',true,false,'확인 필요')
on conflict (kind, code) do nothing;

create or replace function core.f_godo_num(t text) returns numeric language sql immutable as $$
  select nullif(regexp_replace(coalesce(t,''), '[^0-9.]', '', 'g'), '')::numeric $$;
create or replace function core.f_godo_ts(t text) returns timestamptz language sql immutable as $$
  select case when coalesce(t,'') ~ '^\d{4}-\d{2}-\d{2}' and t !~ '^0000' then (left(t,19)::timestamp) at time zone 'Asia/Seoul' end $$;
-- 옵션 추가금: 엑셀 옵션정보의 '+75,000' 합 − ' -5,000' 합, API 옵션([[이름,값,'',추가금,null],…])의 4번째 값 합
create or replace function core.f_godo_opt(p_src text, p_opt jsonb) returns numeric language plpgsql immutable as $$
declare v numeric := 0; s text; e jsonb;
begin
  if p_src = 'excel' then
    s := coalesce(p_opt #>> '{}', '');
    select coalesce(sum(replace(m[1],',','')::numeric),0) into v from regexp_matches(s, '\+\s*([0-9][0-9,]*)', 'g') m;
    v := v - (select coalesce(sum(replace(m[1],',','')::numeric),0) from regexp_matches(s, '\s-\s*([0-9][0-9,]*)', 'g') m);
    return v;
  end if;
  if jsonb_typeof(p_opt) = 'string' and (p_opt #>> '{}') like '[%' then p_opt := (p_opt #>> '{}')::jsonb; end if;
  if jsonb_typeof(p_opt) = 'array' then
    for e in select * from jsonb_array_elements(p_opt) loop
      if jsonb_typeof(e) = 'array' and jsonb_array_length(e) >= 4 and jsonb_typeof(e->3) = 'number' then v := v + (e->>3)::numeric; end if;
    end loop;
  end if;
  return v;
exception when others then return 0;
end $$;

create or replace function core.f_godo_hist_apply(p_dry boolean default true, p_include_unmatched_after boolean default false, p_by uuid default null)
returns jsonb language plpgsql volatile as $$
declare v_upload bigint; v_ins int := 0; v_out jsonb; v_prev int;
begin
  drop table if exists _gh;
  create temp table _gh on commit drop as
  with base as (
    select h.row_hash, h.mall, h.source src, h.order_no raw_no, h.data d,
      case h.mall when 'P몰' then 'pcnik35-P' when 'S몰' then 'pcnik35-S' when 'AT몰' then 'pcnik35-AT' when '시흥몰' then 'samsungsh' end acct,
      case h.mall when 'P몰' then 1 when 'S몰' then 2 when 'AT몰' then 3 else 4 end mall_ord,
      coalesce(h.data->>'주문상태','') st_raw,
      case when h.source='excel' then coalesce(h.data->>'주문상태','') else coalesce((select c.label from core.godo_code c where c.kind='status' and c.code = h.data->>'주문상태'), h.data->>'주문상태') end st,
      case when h.source='excel' then coalesce(h.data->>'주문상태','') in ('결제실패','고객결제중단','자동취소')
           else coalesce((select not c.sale from core.godo_code c where c.kind='status' and c.code = h.data->>'주문상태'), false) end excluded,
      case when h.source='excel' then coalesce(h.data->>'주문상태','') in ('환불완료','환불접수','환불보류','관리자취소','고객요청취소','반품접수','반품완료')
           else coalesce((select c.refund from core.godo_code c where c.kind='status' and c.code = h.data->>'주문상태'), false) end is_refund,
      core.f_godo_ts(h.data->>'주문일자') order_at,
      core.f_godo_ts(case when h.source='excel' then h.data->>'클레임 완료일자' else h.data->>'취소일' end) claim_at,
      case when h.source='excel' then nullif(h.data->>'상품코드','') else nullif(h.data->>'상품번호','') end product_code,
      case when h.source='excel' then coalesce(case when btrim(coalesce(h.data->>'모델명','')) ~ '참조|없음|^-+$' then null else nullif(btrim(h.data->>'모델명'),'') end, nullif(btrim(h.data->>'자체상품코드'),''))
           else coalesce(case when btrim(coalesce(h.data->>'모델명','')) ~ '참조|없음|^-+$' then null else nullif(btrim(h.data->>'모델명'),'') end, nullif(btrim(h.data->>'상품코드'),'')) end model_code,
      coalesce(h.data->>'상품명','') pname,
      case when h.source='excel' then nullif(h.data->>'옵션정보','') else nullif(h.data #>> '{옵션}','') end option_text,
      coalesce(core.f_godo_num(case when h.source='excel' then h.data->>'상품수량' else h.data->>'수량' end), 1) qty,
      coalesce(core.f_godo_num(case when h.source='excel' then h.data->>'판매가' else h.data->>'상품가격' end), 0) unit,
      core.f_godo_opt(h.source, case when h.source='excel' then h.data->'옵션정보' else h.data->'옵션' end) opt,
      core.f_godo_num(case when h.source='excel' then h.data->>'총 품목 금액' else h.data->>'총상품금액' end) items_total,
      coalesce(core.f_godo_num(case when h.source='excel' then h.data->>'총 배송 금액' else h.data->>'배송비' end), 0) ship_total,
      case when h.source='excel' then coalesce(core.f_godo_num(h.data->>'쿠폰 할인 금액'),0)+coalesce(core.f_godo_num(h.data->>'회원 할인 금액'),0)+coalesce(core.f_godo_num(h.data->>'모바일앱 할인금액'),0) else 0 end disc_line,
      case when h.source='excel' then replace(nullif(h.data->>'결제방법',''), '무통장 입금', '무통장입금')
           else coalesce((select c.label from core.godo_code c where c.kind='pay' and c.code = h.data->>'결제수단'), nullif(h.data->>'결제수단','')) end pay,
      nullif(btrim(coalesce(h.data->>'주문자 이름', h.data->>'주문자명')),'') bname,
      nullif(coalesce(h.data->>'주문자 핸드폰 번호', h.data->>'주문자휴대폰'),'') bphone,
      case when h.source='excel' then coalesce(core.f_godo_num(h.data->>'주문코드(순서)')::int, 0) else coalesce(core.f_godo_num(h.data->>'줄번호')::int, 0) end seq_raw,
      case when h.source='excel' then h.data->>'상품주문번호' else h.data->>'상품번호' end line_ref
    from raw.godo_order_hist h),
  coll as (select raw_no, min(mall_ord) first_ord from base group by raw_no having count(distinct mall) > 1),
  slstart as (select channel_name mall, min(order_at) t from core.orders where source='shoplinker' group by 1),
  slno as (select distinct channel_name mall, order_no from core.orders where source='shoplinker'),
  keyed as (
    select b.*,
      row_number() over (partition by b.mall, b.raw_no order by b.seq_raw, b.line_ref, b.row_hash) line_no,
      case when c.raw_no is not null and c.first_ord < b.mall_ord then b.raw_no || '#' || b.mall else b.raw_no end order_no,
      (n.order_no is not null) matched,
      (s.t is not null and b.order_at >= s.t) after_sl,
      (b.unit + b.opt) * b.qty line_base
    from base b
    left join coll c on c.raw_no = b.raw_no
    left join slstart s on s.mall = b.mall
    left join slno n on n.mall = b.mall and n.order_no = b.raw_no),
  alloc as (
    select k.*,
      sum(k.line_base) over (partition by k.mall, k.raw_no) base_sum,
      count(*) over (partition by k.mall, k.raw_no) n_lines,
      row_number() over (partition by k.mall, k.raw_no order by k.line_no) rn,
      row_number() over (partition by k.mall, k.raw_no order by k.line_no desc) rn_desc
    from keyed k)
  select a.*,
    case when a.items_total is null then a.line_base
         when a.base_sum > 0 then round(a.items_total * a.line_base / a.base_sum)
         when a.rn = 1 then a.items_total else 0 end gross0,
    case when a.excluded then 'excluded' when a.matched then 'matched' when a.after_sl and not p_include_unmatched_after then 'hold' else 'load' end fate
  from alloc a;
  -- 반올림 잔차는 주문의 마지막 줄에
  alter table _gh add column gross numeric;
  update _gh g set gross = g.gross0 + case when g.rn_desc = 1 and g.items_total is not null and g.base_sum > 0 then g.items_total - t.s else 0 end
    from (select mall, raw_no, sum(gross0) s from _gh group by 1,2) t where t.mall = g.mall and t.raw_no = g.raw_no;

  v_out := jsonb_build_object(
    'dry', p_dry, 'include_unmatched_after', p_include_unmatched_after,
    'rows', (select count(*) from _gh), 'orders', (select count(distinct (mall, raw_no)) from _gh),
    'fate', (select jsonb_object_agg(fate, n) from (select fate, count(*) n from _gh group by 1) z),
    'excluded_by_status', (select jsonb_agg(jsonb_build_object('src', src, 'status', st_raw, 'label', st, 'rows', n) order by n desc) from (select src, st_raw, st, count(*) n from _gh where fate='excluded' group by 1,2,3) z),
    'matched_by_mall', (select jsonb_agg(jsonb_build_object('mall', mall, 'orders', n) order by mall) from (select mall, count(distinct raw_no) n from _gh where fate='matched' group by 1) z),
    'hold_by_mall_status', (select jsonb_agg(jsonb_build_object('mall', mall, 'status', st, 'orders', n, 'net', net) order by mall, n desc) from (select mall, st, count(distinct raw_no) n, sum(case when is_refund then 0 else gross end) net from _gh where fate='hold' group by 1,2) z),
    'load_by_mall_year', (select jsonb_agg(jsonb_build_object('mall', mall, 'year', y, 'orders', n, 'rows', r, 'gross', gross, 'refund', refund, 'net', gross-refund) order by mall, y)
        from (select mall, extract(year from order_at at time zone 'Asia/Seoul')::int y, count(distinct raw_no) n, count(*) r, sum(gross) gross, sum(case when is_refund then gross else 0 end) refund from _gh where fate='load' group by 1,2) z),
    'collisions', (select coalesce(jsonb_agg(distinct raw_no), '[]'::jsonb) from _gh where order_no <> raw_no),
    'alloc_note', (select jsonb_build_object('orders_total_from_items', count(distinct (mall,raw_no)) filter (where items_total is not null),
                                             'orders_items_null', count(distinct (mall,raw_no)) filter (where items_total is null),
                                             'orders_base_ne_items', count(distinct (mall,raw_no)) filter (where items_total is not null and base_sum <> items_total),
                                             'orders_base_zero', count(distinct (mall,raw_no)) filter (where items_total is not null and base_sum = 0),
                                             'no_buyer_key', count(*) filter (where fate='load' and core.f_buyer_key(bname, bphone) is null)) from _gh),
    'existing_godo_hist_rows', (select count(*) from core.orders where source='godo_hist'));
  if p_dry then return v_out; end if;

  select count(*) into v_prev from core.orders where source='godo_hist';
  update raw.upload set note = concat_ws(' · ', note, '재적재로 대체 '||to_char(now() at time zone 'Asia/Seoul','MM-DD HH24:MI')) where source='godo_hist' and rolled_back_at is null;
  delete from core.orders where source='godo_hist';
  insert into raw.upload (source, file_name, uploaded_by, row_count, note)
  values ('godo_hist', 'raw.godo_order_hist → core.orders', p_by, (select count(*) from _gh where fate='load'),
          '고도몰 과거 주문 원장 반영 (mvp_180)'||case when p_include_unmatched_after then ' · 샵링커 이후 불일치 포함' else '' end||case when v_prev>0 then ' · 이전 '||v_prev||'줄 교체' else '' end)
  returning id into v_upload;
  insert into core.orders (source, channel_type, channel_name, channel_account, order_no, line_no, source_ref, order_at, cancelled_at, status,
      product_code, model_code, product_name_raw, option_text, qty, unit_price, gross_amount, discount_amount, refund_amount,
      payment_method, buyer_key, buyer_name_raw, shipping_fee, raw_payload, upload_id)
  select 'godo_hist', '자사몰', g.mall, g.acct, g.order_no, g.line_no,
      g.mall || ':' || coalesce(g.line_ref, '') || case when count(*) over (partition by g.mall, g.line_ref) > 1 then ':' || g.raw_no || ':' || g.line_no else '' end, g.order_at,
      case when g.is_refund then g.claim_at end, g.st,
      g.product_code, g.model_code, g.pname, g.option_text, g.qty, g.unit + g.opt,
      g.gross, g.disc_line, case when g.is_refund then g.gross else 0 end,
      g.pay, core.f_buyer_key(g.bname, g.bphone), g.bname,
      case when g.rn = 1 then g.ship_total else 0 end, g.d, v_upload
  from _gh g where g.fate = 'load';
  get diagnostics v_ins = row_count;
  delete from core.dash_cache where true;
  return v_out || jsonb_build_object('inserted', v_ins, 'replaced', v_prev, 'upload_id', v_upload);
end $$;

create or replace function public.fn_godo_hist_apply(p_dry boolean default true, p_include_unmatched_after boolean default false)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 실행할 수 있습니다' using errcode='42501'; end if;
  return core.f_godo_hist_apply(p_dry, p_include_unmatched_after, auth.uid());
end $$;
revoke all on function public.fn_godo_hist_apply(boolean, boolean) from public, anon;
grant execute on function public.fn_godo_hist_apply(boolean, boolean) to authenticated, service_role;

-- 대시보드 원장 모드의 자사몰 출처 목록에 godo_hist (2군데)
do $o$ declare d text; n int; begin
  select pg_get_functiondef(oid) into d from pg_proc where proname='f_dash_payload';
  n := (length(d) - length(replace(d, '(''shoplinker'',''godo'',''smartstore'')', ''))) / length('(''shoplinker'',''godo'',''smartstore'')');
  if n <> 2 then raise exception 'dash 출처 목록 %개', n; end if;
  d := replace(d, '(''shoplinker'',''godo'',''smartstore'')', '(''shoplinker'',''godo'',''godo_hist'',''smartstore'')');
  execute d;
end $o$;

-- fn_order_list : 머리글 정렬을 서버에서 (검색된 전체 정렬 · 화면은 1페이지로). p_sort = date|amt|gross|refund|qty|channel|kind|customer|product|status|handler _ asc|desc (pg_get_functiondef 통째 치환 — OUT 열이 있어 create or replace 로는 못 바꾼다).
-- 실행 기록 2026-09-22: dry → fate {load 21295, matched 1116, hold 111, excluded 4440} · 적용 upload 533 → 재적재(모델명 정리) upload 534 · 19,909 주문 전부 sum(gross)=총 품목 금액 · 2026 자료 변화 없음 · 최대 order_at 2025-06-24.
-- 보류(hold) 109건 = 샵링커 시작일 이후인데 주문번호가 원장에 없는 것 (구매확정·배송중 43건 순매출 4,800만 · 나머지 환불·취소). 넣으려면 core.f_godo_hist_apply(false, true).
