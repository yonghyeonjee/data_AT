-- mvp_193 (2026-10-08) DPS 채널 이름 · 대시보드 매장 = 일반 + 구독 — 적용 기록 (DB 에는 이미 반영됨)
--
-- 요청: "DPS 대표입력은 대표님(DPS)으로 변경" · "DPS 온라인(채널 미확인)은 DPS 채널 미확인으로만"
--       "매장(시흥)과 매장구독(시흥)은 모두 매장 매출이고 일반/구독은 별도로 구분해야함"
--
-- ── 1. 이름 정리 함수 — 수집 PC(build_dps_raw.mjs · 저장소 밖)가 옛 이름을 계속 보내도 DB 가 새 이름으로 바꾼다 ──
create or replace function core.f_dps_channel_norm(p text) returns text language sql immutable as $f$
  select case p when 'DPS 대표 입력' then '대표님(DPS)' when 'DPS 온라인(채널 미확인)' then 'DPS 채널 미확인' else p end $f$;
-- core.f_dps_raw_upsert: values 의 nullif(r->>'channel','') → core.f_dps_channel_norm(nullif(r->>'channel',''))  (pg_get_functiondef 치환, 지점 1)
-- core.f_dash_payload: 채널 목록 ('DPS 대표 입력','기타',false,35) → ('대표님(DPS)','기타',false,35)
--                               ('DPS 온라인(채널 미확인)','기타',false,37) → ('DPS 채널 미확인','기타',false,37)   (지점 각 1)
-- ── 2. 전표 갱신 ──
-- update dps.sale set channel = core.f_dps_channel_norm(channel), updated_at = now()
--  where channel in ('DPS 대표 입력','DPS 온라인(채널 미확인)');   -- 4,777 줄 (대표 2,057 · 채널 미확인 2,720)
-- perform core.f_dash_mark_dirty(true);  -- 캐시는 지우지 않고 다시 굽기 예약 (dash-warm-req 1분 cron)
--
-- ── 3. 화면 (dash/index.html · dash/test 동기화 · admin DASH_V 165 → 178) ──
-- 온·오프 띠: 매장 = 매장(시흥) + 매장구독(시흥), 작은 글씨 '일반 N · 구독 M'
-- KPI: '매장 (일반 · 구독)' 칸 — 합계 + 일반/구독 + 전기 대비. VMS·렌탈 묶음에서 구독을 뺐다.
-- 채널·그룹 자체는 그대로(둘 다 '오프라인' 그룹 · 채널 이름 그대로) — 채널 순위·표·몰 고르기에서는 두 줄로 따로 보인다.
