-- mvp_183 · 2026-10-03 · 매장 직접 방문 채널의 유입경로 정리
-- "방문이 매장이면 검색광고는 일단 네이버로 바꾸자. 매장일 경우 네이버·구글·카카오 정도로"
-- '검색광고-방문'(ad_visit, 옛 이카운트 가망고객 분류 — 검색광고 뒤의 행동으로 -방문/-전화 를 갈랐다) 은 끄고,
-- 손님이 우리를 어디서 봤는지로 네이버·구글·카카오 세 줄을 매장 직접 방문 채널에 둔다.
-- 화면은 fn_inq_codes 로 읽으므로 배포 없이 바로 바뀐다. 옛 상담 22건의 글자('검색광고-방문')는 그대로 둔다.
-- VMS 의 '검색광고-전화'(ad_call) 는 손대지 않았다.

begin;
update core.inq_route set active=false where code='ad_visit';
insert into core.inq_route(code,label,channel_code,sort_no,active) values
  ('sv_naver','네이버','store_visit',160,true),
  ('sv_google','구글','store_visit',161,true),
  ('sv_kakao','카카오','store_visit',162,true)
on conflict (code) do update set label=excluded.label, channel_code=excluded.channel_code, sort_no=excluded.sort_no, active=true;
commit;

-- 되돌리기
-- update core.inq_route set active=true where code='ad_visit';
-- update core.inq_route set active=false where code in ('sv_naver','sv_google','sv_kakao');

-- 옛 글자까지 합치고 싶으면(검색광고 = 사실상 네이버였다는 전제):
-- update crm.consult set inflow_route='네이버' where channel_code='store_visit' and inflow_route='검색광고-방문';
