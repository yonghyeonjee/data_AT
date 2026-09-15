-- mvp_150 (2026-09-15) — 이카운트 전표 3건 지적 (고창재 프로님 테스트)
--
-- ① 재고부족 — 고칠 것 없었다. 타이밍이었다.
--    테스트 17:05:10 / 재고 999 고정 17:17:37 (inv.movement ref_type='no_sync_999', 2,457줄).
--    그 12분 사이 AT-00614(HAF-CIN3/EXP) 가 -67 이라 막혔다. 지금은 999 라 통과한다.
--    재고를 보는 곳은 inv.v_stock 이 아니라 core.f_order_submit 안의
--      select sum(qty_signed) from inv.v_ledger where item_code=? and warehouse=?
--    즉 '창고별' 합계다. 앞으로 재고를 손볼 때는 창고(00001 본사창고)까지 맞춰야 한다.
--
-- ② 거래처명에 고객명이 들어갔다 (이흥노 · 삼덕초등학교)
--    core.f_sl_to_order 는 cust_code 는 채널 거래처(ec.channel_cust)에서 가져오면서
--    cust_name 에는 구매자명(r.buyer)을 넣는다. core.f_order_body 가 그걸 그대로
--    CUST_DES 로 보내 이카운트 거래처명 칸에 고객 이름이 찍혔다.
--    → CUST_DES 를 '거래처코드의 이카운트 거래처명' 에서 찾도록 바꾼다.
--      (ec.order_queue.cust_name 은 우리 기록용으로 그대로 둔다 — 누가 산 건지는 남아야 한다)
--
-- ③ 특이사항에 010-0000-0000 이 들어갔다
--    U_MEMO1 은 이카운트 필수값이다. ec_field_map 이 phone → U_MEMO1 인데
--    샵링커 주문은 phone 이 null 이라 매핑이 건너뛰어지고, 마지막 기본값인
--    가짜 번호 '010-0000-0000' 이 박혔다 (큐 9건 중 전화가 있는 건은 1건뿐).
--    → 적요(q.remark, 'N월 주문건') → 전화 → 주문월 순으로 채운다. 가짜 번호는 없앤다.
--    → 적요 자체도 'N월 주문건 / 2026-09-15' 에서 'N월 주문건' 으로 줄인다
--      (변환한 날짜는 ec.order_queue.created_at 에 이미 남는다).
--
-- 적용은 본문을 옮겨 적지 않고 pg_get_functiondef 를 읽어 부분만 치환한다 (CLAUDE.md 작업 방식 2).

-- ───────── ② CUST_DES · ③ U_MEMO1 (core.f_order_body) ─────────
do $outer$
declare v_def text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core'
   where p.proname='f_order_body';
  if v_def is null then raise exception '함수 없음'; end if;
  v_new := v_def;

  v_n := (length(v_new) - length(replace(v_new, '''CUST'', q.cust_code, ''CUST_DES'', q.cust_name,','')))
        / length('''CUST'', q.cust_code, ''CUST_DES'', q.cust_name,');
  if v_n <> 1 then raise exception '① 지점 % 개', v_n; end if;
  v_new := replace(v_new,
    '''CUST'', q.cust_code, ''CUST_DES'', q.cust_name,',
    '''CUST'', q.cust_code,'
 || E'\n            ''CUST_DES'', coalesce((select c.name from ec.customer c where c.code = q.cust_code), q.cust_name),   /* 거래처명은 거래처코드 기준 — 구매자 이름을 쓰지 않는다 */');

  v_n := (length(v_new) - length(replace(v_new,
    'if nullif(base->>''U_MEMO1'','''') is null then base := base || jsonb_build_object(''U_MEMO1'', coalesce(nullif(regexp_replace(coalesce(q.phone,''''),''[^0-9-]'','''',''g''),''''), ''010-0000-0000'')); end if;','')))
    / length('if nullif(base->>''U_MEMO1'','''') is null then base := base || jsonb_build_object(''U_MEMO1'', coalesce(nullif(regexp_replace(coalesce(q.phone,''''),''[^0-9-]'','''',''g''),''''), ''010-0000-0000'')); end if;');
  if v_n <> 1 then raise exception '② 지점 % 개', v_n; end if;
  v_new := replace(v_new,
    'if nullif(base->>''U_MEMO1'','''') is null then base := base || jsonb_build_object(''U_MEMO1'', coalesce(nullif(regexp_replace(coalesce(q.phone,''''),''[^0-9-]'','''',''g''),''''), ''010-0000-0000'')); end if;',
    'if nullif(base->>''U_MEMO1'','''') is null then'
 || E'\n    base := base || jsonb_build_object(''U_MEMO1'', coalesce('
 || E'\n      nullif(regexp_replace(coalesce(q.remark,''''),''[^0-9A-Za-z가-힣 ,.()/-]'','' '',''g''),''''),'
 || E'\n      nullif(regexp_replace(coalesce(q.phone,''''),''[^0-9-]'','''',''g''),''''),'
 || E'\n      to_char(q.io_date,''FMMM'')||''월 주문건''));   /* 필수값 — 가짜 번호 대신 주문월 (mvp_150) */'
 || E'\n  end if;');

  execute v_new;
end $outer$;

-- ───────── ③ 적요를 'N월 주문건' 으로 (core.f_sl_to_order) ─────────
do $outer$
declare v_def text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core'
   where p.proname='f_sl_to_order';
  v_new := v_def;

  v_n := (length(v_new) - length(replace(v_new,
    '''remark'', to_char(r.ord_date,''FMMM'')||''월 주문건 / ''||to_char(v_today,''YYYY-MM-DD''),','')))
    / length('''remark'', to_char(r.ord_date,''FMMM'')||''월 주문건 / ''||to_char(v_today,''YYYY-MM-DD''),');
  if v_n <> 1 then raise exception '지점 % 개', v_n; end if;
  v_new := replace(v_new,
    '''remark'', to_char(r.ord_date,''FMMM'')||''월 주문건 / ''||to_char(v_today,''YYYY-MM-DD''),',
    '''remark'', to_char(r.ord_date,''FMMM'')||''월 주문건'',   /* 주문일의 월 — 이카운트 특이사항으로 간다 (mvp_150) */');

  execute v_new;
end $outer$;

-- ───────── 확인 ─────────
-- 큐 15번(이흥노 · SSG)으로 실제 나갈 본문을 뽑아 봤다:
--   거래처코드 8708801143 · 거래처명 '이흥노' → 'SSG'
--   특이사항  '010-0000-0000' → '9월 주문건 / 2026-09-15'
--   (이 큐는 옛 적요라 날짜가 붙어 있고, 새로 변환하는 건부터 '9월 주문건' 만 들어간다)
--
-- 이미 이카운트로 나간 2장(큐 14·15)은 거래처명이 고객명인 채로 등록돼 있다.
-- 이카운트에서 지우고 다시 보내야 바뀐다. 실패로 남아 있는 3장(큐 10·11·13)은
-- 화면 [재전송] 으로 바로 다시 보내면 고쳐진 본문으로 나간다.
