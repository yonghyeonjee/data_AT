-- mvp_163 · 2026-09-21
-- ① 데이터 상태 카드 — 자동 적재 원천(홈페이지 문의·구독·소모품·VMS/B2B)이 crm.consult 에서 행·기간·최근 30일을 센다
--    (전엔 stat CTE 에 없어 행 0 · '없음' 으로 보였다). 홈페이지 문의는 고도몰 게시판이 아니라 별도 서비스 → 지메일 → gmail_inquiry.gs → fn_inquiry_mail_ingest.
-- ② 'CRM 발송 고객' — send_log 카드에 발송완료·실패·캠페인별·실패 사유(detail)
-- ③ fn_sl_refund_apply — 샵링커 웹 주문목록(취소/반품 상태) 을 주문번호로 대조해 환불만 반영 (원장에 줄을 만들지 않는다)
-- ④ f_source_last: web_inquiry = 지메일 자동 적재 기준

-- ① 원천 설명
update core.data_source set
  label = '홈페이지 문의 (자동 적재)',
  how   = '홈페이지(고도몰 게시판이 아니라 별도 서비스)의 문의 메일을 GAS gmail_inquiry 가 1분마다 읽어 fn_inquiry_mail_ingest 로 적재 · 잔디 「웹 문의 수신」 카드와 같은 건. 붙여넣기는 메일이 안 왔을 때 예비용',
  auto_plan = '이미 자동. 홈페이지 서비스가 POST 로 직접 보내면(개발사 요청서 전달됨) 메일 경유가 빠진다',
  expect_days = 7, alert = true
 where key = 'web_inquiry';
update core.data_source set
  label = 'CRM 발송 고객 (발송 이력)',
  how   = '센드온 발송 결과(수신번호·상태·비고)를 파일 올리기 또는 붙여넣기 · 발송완료·실패가 캠페인별로 아래에 보이고 [발송 대상 추출]에서 빠집니다 (실패 건도 보낸 것으로 봄)'
 where key = 'send_log';
update core.data_source set
  label = '구독 문의 (자동 적재)',
  how   = '구독 문의 폼 → GAS v15 → fn_submit_inquiry 자동 적재. 배정·잔디 카드도 데이터센터가 보낸다. 멈추면 시트 [상담관리] 만 쌓이고 상담 화면이 빈다'
 where key = 'web_subscription';
update core.data_source set
  label = '소모품·렌탈 문의 (자동 적재)',
  how   = '소모품·렌탈 폼 → GAS → fn_submit_inquiry 자동 적재. 담당자 문의 관리에 쌓이는 그대로가 적재된 것'
 where key = 'web_supply';
update core.data_source set
  label = 'VMS·B2B 문의 (자동 적재)',
  how   = 'VMS·B2B 폼 → GAS → fn_submit_inquiry 자동 적재(박은지 프로 고정 배정). 담당자 문의 관리에 쌓이는 그대로가 적재된 것'
 where key = 'web_b2b';
update core.data_source set expect_days = 30 where key in ('web_supply','web_b2b');   -- 드문 폼이라 열흘 넘게 비어도 정상

