-- mvp_311 · 2026-11-23 · 판매 찾기 범위를 고객 흐름과 맞춘다 (적용 기록)
-- "판매 확인 필요인데 이렇게 뜨는게 이상해" — 최지영 프로 내 고객에는 구매(시흥몰 주문 · 원장 밖 DPS 전표)가 보이는데
-- 판매 확인 필요는 '판매를 못 찾았습니다' · 후보 0건. 판매 찾기가 원장의 dps·store(·ecount) 줄만 봤기 때문.
--
-- ① dps.sale.is_direct — 매장 전표(is_store)가 아니어도 그 판매사원의 판매로 원장에 넣을 전표.
--    core.f_dps_promote_direct() 가 켠다: (a) 기타사항에 '직판' (2026-11-01 이후) 또는
--    (b) 같은 판매사원이 담당인 상담의 고객(고객키 또는 휴대폰 뒤 8자리)이 산 전표(상담일 하루 전(판매 완료로 저장한 상담은 7일 전) ~ 45일 뒤)이고
--        그 고객의 온라인 주문(샵링커·고도몰)이 전표일 30일 전 ~ 2일 뒤에 없을 때 (있으면 온라인 주문을 DPS 에 등록한 전표라 두 번 세게 된다 — f_dps_classify 와 같은 창).
--    core.f_dps_ledger_sync 가 분류 다음에 부르고, (is_store or is_direct) 전표를 원장에 넣는다(직판/직판 · sale_kind 직판).
-- ② core.f_consult_link_sales — 판매 완료로 저장한 상담은 그 고객의 온라인 주문(shoplinker·godo·smartstore)도 잇는다
--    (상담 2일 뒤부터 · DPS·매장 판매가 있으면 그쪽 먼저 · 메모 '온라인 주문 … 에 이어짐'). 자동으로 판매완료가 되는 쪽(상담완료 등)은 전처럼 같은 담당의 DPS 판매만.
-- 원문 백업 core.fn_src_backup tag 'before mvp_311'.

alter table dps.sale add column if not exists is_direct boolean not null default false;

create or replace function core.f_dps_promote_direct() returns integer
language plpgsql security definer set search_path to 'pg_catalog','public' as $f$
declare n int;
begin
  update dps.sale s set is_direct = true, updated_at = now()
   where not s.is_direct and not s.is_store and s.doc_type = '판매' and s.buyer_key is not null and s.amount > 0
     and ( (coalesce(s.etc_note,'') like '%직판%' and s.sale_date >= date '2026-11-01')
        or ( exists (select 1 from crm.consult c
                      where c.deleted_at is null and c.linked_order_id is null and c.handler = s.staff_name
                        and c.result in ('구매완료','진행전','진행중','보류','상담완료')
                        and coalesce(c.inflow_route,'') <> '매장 구매 후'
                        and c.consult_at > now() - interval '400 days'
                        and (c.buyer_key = s.buyer_key
                             or (nullif(right(regexp_replace(coalesce(c.phone,''),'\D','','g'),8),'') = nullif(right(regexp_replace(coalesce(s.buyer_phone,''),'\D','','g'),8),'')
                                 and right(regexp_replace(coalesce(c.phone,''),'\D','','g'),8) !~ '^(\d)\1{7}$'))
                        and s.sale_date between (c.consult_at at time zone 'Asia/Seoul')::date - (case when c.result = '구매완료' then 7 else 1 end)
                                            and (c.consult_at at time zone 'Asia/Seoul')::date + 45)
             and not exists (select 1 from core.orders o where o.buyer_key = s.buyer_key and o.source in ('shoplinker','godo','godo_hist')
                                and (o.order_at at time zone 'Asia/Seoul')::date between s.sale_date - 30 and s.sale_date + 2)
             and not exists (select 1 from dps.godo_key g where g.buyer_key = s.buyer_key and g.ordered_on between s.sale_date - 30 and s.sale_date + 2) ) );
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function core.f_dps_promote_direct() from public, anon, authenticated;

insert into core.fn_src_backup(tag, fn, src) select 'before mvp_311', p.oid::regprocedure::text, pg_get_functiondef(p.oid) from pg_proc p
 where p.pronamespace = 'core'::regnamespace and p.proname in ('f_consult_link_sales','f_dps_ledger_sync');

do $outer$
declare v_new text; v_n int; r text[];
  reps text[][] := array[
    ['v_cls := core.f_dps_classify();', 'v_cls := core.f_dps_classify(); perform core.f_dps_promote_direct();', '1'],
    ['(s.is_store or (coalesce(s.etc_note,'''') like ''%직판%'' and s.sale_date >= date ''2026-11-01''))', '(s.is_store or s.is_direct)', '2'],
    ['s.is_subscription, s.mapping_level', 's.is_subscription, s.mapping_level, s.is_direct', '1'],
    ['coalesce(r.etc_note,'''') like ''%직판%''', 'r.is_direct', '3']];
begin
  select pg_get_functiondef(p.oid) into v_new from pg_proc p where p.proname = 'f_dps_ledger_sync' and p.pronamespace = 'core'::regnamespace;
  foreach r slice 1 in array reps loop
    v_n := (length(v_new) - length(replace(v_new, r[1], ''))) / length(r[1]);
    if v_n <> r[3]::int then raise exception '원장 지점 % : % (기대 %)', left(r[1], 40), v_n, r[3]; end if;
    v_new := replace(v_new, r[1], r[2]);
  end loop;
  execute v_new;
end $outer$;

do $outer$
declare v_new text; v_n int; r text[];
  reps text[][] := array[
    ['where o.source in (''dps'',''store'',''ecount'') and not coalesce(o.is_test,false) and o.net_amount > 0',
     'where (o.source in (''dps'',''store'',''ecount'') or (o.source in (''shoplinker'',''godo'',''smartstore'') and o.buyer_key in (select c2.buyer_key from crm.consult c2 where c2.result = ''구매완료'' and c2.linked_order_id is null and c2.deleted_at is null and c2.buyer_key is not null))) and not coalesce(o.is_test,false) and o.net_amount > 0', '1'],
    ['and (o.source <> ''ecount'' or k.outx)',
     'and (o.source <> ''ecount'' or k.outx) and (o.source in (''dps'',''store'',''ecount'') or (k.result = ''구매완료'' and o.buyer_key = k.buyer_key and k.consult_at < now() - interval ''2 days''))', '1'],
    ['order by k.id, abs(extract(epoch from o.order_at - k.consult_at)), o.id', 'order by k.id, (o.source not in (''dps'',''store'',''ecount'')), abs(extract(epoch from o.order_at - k.consult_at)), o.id', '1'],
    ['else ''판매 입력 '' end', 'when m1.src = ''store'' then ''판매 입력 '' else ''온라인 주문 '' end', '1']];
begin
  select pg_get_functiondef('core.f_consult_link_sales(integer)'::regprocedure) into v_new;
  foreach r slice 1 in array reps loop
    v_n := (length(v_new) - length(replace(v_new, r[1], ''))) / length(r[1]);
    if v_n <> r[3]::int then raise exception '잇기 지점 % : % (기대 %)', left(r[1], 40), v_n, r[3]; end if;
    v_new := replace(v_new, r[1], r[2]);
  end loop;
  execute v_new;
end $outer$;
