-- mvp_308 · 2026-11-23 · 관리자 메뉴 재배치 (메뉴 개편안 1단계 · 적용 기록)
-- 11-06 에 이미 된 것: [대시보드] 묶음(mvp_281) · 하위 메뉴 = 헤더 아래 탭 줄(v285) · 메뉴 찾기 · 묶음 기본 접힘(v284)
-- 이번: CRM 을 [고객·상담] / [문자·마케팅] 으로 나눔 · 이카운트 주문 화면을 [주문·매출] 로 · [상품] · [데이터 수집] ·
--       설정 화면 셋을 맨 아래 [설정] 으로 · '발송'이 세 뜻으로 쓰이던 이름 정리
-- 메뉴는 DB 에서 읽으므로 화면 배포 없이 바로 반영 (운영·테스트 같은 줄). 화면 쪽은 NAV_FALLBACK·NAV_GICON·메뉴 찾기 별명(NAV_ALIAS)만.
--
-- 되돌리기 (예전 묶음·이름):
--   update core.menu_group set label='CRM', sort=20 where code='crm';
--   update core.menu_group set label='매출', sort=10 where code='sales';
--   update core.menu_group set label='오픈마켓-이카운트 발송', sort=30 where code='inv';
--   update core.menu_group set label='데이터', sort=40 where code='data';
--   update core.menu_group set label='운영', sort=50 where code='ops';
--   update core.menu_group set state='off' where code='mkt';
--   update core.menu_item set group_code='crm', label=case code when 'crm' then '발송 대상 추출 · 수동' when 'followup' then '자동 발송 대상'
--     when 'sms' then '메시지 발송 관리' when 'utm' then '발송 링크 관리' else label end,
--     sort=case code when 'crm' then 40 when 'followup' then 45 when 'sms' then 48 when 'utm' then 50 else sort end
--    where code in ('sms','crm','followup','utm','lucky');
--   update core.menu_item set group_code='inv', label=case code when 'oq' then '주문서 · 전송' else label end, sort=case code when 'oq' then 40 else 45 end where code in ('oq','wiz');
--   update core.menu_item set label='품목' where code='items';
--   update core.menu_item set group_code='data', label='설정 · 담당자', sort=30 where code='settings';
--   update core.menu_item set label=case code when 'option' then '옵션 · 권한' else '알림 관리' end, sort=case code when 'option' then 10 else 20 end where code in ('option','notify');

-- 묶음
insert into core.menu_group(code, label, sort, state, envs, note)
values ('mkt', '문자·마케팅', 30, 'on', array['test','prod'], '문자 발송 · 보낼 고객 찾기 · 자동 발송 · 캠페인·단축 링크 · 행운 이벤트 (2026-11-23 CRM 에서 나눔)')
on conflict (code) do update set label = excluded.label, sort = excluded.sort, state = 'on', note = excluded.note, updated_at = now();

update core.menu_group g set label = v.label, sort = v.sort, updated_at = now()
  from (values ('crm','고객·상담',20), ('sales','주문·매출',40), ('inv','상품',50), ('data','데이터 수집',60), ('ops','설정',90)) v(code, label, sort)
 where g.code = v.code;

-- 메뉴 (묶음 · 이름 · 순서)
update core.menu_item i set group_code = v.grp, label = v.label, sort = v.sort, updated_at = now()
  from (values
    ('inbox',    'crm',   '문의 관리',          10),
    ('consults', 'crm',   '상담·가망고객',      20),
    ('customers','crm',   '고객 통합',          30),
    ('sms',      'mkt',   '문자 발송',          10),
    ('crm',      'mkt',   '보낼 고객 찾기',     20),
    ('followup', 'mkt',   '자동 발송',          30),
    ('utm',      'mkt',   '캠페인·단축 링크',   40),
    ('lucky',    'mkt',   '행운 이벤트',        90),
    ('orders',   'sales', '통합 원장',          20),
    ('online',   'sales', '온라인 채널',        30),
    ('daily',    'sales', '매장 일마감',        40),
    ('wiz',      'sales', '주문 변환',          50),
    ('oq',       'sales', '이카운트 주문서',    60),
    ('items',    'inv',   '품목·구독 요금',     30),
    ('upload',   'data',  '데이터 가져오기',    10),
    ('log',      'data',  '서비스 로그',        20),
    ('settings', 'ops',   '담당자·배정',        10),
    ('option',   'ops',   '옵션·권한',          20),
    ('notify',   'ops',   '잔디 알림',          30)
  ) v(code, grp, label, sort)
 where i.code = v.code;
