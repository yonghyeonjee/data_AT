-- mvp_276 · 2026-11-04 — 상담 견적 통합 화면 (/quote/) : 구독 계산기 + 견적서 + 혼수/입주/이사 일시불 계산을 데이터센터 한 화면으로
--  ① core.f_quote_page_ok — 견적서 RPC(fn_quote_page_save/list/get/customer/share · fn_quote_nc_*)를 담당자 세션(x-dc-session)으로도 통과시킨다.
--     고도몰 견적서 페이지의 보안 코드(quote_page_code_hash)는 그대로 둔다 — 두 길이 같이 열린다.
--  ② public.fn_quote_page_me(p_code) — 화면이 "누구로 열렸나"를 묻는다 ({ok, me, by:'session'|'code'}).
--  ③ sub.policy 'lump' — 일시불(삼성카드 플러스페이 6/12 · 장기할부) 혜택 구간표. 엑셀 '6-12 할부_조건부' 시트(2026-09 판)를 옮긴 것.
--     금액 구간은 [하한, 값] 내림차순 · 값이 "2%" 처럼 문자열이면 결제액의 비율. 본사 표가 바뀌면 이 행만 고친다 (관리자 화면 정책 편집은 다음 판).
--  ④ sub.f_policy_export 에 'lump' 추가 → sdp/sub/sub_policy.js (SUB_POLICY.lump) 로 배포된다.

-- ① 담당자 세션도 통과
create or replace function core.f_quote_page_ok(p_code text) returns boolean
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select encode(extensions.digest(coalesce(p_code,''), 'sha256'), 'hex') = coalesce((select value from core.app_setting where key = 'quote_page_code_hash'), 'x')
      or exists (select 1 from core.staff_session s
                  where s.token_hash = core.f_store_tok_hash() and s.revoked_at is null and s.expires_at > now());
$$;
revoke all on function core.f_quote_page_ok(text) from public;

-- 세션의 담당자 이름 (없으면 null)
create or replace function core.f_quote_page_me() returns text
language sql stable security definer set search_path to 'pg_catalog','public' as $$
  select s.staff from core.staff_session s
   where s.token_hash = core.f_store_tok_hash() and s.revoked_at is null and s.expires_at > now()
   order by s.created_at desc limit 1;
$$;
revoke all on function core.f_quote_page_me() from public;

-- ② 화면 부팅: 누구로 열렸나
create or replace function public.fn_quote_page_me(p_code text default null) returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_quote_page_me();
begin
  if v_me is not null then
    update core.staff_session set last_seen = now() where token_hash = core.f_store_tok_hash() and revoked_at is null;
    return jsonb_build_object('ok', true, 'me', v_me, 'by', 'session');
  end if;
  if core.f_quote_page_ok(p_code) then return jsonb_build_object('ok', true, 'me', null, 'by', 'code'); end if;
  perform pg_sleep(0.7);
  return jsonb_build_object('ok', false, 'mode', case when core.f_store_session_mode() then 'session' else 'code' end);
end $$;
grant execute on function public.fn_quote_page_me(text) to anon, authenticated, service_role;

