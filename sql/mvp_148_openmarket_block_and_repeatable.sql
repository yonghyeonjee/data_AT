-- mvp_148 (2026-09-15) — 오픈마켓 고객 발송 차단 + 누가 뽑아도 같은 수
--
-- 왜
--  ① 오픈마켓(스마트스토어·쿠팡·11번가·지마켓·옥션·SSG·롯데온 등)에서 받은 주문자 정보는
--     그 주문을 이행하는 데만 쓸 수 있다. 우리 이름으로 광고·안내 문자를 보내는 근거가 되지 않는다.
--     그런데 [발송 대상 추출] 의 '제품 재구매' 기준이 오픈마켓 주문까지 세고 있었다
--     (정수기 필터 HAF- : 전체 4,083명 중 3,851명이 오픈마켓).
--  ② 저장 조건(crm.segment)에 '대상 기준'과 '제품'이 안 담겨 있어, 같은 버튼을 눌러도
--     사람마다 다른 수가 나왔다. '거래 재구매 주기' 는 now() 를 써서 하루만 지나도 대상이 바뀐다.
--
-- 무엇을 바꿨나 (public.fn_crm_targets_v2)
--  ① 제품 기준: 그 제품을 '오픈마켓에서' 산 기록은 근거로 세지 않는다
--     → po.channel_type <> '오픈마켓'
--  ② 기준과 무관하게, 오픈마켓에서만 알게 된 고객은 전부 뺀다
--     → 남는 조건 = 우리가 직접 받은 동의(consent_marketing, 자사몰 회원)
--                 또는 자사몰·VMS·렌탈·매장에서의 직접 거래
--     제외된 인원은 summary.blocked_open 으로 화면에 보여 준다
--  ③ 새 인자 p_asof date — '거래 재구매 주기' 의 예상재구매일을 이 날짜로 계산한다.
--     비우면 오늘. 기준일을 적어 두면 누가 언제 뽑아도 같은 사람이 나온다.
--     (기본값 인자 추가라 옛 시그니처 drop → 새로 create → grant, 한 트랜잭션)
--     응답 summary.asof 로 실제 쓴 날짜를 돌려준다.
--
-- 적용 방법 — 본문을 옮겨 적지 않는다. pg_get_functiondef 를 읽어 부분만 치환하고,
--            치환 전 지점 개수를 세어 0개·중복이면 중단한다 (CLAUDE.md 작업 방식 2).
--            아래는 실제로 실행한 DO 블록 두 개.

