-- mvp_177 · 이카운트 판매현황의 '오픈마켓' 전표가 VMS 로 들어와 온라인 매출이 이중 계상되던 것 (2026-09-22)
-- "VMS 에 냉장고 이런 게 왜 있지? 이카운트에서 VMS 인 것만 가져온 것 맞지?"
--
-- 진단 : 이카운트 판매현황 업로드(mapRows ecount_sales)는 VMS 필터 없이 파일 전체를 channel VMS 로 넣는다. 2020~2026-08 초까지의 파일은 영업담당이
--   택배·오토바이(퀵)·이정우·오영환·고병재·김성욱… = 전부 소모품 통신판매라 문제가 없었는데, 9/18 에 올린 판매현황_0918.xlsx(upload 383~391) 에
--   영업담당 '오픈마켓' 전표가 섞여 있었다 — 2026-08-31 자 온라인 몰 월 마감 전표 2,561줄 · 7.15억 (프라자몰 1.69억 · SSG 1.35억 · 스마트스토어 B2B 1.28억 · 쿠팡 1.02억 · 에스몰 0.66억 · 시흥몰 0.54억 · 스마트스토어 AT 0.37억 …).
--   같은 매출이 샵링커 원장(2026-08 P몰 2.93억 · SSG 1.58억 · 쿠팡 1.34억 · B2B 1.27억 · S몰 0.70억 · 시흥몰 0.61억)에 이미 있어 이중 계상이고, VMS 카테고리에 냉장고·세탁기·TV 가 보인 것도 이 줄들이다.
--   2020·2022·2023 의 '오픈마켓' 25줄(150만원)도 같은 성격.
-- 1) 정리 : notes '영업:오픈마켓%' 인 ecount 줄 2,586 · 7.17억 → core.orders_ecount_openmarket_20260922 에 두고 삭제. core.dash_cache 비움. 남은 VMS 대물은 박은지 B2B 5줄(케이모텔 세탁기 등 — 정상).
-- 2) 재발 방지 : core.f_orders_bulk_upsert 가 p_source='ecount' 이고 notes 가 '영업:오픈마켓' 로 시작하면 건너뛴다 (응답 '오픈마켓제외'). 화면 mapRows 도 같은 줄을 빼고 미리보기에 "오픈마켓 전표 N줄은 제외" 안내(ecountGuard).
create table if not exists core.orders_ecount_openmarket_20260922 as
select * from core.orders where source in ('ecount','ecount_sales') and notes like '영업:오픈마켓%';
delete from core.orders where id in (select id from core.orders_ecount_openmarket_20260922);
delete from core.dash_cache where true;
do $outer$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='core' and p.proname='f_orders_bulk_upsert';
  if position('v_n int := 0; v_noKey int := 0; v_dup int := 0;' in v_def) = 0 then raise exception '지점 없음 1'; end if;
  if position('/* 샵링커 파일 줄이 API 수집으로 이미 들어온 줄' in v_def) = 0 then raise exception '지점 없음 2'; end if;
  if position('''중복건너뜀'', v_dup);' in v_def) = 0 then raise exception '지점 없음 3'; end if;
  v_def := replace(v_def, 'v_n int := 0; v_noKey int := 0; v_dup int := 0;', 'v_n int := 0; v_noKey int := 0; v_dup int := 0; v_open int := 0;');
  v_def := replace(v_def, '/* 샵링커 파일 줄이 API 수집으로 이미 들어온 줄',
    '/* 이카운트 판매현황의 영업담당 ''오픈마켓'' 전표는 온라인 몰 매출(월 마감)이라 샵링커 원장과 겹친다 — VMS 로 넣지 않는다 (mvp_177) */
    if p_source = ''ecount'' and coalesce(r->>''notes'','''') like ''영업:오픈마켓%'' then v_open := v_open + 1; continue; end if;
    /* 샵링커 파일 줄이 API 수집으로 이미 들어온 줄');
  v_def := replace(v_def, '''중복건너뜀'', v_dup);', '''중복건너뜀'', v_dup, ''오픈마켓제외'', v_open);');
  execute v_def;
end $outer$;
-- 결과 : removed 2586 · 716,660,124원 · VMS 대물 남은 것 5줄(B2B)
