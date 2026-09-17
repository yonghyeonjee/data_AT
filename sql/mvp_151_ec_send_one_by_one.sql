-- mvp_151 (2026-09-17) — 이카운트 전송 "성공 0장 · 실패 20장 · 서버 응답이 늦습니다"
--
-- 무슨 일이었나
--   core.f_order_send 는 받은 전표를 한 문장(한 트랜잭션) 안에서 순서대로 이카운트에 보낸다.
--   그런데 core.f_ec_call 은 이카운트 호출 제한 때문에 호출 사이에 1.2초를 쉰다(pg_sleep) + 왕복 0.3~0.5초.
--   담당자 화면 RPC 는 anon 이라 statement_timeout 이 3초 → 두 장쯤 보내다 57014 로 문장 전체가 롤백.
--   16장·20장이 전부 status='ready', try_count=0 으로 남은 이유다(시도 자체가 기록되지 않았다).
--
-- 더 나쁜 것
--   롤백은 DB 만 되돌린다. 이미 나간 HTTP(이카운트 SaveSaleOrder)는 돌아오지 않는다.
--   → 이카운트에는 전표가 생겼는데 우리 쪽엔 '대기' 로 남는다. ec.api_log 도 같은 문장 안이라 같이 사라져 흔적이 없다.
--   게다가 화면 rpc() 가 "타임아웃은 롤백되니 다시 보내도 안전하다" 며 두 번 더 보낸다 → 클릭 한 번에 3번 시도.
--   f_order_send 는 io_date, id 순으로 돌므로 매번 같은 첫 한두 장이 나간다:
--     #13 2026090889A80F(SSG·송영선) · #10 2609110917059486(S몰·윤만수) · (#11 2609111600186878 P몰·박다혜)
--   9/17 두 번의 클릭 × 최대 3회 시도 → 이 전표들이 이카운트에 여러 장 있을 수 있다. 이카운트에서 눈으로 확인해 지워야 한다.
--   (이카운트 OpenAPI 에 판매주문 '조회' 가 없어 우리 쪽에서 확인할 수 없다 — ec.api_def 참고)
--
-- 고친 것
--   서버 (아래) — 시간 예산 1.0초. 예산을 넘긴 뒤에는 새 전표를 시작하지 않고 remaining 으로 돌려준다.
--   화면 — ecSend 가 한 장씩 보낸다(장 사이 1.3초는 화면이 둔다). rpc() 는 order_send 를 절대 재시도하지 않는다(RPC_NO_RETRY).
--          관리자 [전체 전송] 은 id 목록을 먼저 받아 한 장씩. 테스트 ptest/ecsend.mjs E1~E7 · A1~A2.
--
-- 적용은 본문을 옮겨 적지 않고 pg_get_functiondef 를 읽어 부분만 치환 (CLAUDE.md 작업 방식 2).
do $outer$
declare v_def text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core'
   where p.proname='f_order_send';
  if v_def is null then raise exception '함수 없음'; end if;
  v_new := v_def;

  v_n := (length(v_new) - length(replace(v_new,
    'declare q record; v_body jsonb; v_res jsonb; n_ok int := 0; n_fail int := 0; det jsonb := ''[]''::jsonb; v_msg text; v_slip text; v_ok boolean; v_d jsonb;','')))
    / length('declare q record; v_body jsonb; v_res jsonb; n_ok int := 0; n_fail int := 0; det jsonb := ''[]''::jsonb; v_msg text; v_slip text; v_ok boolean; v_d jsonb;');
  if v_n <> 1 then raise exception '① 지점 % 개', v_n; end if;
  v_new := replace(v_new,
    'declare q record; v_body jsonb; v_res jsonb; n_ok int := 0; n_fail int := 0; det jsonb := ''[]''::jsonb; v_msg text; v_slip text; v_ok boolean; v_d jsonb;',
    'declare q record; v_body jsonb; v_res jsonb; n_ok int := 0; n_fail int := 0; det jsonb := ''[]''::jsonb; v_msg text; v_slip text; v_ok boolean; v_d jsonb;'
 || E'\n        v_start timestamptz := clock_timestamp(); v_rest bigint[] := ''{}'';   /* 시간 예산 — 호출자의 statement_timeout 안에 끝내야 한다 (mvp_151) */');

  v_n := (length(v_new) - length(replace(v_new, '    v_body := core.f_order_body(q.id);','')))
        / length('    v_body := core.f_order_body(q.id);');
  if v_n <> 1 then raise exception '② 지점 % 개', v_n; end if;
  v_new := replace(v_new, '    v_body := core.f_order_body(q.id);',
    '    /* 이카운트 호출은 한 장에 1.2초 간격 + 왕복이라, 담당자 화면(anon 3초) 안에는 한두 장만 들어간다.'
 || E'\n       예산을 넘긴 채 다음 장을 시작하면 문장이 타임아웃으로 롤백되는데, 이미 나간 HTTP 는 되돌아오지 않아'
 || E'\n       이카운트에는 전표가 생기고 우리 쪽엔 기록이 없는 상태(중복 위험)가 된다. 그래서 남은 건은 손대지 않고 돌려준다. */'
 || E'\n    if clock_timestamp() - v_start > interval ''1.0 second'' then v_rest := v_rest || q.id; continue; end if;'
 || E'\n    v_body := core.f_order_body(q.id);');

  v_n := (length(v_new) - length(replace(v_new,
    '  return jsonb_build_object(''ok'', n_fail = 0, ''sent'', n_ok, ''failed'', n_fail, ''by'', p_by, ''detail'', det);','')))
    / length('  return jsonb_build_object(''ok'', n_fail = 0, ''sent'', n_ok, ''failed'', n_fail, ''by'', p_by, ''detail'', det);');
  if v_n <> 1 then raise exception '③ 지점 % 개', v_n; end if;
  v_new := replace(v_new,
    '  return jsonb_build_object(''ok'', n_fail = 0, ''sent'', n_ok, ''failed'', n_fail, ''by'', p_by, ''detail'', det);',
    '  return jsonb_build_object(''ok'', n_fail = 0 and coalesce(array_length(v_rest,1),0) = 0, ''sent'', n_ok, ''failed'', n_fail, ''by'', p_by, ''detail'', det,'
 || E'\n                            ''remaining'', to_jsonb(v_rest));   /* 이번 호출에서 손대지 않은 전표 — 화면이 이어서 보낸다 */');

  execute v_new;
end $outer$;

-- 남은 숙제: ec.api_log 도 같은 문장 안에서 쓰므로 롤백되면 호출 흔적이 사라진다.
--            바깥으로 나간 호출 기록은 자기호출(extensions.http → PostgREST)로 따로 커밋해야 한다 (CLAUDE.md 함정).
