-- mvp_260 · 2026-11-02 · 렌탈(임대) 계약 명부 보기 · CRM 문자 발송 대상
-- 관리자 › 발송 대상 추출 › [렌탈 고객] 카드가 명부를 계약 줄 그대로 보이고,
-- 문자 보내기 ④ [렌탈 고객 불러오기] 가 같은 조건으로 휴대폰 번호 하나 = 한 사람(여러 업체·기기는 묶음)을 실번호로 받는다.
-- 규칙(다른 CRM 발송과 같음): 휴대폰만 · 문자 수신거부(crm.sms_optout 뒤 8자리) 항상 제외 · 이미 보낸 사람 제외(선택) ·
--   광고 문자는 수신 동의 또는 6개월 안 거래(최근 6개월 렌탈 청구 · 계약 기간이 6개월 안까지 이어짐)인 사람만 (p_ad_only)
-- 추출·내보내기·불러오기는 crm.access_log ('rental_list' · 'rental_export' · ':unmask')

create or replace function public.fn_rental_targets(
  p_reason text, p_state text default 'active', p_q text default null, p_due_days integer default 90,
  p_billed6 boolean default false, p_ad_only boolean default false, p_no_send_days integer default null,
  p_send boolean default false, p_limit integer default 50, p_offset integer default 0,
  p_unmask boolean default false, p_export boolean default false)
returns jsonb language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare
  v_role text := core.f_role();
  v_un   boolean;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_st   text := lower(coalesce(nullif(btrim(p_state),''),'active'));
  v_q    text := nullif(btrim(coalesce(p_q,'')),'');
  v_dig  text := nullif(regexp_replace(coalesce(p_q,''),'\D','','g'),'');
  v_lim  int;
  v_out  jsonb;
