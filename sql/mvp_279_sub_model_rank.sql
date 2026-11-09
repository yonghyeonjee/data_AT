-- mvp_279 (2026-11-09) 구독센터 '인기순' — 최근 12개월 매장 구독 계약이 많은 모델 순위
-- 공개 파일(sub_index.js)에는 계약 수가 아니라 순위만 싣는다. 취소·미신청·해지완료는 세지 않는다.
create or replace function public.fn_sub_model_rank() returns jsonb
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with c as (
    select upper(regexp_replace(model, '\s+', '', 'g')) as model, count(*) as n
      from dps.sub_contract
     where status in ('구독','접수','가입')
       and coalesce(contract_date, apply_date) >= current_date - interval '12 months'
       and coalesce(model, '') <> ''
     group by 1
  ), r as (select model, dense_rank() over (order by n desc) as rk from c)
  select coalesce(jsonb_object_agg(model, rk), '{}'::jsonb) from r;
$$;
revoke all on function public.fn_sub_model_rank() from public, anon, authenticated;
grant execute on function public.fn_sub_model_rank() to service_role;
