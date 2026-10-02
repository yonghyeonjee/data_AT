-- mvp_184 · 2026-10-03 · 대시보드 캐시를 지우지 않는다 — '오래됨' 표시 + 있는 캐시를 바로 준다
-- "여기가 답답해 더 빠르게 안돼?" (관리자 매출 대시보드, 폰, 01:37 KST)
--
-- 원인: core.app_setting 의 statement 트리거(dash_cache_bust)가 대시보드 캐시를 통째로 지웠다.
--   샵링커 수집이 돌 때마다 fn_sl_log 가 app_setting('sl_last_sync') 를 쓰므로 하루 5번 캐시가 0 이 됐다
--   (10-02 16:36 UTC 수집 → 0행 → 16:45 워머가 1분 37초 걸려 다시 채움).
--   그 틈에 연 사람은 집계를 직접 떠안는다: 12개월 원장 7.9~13초 > authenticated 8초 → 57014 →
--   화면 rpc() 가 두 번 더 재시도 → '불러오는 중' 이 20초 넘게 가다 실패.
--   /dash/(anon 3초)는 그 틈에 아예 못 열렸다. [캐시 지우고 새로고침](fn_dash_refresh)도 8초 안에 12벌을
--   다시 굽게 돼 있어 늘 시간 초과 → 같은 트랜잭션의 delete 도 롤백 → 아무 일도 안 하고 오류만 났다.
--   fn_sl_refund_apply · f_godo_hist_apply 도 같은 delete-all 을 했다.
--
-- 바꾼 것
--   ① core.dash_cache_state (한 줄) — dirty_at(이 시각 전에 구운 캐시는 오래됨) · rebuild_req(지금 다시 구워 달라)
--   ② core.f_dash_src_at() = greatest(orders·store_daily·channel_daily 의 max(updated_at), dirty_at)
--   ③ core.f_dash_payload_get(from,to,mode) — 캐시가 24시간 안이면 나이와 상관없이 바로 준다
--      (+ cached:true · stale:(built_at < src) · built_at). 없거나 24시간 넘었으면 예전처럼 굽는다.
--      fn_dash_payload · fn_dash_payload_pub 가 이걸 쓴다.
--   ④ 캐시를 지우던 네 곳 → dirty 표시만: 트리거 · fn_sl_refund_apply · f_godo_hist_apply · fn_dash_refresh
--   ⑤ fn_dash_refresh 는 굽지 않고 '다시 굽기 예약'(rebuild_req) 만 한다 → 1분마다 도는 dash-warm-req 가 처리
--   ⑥ f_dash_warm: 동시 실행 막기(advisory lock) · built_at 만 보고 판단(전엔 키마다 1MB payload 를 꺼내
--      jsonb_set 하느라 할 일 없는 회차도 5초) · 원장(ledger) 먼저 · 3일 지난 키 정리 · 예약 처리 표시
--
-- 결과: 수집 직후에도 바로 열린다(직전 집계 · '새 자료 반영 중' 표시). 새 자료는 다음 워머(최대 15분,
--       버튼을 누르면 1분 안에 시작)가 굽는다.

-- ① 상태 한 줄
create table if not exists core.dash_cache_state(
  id boolean primary key default true check (id),
  dirty_at timestamptz not null default now(),
  rebuild_req boolean not null default false,
  req_at timestamptz
);
alter table core.dash_cache_state enable row level security;
revoke all on core.dash_cache_state from public, anon, authenticated;
insert into core.dash_cache_state(id, dirty_at) values (true, 'epoch') on conflict do nothing;   -- 지금 캐시를 괜히 오래됨으로 만들지 않게

