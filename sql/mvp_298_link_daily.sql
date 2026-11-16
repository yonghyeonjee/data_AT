-- mvp_298 · 2026-11-16 · 발송 링크 관리: 링크·캠페인 날짜별 클릭 (적용됨)
-- core.f_link_daily = 본체(권한 없음 · public/anon/authenticated 실행 회수), public.fn_link_daily = 관리자 래퍼
create or replace function core.f_link_daily(p_slug text default null, p_campaign text default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $f$
declare v_to date := coalesce(p_to, (now() at time zone 'Asia/Seoul')::date);
        v_from date; v_slugs text[];
begin
  if nullif(p_slug,'') is not null then v_slugs := array[p_slug];
  elsif nullif(p_campaign,'') is not null then select array_agg(slug) into v_slugs from crm.link where campaign = p_campaign;
  else raise exception '링크나 캠페인을 고르세요' using errcode='22023'; end if;
  v_slugs := coalesce(v_slugs, '{}');
  v_from := coalesce(p_from,
     (select least(min((h.at at time zone 'Asia/Seoul')::date), v_to) from crm.link_hit h where h.slug = any(v_slugs)),
     v_to - 29);
  if v_to - v_from > 400 then v_from := v_to - 400; end if;
  return (with h as (
      select (h.at at time zone 'Asia/Seoul') t, h.slug, h.buyer_key, coalesce(h.ua,'') ua
        from crm.link_hit h where h.slug = any(v_slugs)
         and h.at >= (v_from::timestamp at time zone 'Asia/Seoul') and h.at < ((v_to + 1)::timestamp at time zone 'Asia/Seoul')),
    d as (select g::date d from generate_series(v_from, v_to, interval '1 day') g),
    per as (select t::date d, count(*) n, count(distinct buyer_key) ppl,
                   count(*) filter (where ua ~* 'mobi|android|iphone|ipad') mob from h group by 1)
    select jsonb_build_object(
      'from', v_from, 'to', v_to, 'slugs', to_jsonb(v_slugs),
      'total', (select count(*) from h),
      'people', (select count(distinct buyer_key) from h),
      'mobile', (select count(*) from h where ua ~* 'mobi|android|iphone|ipad'),
      'days', (select coalesce(jsonb_agg(jsonb_build_object('d', d.d, 'n', coalesce(per.n,0), 'ppl', coalesce(per.ppl,0), 'mob', coalesce(per.mob,0)) order by d.d), '[]'::jsonb)
               from d left join per on per.d = d.d),
      'hours', (select coalesce(jsonb_agg(jsonb_build_object('h', x.hh, 'n', x.n) order by x.hh), '[]'::jsonb)
               from (select extract(hour from t)::int hh, count(*) n from h group by 1) x),
      'by_link', (select coalesce(jsonb_agg(jsonb_build_object('slug', x.slug, 'label', l.label, 'n', x.n) order by x.n desc), '[]'::jsonb)
               from (select slug, count(*) n from h group by 1) x left join crm.link l on l.slug = x.slug)));
end $f$;
create or replace function public.fn_link_daily(p_slug text default null, p_campaign text default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $f$
begin
  if core.f_role() not in ('admin','user','uploader') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_link_daily(p_slug, p_campaign, p_from, p_to);
end $f$;
revoke all on function core.f_link_daily(text,text,date,date) from public, anon, authenticated;
revoke all on function public.fn_link_daily(text,text,date,date) from public, anon;
grant execute on function public.fn_link_daily(text,text,date,date) to authenticated, service_role;
