-- mvp_195 · 문자 수신거부 목록 업로드 · 발송 대상 카테고리 조건 줄 표시 · 내보내기 상한 (2026-10-08 · v181)
-- "admin에 새로 문자 수신거부한 목록도 업로드 해야해" / "이 고객은 모바일 웨어러블로 구분되는데?" / "6천명으로 나오는데, 다운로드하면 5천명만 나와"
-- 적용 기록용 — DB 에는 이미 반영돼 있다.
-- 본문에 temp table 구문(create temp table … on commit …)이 있는 함수는 MCP execute_sql 로 보낼 수 없어(60초 끊김)
-- 서버에 저장된 본문을 읽어 replace 로 패치했다(③·⑤·⑥ 의 do 블록을 그대로 적어 둔다). 지점 개수가 1이 아니면 전부 롤백.

-- ───────── ① 표 ─────────
create table crm.sms_optout (
  id bigserial primary key,
  d8 text not null unique,                      -- 휴대폰 뒤 8자리 — 고객 마스터와 맞추는 키 (이름이 달라도 같은 번호면 같은 사람)
  phone text not null,                          -- 숫자만
  name text,
  opted_at timestamptz not null default now(),  -- 수신거부일 (줄 → 화면에서 고른 날짜 → 지금)
  source text,                                  -- 센드온 080 · 고객 요청 · 상담 중 거부 · 기타
  note text,
  buyer_key char(16),                           -- 매칭 고객 대표 키 (여럿이면 가장 작은 것)
  matched int not null default 0,               -- 뒤 8자리가 같은 고객 수 (0 = 마스터에 없음 — 그래도 남겨 앞으로 들어오는 고객을 거른다)
  upload_id bigint,                             -- 처음 들어온 업로드
  last_upload_id bigint,                        -- 마지막으로 보낸 업로드
  released_at timestamptz,                      -- 되돌리기로 해제된 때 (null = 살아 있음 · 다시 올라오면 null 로)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table crm.sms_optout enable row level security;            -- 정책 없음 · security definer 함수로만 읽고 쓴다

create table crm.sms_optout_touch (                               -- 업로드가 끈 수신동의의 이전 값 (되돌리기용)
  id bigserial primary key,
  upload_id bigint not null,
  customer_id bigint not null,
  buyer_key char(16),
  d8 text,
  prev_consent boolean,
  prev_source text,
  prev_updated_at timestamptz,
  created_at timestamptz not null default now()
);
create index ix_sms_optout_touch_up on crm.sms_optout_touch (upload_id);
alter table crm.sms_optout_touch enable row level security;

-- ───────── ② 데이터 소스 카드 ─────────
insert into core.data_source (key, label, owner, feed_mode, alert, expect_days, sort_no, active, how, auto_plan) values
 ('sms_optout', '문자 수신거부 목록', '온라인사업부', 'manual', false, 365, 68, true,
  '센드온 080 수신거부 목록(또는 고객 요청)을 파일 올리기·붙여넣기 — 휴대폰 뒤 8자리로 고객 마스터와 맞춰 수신동의를 끄고, 마스터에 없는 번호도 목록에 남아 [발송 대상 추출]·미입금·후속 관리에서 항상 빠집니다',
  '센드온 API 가 붙으면 080 수신거부 목록을 자동으로 받는다');
-- core.f_source_last:        when 'sms_optout' then (select max(uploaded_at) from raw.upload where source='sms_optout')
-- core.f_data_status_build:  stat CTE 에 한 줄 — select 'sms_optout', count(*), min(opted_at at time zone 'Asia/Seoul')::date,
--                            max(coalesce(opted_at, created_at) at time zone 'Asia/Seoul')::date,
--                            count(*) filter (where created_at > now() - interval '30 days') from crm.sms_optout where released_at is null

-- ───────── ③ 적재 함수 (admin · staff · uploader) ─────────
CREATE OR REPLACE FUNCTION public.fn_sms_optout_import(p_rows jsonb, p_file text DEFAULT NULL::text, p_source text DEFAULT NULL::text, p_opted_at date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_up bigint; v_rows int := 0; v_new int := 0; v_dup int := 0; v_matched int := 0; v_off int := 0; v_unmatched int := 0; v_sample jsonb;
        v_src text := coalesce(nullif(btrim(coalesce(p_source,'')),''), '센드온 080');
begin
  if not core.f_is_service() and core.f_role() not in ('admin','staff','uploader') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then return jsonb_build_object('rows',0,'new',0,'dup',0,'matched',0,'off',0,'unmatched',0); end if;
  insert into raw.upload (source, file_name, uploaded_by, row_count, note) values ('sms_optout', p_file, auth.uid(), 0, v_src) returning id into v_up;

  /* ① 번호 목록 — 같은 번호(뒤 8자리)는 한 줄. 날짜는 줄 → 화면에서 고른 날짜 → 지금 */
  with src as (
    select distinct on (d8) d8, phone, name, opted_at, note from (
      select right(regexp_replace(coalesce(r->>'phone',''), '\D', '', 'g'), 8) d8,
             regexp_replace(coalesce(r->>'phone',''), '\D', '', 'g') phone,
             nullif(btrim(coalesce(r->>'name','')),'') name,
             coalesce(case when coalesce(r->>'opted_at','') ~ '(Z|[+-][0-9]{2}:?[0-9]{2})$' then core.f_ts(r->>'opted_at')
                           else nullif(btrim(coalesce(r->>'opted_at','')),'')::timestamp at time zone 'Asia/Seoul' end,
                      case when p_opted_at is not null then p_opted_at::timestamp at time zone 'Asia/Seoul' end, now()) opted_at,
             nullif(left(btrim(coalesce(r->>'note','')), 200), '') note
        from jsonb_array_elements(p_rows) r) x
     where length(d8) = 8 and length(phone) >= 10
     order by d8, opted_at desc),
  ins as (
    insert into crm.sms_optout (d8, phone, name, opted_at, source, note, upload_id, last_upload_id)
    select d8, phone, name, opted_at, v_src, note, v_up, v_up from src
    on conflict (d8) do update set opted_at = greatest(crm.sms_optout.opted_at, excluded.opted_at), name = coalesce(excluded.name, crm.sms_optout.name),
      note = coalesce(excluded.note, crm.sms_optout.note), source = excluded.source, last_upload_id = excluded.last_upload_id,
      released_at = null, updated_at = now()
    returning (xmax = 0) inserted)
  select count(*), count(*) filter (where inserted) into v_rows, v_new from ins;
  v_dup := v_rows - v_new;

  /* ② 고객 마스터 — 뒤 8자리가 같은 고객 전부 수신동의 끔. 이전 값은 touch 에 남겨 되돌릴 수 있게 */
  with src as (
    select distinct right(regexp_replace(coalesce(r->>'phone',''), '\D', '', 'g'), 8) d8 from jsonb_array_elements(p_rows) r
     where length(regexp_replace(coalesce(r->>'phone',''), '\D', '', 'g')) >= 10),
  hit as (
    select c.id, c.buyer_key, c.consent_marketing, c.consent_source, c.consent_updated_at, o.d8, o.opted_at
      from crm.customer c join src s on s.d8 = right(regexp_replace(coalesce(c.phone,''), '\D', '', 'g'), 8)
      join crm.sms_optout o on o.d8 = s.d8),
  touch as (
    insert into crm.sms_optout_touch (upload_id, customer_id, buyer_key, d8, prev_consent, prev_source, prev_updated_at)
    select v_up, h.id, h.buyer_key, h.d8, h.consent_marketing, h.consent_source, h.consent_updated_at from hit h
    returning customer_id, prev_consent),
  upd as (
    update crm.customer c set consent_marketing = false, consent_source = 'optout', consent_updated_at = h.opted_at
      from hit h where h.id = c.id returning c.id),
  hist as (
    insert into crm.consent_history (buyer_key, consent, changed_at, source, evidence)
    select h.buyer_key, false, h.opted_at, 'optout', '문자 수신거부 목록 · ' || v_src || ' · upload ' || v_up from hit h where h.buyer_key is not null
    returning 1)
  select (select count(*) from upd), (select count(*) from touch where coalesce(prev_consent, false)) into v_matched, v_off;

  /* ③ 번호 줄에 매칭 고객 수·대표 키, 마스터에 없는 번호 수·예시 */
  update crm.sms_optout o set matched = x.n, buyer_key = x.bk::char(16), updated_at = now()
    from (select right(regexp_replace(coalesce(c.phone,''), '\D', '', 'g'), 8) d8, count(*) n, min(c.buyer_key::text) bk from crm.customer c
           where c.phone is not null group by 1) x
   where x.d8 = o.d8 and o.last_upload_id = v_up;
  select count(*), (select jsonb_agg(jsonb_build_object('name', y.name, 'phone', '···' || right(y.d8, 4))) from (select name, d8 from crm.sms_optout where last_upload_id = v_up and matched = 0 limit 5) y)
    into v_unmatched, v_sample from crm.sms_optout where last_upload_id = v_up and matched = 0;

  update raw.upload set row_count = v_rows, error_count = v_unmatched,
         note = v_src || ' · 번호 ' || v_rows || ' (새 ' || v_new || ') · 고객 ' || v_matched || ' (동의 끔 ' || v_off || ') · 마스터에 없음 ' || v_unmatched
   where id = v_up;
  return jsonb_build_object('rows', v_rows, 'new', v_new, 'dup', v_dup, 'matched', v_matched, 'off', v_off, 'unmatched', v_unmatched,
                            'sample', coalesce(v_sample, '[]'::jsonb), 'upload_id', v_up, 'source', v_src);
end $function$;
revoke all on function public.fn_sms_optout_import(jsonb,text,text,date) from public, anon;
grant execute on function public.fn_sms_optout_import(jsonb,text,text,date) to authenticated, service_role;

-- ───────── ④ 후속 관리 — 줄마다 수신거부 표시 (fn_crm_followups, 세 카드 공통) ─────────
--   left join crm.sms_optout oo on oo.released_at is null and oo.d8 = right(regexp_replace(coalesce(t.phone,''), '\D', '', 'g'), 8)
--   → 응답 rows[].optout (화면 [수신거부] 빨간 태그)

-- ───────── ⑤ 되돌리기 — fn_upload_rollback 의 sms_optout 가지 (최종본) ─────────
--   declare 에 v_cres int := 0; v_orel int := 0;  반환에 'consent_restored', v_cres, 'optout_released', v_orel
--    elsif u.source = 'sms_optout' then
--      /* 번호 해제 — 이 번호를 보낸 업로드(처음·마지막)가 전부 되돌려졌을 때만. 다른 살아 있는 업로드가 같은 번호를 보냈으면 그대로 둔다 */
--      update crm.sms_optout o set released_at = now(), updated_at = now()
--       where o.released_at is null and (o.upload_id = u.id or o.last_upload_id = u.id)
--         and (o.upload_id = u.id or o.upload_id in (select r.id from raw.upload r where r.rolled_back_at is not null))
--         and (o.last_upload_id = u.id or o.last_upload_id in (select r.id from raw.upload r where r.rolled_back_at is not null));
--      get diagnostics x = row_count; v_orel := v_orel + x;
--      /* 수신동의는 처음 끄기 전 값으로(그 고객의 가장 오래된 touch · 수신거부가 아니었던 값) — 아직 살아 있는 수신거부 번호의 고객은 끈 채로 둔다 */
--      update crm.customer c set consent_marketing = t.prev_consent, consent_source = t.prev_source, consent_updated_at = t.prev_updated_at
--        from (select distinct on (t0.customer_id) t0.customer_id, t0.d8, t0.prev_consent, t0.prev_source, t0.prev_updated_at
--                from crm.sms_optout_touch t0
--               where t0.customer_id in (select t1.customer_id from crm.sms_optout_touch t1 where t1.upload_id = u.id)
--                 and t0.prev_source is distinct from 'optout'
--               order by t0.customer_id, t0.created_at, t0.id) t
--       where t.customer_id = c.id and c.consent_source = 'optout'
--         and not exists (select 1 from crm.sms_optout o2 where o2.d8 = t.d8 and o2.released_at is null);
--      get diagnostics x = row_count; v_cres := v_cres + x;
--   롤백 실험: A(한 번 올리고 되돌림) restored 1 · released 1 · 동의 true/store 복구
--            B(1→2 올리고 1 되돌림) released 0 · 동의 그대로 꺼짐 → 2 되돌림 released 1 · restored 1 · 처음 값 복구 / C(2→1 순서) 같음

-- ───────── ⑥ 발송 대상 추출 · 미입금 — 항상 제외 + 카테고리 조건 줄 표시 + 내보내기 상한 (서버측 replace 패치 블록 그대로) ─────────
do $outer$
declare v_src text; v_args text; v_new text; i int; a text; b text; cnt int; pairs text[][];
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_crm_targets_v2';
  if v_src like '%sms_optout%' then raise exception 'targets 이미 패치됨'; end if;
  pairs := array[
    [$a$v_blocked int := 0; v_bad int := 0;$a$,
     $b$v_blocked int := 0; v_bad int := 0; v_optout int := 0;$b$],
    [$a$case when p_export then 5000 else least($a$,
     $b$case when p_export then 100000 else least($b$],
    [$a$  -- 오픈마켓(스마트스토어·쿠팡 등)에서만 알게 된 고객은 마케팅 발송에 쓸 수 없다.$a$,
     $b$  /* 카테고리 조건은 '한 번이라도 그 카테고리를 산 고객'(customer_roll.cats) — 줄의 최근 구매·최근 상품은 그 카테고리의 마지막 구매로 보여준다 (v181).
     전엔 전체 마지막 구매(예: 토너)가 보여 왜 모바일·웨어러블에 들었는지 알 수 없었다. 취소·환불뿐이면 그것이라도 보인다(cats 와 같은 기준). */
  if coalesce(p_category,'') <> '' and p_basis <> 'product' then
    update _c t set last_at = x.at, last_product = x.pn, last_category = p_category
      from (select po.buyer_key,
                   (array_agg(po.order_at order by (coalesce(po.status,'') in ('취소','환불')), po.order_at desc))[1] at,
                   (array_agg(po.product_name_raw order by (coalesce(po.status,'') in ('취소','환불')), po.order_at desc))[1] pn
              from core.orders po
             where not coalesce(po.is_test,false) and po.category = p_category
             group by po.buyer_key) x
     where x.buyer_key = t.buyer_key;
  end if;
  -- 오픈마켓(스마트스토어·쿠팡 등)에서만 알게 된 고객은 마케팅 발송에 쓸 수 없다.$b$],
    [$a$  if p_no_send_days is not null then$a$,
     $b$  /* 문자 수신거부 (mvp_195) — 번호 뒤 8자리가 crm.sms_optout(해제 안 된 것)에 있으면 옵션과 무관하게 항상 뺀다 */
  delete from _c where right(regexp_replace(coalesce(phone,''),'\D','','g'), 8) in (
    select so.d8 from crm.sms_optout so where so.released_at is null);
  get diagnostics v_optout = row_count;
  if p_no_send_days is not null then$b$],
    [$a$'blocked_bad', v_bad,$a$,
     $b$'blocked_bad', v_bad, 'blocked_optout', v_optout,$b$]
  ];
  v_new := v_src;
  for i in 1..array_length(pairs,1) loop
    a := pairs[i][1]; b := pairs[i][2];
    cnt := (length(v_new)-length(replace(v_new,a,'')))/length(a);
    if cnt <> 1 then raise exception 'targets 지점 % 개수 % (기대 1)', i, cnt; end if;
    v_new := replace(v_new, a, b);
  end loop;
  execute format('create or replace function public.fn_crm_targets_v2(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_new);

  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_unpaid_list';
  if v_src like '%sms_optout%' then raise exception 'unpaid 이미 패치됨'; end if;
  pairs := array[
    [$a$declare v_role text; v_total int; v_lim int;$a$,
     $b$declare v_role text; v_total int; v_lim int; v_optout int := 0;$b$],
    [$a$case when p_export then 5000 else 200 end$a$,
     $b$case when p_export then 100000 else 200 end$b$],
    [$a$  if p_no_send_days is not null then$a$,
     $b$  /* 문자 수신거부 (mvp_195) — 번호 뒤 8자리가 crm.sms_optout(해제 안 된 것)에 있으면 항상 뺀다 */
  delete from _ur where right(regexp_replace(coalesce(phone,''),'\D','','g'), 8) in (
    select so.d8 from crm.sms_optout so where so.released_at is null);
  get diagnostics v_optout = row_count;
  if p_no_send_days is not null then$b$],
    [$a$      'never_sent', (select count(*) from _ur where last_sent is null),$a$,
     $b$      'never_sent', (select count(*) from _ur where last_sent is null),
      'blocked_optout', v_optout,$b$]
  ];
  v_new := v_src;
  for i in 1..array_length(pairs,1) loop
    a := pairs[i][1]; b := pairs[i][2];
    cnt := (length(v_new)-length(replace(v_new,a,'')))/length(a);
    if cnt <> 1 then raise exception 'unpaid 지점 % 개수 % (기대 1)', i, cnt; end if;
    v_new := replace(v_new, a, b);
  end loop;
  execute format('create or replace function public.fn_unpaid_list(%s) returns jsonb language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_args, v_new);
end $outer$;
-- 확인(롤백 블록): 내보내기 total 6,020 = rows 6,020 · 1.69MB · 1.1초 / 카테고리 모바일·웨어러블 479줄 전부 category 일치 · 문제의 줄이 2025-08-10 갤럭시 액세서리(SM-…)로 보임
--               / 수신거부 한 번호 넣으면 6,020 → 6,019 · blocked_optout 1 · 해제하면 다시 6,020
