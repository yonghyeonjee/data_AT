-- mvp_42: 2026-09-04 수정 2건

-- (1) Supabase 는 API 롤에 safeupdate 를 로드해 WHERE 없는 DELETE 를 막는다.
--     core.f_dash_payload 의 임시테이블 비우기(delete from _x;) 가 여기 걸려
--     콘솔은 "DELETE requires a WHERE clause", /dash 는 400 을 뱉었다 → truncate 로 교체.
do $$
declare src text;
begin
  select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='core' and p.proname='f_dash_payload';
  src := regexp_replace(src, 'delete\s+from\s+(_[a-z0-9_]+)\s*;', 'truncate \1;', 'gi');
  execute src;
end $$;

-- (2) 이카운트 거래처코드 마스터 기준으로 스마트스토어 3계정 매핑 정정
--     samsung_pmall           = 스마트스토어 P몰(B2B몰)   → B2B      (기존 E스토어 ✗)
--     samsungat@naver.com     = 스마트스토어 at몰(E스토어) → E스토어  (기존 B2B스토어 ✗)
--     samsungshmall@naver.com = 스마트스토어 가전시장      → 가전시장 (기존 시흥스토어 ✗)
update core.sl_channel_map set channel_name='B2B'    where mall_name='스마트스토어' and seller_admin_id='samsung_pmall';
update core.sl_channel_map set channel_name='E스토어'  where mall_name='스마트스토어' and seller_admin_id='samsungat@naver.com';
update core.sl_channel_map set channel_name='가전시장' where mall_name='스마트스토어' and seller_admin_id='samsungshmall@naver.com';
update core.orders set channel_name='B2B'    where source='shoplinker' and channel_account='samsung_pmall';
update core.orders set channel_name='E스토어'  where source='shoplinker' and channel_account='samsungat@naver.com' and channel_name='B2B스토어';
update core.orders set channel_name='가전시장' where source='shoplinker' and channel_account='samsungshmall@naver.com';
