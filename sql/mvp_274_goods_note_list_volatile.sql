-- mvp_274 (2026-11-03) 상품 안내 문구 · 스마트 패키지 목록 "cannot execute UPDATE in a read-only transaction"
-- 세션 로그인(mvp_256)에서 core.f_staff 가 staff_session.last_seen 을 UPDATE 하는데, 두 목록 함수가 stable 이라 읽기 전용으로 돌아 막혔다.
-- core.f_staff 를 부르는 매장 함수는 volatile 이어야 한다 (남은 stable 매장 함수 없음 확인).
alter function public.fn_store_goods_note_list(text) volatile;
alter function public.fn_store_spkg_conf_list(text) volatile;
