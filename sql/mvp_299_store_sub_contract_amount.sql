-- mvp_299 · 2026-11-17 · 담당자 화면 구독 = 계약 기준 (DB 에 적용됨)
-- "구독의 경우엔 판매 전표가 자동으로 발생하지는 않는데, 프로님들이 전표를 하나 만들고 나중에 삭제하는 방식
--  그러므로 실제는 구독 계약에서만 확인하는 것이 맞는거지" → "응, 바꿔줘"
-- 구독 계약(dps.subscription)이 붙은 DPS 전표(core.orders source dps · option_text '구독 …')는 임시 전표다
-- (AA2P 1,000원 · A4용지 10원 · 0원 등 — 2026-11-17 기준 2,275줄, 그중 품목이 모델과 다른 줄 227).
-- 담당자 화면 구매 합계(spent)에서 그 금액을 뺀다. 줄마다 계약 금액(월 요금 × 개월)은 화면이 subs 로 보인다.
-- 계약이 안 붙은 구독 전표(매장구독 채널 · 실제 금액)는 그대로 센다.
-- DPS 에서 지운 전표는 수집 쪽에서 빠지지 않는다(f_dps_raw_upsert 는 들어온 판매번호만 갱신) — 금액은 이제 안 쓰지만 건수에는 남는다.
do $outer$
declare r record; v_def text; v_n int;
begin
  for r in select * from (values
    ('fn_store_customer_detail', $q$'spent', (select coalesce(sum(o.gross_amount - o.refund_amount),0) from core.orders o where o.buyer_key = c.buyer_key and not coalesce(o.is_test,false)),$q$,
                                 $q$'spent', (select coalesce(sum(o.gross_amount - o.refund_amount),0) from core.orders o where o.buyer_key = c.buyer_key and not coalesce(o.is_test,false) and not (o.source = 'dps' and coalesce(o.option_text,'') like '구독 %')),   /* 구독 계약이 붙은 DPS 전표는 임시 전표 — 금액 제외 (mvp_299) */$q$),
    ('fn_store_customer_search', $q$'spent', (select coalesce(sum(o.gross_amount - o.refund_amount),0) from core.orders o where o.buyer_key = c.buyer_key and not coalesce(o.is_test,false)),$q$,
                                 $q$'spent', (select coalesce(sum(o.gross_amount - o.refund_amount),0) from core.orders o where o.buyer_key = c.buyer_key and not coalesce(o.is_test,false) and not (o.source = 'dps' and coalesce(o.option_text,'') like '구독 %')),   /* mvp_299 */$q$),
    ('fn_store_my_customers', $q$coalesce(sum(o.gross_amount - o.refund_amount),0) spent,$q$,
                              $q$coalesce(sum(o.gross_amount - o.refund_amount) filter (where not (o.source = 'dps' and coalesce(o.option_text,'') like '구독 %')),0) spent,   /* mvp_299 */$q$)
  ) t(fn, a, b) loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname=r.fn;
    v_n := (length(v_def) - length(replace(v_def, r.a, ''))) / length(r.a);
    if v_n <> 1 then raise exception '% 지점 개수 %', r.fn, v_n; end if;
    execute replace(v_def, r.a, r.b);
  end loop;
end $outer$;
