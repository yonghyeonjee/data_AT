-- mvp_299 (2026-11-18) — 담당자 화면: 잔디로 들어온 문의의 처리 상태 (처리 전 / 진행 중 / 완료)
-- 적용됨. 기록용.
CREATE OR REPLACE FUNCTION public.fn_store_inquiries(p_code text, p_days integer DEFAULT 30, p_all boolean DEFAULT false)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
/* 잔디로 들어온 문의(폼·홈페이지·수동 접수)의 처리 상태: 처리 전 / 진행 중 / 완료.
   이어서 새 상담을 넣었으면(superseded_by) 그 마지막 상담의 상태로 본다. */
declare v_me text := core.f_staff(p_code); v_mgr boolean; v_from timestamptz;
begin
  perform set_config('dc.me', coalesce(v_me,''), true);
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v_mgr := core.f_staff_is_mgr(v_me);
  v_from := now() - make_interval(days => least(greatest(coalesce(p_days,30),1),180));
  return (with recursive base as (
      select k.* from crm.consult_scoped k
       where k.created_at >= v_from and k.deleted_at is null
         and (k.source in ('web_subscription','web_supply','web_b2b','gmail_homepage','homepage_api','homepage_csv')
              or (k.source='store' and k.notes ilike '%문의 접수%'))
         and (k.handler = v_me or (p_all and v_mgr))
    ), ch as (
      select b.id root, b.id cur, 0 d from base b
      union all select ch.root, c.superseded_by, ch.d+1 from ch join crm.consult c on c.id=ch.cur where c.superseded_by is not null and ch.d<6
    ), fin as (select distinct on (root) root, cur from ch order by root, d desc
    ), r as (
      select b.*, f.cur fin_id, fc.result fin_result, fc.handler fin_handler, fc.updated_at fin_at,
        case when fc.result='진행전' then 'todo' when fc.result in ('진행중','보류') then 'ing' else 'done' end st
      from base b join fin f on f.root=b.id join crm.consult fc on fc.id=f.cur)
    select jsonb_build_object('me', v_me, 'mgr', v_mgr, 'days', p_days,
      'counts', jsonb_build_object('todo',count(*) filter (where st='todo'),'ing',count(*) filter (where st='ing'),'done',count(*) filter (where st='done'),'all',count(*)),
      'rows', coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'fin_id', fin_id, 'st', st, 'result', fin_result,
        'at', to_char(created_at at time zone 'Asia/Seoul','MM-DD HH24:MI'),
        'done_at', case when st='done' then to_char(fin_at at time zone 'Asia/Seoul','MM-DD HH24:MI') end,
        'name', customer_name, 'tel', regexp_replace(coalesce(phone,''),'\D','','g'),
        'phone', case when phone is null then null else left(regexp_replace(phone,'\D','','g'),3)||'-****-'||right(regexp_replace(phone,'\D','','g'),4) end,
        'src', coalesce((select ch.label from core.inq_channel ch where ch.code=r.channel_code), core.f_consult_src(r.source, r.inflow_route)),
        'interest', interest_category, 'model', interest_model_code, 'handler', coalesce(fin_handler, handler), 'mine', coalesce(fin_handler,handler)=v_me,
        'callback_at', callback_at, 'content', left(content,80)) order by (st='todo') desc, (st='ing') desc, created_at desc), '[]'::jsonb))
    from r);
end $function$;
revoke all on function public.fn_store_inquiries(text,int,boolean) from public;
grant execute on function public.fn_store_inquiries(text,int,boolean) to anon, authenticated, service_role;