begin
  if not core.f_is_service() and v_role not in ('admin','staff') then
    raise exception '권한이 없습니다' using errcode='42501';
  end if;
  if coalesce(btrim(p_reason),'') = '' then raise exception '캠페인명(쓰는 이유)을 적어 주세요' using errcode='22023'; end if;
  if v_st not in ('active','due','over','closed','all') then raise exception '상태 값이 틀렸습니다' using errcode='22023'; end if;
  v_un  := (p_unmask or p_send) and (v_role = 'admin' or core.f_is_service());
  v_lim := least(greatest(coalesce(p_limit,50),1), case when p_export or p_send then 100000 else 200 end);

  with r as (
    select c.*, regexp_replace(coalesce(c.phone,''),'\D','','g') ph,
           (c.monthly_fee is not null) has_fee,
           case when c.closed then 'closed'
                when c.cur_end is null then 'nodate'
                when c.cur_end < v_today then 'over'
                when c.cur_end <= v_today + greatest(coalesce(p_due_days,90),1) then 'due'
                else 'active' end st,
           cu.consent_marketing consent,
           (select max(o.order_at) from core.orders o where o.source='rental' and o.buyer_key = c.buyer_key) billed_at
      from crm.rental_contract c
      left join crm.customer cu on cu.buyer_key = c.buyer_key
  ), r2 as (
    select r.*, (ph ~ '^01[016789][0-9]{7,8}$') mob,
           (ph <> '' and right(ph,8) in (select so.d8 from crm.sms_optout so where so.released_at is null)) optout,
           (billed_at >= now() - interval '6 months') billed6,
           (not closed and cur_end is not null and cur_end >= v_today - 180) term6,
           (select max(l.sent_at) from crm.send_log l where l.buyer_key = r.buyer_key) last_sent
      from r
  ), r3 as (
    select r2.*, (coalesce(consent,false) or coalesce(billed6,false) or term6) ad_ok
      from r2
     where (v_st = 'all'
            or (v_st = 'active' and st <> 'closed')
            or (v_st = 'due' and st = 'due')
            or (v_st = 'over' and st = 'over')
            or (v_st = 'closed' and st = 'closed'))
       and (v_q is null or company ilike '%'||v_q||'%' or coalesce(device,'') ilike '%'||v_q||'%'
            or coalesce(address,'') ilike '%'||v_q||'%' or coalesce(code,'') ilike '%'||v_q||'%' or coalesce(biz_no,'') ilike '%'||v_q||'%'
            or (v_dig is not null and length(v_dig) >= 3 and ph like '%'||v_dig||'%'))
       and (not p_billed6 or coalesce(billed6,false))
       and (not p_ad_only or (coalesce(consent,false) or coalesce(billed6,false) or term6))
       and (p_no_send_days is null or last_sent is null or last_sent < now() - (p_no_send_days||' days')::interval)
  ), sendable as (   /* 문자로 갈 수 있는 줄: 휴대폰 · 수신거부 아님 */
    select * from r3 where mob and not optout
  ), grp as (       /* 휴대폰 번호 하나 = 한 사람 */
    select ph, (array_agg(buyer_key order by buyer_key nulls last))[1] bkey,
           string_agg(distinct company, ' · ') companies, count(*) n_rows,
           string_agg(distinct nullif(device,''), ' · ') devices, sum(monthly_fee) fee,
           min(cur_end) filter (where not closed) end_min, bool_or(ad_ok) ad_ok, bool_or(coalesce(consent,false)) consent,
           max(billed_at) billed_at, max(last_sent) last_sent
      from sendable group by ph
  ), summ as (
    select jsonb_build_object(
      'rows', (select count(*) from r3), 'companies', (select count(distinct coalesce(nullif(code,''),company)) from r3),
      'active', (select count(*) from r3 where st <> 'closed'), 'closed', (select count(*) from r3 where st = 'closed'),
      'due', (select count(*) from r3 where st = 'due'), 'over', (select count(*) from r3 where st = 'over'), 'nodate', (select count(*) from r3 where st = 'nodate'),
      'fee_sum', (select coalesce(sum(monthly_fee) filter (where st <> 'closed'),0) from r3),
      'mobiles', (select count(*) from grp), 'mobiles_ad', (select count(*) filter (where ad_ok) from grp),
      'landline_rows', (select count(*) from r3 where ph <> '' and not mob), 'nophone_rows', (select count(*) from r3 where ph = ''),
      'optout_rows', (select count(*) from r3 where optout), 'consent', (select count(*) filter (where consent) from grp),
      'billed6', (select count(distinct ph) from sendable where billed6),
      'roster_at', (select max(loaded_at) from crm.rental_contract),
      'all_rows', (select count(*) from crm.rental_contract)) s
  )
  select jsonb_build_object('ok', true, 'state', v_st, 'unmask', v_un, 'summary', summ.s,
    'total', case when p_send then (select count(*) from grp) else (select count(*) from r3) end,
    'rows', case when p_send then
      (select coalesce(jsonb_agg(jsonb_build_object(
          'phone', g.ph, 'name', left(g.companies, 40), 'key', g.bkey, 'ad_ok', g.ad_ok,
          'vars', jsonb_strip_nulls(jsonb_build_object('상호', left(g.companies,40), '임대기기', left(g.devices,40),
                     '월임대료', case when g.fee is not null then to_char(g.fee,'FM999,999,999') end,
                     '계약종료일', to_char(g.end_min,'YYYY.MM.DD')))) order by g.companies), '[]'::jsonb)
         from (select * from grp order by companies limit v_lim offset greatest(coalesce(p_offset,0),0)) g)
    else
      (select coalesce(jsonb_agg(jsonb_build_object(
          'id', x.id, 'code', x.code, 'company', x.company, 'device', x.device, 'fee', x.monthly_fee,
          'start', coalesce(to_char(x.cur_start,'YYYY-MM-DD'), x.start_raw), 'end', coalesce(to_char(x.cur_end,'YYYY-MM-DD'), x.end_raw),
          'days', case when x.cur_end is not null then x.cur_end - v_today end, 'st', x.st, 'note', left(x.note, 80),
          'region', nullif(array_to_string((regexp_split_to_array(btrim(coalesce(x.address,'')), '\s+'))[1:2], ' '), ''),
          'phone', case when x.ph = '' then null when v_un then x.ph
                        when length(x.ph) >= 9 then left(x.ph,3)||'-****-'||right(x.ph,4) else '****' end,
          'mob', x.mob, 'optout', x.optout, 'consent', coalesce(x.consent,false), 'ad_ok', x.ad_ok,
          'billed_at', to_char(x.billed_at at time zone 'Asia/Seoul','YYYY-MM-DD'), 'linked', x.buyer_key is not null,
          'last_sent', to_char(x.last_sent at time zone 'Asia/Seoul','YYYY-MM-DD')) order by x.ord, x.company, x.row_no), '[]'::jsonb)
         from (select r3.*, case st when 'due' then 0 when 'over' then 1 when 'active' then 2 when 'nodate' then 3 else 4 end ord
                 from r3 order by ord, company, row_no limit v_lim offset greatest(coalesce(p_offset,0),0)) x)
    end)
    into v_out from summ;

  if coalesce(p_offset,0) = 0 or p_export or p_send then
    insert into crm.access_log (actor, actor_email, action, row_count, reason)
    values (auth.uid(), (select p.email from public.profiles p where p.id = auth.uid()),
            case when p_send then 'rental_send' when p_export then 'rental_export' else 'rental_list' end || case when v_un then ':unmask' else '' end,
            (v_out->>'total')::int, p_reason);
  end if;
  return v_out;
end $f$;

revoke all on function public.fn_rental_targets(text,text,text,integer,boolean,boolean,integer,boolean,integer,integer,boolean,boolean) from public, anon;
grant execute on function public.fn_rental_targets(text,text,text,integer,boolean,boolean,integer,boolean,integer,integer,boolean,boolean) to authenticated, service_role;
