-- mvp_160 · 2026-09-19 · 외부 대시보드 발표용: 고객 셀(신규/재구매) + 24개월 캐시 워밍
-- ① core.f_dash_payload 에 'ccells' 추가 — [일 인덱스, 채널, 구매 고객 수(고객×구매일), 그중 첫 구매 고객 수]
--    신규 = 그 고객(buyer_key)의 첫 구매일(전 채널·전 기간, 취소·환불 제외)이 그날. 단위는 고객×구매일이라 기간 합산이 정확하다.
--    화면은 오픈마켓(안심번호)에는 "식별 불가"로 보인다.
-- ② core.f_dash_warm 에 (이번 달 1일 - 23개월, 오늘) 키 추가 — /dash/ 가 DC_MONTHS=24 로 부르므로(전년 동기 비교) 15분마다 미리 굽는다.
--    24개월 payload: ledger 1.07MB · manual 1.12MB, 빌드 5~12초 (anon 3초 제한이라 캐시가 꼭 있어야 한다).
-- 적용은 prosrc 부분 치환 (지점 개수 검증) — 본문 재작성 아님.
do $outer$
declare v_src text; v_args text; a text; b text; c text; v_cnt int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core' where p.proname='f_dash_payload';
  a := $a$  create temp table if not exists _pm (mi int, ym text) on commit drop;$a$;
  v_cnt := (length(v_src)-length(replace(v_src,a,'')))/length(a); if v_cnt <> 1 then raise exception '_pm 지점 %', v_cnt; end if;
  v_src := replace(v_src, a,
$n$  /* 고객 셀 (2026-09-19): 신규 = 그 고객의 첫 구매일(전 채널·전 기간, 취소·환불 제외)이 그날인 경우. 단위는 고객×구매일 */
  create temp table if not exists _fb (buyer_key text, first_day date) on commit drop;
  truncate _fb;
  insert into _fb
  select o.buyer_key::text, min((o.order_at at time zone 'Asia/Seoul')::date) from core.orders_live o
   where o.buyer_key is not null and coalesce(o.status,'') not in ('취소','환불') group by 1;
  create temp table if not exists _cu (di int, ci int, b int, nb int) on commit drop;
  truncate _cu;
  insert into _cu
  select x.di, x.ci, count(distinct x.bk), count(distinct x.bk) filter (where fb.first_day = x.d)
    from (select distinct (o.order_at at time zone 'Asia/Seoul')::date d, ((o.order_at at time zone 'Asia/Seoul')::date - p_from) di, c.ci, o.buyer_key::text bk
            from core.orders_live o
            join _ch c on c.name = case when o.source = 'rental' then '렌탈' when o.source in ('ecount','ecount_sales') then '통신판매(VMS)'
                                        when o.source = 'store' then case when o.sale_kind = '구독' then '매장구독(시흥)' when o.sale_kind = '직판' then '직판' else '매장(시흥)' end
                                        else core.f_channel_norm(o.channel_name) end
           where o.buyer_key is not null and coalesce(o.status,'') not in ('취소','환불')
             and (o.order_at at time zone 'Asia/Seoul')::date between p_from and p_to) x
    join _fb fb on fb.buyer_key = x.bk
   group by 1, 2;

$n$ || a);
  b := $b$    'ocells', (select coalesce(jsonb_agg(jsonb_build_array(di, ci, n) order by di, ci), '[]'::jsonb) from _oc),$b$;
  v_cnt := (length(v_src)-length(replace(v_src,b,'')))/length(b); if v_cnt <> 1 then raise exception 'ocells 지점 %', v_cnt; end if;
  v_src := replace(v_src, b, b || $m$
    'ccells', (select coalesce(jsonb_agg(jsonb_build_array(di, ci, b, nb) order by di, ci), '[]'::jsonb) from _cu),$m$);
  execute format('create or replace function core.f_dash_payload(%s) returns jsonb language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);

  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core' where p.proname='f_dash_warm';
  c := $c$      ((date_trunc('month', d) - interval '11 months')::date, d),          -- 관리자 대시보드 기본 (최근 12개월)$c$;
  v_cnt := (length(v_src)-length(replace(v_src,c,'')))/length(c); if v_cnt <> 1 then raise exception 'warm 지점 %', v_cnt; end if;
  v_src := replace(v_src, c, c || $w$
      ((date_trunc('month', d) - interval '23 months')::date, d),          -- 외부 대시보드 /dash/ (최근 24개월 · 전년 동기 비교용, 2026-09-19)$w$);
  execute format('create or replace function core.f_dash_warm(%s) returns jsonb language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
