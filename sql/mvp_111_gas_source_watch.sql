-- mvp_111 · 홈페이지 폼 3종(GAS 경유)을 수집 미도착 감시에 편입 (2026-09-12)
--
-- 문제 : GAS 는 일부러 조용히 실패한다. dcForwardInquiry_ · dcPost_ 가 예외를 전부
--        삼키고 Logger 에만 남긴다. 접수와 잔디를 끊지 않으려는 설계라 그 자체는 맞다.
--        그런데 Datacenter 적재만 멈추면 잔디는 계속 오고 시트도 계속 쌓이므로
--        상담 화면만 조용히 비어 간다. 편집기를 열어 로그를 보기 전까지 아무도 모른다.
--        (2026-09-11 키 교체 직후가 실제로 이 상태였다)
--
-- 해결 : mvp_101 이 만든 core.data_source 감시에 세 소스를 넣는다.
--        매일 아침 09:10 에 밀린 것이 잔디로 나간다. 코드 수정도 배포도 없다.
--        기존 'web_inquiry' 는 crm.web_inquiry(고도몰 견적 게시판)를 보므로 이 셋과 다르다.
--
-- expect_days 는 2026-09-04~11 실측 최대 간격에 여유를 둔 값이다.
--   web_subscription 최대 2.0일 → 3    web_supply 최대 3.5일 → 10    web_b2b 최대 6.9일 → 14
--   소모품·VMS 는 표본이 4~5건뿐이라 넉넉히 잡았다. 오경보가 한 번이라도 나면
--   아무도 안 보게 되므로, 좁히는 것은 표본이 쌓인 뒤에 한다.

-- ── 1. f_source_last 에 세 갈래 추가 (본문을 다시 쓰지 않고 부분 치환) ──
do $outer$
declare v_src text; v_args text; v_new text; v_hits int;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'core'
   where p.proname = 'f_source_last';
  if v_src is null then raise exception 'core.f_source_last 를 찾을 수 없습니다'; end if;

  v_hits := (length(v_src) - length(replace(v_src, 'else null end', ''))) / length('else null end');
  if v_hits <> 1 then raise exception '치환 지점이 %개입니다 — 중단', v_hits; end if;

  v_new := replace(v_src, 'else null end',
$add$when 'web_subscription' then (select max(created_at) from crm.consult where source = 'web_subscription')
    when 'web_supply'       then (select max(created_at) from crm.consult where source = 'web_supply')
    when 'web_b2b'          then (select max(created_at) from crm.consult where source = 'web_b2b')
    else null end$add$);

  execute format('create or replace function core.f_source_last(%s) returns timestamptz
                  language sql stable security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_new);
end $outer$;

-- ── 2. 소스 3건 등록 ──
insert into core.data_source (key, label, owner, backup_owner, expect_days, how, auto_plan, sort_no, active, alert) values
  ('web_subscription','구독 문의 (홈페이지 폼 → GAS)','온라인사업부','매장 프로', 3,
   'GAS 구독문의 프로젝트가 자동 적재. 멈추면 시트 [상담관리] 는 쌓이는데 상담 화면만 빈다',
   '고도몰 PHP 또는 Edge Function 으로 옮기면 GAS 제거 가능', 80, true, true),
  ('web_supply','소모품·렌탈 문의 (홈페이지 폼 → GAS)','온라인사업부','매장 프로', 10,
   'GAS 소모품렌탈 프로젝트가 자동 적재. 멈추면 시트 [상담결과] 는 쌓이는데 상담 화면만 빈다',
   '고도몰 PHP 또는 Edge Function 으로 옮기면 GAS 제거 가능', 81, true, true),
  ('web_b2b','VMS·B2B 문의 (홈페이지 폼 → GAS)','온라인사업부','매장 프로', 14,
   'GAS VMS 프로젝트가 자동 적재. 멈추면 시트 [raw_B2B] 는 쌓이는데 상담 화면만 빈다',
   '고도몰 PHP 또는 Edge Function 으로 옮기면 GAS 제거 가능', 82, true, true)
on conflict (key) do nothing;

-- ── 확인 ──
-- select key, label, expect_days, core.f_source_last(key) from core.data_source
--  where key in ('web_subscription','web_supply','web_b2b');
-- select * from core.f_source_overdue();   -- 방금 넣은 셋이 뜨면 안 된다
