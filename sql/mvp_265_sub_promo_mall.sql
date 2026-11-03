-- mvp_265 (2026-11-03) 행사 문구 몰 구분 — 데이터센터 하나로 시흥몰·프라자몰 상품상세 구독탭을 같이 운영
-- "몰 구분 추가": 행사 문구마다 대상 몰을 고른다 (아무것도 안 고르면 모든 몰)
--   sub.mall        : 몰 목록 (code · name · domain) — sh 시흥몰(samsungsh.co.kr) · pm 프라자몰(samsungpmall.com)
--   sub.promo.malls : 대상 몰 코드 배열 · 비면 모든 몰 · 상품번호(goods)로 고른 행사는 몰마다 번호가 겹치므로 몰을 안 고르면 시흥몰로 저장
--   배포(sub_policy.js): promos    = 시흥몰에 나갈 것만 (모든 몰 + sh) — 고도몰 시흥몰에 올라가 있는 예전 구독탭 사본도 그대로 맞게 동작
--                        promosAll = 전부 (malls 표시 포함) — 새 sub_tab.js 가 SUB_TAB_CONFIG.mall(기본 'sh') 로 골라 쓴다
--   화면(f_policy_view): promos 에 malls · 몰 목록 malls 추가 → 매장 [구독 혜택 안내] · 관리자 [구독 혜택 정책] 에서 칩으로 고른다
-- 함수는 서버 원본(pg_get_functiondef)을 읽어 지점만 바꾼다 (지점 개수 검증)

create table if not exists sub.mall (
  code    text primary key check (code ~ '^[a-z]{2,8}$'),
  name    text not null,
  domain  text,
  sort    integer not null default 100
);
alter table sub.mall enable row level security;
insert into sub.mall (code, name, domain, sort) values
  ('sh', '시흥몰',   'www.samsungsh.co.kr',   10),
  ('pm', '프라자몰', 'www.samsungpmall.com',  20)
on conflict (code) do nothing;

alter table sub.promo add column if not exists malls text[] not null default '{}';