-- ④ 자동 적재 기준 시각
create or replace function core.f_source_last(p_key text) returns timestamptz language sql stable as $$
  select case p_key
    when 'shoplinker'      then greatest((select max(created_at) from core.orders where source='shoplinker'),
                                          (select max(ran_at) from core.sl_log where status = 'DONE' and fetched > 0))
    when 'store'           then (select max(created_at) from core.orders where source='store')
    when 'store_manual'    then (select max(updated_at) from core.store_daily)
    when 'ecount_sales'    then (select max(created_at) from core.orders where source='ecount')
    when 'rental'          then (select max(created_at) from core.orders where source='rental')
    when 'ecount_prospect' then (select max(created_at) from crm.consult where source='ecount_prospect')
    when 'web_inquiry'     then greatest((select max(created_at) from crm.web_inquiry),
                                         (select max(created_at) from crm.consult where source = 'gmail_homepage'))   /* 2026-09-21: 홈페이지 문의는 지메일 자동 적재가 원천 */
    when 'godo_member'     then (select max(uploaded_at) from raw.upload where source in ('P몰','S몰','AT몰','시흥몰'))
    when 'channel_daily'   then (select max(updated_at) from core.channel_daily)
    when 'ec_slip'         then greatest((select max(uploaded_at) from ec.slip_ref), (select max(sent_at) from ec.order_queue where status = 'sent'))
    when 'ec_customer'     then (select max(uploaded_at) from raw.upload where source='ecount_customer')
    when 'sub_plan'        then (select max(updated_at) from core.app_setting where key like 'sub_plan%')
    when 'web_subscription' then (select max(created_at) from crm.consult where source = 'web_subscription')
    when 'web_supply'       then (select max(created_at) from crm.consult where source = 'web_supply')
    when 'web_b2b'          then (select max(created_at) from crm.consult where source = 'web_b2b')
    when 'send_log'      then greatest((select max(uploaded_at) from raw.upload where source='send_log'), (select max(sent_at) from crm.send_log))
    when 'unpaid_order'  then (select max(uploaded_at) from crm.unpaid_order)
    else null end;
$$;

