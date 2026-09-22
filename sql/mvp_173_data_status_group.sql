-- mvp_173 · 2026-09-22 · 데이터 소스 카드를 수동/자동으로 나누고 고도몰 주문을 센다
-- "카드들이 잘보이게 요약 정보로 하고, 수동, 자동 나눠두고"

-- ① core.data_source.feed_mode — 'auto'(수집기·폼이 알아서) / 'manual'(사람이 파일) / 'mixed'(몰마다 다름)
alter table core.data_source add column if not exists feed_mode text;
alter table core.data_source drop constraint if exists data_source_feed_mode_chk;
alter table core.data_source add constraint data_source_feed_mode_chk check (feed_mode in ('auto','manual','mixed'));
update core.data_source set feed_mode = case key
  when 'shoplinker' then 'auto'  when 'ec_slip' then 'auto'
  when 'web_inquiry' then 'auto' when 'web_subscription' then 'auto'
  when 'web_supply' then 'auto'  when 'web_b2b' then 'auto'
  when 'store' then 'auto'       when 'store_manual' then 'auto'
  when 'channel_daily' then 'auto'
  when 'godo_order' then 'mixed'          -- P·AT·S 는 파일, 시흥몰은 OpenAPI
  else 'manual' end;

-- ② fn_data_status 패치 4곳 (원본 prosrc 치환 — 본문을 다시 쓰지 않는다)
--   ㉠ stat CTE 에 godo_order 추가. n30 은 loaded_at 기준 — 과거 주문이라 주문일 기준이면 늘 0 이다.
--   ㉡ godo_detail CTE : 몰 × source 별 줄·주문·기간·파일 수 (화면 카드의 몰별 요약)
--   ㉢ detail 에 godo_detail 연결
--   ㉣ 응답에 feed_mode
--   ㉤ up CTE : raw.upload.source 는 'godo_order_hist' 라 카드 key 와 안 붙어 마지막 적재가 비었다 → 매핑
do $outer$
declare v_src text; v_args text; v_n int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_data_status';

  if position('    union all
    select ''ec_customer''' in v_src) = 0 then raise exception '지점 ㉠ 없음'; end if;
  v_src := replace(v_src, '    union all
    select ''ec_customer''',
'    union all
    select ''godo_order'', count(*), min(ordered_at)::date, max(ordered_at)::date,
           count(*) filter (where loaded_at > now() - interval ''30 days'')
      from raw.godo_order_hist
    union all
    select ''ec_customer''');

  if position('  sl_refund as (' in v_src) = 0 then raise exception '지점 ㉡ 없음'; end if;
  v_src := replace(v_src, '  sl_refund as (',
'  godo_detail as (
    select jsonb_build_object(
      ''malls'', coalesce((select jsonb_agg(jsonb_build_object(
            ''mall'', g.mall, ''how'', case when g.source=''api'' then ''자동'' else ''수동'' end,
            ''rows'', g.rows, ''orders'', g.orders, ''from'', g.mn, ''to'', g.mx, ''files'', g.files) order by g.mall)
        from (select mall, source, count(*) rows, count(distinct order_no) orders,
                     min(ordered_at)::date mn, max(ordered_at)::date mx, count(distinct source_file) files
                from raw.godo_order_hist group by mall, source) g), ''[]''::jsonb)) j
  ),
  sl_refund as (');

  v_n := (length(v_src) - length(replace(v_src, 'when ''shoplinker'' then (select j from sl_refund) else null end', ''))) / length('when ''shoplinker'' then (select j from sl_refund) else null end');
  if v_n <> 1 then raise exception '지점 ㉢ 없음 (%)', v_n; end if;
  v_src := replace(v_src,
    'when ''shoplinker'' then (select j from sl_refund) else null end',
    'when ''shoplinker'' then (select j from sl_refund) when ''godo_order'' then (select j from godo_detail) else null end');

  v_n := (length(v_src) - length(replace(v_src, '''alert'', d.alert,', ''))) / length('''alert'', d.alert,');
  if v_n <> 1 then raise exception '지점 ㉣ 없음 (%)', v_n; end if;
  v_src := replace(v_src, '''alert'', d.alert,', '''alert'', d.alert, ''feed_mode'', coalesce(d.feed_mode,''manual''),');

  v_n := (length(v_src) - length(replace(v_src, 'when u.source = ''shoplinker_refund'' then ''shoplinker''', ''))) / length('when u.source = ''shoplinker_refund'' then ''shoplinker''');
  if v_n <> 1 then raise exception '지점 ㉤ 없음 (%)', v_n; end if;
  v_src := replace(v_src,
    'when u.source = ''shoplinker_refund'' then ''shoplinker''',
    'when u.source = ''shoplinker_refund'' then ''shoplinker''
                when u.source = ''godo_order_hist'' then ''godo_order''');

  execute format('create or replace function public.fn_data_status(%s) returns jsonb
                  language plpgsql stable security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;

-- 화면(admin.html) : loadDataStatus 가 feed_mode 로 카드를 ['manual','mixed','auto'] 순서로 묶고
--   묶음 머리(.dsgrp)에 이름·개수·[확인 필요 N]·한 줄 설명. 고도몰 주문은 dsDetail 이 몰별 줄·주문·기간을 보인다.
--   ARCHIVE(godo_order) : 과거 자료 보관함이라 '30일' → '30일 적재', 경과일은 빨갛게 하지 않고 '(과거 자료)' 를 붙인다.
-- 테스트 ptest/dsgroup.mjs D1~D6 × PC·폰 = 16
