-- mvp_309 · 2026-11-23 · 관리자 '설정 한 곳' (메뉴 개편안 2단계 · 적용 기록)
-- 사이드바 맨 아래 [설정] 한 줄 — 설정·옵션·알림 화면(settings·option·notify)과 문자 발송의 설정·계정, 캠페인의 단축 링크 주소를
-- 화면 위 '설정 탭'(담당자·계정 / 문의 자동 배정 / 잔디 알림 / 외부 연동 / 담당자 화면)으로 묶었다. 화면 코드는 그대로(SET_HUB · admin.html v361).
-- DB 는 이름 하나만: menu_item settings 의 이름 '담당자·배정' → '설정'. option·notify 는 'on' 그대로 둔다 —
-- 사이드바에서 숨기는 건 화면(SET_VIEWS)이고, 계정별 메뉴 숨김(menu_access)·주소(#option)는 전처럼 돈다.
-- 되돌리기: update core.menu_item set label='담당자·배정', updated_at=now() where code='settings';

update core.menu_item set label = '설정', updated_at = now() where code = 'settings';