-- ② 원천이 마지막으로 바뀐 시각
create or replace function core.f_dash_src_at() returns timestamptz
language sql stable set search_path to 'pg_catalog','public' as $f$
  select greatest(
    coalesce((select max(updated_at) from core.orders), 'epoch'::timestamptz),
    coalesce((select max(updated_at) from core.store_daily), 'epoch'::timestamptz),
    coalesce((select max(updated_at) from core.channel_daily), 'epoch'::timestamptz),
    coalesce((select dirty_at from core.dash_cache_state where id), 'epoch'::timestamptz))
$f$;
revoke execute on function core.f_dash_src_at() from public;

create or replace function core.f_dash_mark_dirty(p_rebuild boolean default false) returns void
language sql volatile set search_path to 'pg_catalog','public' as $f$
  insert into core.dash_cache_state(id, dirty_at, rebuild_req, req_at)
  values (true, now(), p_rebuild, case when p_rebuild then now() end)
  on conflict (id) do update
     set dirty_at = now(),
         rebuild_req = core.dash_cache_state.rebuild_req or excluded.rebuild_req,
         req_at = coalesce(excluded.req_at, core.dash_cache_state.req_at);
$f$;
revoke execute on function core.f_dash_mark_dirty(boolean) from public;

-- ③ 있는 캐시를 바로 준다
create or replace function core.f_dash_payload_get(p_from date, p_to date, p_mode text default 'manual')
returns jsonb language plpgsql volatile set search_path to 'pg_catalog','public' as $f$
declare v_key text; v_out jsonb; v_at timestamptz;
begin
  v_key := p_from::text || '|' || p_to::text || '|' || coalesce(nullif(p_mode,''), 'manual');
  select c.payload, c.built_at into v_out, v_at from core.dash_cache c where c.cache_key = v_key;
  if v_out is not null and v_at > now() - interval '24 hours' then
    return v_out || jsonb_build_object('cached', true, 'stale', v_at < core.f_dash_src_at(), 'built_at', v_at);
  end if;
  return core.f_dash_payload_cached(p_from, p_to, p_mode, interval '24 hours')
         || jsonb_build_object('stale', false, 'built_at', now());
end $f$;
revoke execute on function core.f_dash_payload_get(date, date, text) from public;

-- ③ 화면 RPC 두 개가 get 을 쓰게 (부분 치환 · 지점 수 검증)
create or replace function pg_temp.patch(p_fn text, p_pat text, p_repl text, p_min int, p_max int)
returns int language plpgsql as $p$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_fn::regprocedure) into v_def;
  select count(*) into v_n from regexp_matches(v_def, p_pat, 'g');
  if v_n < p_min or v_n > p_max then raise exception '% : 지점 % 개 (기대 %~%)', p_fn, v_n, p_min, p_max; end if;
  execute regexp_replace(v_def, p_pat, p_repl, 'g');
  return v_n;
end $p$;

select pg_temp.patch('public.fn_dash_payload(date,date,text)',
  $r$core\.f_dash_payload_cached\(p_from, p_to, p_mode, interval '24 hours'\)$r$,
  $r$core.f_dash_payload_get(p_from, p_to, p_mode)$r$, 1, 1);
