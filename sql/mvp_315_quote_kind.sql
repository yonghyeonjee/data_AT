-- mvp_315 · 2026-11-23 · 견적 구분 — 기존 견적서 페이지 / 상담 견적(/quote/) (적용 기록)
-- "견적은 기존과 new를 구분해줘야해"
--
-- /quote/(상담 견적)는 quote.meta.page = 'dc-quote' 로 저장한다. 기존 시흥몰 견적서 페이지와 quote/sheet 편집 저장분은 표시가 없다.
-- sheet 에서 고쳐 저장한 다음 차수는 표시가 빠지므로 '견적번호의 어느 차수든 dc-quote 였으면 new' 로 본다.

create or replace function core.f_quote_kind(p_no text) returns text language sql stable set search_path to 'pg_catalog','public' as $f$
  select case when exists (select 1 from crm.quote z where z.quote_no = p_no and z.quote->'meta'->>'page' = 'dc-quote') then 'new' else 'old' end
$f$;

-- 응답에 kind 추가 (서버 원본을 읽어 부분 치환 · 원문 백업 core.fn_src_backup tag 'before mvp_315')
--   fn_store_quotes          : … 'until', q.summary->>'until', 'kind', core.f_quote_kind(q.quote_no), 'items', …
--   fn_store_consults_my     : quotes[] 줄 끝 'counselor', q.counselor, 'kind', core.f_quote_kind(q.quote_no)  ·  quote 한 줄에도 'kind'
--   fn_store_consult_detail  : quotes[] 줄 끝에 'kind'
-- 화면(store.html · store/test): 태그 [상담 견적]·[기존] · 견적서 화면 거르개 · [열기 ↗] 는 만든 화면으로
