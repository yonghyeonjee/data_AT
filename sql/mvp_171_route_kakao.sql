-- mvp_171 (2026-09-21) — 이미 DB 에 반영됨. 기록용.
-- 상담 입력 유입경로 select 에 '카카오채널' — 채널 공통(channel_code null)이라 어느 문의 채널을 골라도 [공통] 묶음에 보인다.
insert into core.inq_route (code, label, channel_code, sort_no, active)
values ('kakao_ch', '카카오채널', null, 190, true)
on conflict (code) do update set label='카카오채널', channel_code=null, sort_no=190, active=true;
