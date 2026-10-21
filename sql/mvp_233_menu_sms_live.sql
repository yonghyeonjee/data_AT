-- mvp_233 · 2026-10-21 · 메시지 발송 관리 '개발 중' → 공개 — "메시지 발송관리도 이제 개발중 빼고 현행으로 돌리자"
update core.menu_item set state = 'on', updated_at = now() where code = 'sms';
-- 같은 판(v223) 화면: 관리자 메뉴 묶음 아코디언 (admin.html renderNav · DB 변경 없음)
