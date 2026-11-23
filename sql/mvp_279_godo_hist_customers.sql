-- mvp_279 · 2026-11-10 · 고도몰 과거 주문 구매자를 고객 표(crm.customer)에 넣는다
-- (적용됨 — 이 파일은 기록용)
--
-- 왜: core.f_godo_hist_apply(mvp_180, 2026-09-22 한 번 실행)가 core.orders 에만 넣고
--     crm.customer 를 만들지 않아, 고도몰 과거 주문(2021-01 ~ 2025-06-23) 구매자 17,228명 중
--     13,214명이 고객 표에 없었다 → 고객 목록·고객 흐름·발송 대상 추출(제품 재구매)에 안 나옴.
--     다른 적재 경로(샵링커·이카운트·DPS·렌탈·매장)는 빠진 고객 0.
--     구매 요약(crm.customer_roll)은 원장 기준이라 이미 들어 있었다(13,214 전부).
--
-- 무엇: ① 지금 있는 godo_hist 구매자를 다른 적재 경로(core.f_orders_bulk_upsert)와 같은 병합 규칙으로 upsert
--       (이름 = 마지막 주문의 주문자 이름 · 번호 = 원본의 주문자 핸드폰 번호(숫자만) · first/last_seen = 주문일 ·
--        source_channels = 몰 이름(P몰·S몰·AT몰·시흥몰) · 수신 동의는 건드리지 않음 = 새 고객은 false)
--       ② core.f_godo_hist_apply 가 다시 돌 때도 같은 upsert 를 하도록(주문 insert 바로 뒤)
--
-- 결과: 새 고객 13,214명(번호 없음 0 · 수신 동의 0) · 기존 4,014명은 first/last_seen·몰 채널만 합쳐짐
--       crm.customer 73,416 → 86,630
--       HIN 필터(HAF-HIN) 제품 재구매 추출(오픈마켓·실패 번호·수신거부 제외) 758 → 2,822 · 수신동의 285 그대로
--       ※ 새로 든 사람은 수신 동의가 없고 마지막 구매가 6개월을 넘어 광고 문자 대상이 아니다.
--         제품 재구매 기준은 광고 여부를 거르지 않으므로 광고 발송에 그대로 쓰면 안 된다.
--
-- 되돌리기: 백업 표 둘(RLS 켬 · anon/authenticated 권한 없음)
--   core.customer_godo_hist_new_20261110  — 이번에 새로 만든 고객 buyer_key 13,214
--   core.customer_godo_hist_bak_20261110  — 이미 있던 4,014명의 바뀌기 전 줄
--   새 고객 지우기(SQL 편집기):
--     delete from crm.customer c using core.customer_godo_hist_new_20261110 n where c.buyer_key = n.buyer_key;
--   기존 고객 되돌리기: bak 표의 first_seen_at·last_seen_at·name·phone·source_channels 로 update.
--
-- 시험: f_godo_hist_apply(false) 를 롤백 블록에서 돌려 새 부분이 고객 줄을 만드는 것 확인.
--   ⚠ 그 시험에서 다시 적재하면 godo_hist 주문이 21,295 → 24,478 줄이 됐다(raw.godo_order_hist 가 9/22 이후 늘었거나
--     샵링커 매칭이 바뀐 탓으로 보임 · 확인 안 함). 다시 돌리기 전에 dry 결과(p_dry=true)부터 볼 것.

-- ① 백업
create table core.customer_godo_hist_bak_20261110 as
  select c.* from crm.customer c
   where c.buyer_key in (select distinct o.buyer_key from core.orders o
                          where o.source='godo_hist' and o.buyer_key is not null and not coalesce(o.is_test,false));
create table core.customer_godo_hist_new_20261110 (buyer_key character(16) primary key, inserted_at timestamptz default now());
alter table core.customer_godo_hist_bak_20261110 enable row level security;
alter table core.customer_godo_hist_new_20261110 enable row level security;
revoke all on core.customer_godo_hist_bak_20261110, core.customer_godo_hist_new_20261110 from anon, authenticated;

