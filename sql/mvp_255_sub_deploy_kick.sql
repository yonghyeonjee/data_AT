-- mvp_255 (2026-10-29) 구독 정책·요금을 저장하면 데이터센터 배포가 바로 걸리게 — 저장 트리거 → Edge Function sub-deploy → GitHub Actions sdp-publish.yml
-- 왜: GitHub 의 10분 예약 실행(schedule)이 실제로는 돌지 않아(2026-10-27 생성 뒤 한 번도 없음) 관리자·매장에서 저장해도 누군가 푸시하거나 [Run workflow] 를 눌러야 반영됐다.
-- 어떻게: sub.policy · sub.card_policy · sub.promo · sub.price_override 에 문장 단위 AFTER 트리거 → sub.f_deploy_kick() 이 pg_net 으로
--         https://…/functions/v1/sub-deploy?by=<표> 를 부른다 (core.f_sub_image_kick 과 같은 방식 · 익명키는 core.app_setting 'anon_key').
--         함수는 GitHub 에 이미 돌고 있거나 90초 안에 시작한 실행이 있으면 건너뛰고, 없으면 workflow_dispatch 를 건다.
--         GitHub 토큰은 Edge Function Secrets 의 GITHUB_DISPATCH_TOKEN 에만 둔다 (fine-grained PAT · data_AT 저장소 Actions: Read and write).
-- 실패해도 저장은 막지 않는다 (예외를 삼키고 경고만). 배포는 그래도 다음 푸시 때 나간다.

create or replace function sub.f_deploy_kick() returns trigger
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_key text;
begin
  begin
    select value into v_key from core.app_setting where key = 'anon_key';
    if coalesce(v_key,'') <> '' then
      perform net.http_post(
        url := 'https://wdahskrcpjooqhwwxjiu.supabase.co/functions/v1/sub-deploy?by=' || tg_table_name,
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
        body := '{}'::jsonb,
        timeout_milliseconds := 20000);
    end if;
  exception when others then
    raise warning 'sub.f_deploy_kick: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists trg_deploy_kick on sub.policy;
create trigger trg_deploy_kick after insert or update or delete on sub.policy
  for each statement execute function sub.f_deploy_kick();
drop trigger if exists trg_deploy_kick on sub.card_policy;
create trigger trg_deploy_kick after insert or update or delete on sub.card_policy
  for each statement execute function sub.f_deploy_kick();
drop trigger if exists trg_deploy_kick on sub.promo;
create trigger trg_deploy_kick after insert or update or delete on sub.promo
  for each statement execute function sub.f_deploy_kick();
drop trigger if exists trg_deploy_kick on sub.price_override;
create trigger trg_deploy_kick after insert or update or delete on sub.price_override
  for each statement execute function sub.f_deploy_kick();

revoke all on function sub.f_deploy_kick() from public, anon, authenticated;

-- 확인: 관리자에서 정책 저장 → select * from net._http_response order by id desc limit 1;  GitHub Actions 에 workflow_dispatch 실행이 생긴다
