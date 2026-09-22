-- mvp_176 · 원장 중복 — 샵링커 파일 적재 줄과 API 수집 줄이 같은 주문을 두 번 넣던 것 (2026-09-22)
-- "동일한 주문인지 아닌지 어떻게 알지? 주문번호 대조해봐야 하는 거 아냐? 동일 주문번호는 중복으로 빼버려"
--
-- 진단 : 샵링커 원장에서 (주문번호, 품목(모델 또는 상품명), 수량, 금액) 이 같은 줄이 둘 이상인 묶음 124개.
--   · 26묶음 = 파일 적재 줄(품목번호 source_ref 없음 · line 1 · 9/3 업로드 1·7·10·11·45·46) + API 수집 줄(품목번호 있음 · line 2) → **진짜 중복** 26줄 · 1,324만원
--     원인 : 파일은 (source, order_no, line_no) 로, API 는 (source, source_ref) 로 겹침을 보는데 API 가 line_no 를 max+1 로 매겨 파일 줄과 만나지 못했다.
--   · 69묶음 = 파일 줄끼리(품목번호 없음, 2~3줄) · 29묶음 = API 줄끼리(품목번호 다름) → 샵링커는 같은 상품 N개를 N줄로 준다(품목번호가 줄마다 다름) — 정상, 안 건드림.
--   · 이상혁 9/21 두 줄(…8600 11:13 / …5745 16:05)은 주문번호·품목번호가 다른 별개 주문 — 중복 아님.
--
-- 1) 정리 : 26줄을 core.orders_dup_backup_20260922 에 두고 삭제 (API 줄을 남긴다 — 상태·환불이 더 최신). crm.consult.linked_order_id 참조 0. core.dash_cache 비움.
-- 2) 재발 방지 :
--   · fn_sl_upsert : 새 품목번호인데 같은 주문번호·품목·수량·금액의 품목번호 없는 줄이 있으면 새 줄을 만들지 않고 그 줄에 source_ref 를 붙인다(이후 on conflict 갱신).
--   · core.f_orders_bulk_upsert : 샵링커 파일 줄이 API 로 이미 들어온 같은 줄이면 건너뛴다 → 응답 '중복건너뜀'.
-- 3) 롤백 테스트 : 파일 2줄(같은 상품 2개) → API 3줄(같은 상품 2 + 다른 상품 1) = updated 2 · inserted 1, 줄 3개 전부 품목번호 / 파일 재적재 3줄 → 중복건너뜀 2 · 새 주문 1 적재 → 총 4줄.

do $outer$
declare v_def text; v_a text; v_b text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_sl_upsert';
  v_a := 'if v_hit is null then
      select coalesce(max(line_no), 0) + 1 into v_line from core.orders';
  if (length(v_def)-length(replace(v_def, v_a, '')))/length(v_a) <> 1 then raise exception 'sl_upsert 지점 없음'; end if;
  v_b := 'if v_hit is null then
      /* 파일로 먼저 들어온 같은 줄(품목번호 없음 · 같은 주문번호·품목·수량·금액)이 있으면 새 줄을 만들지 않고 그 줄에 품목번호를 붙인다
         — 파일 line 1 · API line 2 로 같은 주문이 두 줄 되던 중복 (mvp_176) */
      select id, line_no into v_hit, v_line from core.orders
       where source = ''shoplinker'' and source_ref is null and order_no = v_ono
         and qty = coalesce((r->>''qty'')::numeric, 1) and gross_amount = coalesce((r->>''gross_amount'')::numeric, 0)
         and ((nullif(r->>''model_code'','''') is not null and model_code = r->>''model_code'') or product_name_raw = coalesce(r->>''product_name'',''''))
       order by id limit 1;
      if v_hit is not null then update core.orders set source_ref = r->>''source_ref'' where id = v_hit; end if;
    end if;
    if v_hit is null then
      select coalesce(max(line_no), 0) + 1 into v_line from core.orders';
  execute replace(v_def, v_a, v_b);

  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='core' and p.proname='f_orders_bulk_upsert';
  if position('v_n int := 0; v_noKey int := 0;' in v_def) = 0 then raise exception 'bulk 지점 없음 1'; end if;
  if position('insert into core.orders (source, channel_type, channel_name, order_no, line_no, source_ref,' in v_def) = 0 then raise exception 'bulk 지점 없음 2'; end if;
  if position('return jsonb_build_object(''upload_id'', v_upload, ''적재'', v_n, ''고객키없음'', v_noKey);' in v_def) = 0 then raise exception 'bulk 지점 없음 3'; end if;
  v_def := replace(v_def, 'v_n int := 0; v_noKey int := 0;', 'v_n int := 0; v_noKey int := 0; v_dup int := 0;');
  v_def := replace(v_def, 'insert into core.orders (source, channel_type, channel_name, order_no, line_no, source_ref,',
    '/* 샵링커 파일 줄이 API 수집으로 이미 들어온 줄(품목번호 있음 · 같은 주문번호·품목·수량·금액)이면 건너뛴다 — 줄 순번이 달라 두 줄이 되던 중복 (mvp_176) */
    if p_source = ''shoplinker'' and nullif(r->>''source_ref'','''') is null and exists (select 1 from core.orders o
         where o.source = ''shoplinker'' and o.source_ref is not null and o.order_no = nullif(r->>''order_no'','''')
           and o.qty = coalesce((r->>''qty'')::numeric, 1) and o.gross_amount = coalesce((r->>''gross_amount'')::numeric, 0)
           and ((nullif(r->>''model_code'','''') is not null and o.model_code = r->>''model_code'') or o.product_name_raw = coalesce(r->>''product_name'','''')))
    then v_dup := v_dup + 1; continue; end if;
    insert into core.orders (source, channel_type, channel_name, order_no, line_no, source_ref,');
  v_def := replace(v_def, 'return jsonb_build_object(''upload_id'', v_upload, ''적재'', v_n, ''고객키없음'', v_noKey);',
                          'return jsonb_build_object(''upload_id'', v_upload, ''적재'', v_n, ''고객키없음'', v_noKey, ''중복건너뜀'', v_dup);');
  execute v_def;
end $outer$;

-- 정리 (백업 → 삭제 → 대시보드 캐시 비움)
create table if not exists core.orders_dup_backup_20260922 as
with g as (
  select id, source_ref, row_number() over (partition by order_no, coalesce(model_code, product_name_raw), qty, gross_amount order by id) rn,
         count(source_ref) over (partition by order_no, coalesce(model_code, product_name_raw), qty, gross_amount) n_ref
    from core.orders where source = 'shoplinker')
select o.* from core.orders o join g on g.id = o.id where g.source_ref is null and g.n_ref >= 1 and g.rn <= g.n_ref;
delete from core.orders where id in (select id from core.orders_dup_backup_20260922);
delete from core.dash_cache where true;
-- 결과 : backed_up 26 · 1,324만원 · 남은 파일+API 겹침 0