-- ③ 일시불 혜택 구간표 (엑셀 6-12 할부_조건부 · 삼성카드장기무이자 시트)
insert into sub.policy (key, value, note, updated_by) values
('lump', $j$
{
  "name": "일시불 카드 혜택",
  "note": "엑셀 '6-12 할부_조건부'(2026-09) 기준 · 금액 구간은 [하한, 값] 내림차순 · 값이 \"2%\" 면 결제액 비율",
  "cards": {
    "베네핏": {"label": "삼성카드 베네핏(제휴)", "plus": true,  "cashback": true},
    "일반":   {"label": "일반 삼성카드",          "plus": true,  "cashback": false},
    "없음":   {"label": "현금 · 타카드",          "plus": false, "cashback": false}
  },
  "months": [6, 12, 24, 36],
  "fee": {"6": 0.015, "12": 0.03, "24": 0, "36": 0},
  "billDisc": {
    "6":  [[5000000, "2%"], [3000000, 100000], [2000000, 60000], [1000000, 40000]],
    "12": [[5000000, "2%"], [3000000, 100000], [2000000, 60000], [1000000, 40000]]
  },
  "billDiscNote": "DPS 시뮬레이션(2026-11-04, 더미고객 9999999999) 결과: 12개월도 6개월과 같은 표 — 250만→6만 · 150만→4만. 엑셀 12개월 표(200만→10만 · 100만→5만)는 DPS와 달라 DPS 값을 채택",
  "dpsVerified": "2026-11-04 시뮬 7회: 1,000만 6/12개월 S포인트 40만·청구할인 20만 · 610만 20만·12.2만 · 350만 8만·10만 · 250만 6만·6만 · 150만(12개월) 4만·4만 — sPoint·billDisc 모두 일치. 혼수포인트는 더미고객이 혼수그룹 미가입이라 0 (정책표 390253으로 확인)",
  "sPoint": [[20000000, 800000], [15000000, 600000], [10000000, 400000], [7000000, 280000], [5000000, 200000], [4000000, 120000], [3000000, 80000], [2000000, 60000], [1000000, 40000]],
  "sPointNote": "'6-12 할부_조건부'!H16 수식 그대로 (2026-11-04 점장님 견적서 판으로 재확인) · DPS 월별 정책 목록에는 없고 시뮬레이션 결과에만 나오는 값",
  "formula": {
    "fee": "결제가 × 이용율 (100만 미만 0) — 6개월 1회 청구, 12개월 2회 분할",
    "billDisc": "결제가 구간 → 청구할인 (500만 이상은 2%)",
    "cashback": "캐시백(송금) = 금액별 S포인트(sPoint) + 제품별 S포인트(J.POINT = DPS 모델별 포인트 합, 수기) + 유형 포인트(typePoint)",
    "benefit": "혜택가 = (결제가 − 청구할인 + 이용료) − 캐시백(송금)",
    "final": "최종체감가 = 혜택가 − 조건부 캐시백 − 추가 혜택 줄(로열등급·삼성카드몰 쿠폰·신세계상품권·주유상품권·IPTV·웨딩마일리지 등 수기)",
    "verified": "2026-11-04 엑셀 예시 610만(혜택가 4,859,500 · 최종 4,109,500) · 1,000만(7,890,000 · 6,840,000) 재현 확인"
  },
  "extras": ["로열등급 (설치 후 차차월 현금 입금)", "삼성카드몰 쇼핑몰 쿠폰 (제휴카드) 차차월 15일", "신세계 상품권 (차차월 이후 택배)", "주유 상품권 (차차월 이후 택배)", "IPTV (SKB 500M↑+IPTV 가입 조건) 선택", "구독 30만원 적용 시 (72개월 지원) 선택", "웨딩마일리지 3개월 적용 시 (결제 1,000만 이상) 선택"],
  "typePoint": {
    "혼수": [[25000000, 1200000], [20000000, 900000], [15000000, 750000], [12000000, 600000], [9000000, 450000], [6000000, 300000]],
    "입주": [[25000000, 1200000], [20000000, 900000], [15000000, 750000], [12000000, 600000], [9000000, 450000], [6000000, 300000]],
    "이사": [[20000000, 600000], [12000000, 300000], [9000000, 150000]]
  },
  "cashback": {
    "6":  [[25000000, 500000], [15000000, 300000], [7000000, 200000], [5000000, 100000], [1000000, 50000]],
    "12": [[20000000, 250000], [15000000, 200000], [10000000, 170000], [3000000, 100000], [1000000, 50000]]
  },
  "cashbackCond": "조건부 캐시백 — 베네핏(삼성스토어·N페이) 카드로 차월 50만원 이상 1회 이용 시, 1회만 ('6-12 할부_조건부'!H18·H27)",
  "member": 0.001,
  "notes": [
    "삼성카드 베네핏(제휴) 발급 후 6/12개월 플러스페이 결제 기준입니다.",
    "캐시백은 결제 익월 말일 처리 후 차차월 5일 입금됩니다.",
    "혼수·입주 포인트는 증빙 승인 후 지급됩니다.",
    "삼성전자 멤버십 가입이 필요합니다."
  ]
}
$j$::jsonb, '일시불(플러스페이 6/12 · 장기할부) 혜택 구간표 — 상담 견적 화면(/quote/)이 읽는다', 'mvp_276')
on conflict (key) do nothing;

-- ④ 배포에 'lump' 포함 (2026-11-04 DB 판 = mvp_265 malls·promosAll + mvp_273 multi 에 lump 한 줄)
create or replace function sub.f_policy_export()
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $$
  with p as (select key, value from sub.policy)
  select jsonb_strip_nulls(jsonb_build_object(
    'ver', sub.f_policy_ver(),
    'defaults', (select value from p where key = 'defaults'),
    'autopay', (select value from p where key = 'autopay'),
    'prepay',  (select value from p where key = 'prepay'),
    'texts',   (select value from p where key = 'texts'),
    'lump',    (select value from p where key = 'lump'),
    'cardNotes', coalesce((select value from p where key = 'card_notes'), '[]'::jsonb),
    'cards', (select coalesce(jsonb_object_agg(card, jsonb_strip_nulls(jsonb_build_object(
                'notes', case when cardinality(notes) > 0 then to_jsonb(notes) end,
                'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'), 'hidden', case when hidden then true end))), '{}'::jsonb)
              from sub.card_policy),
    'promos', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                'text', text, 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                'cats', case when cardinality(cats) > 0 then to_jsonb(cats) end,
                'models', case when cardinality(models) > 0 then to_jsonb(models) end,
                'goods', case when cardinality(goods) > 0 then to_jsonb(goods) end,
                'malls', case when cardinality(malls) > 0 then to_jsonb(malls) end,
                'months', months, 'amount', amount, 'amounts', amounts,
                'maxTerm', case when (months is not null or amount is not null or amounts is not null) and not max_term_only then false end)) order by sort, id), '[]'::jsonb)
               from sub.promo where active and (to_d is null or to_d >= (now() at time zone 'Asia/Seoul')::date - 1)
                 and (cardinality(malls) = 0 or 'sh' = any(malls))),
    'promosAll', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                'text', text, 'from', to_char(from_d,'YYYY-MM-DD'), 'to', to_char(to_d,'YYYY-MM-DD'),
                'cats', case when cardinality(cats) > 0 then to_jsonb(cats) end,
                'models', case when cardinality(models) > 0 then to_jsonb(models) end,
                'goods', case when cardinality(goods) > 0 then to_jsonb(goods) end,
                'malls', case when cardinality(malls) > 0 then to_jsonb(malls) end,
                'months', months, 'amount', amount, 'amounts', amounts,
                'maxTerm', case when (months is not null or amount is not null or amounts is not null) and not max_term_only then false end)) order by sort, id), '[]'::jsonb)
               from sub.promo where active and (to_d is null or to_d >= (now() at time zone 'Asia/Seoul')::date - 1)),
    'points', sub.f_point_export(),
    'multi', (select value from p where key = 'multi'),
    'bundle', sub.f_bundle_export(),
    'overrides', sub.f_price_override_live()));
$$;

-- 확인
-- select key, value->>'name', updated_by from sub.policy where key = 'lump';
-- select jsonb_pretty(sub.f_policy_export()->'lump');
-- select public.fn_quote_page_me(null);   -- 세션 없이: {"ok": false, "mode": ...}
