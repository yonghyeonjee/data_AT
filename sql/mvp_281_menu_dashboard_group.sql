-- mvp_281 · 2026-11-06 · 관리자 메뉴 — [대시보드] 묶음 (적용됨 · 기록용)
-- "매출 메뉴는 사실 통계를 모아 두는 거잖아 · 대시보드 메뉴들을 모아서 보게" → 경영 지표(맨 위 묶음 밖에 있던 것)·매출 대시보드·상담 대시보드(·꺼진 주문·판매·매출 흐름)를
-- 홈 바로 다음 묶음 [대시보드] 로. 매출 묶음에는 통합 원장·온라인 채널·매장 일마감만 남는다. 메뉴는 DB 에서 읽으므로 화면 배포 없이 바로.
-- 되돌리기: update core.menu_item set group_code=case code when 'exec' then '_top' else 'sales' end where code in ('exec','dash','flow'); update … set group_code='crm', sort=15 where code='cdash'; update core.menu_group set state='off' where code='dashboard';

insert into core.menu_group(code,label,sort,state,envs,note)
values ('dashboard','대시보드',5,'on',array['test','prod'],'경영 지표 · 매출 대시보드 · 상담 대시보드 — 통계 화면을 한 묶음에 (2026-11-06)')
on conflict (code) do update set label=excluded.label, sort=excluded.sort, state='on', note=excluded.note;

update core.menu_item set group_code='dashboard', updated_at=now(),
  sort=case code when 'exec' then 10 when 'dash' then 20 when 'cdash' then 30 when 'flow' then 40 end
 where code in ('exec','dash','cdash','flow');

-- 화면(admin.html): NAV_GICON 에 dashboard:'exec' (매출 묶음 아이콘은 orders) · NAV_FALLBACK 같은 구조.