-- ② 지금 있는 구매자 upsert
with src as (
  select o.buyer_key k,
         (array_agg(o.buyer_name_raw order by o.order_at desc) filter (where nullif(btrim(o.buyer_name_raw),'') is not null))[1] n,
         max(nullif(regexp_replace(coalesce(o.raw_payload->>'주문자 핸드폰 번호', o.raw_payload->>'주문자휴대폰',''),'\D','','g'),'')) p,
         min(o.order_at) t0, max(o.order_at) t1,
         array_agg(distinct o.channel_name) ch
    from core.orders o
   where o.source='godo_hist' and o.buyer_key is not null and not coalesce(o.is_test,false)
   group by o.buyer_key),
up as (
  insert into crm.customer (buyer_key, name, phone, account_type, first_seen_at, last_seen_at, source_channels)
  select k, coalesce(n,'(미상)'), p, 'personal', t0, t1, ch from src
  on conflict (buyer_key) do update set
    last_seen_at  = greatest(crm.customer.last_seen_at, excluded.last_seen_at),
    first_seen_at = least(crm.customer.first_seen_at, excluded.first_seen_at),
    name    = case when crm.customer.name = '(미상)' then excluded.name else crm.customer.name end,
    phone   = coalesce(crm.customer.phone, excluded.phone),
    source_channels = (select array_agg(distinct x) from unnest(coalesce(crm.customer.source_channels,'{}') || excluded.source_channels) x)
  returning buyer_key, (xmax = 0) is_new)
insert into core.customer_godo_hist_new_20261110 (buyer_key) select buyer_key from up where is_new;

-- ③ 적재 함수 부분 치환 (서버 원본을 읽어 한 곳만 · 본문을 다시 쓰지 않음)
do $outer$
declare v_def text; v_anchor text := 'get diagnostics v_ins = row_count;'; v_n int;
  v_add text := $add$get diagnostics v_ins = row_count;
  /* 고도몰 과거 주문 구매자도 고객 표에 (mvp_279 · 2026-11-10) — 다른 적재 경로와 같은 병합 규칙 · 수신 동의는 건드리지 않는다 */
  insert into crm.customer (buyer_key, name, phone, account_type, first_seen_at, last_seen_at, source_channels)
  select z.k, coalesce((array_agg(z.n order by z.t desc) filter (where z.n is not null))[1], '(미상)'), max(z.p), 'personal', min(z.t), max(z.t), array_agg(distinct z.m)
    from (select core.f_buyer_key(g.bname, g.bphone) k, g.bname n,
                 nullif(regexp_replace(coalesce(g.bphone,''), '\D', '', 'g'), '') p, g.order_at t, g.mall m
            from _gh g where g.fate = 'load') z
   where z.k is not null
   group by z.k
  on conflict (buyer_key) do update set
    last_seen_at  = greatest(crm.customer.last_seen_at, excluded.last_seen_at),
    first_seen_at = least(crm.customer.first_seen_at, excluded.first_seen_at),
    name    = case when crm.customer.name = '(미상)' then excluded.name else crm.customer.name end,
    phone   = coalesce(crm.customer.phone, excluded.phone),
    source_channels = (select array_agg(distinct x) from unnest(coalesce(crm.customer.source_channels, '{}') || excluded.source_channels) x);$add$;
begin
  v_def := pg_get_functiondef('core.f_godo_hist_apply'::regproc);
  v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  if v_n <> 1 then raise exception '지점 % 개', v_n; end if;
  if position('mvp_279' in v_def) > 0 then raise exception '이미 적용됨'; end if;
  execute replace(v_def, v_anchor, v_add);
end $outer$;

-- 캐시: 고객 통계(customer_stats_cache)·발송 대상 선택지(crm_options)는 cron rpc-warm(5분)이 다시 굽는다. 지우지 않았다.
