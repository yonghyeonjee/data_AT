-- mvp_51 : 재고 실사 반영 (스프레드시트 재고표 → inv)
--   rows: [{model, qty, category?, cost?, name?}]
--   ① 기존 품목(코드/모델) → ② ec.product_alias 완전일치 → ③ 접미사(TND/HYP/KR) 제거 일치 → ④ 모델명을 코드로 신규 생성
--   기록은 "차이만" adjust  : 실사수량 − 해당 시점 현재고. 같은 실사를 두 번 넣어도 안전(멱등).
create or replace function core.f_inv_stocktake(p_rows jsonb, p_date date, p_warehouse text, p_source text, p_by text)
returns jsonb language plpgsql set search_path to 'pg_catalog','public' as $$
declare r jsonb; v_model text; v_key text; v_base text; v_code text; v_qty numeric; v_cur numeric; v_delta numeric;
        n_item int := 0; n_new int := 0; n_adj int := 0; n_skip int := 0; v_ts timestamptz; unmatched text[] := '{}';
begin
  if p_date is null then raise exception '실사일자가 필요합니다'; end if;
  if not exists (select 1 from ec.warehouse where code = p_warehouse and active) then raise exception '창고가 없습니다: %', p_warehouse; end if;
  v_ts := (p_date::timestamp + interval '18 hours') at time zone 'Asia/Seoul';
  if jsonb_typeof(p_rows) <> 'array' then p_rows := jsonb_build_array(p_rows); end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_model := btrim(coalesce(r->>'model', r->>'code', ''));
    v_qty := nullif(btrim(coalesce(r->>'qty','')),'')::numeric;
    if v_model = '' or v_qty is null then n_skip := n_skip + 1; continue; end if;
    v_key := upper(regexp_replace(v_model, '[^A-Za-z0-9가-힣]', '', 'g'));
    v_base := regexp_replace(v_key, '(TND|HYP|KR)$', '');
    v_code := null;
    select code into v_code from inv.item
      where upper(code) = upper(v_model)
         or upper(regexp_replace(coalesce(model,''), '[^A-Za-z0-9가-힣]', '', 'g')) = v_key limit 1;
    if v_code is null then
      select ec_code into v_code from ec.product_alias where alias_key = v_key order by ec_code limit 1;
    end if;
    if v_code is null then
      select ec_code into v_code from ec.product_alias
       where regexp_replace(alias_key, '(TND|HYP|KR)$', '') = v_base
         and length(alias_key) <= length(v_key) + 4
       order by length(alias_key), ec_code limit 1;
    end if;
    if v_code is null then v_code := upper(v_model); unmatched := unmatched || v_model; end if;
    if not exists (select 1 from inv.item where code = v_code) then n_new := n_new + 1; end if;
    insert into inv.item (code, name, model, category, cost, track, updated_at)
    values (v_code, coalesce(nullif(btrim(r->>'name'),''), v_model), v_model, nullif(btrim(r->>'category'),''), nullif(btrim(r->>'cost'),'')::numeric, true, now())
    on conflict (code) do update set model = coalesce(inv.item.model, excluded.model),
      category = coalesce(inv.item.category, excluded.category), cost = coalesce(excluded.cost, inv.item.cost), updated_at = now();
    n_item := n_item + 1;
    select coalesce(sum(qty_signed),0) into v_cur from inv.v_ledger where item_code = v_code and warehouse = p_warehouse and moved_at <= v_ts;
    v_delta := v_qty - v_cur;
    if v_delta = 0 then continue; end if;
    insert into inv.movement (moved_at, kind, item_code, warehouse, qty, unit_cost, ref_type, ref_no, note, created_by)
    values (v_ts, 'adjust', v_code, p_warehouse, v_delta, nullif(btrim(r->>'cost'),'')::numeric, 'stocktake', p_source, '실사 ' || p_date::text || ' 수량 ' || v_qty::text, p_by);
    n_adj := n_adj + 1;
  end loop;
  return jsonb_build_object('ok', true, 'items', n_item, 'new_items', n_new, 'adjusted', n_adj, 'skipped', n_skip, 'unmatched', to_jsonb(unmatched));
end $$;

create or replace function public.fn_inv_stocktake(p_rows jsonb, p_date date, p_warehouse text default '00001', p_source text default 'stocktake')
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_res jsonb;
begin
  if core.f_role() not in ('admin','user') then raise exception '권한이 없습니다' using errcode='42501'; end if;
  v_res := core.f_inv_stocktake(p_rows, p_date, p_warehouse, p_source,
      coalesce((select handler_name from public.profiles where id = auth.uid()), (select email from public.profiles where id = auth.uid()), 'admin'));
  insert into raw.upload (source, file_name, row_count, error_count, uploaded_by)
  values ('inv_stocktake', p_source, (v_res->>'adjusted')::int, (v_res->>'skipped')::int, (select email from public.profiles where id = auth.uid()));
  return v_res;
end $$;
revoke all on function public.fn_inv_stocktake(jsonb,date,text,text) from public, anon;
grant execute on function public.fn_inv_stocktake(jsonb,date,text,text) to authenticated;
