-- mvp_136 · 2026-09-14 — 고객 견적서(/q/) 전화 버튼에 담당 휴대폰이 나오게
-- fn_quote_public 은 core.namecard(견적 opt.namecardId → 이름) → core.staff.mobile → 매장 번호 순으로 고른다.
-- core.namecard 에 카드가 없으면 매장 번호로 떨어지므로 ① 지용현 카드를 직접 넣고 ② fn_submit_quote 가 payload.namecard 를 upsert 하게 했다
--    (견적내역 GAS dcForwardQuote_ 가 네임카드 탭에서 찾아 같이 보낸다 — tools/gas/quote_forward.gs).
insert into core.namecard (id, name, position, dept, store, mobile, tel, email, addr, updated_at)
values ('NC1788421248760', '지용현', '프로', '온라인/test', '삼성스토어 시흥', '010-2101-9986', '031-8042-3166', 'test@test.com', '경기도 시흥시 서해안로1685번길 12 (대야동)', now())
on conflict (id) do nothing;
update core.staff set mobile = '010-2101-9986', updated_at = now() where name = '지용현' and coalesce(mobile,'') = '';
-- fn_submit_quote 패치: '견적번호가 없습니다' 검사 직후에 아래 블록 삽입 (지점 1개 확인 뒤 replace)
--   if p_data->'namecard'->>'id' 와 ->>'name' 이 있으면 core.namecard upsert(id 기준, 빈 값은 기존 유지) + staff.mobile 이 비었으면 채움