do $outer$
declare v_def text; v_blk text; v_all text;
begin
  ------------------------------------------------------------------ sub.f_promo_save
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'sub' and p.proname = 'f_promo_save';
  if (length(v_def) - length(replace(v_def, 'v_months int;', ''))) / length('v_months int;') <> 1 then raise exception 'f_promo_save 지점1'; end if;
  v_def := replace(v_def, 'v_months int;',
    'v_malls text[] := coalesce((select array_agg(distinct lower(btrim(x)) order by lower(btrim(x))) from unnest(sub.f_arr(p_data->''malls'')) x where btrim(x) <> ''''), ''{}'');' || chr(10) ||
    '        v_months int;');
  if (length(v_def) - length(replace(v_def, 'if v_from is not null and v_to is not null', ''))) / length('if v_from is not null and v_to is not null') <> 1 then raise exception 'f_promo_save 지점2'; end if;
  v_def := replace(v_def, 'if v_from is not null and v_to is not null',
    'if exists (select 1 from unnest(v_malls) m where m not in (select code from sub.mall)) then raise exception ''모르는 몰 코드입니다: %'', array_to_string(v_malls, '','') using errcode = ''22023''; end if;' || chr(10) ||
    '  if cardinality(v_malls) = 0 and cardinality(sub.f_arr(p_data->''goods'')) > 0 then v_malls := ''{sh}''; end if;   -- 상품번호는 몰마다 겹친다' || chr(10) ||
    '  if v_from is not null and v_to is not null');
  if (length(v_def) - length(replace(v_def, '(text, from_d, to_d, cats, models, goods, active,', ''))) / length('(text, from_d, to_d, cats, models, goods, active,') <> 1 then raise exception 'f_promo_save 지점3'; end if;
  v_def := replace(v_def, '(text, from_d, to_d, cats, models, goods, active,', '(text, from_d, to_d, cats, models, goods, malls, active,');
  if (length(v_def) - length(replace(v_def, 'v_models, sub.f_arr(p_data->''goods''),', ''))) / length('v_models, sub.f_arr(p_data->''goods''),') <> 1 then raise exception 'f_promo_save 지점4'; end if;
  v_def := replace(v_def, 'v_models, sub.f_arr(p_data->''goods''),', 'v_models, sub.f_arr(p_data->''goods''), v_malls,');
  if (length(v_def) - length(replace(v_def, 'goods = sub.f_arr(p_data->''goods''),', ''))) / length('goods = sub.f_arr(p_data->''goods''),') <> 1 then raise exception 'f_promo_save 지점5'; end if;
  v_def := replace(v_def, 'goods = sub.f_arr(p_data->''goods''),',
    'goods = sub.f_arr(p_data->''goods''),' || chr(10) ||
    '           malls = case when p_data ? ''malls'' or cardinality(sub.f_arr(p_data->''goods'')) > 0 then v_malls else malls end,');
  execute v_def;

  ------------------------------------------------------------------ sub.f_promo_json (끄기·켜기 때 그대로 다시 저장)
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'sub' and p.proname = 'f_promo_json';
  if (length(v_def) - length(replace(v_def, '''goods'', to_jsonb(goods),', ''))) / length('''goods'', to_jsonb(goods),') <> 1 then raise exception 'f_promo_json 지점'; end if;
  v_def := replace(v_def, '''goods'', to_jsonb(goods),', '''goods'', to_jsonb(goods), ''malls'', to_jsonb(malls),');
  execute v_def;

  ------------------------------------------------------------------ sub.f_policy_view (매장·관리자 화면)
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'sub' and p.proname = 'f_policy_view';
  if (length(v_def) - length(replace(v_def, '''goods'', to_jsonb(goods),', ''))) / length('''goods'', to_jsonb(goods),') <> 1 then raise exception 'f_policy_view 지점1'; end if;
  v_def := replace(v_def, '''goods'', to_jsonb(goods),', '''goods'', to_jsonb(goods), ''malls'', to_jsonb(malls),');
  if (length(v_def) - length(replace(v_def, '''cats'', (select coalesce(jsonb_agg(k order by k)', ''))) / length('''cats'', (select coalesce(jsonb_agg(k order by k)') <> 1 then raise exception 'f_policy_view 지점2'; end if;
  v_def := replace(v_def, '''cats'', (select coalesce(jsonb_agg(k order by k)',
    '''malls'', (select coalesce(jsonb_agg(jsonb_build_object(''code'', code, ''name'', name, ''domain'', domain) order by sort, code), ''[]''::jsonb) from sub.mall),' || chr(10) ||
    '    ''cats'', (select coalesce(jsonb_agg(k order by k)');
  execute v_def;

  ------------------------------------------------------------------ sub.f_policy_export (sub_policy.js)
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'sub' and p.proname = 'f_policy_export';
  if (length(v_def) - length(replace(v_def, '''goods'', case when cardinality(goods) > 0 then to_jsonb(goods) end,', ''))) / length('''goods'', case when cardinality(goods) > 0 then to_jsonb(goods) end,') <> 1 then raise exception 'f_policy_export 지점1'; end if;
  v_def := replace(v_def, '''goods'', case when cardinality(goods) > 0 then to_jsonb(goods) end,',
    '''goods'', case when cardinality(goods) > 0 then to_jsonb(goods) end,' || chr(10) ||
    '                ''malls'', case when cardinality(malls) > 0 then to_jsonb(malls) end,');
  if position('''promos'', (select' in v_def) = 0 or position('''points''' in v_def) = 0 then raise exception 'f_policy_export 지점2'; end if;
  v_blk := substr(v_def, position('''promos'', (select' in v_def), position('''points''' in v_def) - position('''promos'', (select' in v_def));
  if (length(v_blk) - length(replace(v_blk, '::date - 1))', ''))) / length('::date - 1))') <> 1 then raise exception 'f_policy_export 지점3'; end if;
  v_all := replace(v_blk, '''promos'', (select', '''promosAll'', (select');
  v_def := replace(v_def, v_blk,
    replace(v_blk, '::date - 1))', '::date - 1)' || chr(10) || '                 and (cardinality(malls) = 0 or ''sh'' = any(malls)))') || v_all);
  execute v_def;
end $outer$;
