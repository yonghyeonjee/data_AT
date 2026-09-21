-- mvp_165 · 2026-09-21 · 온라인 채널 일매출 구글 시트 자동 적재
-- core.api_key 'channel_daily' (SHA-256 해시만 저장 · 값은 _secrets.local.md)
-- fn_channel_daily_ingest(p_key text, p_rows jsonb, p_file text default null) — anon 허용, core.f_api_ok('channel_daily') 검사,
--   rows [{date, channel, sales, refund}] → core.channel_daily upsert(source 'sheet_gas'), 값이 같으면 updated_at 도 안 건드림
-- core.data_source channel_daily how/auto_plan/expect_days 3
-- 9월 1~17일 147줄은 세션에서 fn_channel_daily_upsert(source 'sheet') 로 적재 (Drive xlsx → openpyxl 파싱)
create or replace function public.fn_channel_daily_ingest(p_key text, p_rows jsonb, p_file text default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_n int := 0; v_skip int := 0; r jsonb; v_ch text; v_d date;
begin
  if not core.f_api_ok('channel_daily', p_key) then raise exception '키가 맞지 않습니다' using errcode='42501'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then return jsonb_build_object('ok', true, 'upserted', 0, 'skipped', 0); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_ch := core.f_channel_norm(r->>'channel');
    v_d := core.f_dt(r->>'date');
    if v_ch is null or v_d is null then v_skip := v_skip + 1; continue; end if;
    insert into core.channel_daily (biz_date, channel, sales, refund, source, file_name, note, updated_by, updated_at)
    values (v_d, v_ch, coalesce((r->>'sales')::numeric,0), coalesce((r->>'refund')::numeric,0), 'sheet_gas', coalesce(p_file,'GAS channel_daily_sync'), nullif(r->>'note',''), null, now())
    on conflict (biz_date, channel) do update set sales = excluded.sales, refund = excluded.refund,
      source = excluded.source, file_name = excluded.file_name, note = coalesce(excluded.note, core.channel_daily.note),
      updated_at = now()
    where core.channel_daily.sales is distinct from excluded.sales or core.channel_daily.refund is distinct from excluded.refund;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'upserted', v_n, 'skipped', v_skip);
end $$;
revoke all on function public.fn_channel_daily_ingest(text, jsonb, text) from public;
grant execute on function public.fn_channel_daily_ingest(text, jsonb, text) to anon, authenticated, service_role;