-- ───────── ①② 오픈마켓 차단 ─────────
do $outer$
declare v_def text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_crm_targets_v2';
  if v_def is null then raise exception '함수 없음'; end if;
  v_new := v_def;

  v_n := (length(v_new) - length(replace(v_new,
    'where po.buyer_key = c.buyer_key and not coalesce(po.is_test,false)','')))
    / length('where po.buyer_key = c.buyer_key and not coalesce(po.is_test,false)');
  if v_n <> 1 then raise exception '① 지점 % 개', v_n; end if;
  v_new := replace(v_new,
    'where po.buyer_key = c.buyer_key and not coalesce(po.is_test,false)',
    'where po.buyer_key = c.buyer_key and not coalesce(po.is_test,false)'
    || E'\n                and coalesce(po.channel_type,'''') <> ''오픈마켓''');

  v_n := (length(v_new) - length(replace(v_new,
    '  if p_next_only then delete from _c where next_product is null; end if;','')))
    / length('  if p_next_only then delete from _c where next_product is null; end if;');
  if v_n <> 1 then raise exception '② 지점 % 개', v_n; end if;
  v_new := replace(v_new,
    '  if p_next_only then delete from _c where next_product is null; end if;',
    '  -- 오픈마켓(스마트스토어·쿠팡 등)에서만 알게 된 고객은 마케팅 발송에 쓸 수 없다.'
 || E'\n  -- 우리가 직접 받은 동의(자사몰 회원) 또는 자사몰·VMS·렌탈·매장 거래가 있어야 남긴다.'
 || E'\n  delete from _c t'
 || E'\n   where not coalesce((select cc.consent_marketing from crm.customer cc where cc.buyer_key = t.buyer_key), false)'
 || E'\n     and not exists (select 1 from core.orders ao'
 || E'\n                      where ao.buyer_key = t.buyer_key and not coalesce(ao.is_test,false)'
 || E'\n                        and coalesce(ao.channel_type,'''') <> ''오픈마켓'');'
 || E'\n  get diagnostics v_blocked = row_count;'
 || E'\n'
 || E'\n  if p_next_only then delete from _c where next_product is null; end if;');

  v_n := (length(v_new) - length(replace(v_new,
    'declare v jsonb; v_role text; v_lim int; v_total int;','')))
    / length('declare v jsonb; v_role text; v_lim int; v_total int;');
  if v_n <> 1 then raise exception '③ 지점 % 개', v_n; end if;
  v_new := replace(v_new,
    'declare v jsonb; v_role text; v_lim int; v_total int;',
    'declare v jsonb; v_role text; v_lim int; v_total int; v_blocked int := 0;');

  v_n := (length(v_new) - length(replace(v_new,
    '''never_sent'', (select count(*) from _c where last_sent is null),','')))
    / length('''never_sent'', (select count(*) from _c where last_sent is null),');
  if v_n <> 1 then raise exception '④ 지점 % 개', v_n; end if;
  v_new := replace(v_new,
    '''never_sent'', (select count(*) from _c where last_sent is null),',
    '''never_sent'', (select count(*) from _c where last_sent is null),'
 || E'\n      ''blocked_open'', v_blocked,');

  execute v_new;
end $outer$;

-- ───────── ③ 기준일 p_asof ─────────
do $outer$
declare v_def text; v_id text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid)
    into v_def, v_id
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_crm_targets_v2';
  v_new := v_def;

  v_n := (length(v_new) - length(replace(v_new, 'p_product text DEFAULT NULL::text)','')))
        / length('p_product text DEFAULT NULL::text)');
  if v_n <> 1 then raise exception '① 지점 % 개', v_n; end if;
  v_new := replace(v_new, 'p_product text DEFAULT NULL::text)',
                          'p_product text DEFAULT NULL::text, p_asof date DEFAULT NULL::date)');

  v_n := (length(v_new) - length(replace(v_new, '(now() at time zone ''Asia/Seoul'')::date','')))
        / length('(now() at time zone ''Asia/Seoul'')::date');
  if v_n <> 2 then raise exception '② 지점 % 개 (2 개여야 함)', v_n; end if;
  v_new := replace(v_new, '(now() at time zone ''Asia/Seoul'')::date',
                          'coalesce(p_asof, (now() at time zone ''Asia/Seoul'')::date)');

  v_n := (length(v_new) - length(replace(v_new, '''blocked_open'', v_blocked,','')))
        / length('''blocked_open'', v_blocked,');
  if v_n <> 1 then raise exception '③ 지점 % 개', v_n; end if;
  v_new := replace(v_new, '''blocked_open'', v_blocked,',
    '''blocked_open'', v_blocked,'
 || E'\n      ''asof'', coalesce(p_asof, (now() at time zone ''Asia/Seoul'')::date),');

  -- 기본값 인자를 더했으므로 옛 판을 먼저 내린다 (두 판이 남으면 호출이 모호해진다).
  -- DROP 은 pg_get_function_identity_arguments (기본값이 들어가면 문법 오류).
  execute format('drop function public.fn_crm_targets_v2(%s)', v_id);
  execute v_new;
  execute 'grant execute on function public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,int,numeric,int,boolean,int,text,int,int,boolean,boolean,text,text,date) to authenticated, service_role';
end $outer$;

-- ───────── 적용 뒤 숫자 (2026-09-15) ─────────
--   수신동의 고객        3,742 →  3,742  (동의는 자사몰 회원가입에서 나오므로 영향 거의 없음)
--   거래 재구매 주기       383 →    352  (오픈마켓에서만 산 31명 제외)
--   정수기 필터 HAF-     4,083 →    235  (자사몰 230 · VMS 5. 3~6개월 창으로 좁히면 53명)
--   건조기 필터 WD-FLTR    101 →     63
--   AI 콤보                248 →    123
--   토너·잉크           34,005 → 32,404  (대부분 VMS 거래처라 영향 작음)

-- ───────── ACL 주의 ─────────
-- drop → create 를 하면 함수 권한이 기본값(PUBLIC 에 EXECUTE)으로 돌아간다.
-- 함수 안에서 anon 을 막고 있긴 하지만 권한 자체를 회수해 둔다.
revoke all on function public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,int,numeric,int,boolean,int,text,int,int,boolean,boolean,text,text,date) from public, anon;
grant execute on function public.fn_crm_targets_v2(text,text,text,text,text,text,date,date,int,numeric,int,boolean,int,text,int,int,boolean,boolean,text,text,date) to authenticated, service_role;
