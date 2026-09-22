-- mvp_172 · 2026-09-22 · 고도몰 주문 원본 파일 업로드 (P·AT·S몰)
-- "p, at, s몰은 나중에 파일로 업로드 할거야 / CRM에 필요한것만 파싱해서 들어갈 수 있겠지?"
--
-- ① core.f_godo_order_hist_put : 해시(row_hash)가 비어 오면 서버가 만든다.
--    exe 는 지금대로 sha1(몰|주문번호|상품번호|줄번호) 를 직접 보내고(규격 그대로),
--    관리자 업로드 화면은 브라우저에서 sha1 을 만들 수 없어 h 없이 보낸다 → 같은 규칙으로 서버가 계산.
--    같은 파일을 다시 올려도 on conflict do nothing 으로 중복되지 않는다.
do $outer$
declare v_src text; v_args text; v_n int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='core'
   where p.proname='f_godo_order_hist_put';

  v_n := (length(v_src) - length(replace(v_src, 'select r->>''h'', p_mall', ''))) / length('select r->>''h'', p_mall');
  if v_n <> 1 then raise exception '지점 ① 없음 (%)', v_n; end if;
  v_src := replace(v_src,
    'select r->>''h'', p_mall',
    'select coalesce(nullif(r->>''h'',''''), encode(extensions.digest(p_mall||''|''||coalesce(r->>''order_no'','''')||''|''||coalesce(r->''data''->>''상품번호'','''')||''|''||coalesce(r->''data''->>''줄번호'',''''), ''sha1''), ''hex'')), p_mall');

  v_n := (length(v_src) - length(replace(v_src, 'where coalesce(r->>''h'','''') <> ''''', ''))) / length('where coalesce(r->>''h'','''') <> ''''');
  if v_n <> 1 then raise exception '지점 ② 없음 (%)', v_n; end if;
  v_src := replace(v_src,
    'where coalesce(r->>''h'','''') <> ''''',
    'where coalesce(nullif(r->>''h'',''''), nullif(r->>''order_no'','''')) is not null');

  execute format('create or replace function core.f_godo_order_hist_put(%s) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'',''extensions'' as %L', v_args, v_src);
end $outer$;

-- ② 데이터 소스 한 줄 (감시는 끔 — 필요할 때만 올리는 원천)
insert into core.data_source (key, label, owner, expect_days, how, sort_no, active, alert, auto_plan)
values ('godo_order', '고도몰 주문 원본 (P·AT·S몰)', '온라인사업부', 90,
        '고도몰 관리자 → 주문 내려받기(엑셀) → 데이터 가져오기에서 몰을 고르고 올린다. 시흥몰은 OpenAPI 로 자동 수집(godo-orders.yml).',
        72, true, false,
        '시흥몰처럼 OpenAPI 키를 받으면 자동 수집으로 옮길 수 있다. 지금은 P·AT·S몰만 파일.')
on conflict (key) do update set label=excluded.label, how=excluded.how, owner=excluded.owner,
  expect_days=excluded.expect_days, sort_no=excluded.sort_no, active=true, alert=excluded.alert, auto_plan=excluded.auto_plan;

-- 화면(admin.html) : detect 'godo_order'(열 '자체상품코드') · mapRows 매핑 · 몰 선택 필수 · fn_godo_order_hist_upsert 500줄씩.
-- 저장하는 칸(시흥몰 OpenAPI 와 같은 이름) : 주문번호 주문일자 결제일자 주문상태 결제금액 총상품금액 배송비 결제수단 환불금액
--   회원ID 회원명 주문자명 주문자휴대폰 주문자전화 이메일 배송지역(시·군·구까지) 상품번호 상품코드 모델명 상품명 옵션 수량
--   상품가격 정가 카테고리 상품주문번호 품목상태 취소일 줄번호
-- 버리는 칸 : 예치금·마일리지 전부 · PG 3열 · 입금계좌·입금자·영수증 · 배송업체·송장·배송일자 · 사은품 · 수수료율·매입가
--   · 브랜드·제조사·원산지 · 텍스트옵션 · 수취인 이름/전화/우편번호/나머지 주소 · 주문시 남기는 글 · 환불 세부 · 클레임 사유·수량 · 모바일앱 할인