-- ①② 데이터 상태
create or replace function public.fn_data_status() returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v jsonb; v_kst date := (now() at time zone 'Asia/Seoul')::date;
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;

  with stat as (
    select 'shoplinker' k, count(*) rows,
           min(order_at at time zone 'Asia/Seoul')::date mn,
           max(order_at at time zone 'Asia/Seoul')::date mx,
           count(*) filter (where order_at > now() - interval '30 days') n30
      from core.orders where source='shoplinker'
    union all
    select 'store', count(*), min(order_at at time zone 'Asia/Seoul')::date, max(order_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where order_at > now() - interval '30 days')
      from core.orders where source in ('store','store_sale')
    union all
    select 'ecount_sales', count(*), min(order_at at time zone 'Asia/Seoul')::date, max(order_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where order_at > now() - interval '30 days')
      from core.orders where source in ('ecount','ecount_sales')
    union all
    select 'rental', count(*), min(order_at at time zone 'Asia/Seoul')::date, max(order_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where order_at > now() - interval '30 days')
      from core.orders where source='rental'
    union all
    select 'store_manual', count(*), min(biz_date), max(biz_date), count(*) filter (where biz_date > v_kst - 30) from core.store_daily
    union all
    select 'ecount_prospect', count(*), min(consult_at at time zone 'Asia/Seoul')::date, max(consult_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where consult_at > now() - interval '30 days')
      from crm.consult where source = 'ecount_prospect'
    /* 자동 적재 문의 4종 — crm.consult 의 source 로 센다 (2026-09-21) */
    union all
    select 'web_inquiry', count(*), min(consult_at at time zone 'Asia/Seoul')::date, max(consult_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where consult_at > now() - interval '30 days')
      from crm.consult where channel_code = 'homepage' and coalesce(source,'') <> 'store'
    union all
    select 'web_subscription', count(*), min(consult_at at time zone 'Asia/Seoul')::date, max(consult_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where consult_at > now() - interval '30 days')
      from crm.consult where source = 'web_subscription'
    union all
    select 'web_supply', count(*), min(consult_at at time zone 'Asia/Seoul')::date, max(consult_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where consult_at > now() - interval '30 days')
      from crm.consult where source = 'web_supply'
    union all
    select 'web_b2b', count(*), min(consult_at at time zone 'Asia/Seoul')::date, max(consult_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where consult_at > now() - interval '30 days')
      from crm.consult where source = 'web_b2b'
    union all
    select 'godo_member', count(*), min(first_seen_at at time zone 'Asia/Seoul')::date, max(last_seen_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where first_seen_at > now() - interval '30 days')
      from crm.customer where source_channels && array['P몰','S몰','AT몰','시흥몰']
    union all
    select 'sub_plan', count(*), min(updated_at at time zone 'Asia/Seoul')::date, max(updated_at at time zone 'Asia/Seoul')::date, 0 from sub.plan
    union all
    select 'send_log', count(*), min(sent_at at time zone 'Asia/Seoul')::date, max(sent_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where sent_at > now() - interval '30 days')
      from crm.send_log
    union all
    select 'channel_daily', count(*), min(biz_date), max(biz_date), count(*) filter (where biz_date > v_kst - 30) from core.channel_daily
    union all
    select 'unpaid_order', count(*), min(ordered_at at time zone 'Asia/Seoul')::date, max(uploaded_at at time zone 'Asia/Seoul')::date,
           count(*) filter (where resolved_at is null)
      from crm.unpaid_order
    union all
    select 'ec_slip', count(*), min(d), max(d), count(*) filter (where d > v_kst - 30) from (
      select io_date d from ec.slip_ref union all select (sent_at at time zone 'Asia/Seoul')::date from ec.order_queue where status = 'sent') s
    union all
    select 'ec_customer', count(*), (select min(uploaded_at at time zone 'Asia/Seoul')::date from raw.upload where source='ecount_customer'),
           (select max(uploaded_at at time zone 'Asia/Seoul')::date from raw.upload where source='ecount_customer'), 0 from ec.customer
  ),
  up as (
    select case when u.source in ('P몰','S몰','AT몰','시흥몰') then 'godo_member'
                when u.source = 'ecount' then 'ecount_sales'
                when u.source = 'shoplinker_refund' then 'shoplinker' else u.source end k,
           max(u.uploaded_at) last_at,
           (array_agg(u.file_name order by u.uploaded_at desc))[1] last_file,
           sum(u.error_count) skipped, count(distinct u.file_name) files
      from raw.upload u group by 1
  ),
  malls as (
    select coalesce(jsonb_agg(jsonb_build_object('mall', m, 'rows',
             (select count(*) from crm.customer c where c.source_channels @> array[m]))), '[]'::jsonb) j
      from unnest(array['P몰','S몰','AT몰','시흥몰']) m
  ),
  /* CRM 발송 고객 — 발송완료·실패를 캠페인별로 (2026-09-21) */
  sl_detail as (
    select jsonb_build_object(
      'sent',   (select count(*) from crm.send_log where status <> 'failed'),
      'failed', (select count(*) from crm.send_log where status = 'failed'),
      'campaigns', coalesce((select jsonb_agg(jsonb_build_object('code', x.campaign, 'name', c.name, 'sent', x.sent, 'failed', x.failed, 'last', x.last) order by x.last desc)
          from (select campaign, count(*) filter (where status <> 'failed') sent, count(*) filter (where status = 'failed') failed,
                       to_char(max(sent_at) at time zone 'Asia/Seoul','YYYY-MM-DD') last
                  from crm.send_log group by campaign) x
          left join crm.campaign c on c.code = x.campaign), '[]'::jsonb),
      'reasons', coalesce((select jsonb_agg(jsonb_build_object('reason', r, 'n', n) order by n desc)
          from (select coalesce(nullif(error_msg,''),'(사유 없음)') r, count(*) n from crm.send_log where status = 'failed' group by 1) y), '[]'::jsonb)) j
  ),
  /* 샵링커 — 취소·환불 반영 현황 */
  sl_refund as (
    select jsonb_build_object(
      'refund_rows_30', (select count(*) from core.orders where source='shoplinker' and refund_amount > 0 and order_at > now() - interval '30 days'),
      'refund_sum_30',  (select coalesce(sum(refund_amount),0) from core.orders where source='shoplinker' and order_at > now() - interval '30 days'),
      'last_refund_upload', (select to_char(max(uploaded_at) at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI') from raw.upload where source='shoplinker_refund')) j
  )
  select jsonb_build_object(
    'now', to_char(now() at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'),
    'sources', coalesce(jsonb_agg(jsonb_build_object(
        'key', d.key, 'label', d.label, 'owner', d.owner, 'how', d.how,
        'expect_days', d.expect_days,
        'rows', coalesce(s.rows,0), 'from', s.mn, 'to', s.mx, 'n30', coalesce(s.n30,0),
        'last_upload', to_char(u.last_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'),
        'last_load', to_char(core.f_source_last(d.key) at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI'),
        'last_file', u.last_file, 'files', coalesce(u.files,0), 'skipped', coalesce(u.skipped,0),
        'age_days', case when s.mx is null then null else least(v_kst - s.mx, coalesce(v_kst - (core.f_source_last(d.key) at time zone 'Asia/Seoul')::date, v_kst - s.mx)) end,   /* 경과 = 자료 마지막 날과 마지막 적재 중 가까운 쪽 (샵링커 주말 헛지연 방지) */
        'alert', d.alert,
        'detail', case d.key when 'send_log' then (select j from sl_detail) when 'shoplinker' then (select j from sl_refund) else null end,
        'state', case
           when coalesce(s.rows,0) = 0 and not d.alert then '준비 중'
           when coalesce(s.rows,0) = 0 then '없음'
           when not d.alert then '정상'                              /* 필수 아닌 원천은 늦어도 지연으로 안 센다 (미입금 주문 등) */
           when s.mx is null then '없음'
           when least(v_kst - s.mx, coalesce(v_kst - (core.f_source_last(d.key) at time zone 'Asia/Seoul')::date, v_kst - s.mx)) > d.expect_days then '지연'
           else '정상' end
      ) order by d.sort_no), '[]'::jsonb),
    'malls', (select j from malls),
    'db', jsonb_build_object(
      'orders', (select count(*) from core.orders),
      'customers', (select count(*) from crm.customer),
      'consults', (select count(*) from crm.consult),
      'store_daily', (select count(*) from core.store_daily),
      'size', (select pg_size_pretty(pg_database_size(current_database()))),
      'span', (select to_char(min(order_at) at time zone 'Asia/Seoul','YYYY-MM-DD')||' ~ '||
                      to_char(max(order_at) filter (where order_at <= now()) at time zone 'Asia/Seoul','YYYY-MM-DD') from core.orders))
  ) into v
  from core.data_source d
  left join stat s on s.k = d.key
  left join up   u on u.k = d.key
  where d.active;
  return v;
end $$;

-- ③ 샵링커 취소·환불 반영 — 주문번호(또는 자사주문번호=샵링커 키) 대조. 원장에 새 줄을 만들지 않는다.
create or replace function public.fn_sl_refund_apply(p_rows jsonb, p_file text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_rows int := 0; v_ref int := 0; v_found int := 0; v_upd int := 0; v_already int := 0; v_status int := 0;
        v_nf jsonb; v_nf_n int := 0; v_upload bigint;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 반영할 수 있습니다' using errcode='42501'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('rows',0,'refund_rows',0,'found',0,'updated',0);
  end if;

  drop table if exists _sr;
  create temp table _sr on commit drop as
  select nullif(btrim(r->>'order_no'),'')            as order_no,
         nullif(btrim(r->>'alt_order_no'),'')        as alt,
         nullif(btrim(r->>'status'),'')              as status,
         nullif(upper(btrim(r->>'model_code')),'')   as model,
         nullif(btrim(r->>'product_name'),'')        as pname,
         core.f_ts(r->>'cancelled_at')               as cancelled_at,
         coalesce(btrim(r->>'status'),'') ~ '(취소완료|배송전취소|입금전취소|주문취소완료|반품완료|반품입고)' as is_refund
    from jsonb_array_elements(p_rows) r;
  delete from _sr where order_no is null and alt is null;
  select count(*), count(*) filter (where is_refund) into v_rows, v_ref from _sr;

  /* 대조: 주문번호(몰 주문번호) 또는 자사주문번호(샵링커 키 = source_ref) */
  drop table if exists _hit;
  create temp table _hit on commit drop as
  select distinct on (o.id) o.id, o.order_no, o.refund_amount, o.status old_status, s.status new_status, s.is_refund, s.cancelled_at,
         (s.model is not null and o.model_code = s.model) or (s.pname is not null and o.product_name_raw = s.pname) as line_match,
         s.model is not null or s.pname is not null as has_line_key
    from _sr s
    join core.orders o on o.source = 'shoplinker'
     and (o.order_no = s.order_no or (s.alt is not null and o.source_ref = s.alt))
   order by o.id, line_match desc;
  /* 주문에 줄이 여럿이고 파일 줄이 제품을 특정하면, 같은 주문의 다른 제품 줄은 건드리지 않는다 */
  delete from _hit h where h.has_line_key and not h.line_match
     and exists (select 1 from _hit h2 where h2.order_no = h.order_no and h2.line_match);

  select count(distinct order_no) into v_found from _hit;

  with u as (
    update core.orders o
       set status = h.new_status,
           refund_amount = o.gross_amount,
           cancelled_at = coalesce(o.cancelled_at, h.cancelled_at, now()),
           updated_at = now()
      from _hit h
     where o.id = h.id and h.is_refund and (o.refund_amount = 0 or o.refund_amount is null or o.status <> h.new_status)
    returning 1)
  select count(*) into v_upd from u;
  select count(*) into v_already from _hit h where h.is_refund and h.refund_amount > 0 and h.old_status = h.new_status;

  /* 취소·반품 '요청' 같은 중간 상태는 상태 글자만 갱신 (환불은 안 잡는다 — 완료돼야 환불) */
  with u2 as (
    update core.orders o set status = h.new_status, updated_at = now()
      from _hit h
     where o.id = h.id and not h.is_refund and h.new_status is not null
       and coalesce(o.refund_amount,0) = 0 and o.status <> h.new_status
       and h.new_status ~ '(요청|A/S|교환)'
    returning 1)
  select count(*) into v_status from u2;

  select count(*), jsonb_agg(order_no) filter (where rn <= 5) into v_nf_n, v_nf from (
    select coalesce(s.order_no, s.alt) order_no, row_number() over () rn from _sr s
     where s.is_refund and not exists (select 1 from core.orders o where o.source = 'shoplinker'
              and (o.order_no = s.order_no or (s.alt is not null and o.source_ref = s.alt)))) x;

  insert into raw.upload (source, file_name, uploaded_by, row_count, error_count, note)
  values ('shoplinker_refund', p_file, auth.uid(), v_rows, v_nf_n,
          '취소·환불 대조 · 환불 줄 '||v_ref||' · 주문 찾음 '||v_found||' · 반영 '||v_upd||' · 이미 환불 '||v_already||' · 못 찾음 '||v_nf_n)
  returning id into v_upload;

  if v_upd > 0 then delete from core.dash_cache where true; end if;   /* 대시보드 24시간 캐시 — 환불이 바로 보이게 */

  return jsonb_build_object('upload_id', v_upload, 'rows', v_rows, 'refund_rows', v_ref, 'found', v_found,
                            'updated', v_upd, 'already', v_already, 'status_only', v_status,
                            'notfound', v_nf_n, 'notfound_sample', coalesce(v_nf,'[]'::jsonb));
end $$;
revoke all on function public.fn_sl_refund_apply(jsonb, text) from public, anon;
grant execute on function public.fn_sl_refund_apply(jsonb, text) to authenticated, service_role;

-- 적용 확인(2026-09-21): 9/18 한가위 LMS 실패 6건을 fn_send_log_import(…, '2609_chuseok', 'sms', '2026-09-18') 로 적재 (6/6 매칭).
-- fn_sl_refund_apply 롤백 테스트: 4줄(배송전취소·없는 번호·반품요청(2줄 주문)·자사주문번호) → found 2 · updated 1 · status_only 2 · notfound 1 · dash_cache 비움.

-- v126 (2026-09-21): 문의 관리 별도 홈페이지 문의 카드 제거에 맞춰
--   fn_inquiry_list 폼 라벨 ('quote','견적 문의',1) → ('quote','홈페이지 문의',1)  (prosrc 부분 치환)
--   core.data_source web_inquiry 는 active=true 그대로 (자동 적재 감시), 화면에서 올리기 버튼만 뺐다
