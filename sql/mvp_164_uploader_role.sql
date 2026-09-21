-- mvp_164 · 2026-09-21 · 업로드 전용 계정 (role 'uploader')
-- ① profiles_role_check 에 'uploader' 추가
-- ② 적재 함수 13개의 f_role() 검사 줄에 'uploader' 허용 (pg_get_functiondef 치환, 지점 1개씩 검증)
--    fn_orders_bulk_upsert · fn_consults_bulk_upsert · fn_customers_bulk_upsert · fn_sl_refund_apply · fn_ec_customers_upsert  (<> 'admin' → not in ('admin','uploader'))
--    fn_channel_daily_upsert · fn_settlement_upsert · fn_listing_request_upsert · fn_inv_items_upsert · fn_utm_campaigns  (not in ('admin','user') → +uploader)
--    fn_send_log_import · fn_unpaid_upsert (not in ('admin','staff') → +uploader) · fn_sub_plan_upsert (not in ('admin','dev') → +uploader)
--    되돌리기 fn_upload_rollback · 설정 · 주문 · CRM 추출은 admin 그대로
-- ③ auth.users + auth.identities 에 dbuploader@samsungat.local 생성(extensions.crypt bf) → 트리거로 profiles(role uploader, handler_name '업로드 전용')
-- ④ core.menu_access: home·upload 빼고 전부 숨김
-- 비밀번호는 여기 적지 않는다. 바꾸려면: update auth.users set encrypted_password = extensions.crypt('새값', extensions.gen_salt('bf')) where email='dbuploader@samsungat.local';
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role = any (array['admin','analyst','send','user','uploader']));
-- (함수 치환·계정 생성 본문은 세션 기록 — 위 요약대로 적용됨)
