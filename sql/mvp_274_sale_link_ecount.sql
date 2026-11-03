-- mvp_274 (2026-11-03) — 판매 확인 필요: VMS·B2B·렌탈(매장 외) 상담은 이카운트 판매도 찾는다 · [판매 다시 맞추기] 가 상담에 'sold' 를 다시 걸지 않게
-- 계기: 박은지 판매 확인 필요에 이소명(#55, web_b2b B-0009 · 상담 08/22 · 메모 'K515,Y515 구매하심') 이 '판매를 못 찾았습니다' 로 떠 있었다.
--   실제로는 이카운트(VMS) 판매 20260825-1 (박은지 · CLT-K515S + CLT-Y515S · 14만) 가 있었는데, 맞추는 규칙이 DPS·매장 판매(source dps·store)만 봤다.
--   또 화면 [DPS 다시 맞추기] 가 목록 첫 줄에 p_action 'sold' 를 걸어 그 상담에 '판매 완료 (일시불) 11-03 16:42 박은지' 메모가 붙었다 (지움).
-- ① core.f_consult_link_sales: o.source in ('dps','store','ecount') + k.outx = core.f_consult_scope(channel_code, source)='out' 일 때만 ecount 와 잇는다
--    (매장 상담이 같은 사람의 토너 주문에 잘못 이어지지 않게) · 메모 '이카운트 판매 YYYY-MM-DD 에 이어짐'
-- ② public.fn_store_sale_candidates: 같은 규칙 · 응답에 'out'
-- ③ public.fn_store_sale_relink(p_code) 새로 — core.f_staff 확인 뒤 core.f_consult_link_sales(120) · 메모 안 남김 · anon/authenticated/service_role
-- 적용: 서버 prosrc 를 읽어 지점 수(각 1개) 검증 뒤 replace → execute (CLAUDE.md 규칙 2). 미리 돌려 보니(롤백) 새로 이어지는 상담은 #55 하나뿐 → 실제 적용 · #55 = 주문 59949.
-- 화면(store.html·store/test): 판매 확인 필요 줄 [판매 아님] (p_action 'done' = 종료 · 서버가 sale_kind·연결을 비움) · [판매 다시 맞추기] → fn_store_sale_relink ·
--   'DPS 판매/이카운트 판매/판매 입력' 표기 skSrcNm · 안내 '판매 내역(DPS·이카운트)에서 … 판매가 아니었으면 [판매 아님]'.
-- 테스트 ptest/saledone.mjs +S12~S14 = 53/53 × test·본.

-- ① 지점 (원본 → 새)
--   where o.source in ('dps','store') and            → where o.source in ('dps','store','ecount') and
--   ...,'') d8\n      from crm.consult c              → ...,'') d8,\n (core.f_consult_scope(c.channel_code, c.source) = 'out') outx\n from crm.consult c
--   and o.order_at between k.consult_at - interval '7 days'  → and (o.source <> 'ecount' or k.outx) and o.order_at between ...
--   case when m1.src='dps' then 'DPS 판매 ' else '판매 입력 ' end → + when m1.src='ecount' then '이카운트 판매 '
-- ② where o.source in ('dps','store') and → where o.source in ('dps','store','ecount') and (o.source <> 'ecount' or core.f_consult_scope(k.channel_code, k.source) = 'out') and
--    return jsonb_build_object('ok', true, 'id', p_id, → + 'out', core.f_consult_scope(k.channel_code, k.source) = 'out',

create or replace function public.fn_store_sale_relink(p_code text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return core.f_consult_link_sales(120);
end $f$;
revoke all on function public.fn_store_sale_relink(text) from public;
grant execute on function public.fn_store_sale_relink(text) to anon, authenticated, service_role;