select pg_temp.patch('public.fn_dash_payload_pub(text,date,date,text)',
  $r$core\.f_dash_payload_cached\($r$, $r$core.f_dash_payload_get($r$, 1, 1);

-- ④ 지우던 곳 → 오래됨 표시
select pg_temp.patch('core.trg_dash_cache_bust()',
  $r$delete from core\.dash_cache where true;$r$,
  $r$update core.dash_cache_state set dirty_at = now() where id;$r$, 1, 1);
select pg_temp.patch('public.fn_sl_refund_apply(jsonb,text)',
  $r$delete from core\.dash_cache where true;$r$,
  $r$perform core.f_dash_mark_dirty(false);$r$, 1, 1);
select pg_temp.patch('core.f_godo_hist_apply(boolean,boolean,uuid)',
  $r$delete from core\.dash_cache where true;$r$,
  $r$perform core.f_dash_mark_dirty(false);$r$, 1, 1);

-- ⑤ [캐시 지우고 새로고침] = 다시 굽기 예약 (8초 안에 12벌을 굽던 판은 늘 시간 초과였다)
create or replace function public.fn_dash_refresh(p_months integer default 12)
 returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $f$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  perform core.f_dash_mark_dirty(true);
  return jsonb_build_object('ok', true, 'queued', true, 'built', 0, 'ms', 0,
                            'note', '다시 집계를 예약했습니다 — 1~3분 안에 반영됩니다');
end $f$;

-- ⑥ 워머
select pg_temp.patch('core.f_dash_warm()',
  $r$begin\s+select greatest\(.*?\) into v_src;$r$,
  $r$begin
  if not pg_try_advisory_xact_lock(7212001) then return jsonb_build_object('ok', true, 'skipped', 'busy'); end if;
  v_src := core.f_dash_src_at();$r$, 1, 1);
select pg_temp.patch('core.f_dash_warm()',
  $r$foreach m in array array\['manual','ledger'\] loop\s+begin perform core\.f_dash_payload_cached\(r\.d_from, r\.d_to, m, v_ttl\); n := n \+ 1;$r$,
  $r$foreach m in array array['ledger','manual'] loop
      begin
        if coalesce((select c.built_at from core.dash_cache c where c.cache_key = r.d_from::text||'|'||r.d_to::text||'|'||m),
                    '-infinity'::timestamptz) <= now() - v_ttl then
          perform core.f_dash_payload_cached(r.d_from, r.d_to, m, interval '0'); n := n + 1;
        end if;$r$, 1, 1);
select pg_temp.patch('core.f_dash_warm()',
  $r$return jsonb_build_object\('ok', true, 'built', n,$r$,
  $r$delete from core.dash_cache
   where cache_key ~ '^[0-9-]{10}[|][0-9-]{10}[|]' and split_part(cache_key, '|', 2)::date < d - 3;
  update core.dash_cache_state set rebuild_req = false where id and rebuild_req and (req_at is null or req_at <= t0);
  return jsonb_build_object('ok', true, 'built', n,$r$, 1, 1);

-- ⑤ 예약 처리: 1분마다, 예약이 있을 때만 워머를 돌린다
select cron.schedule('dash-warm-req', '* * * * *',
  $c$select core.f_dash_warm() where exists (select 1 from core.dash_cache_state where id and rebuild_req)$c$);

-- ⑦ 화면이 '새 자료가 다 구워졌나' 를 가볍게 묻는 RPC (payload 700KB 를 다시 받지 않고 built_at 만)
create or replace function public.fn_dash_status(p_from date, p_to date, p_mode text default 'ledger')
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $f$
declare v_at timestamptz; v_src timestamptz; v_req boolean;
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  select c.built_at into v_at from core.dash_cache c
   where c.cache_key = p_from::text || '|' || p_to::text || '|' || coalesce(nullif(p_mode,''), 'manual');
  v_src := core.f_dash_src_at();
  select s.rebuild_req into v_req from core.dash_cache_state s where s.id;
  return jsonb_build_object('built_at', v_at, 'src_at', v_src, 'stale', v_at is null or v_at < v_src,
                            'rebuild_req', coalesce(v_req, false), 'now', now());
end $f$;
revoke execute on function public.fn_dash_status(date, date, text) from public, anon;
grant execute on function public.fn_dash_status(date, date, text) to authenticated, service_role;

-- 확인 (2026-10-03, 롤백 블록)
--   관리자 fn_dash_payload 85ms · cached · stale false → app_setting 을 건드려도 캐시 16→16행 · 25ms · stale true
--   fn_dash_refresh 1ms (queued) → 16:51 dash-warm-req 가 집어 1분 38초에 16벌 재구축 · 예약 해제
--   할 일 없는 워머 2.9초(그중 대부분 f_sl_pending) · 예약 없는 1분 잡 3~27ms · fn_dash_status 48ms · anon 42501
