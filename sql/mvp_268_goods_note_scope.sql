-- mvp_268 (2026-11-03) 상품 안내 문구 — 공통 / 개별 구분
-- "위치 선택하는 건 좋아, 대신 공통 개별을 구분할 수만 있으면 좋겠어"
--   scope : goods 개별(상품번호·모델번호로 고른 상품만) · all 공통(그 몰의 모든 상품 상세)
--   공통은 대상 상품번호·모델번호를 비운다. 위치·색·버튼·시험/공개는 개별과 같다.

alter table sub.goods_note add column if not exists scope text not null default 'goods' check (scope in ('goods','all'));
alter table sub.goods_note drop constraint if exists goods_note_check;
alter table sub.goods_note add constraint goods_note_target_check check (scope = 'all' or cardinality(goods) + cardinality(models) > 0);

-- 점 고치기 — 고칠 곳이 정확히 1곳일 때만
do $$
declare v_src text; v_new text;
begin
  -- 1) sub.f_goods_note_json: scope 를 내보낸다
  select pg_get_functiondef('sub.f_goods_note_json(sub.goods_note)'::regprocedure) into v_src;
  if (length(v_src) - length(replace(v_src, $q$'pos', n.pos,$q$, ''))) / length($q$'pos', n.pos,$q$) <> 1 then raise exception 'f_goods_note_json 고칠 곳'; end if;
  execute replace(v_src, $q$'pos', n.pos,$q$, $q$'pos', n.pos, 'scope', n.scope,$q$);

  -- 2) public.fn_goods_note: 공통 문구는 상품번호·모델번호와 상관없이 나간다
  select pg_get_functiondef('public.fn_goods_note(text, text, text[], boolean)'::regprocedure) into v_src;
  if (length(v_src) - length(replace(v_src, $q$and ((p_goods is not null and$q$, ''))) / length($q$and ((p_goods is not null and$q$) <> 1 then raise exception 'fn_goods_note 고칠 곳'; end if;
  execute replace(v_src, $q$and ((p_goods is not null and$q$, $q$and (n.scope = 'all' or (p_goods is not null and$q$);

  -- 3) public.fn_store_goods_note_save: scope 받기 · 공통이면 대상 비우고 대상 검사 건너뜀
  select pg_get_functiondef('public.fn_store_goods_note_save(text, jsonb)'::regprocedure) into v_src;
  v_new := v_src;
  v_new := replace(v_new, $q$v_body text;$q$, $q$v_body text; v_scope text := case when p_data->>'scope' = 'all' then 'all' else 'goods' end;$q$);
  v_new := replace(v_new, $q$  v_body  := btrim(coalesce(p_data->>'body', ''));$q$, $q$  if v_scope = 'all' then v_goods := '{}'; v_models := '{}'; end if;
  v_body  := btrim(coalesce(p_data->>'body', ''));$q$);
  v_new := replace(v_new, $q$if cardinality(v_goods) + cardinality(v_models) = 0 then$q$, $q$if v_scope <> 'all' and cardinality(v_goods) + cardinality(v_models) = 0 then$q$);
  v_new := replace(v_new, $q$insert into sub.goods_note (mall, goods,$q$, $q$insert into sub.goods_note (scope, mall, goods,$q$);
  v_new := replace(v_new, $q$values (coalesce(nullif(p_data->>'mall',''), 'pm'), v_goods$q$, $q$values (v_scope, coalesce(nullif(p_data->>'mall',''), 'pm'), v_goods$q$);
  v_new := replace(v_new, $q$set mall = coalesce(nullif(p_data->>'mall',''), mall), goods = v_goods$q$, $q$set scope = v_scope, mall = coalesce(nullif(p_data->>'mall',''), mall), goods = v_goods$q$);
  if (length(v_new) - length(replace(v_new, 'v_scope', ''))) / length('v_scope') <> 5 then
    raise exception 'fn_store_goods_note_save 고칠 곳이 맞지 않습니다 (v_scope %)', (length(v_new) - length(replace(v_new, 'v_scope', ''))) / length('v_scope');
  end if;
  execute v_new;
end $$;
