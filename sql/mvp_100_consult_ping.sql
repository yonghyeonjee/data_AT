-- mvp_100 · 실시간 상담 알림용 신호 테이블 (2026-09-09)
-- 문제 : 담당자 화면(store.html, anon 키)이 crm.consult 를 Realtime 으로 구독하려 했지만
--        anon 에 crm 스키마 권한이 없어 CHANNEL_ERROR → 20초 폴링만 동작 → "알림이 느리다".
-- 해결 : crm.consult 를 열지 않는다(실명·전화가 새어 나감). 대신 개인정보 없는 신호 테이블
--        public.consult_ping 을 두고 상담 INSERT 트리거로 한 줄 넣는다. 화면은 이 표만 구독.

create table if not exists public.consult_ping(
  id          bigserial primary key,
  consult_id  bigint not null,
  source      text,
  handler     text,          -- 입력 담당자명 (본인 입력이면 알림 안 함 판단용)
  name_masked text,          -- 홍*동 형태. 실명은 RPC 로만
  at          timestamptz not null default now()
);
comment on table public.consult_ping is '상담 등록 신호(Realtime 구독용). 개인정보 없음. 30일 후 삭제';

alter table public.consult_ping enable row level security;
drop policy if exists consult_ping_read on public.consult_ping;
create policy consult_ping_read on public.consult_ping for select to anon, authenticated using (true);
grant select on public.consult_ping to anon, authenticated;
revoke insert, update, delete on public.consult_ping from anon, authenticated;

create or replace function core.f_consult_ping() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.consult_ping(consult_id, source, handler, name_masked)
  values (new.id, new.source, new.handler,
    case when new.customer_name is null or btrim(new.customer_name) = '' then null
         when length(btrim(new.customer_name)) <= 2 then left(btrim(new.customer_name),1) || '*'
         else left(btrim(new.customer_name),1) || repeat('*', length(btrim(new.customer_name)) - 2) || right(btrim(new.customer_name),1) end);
  return new;
end $$;
drop trigger if exists trg_consult_ping on crm.consult;
create trigger trg_consult_ping after insert on crm.consult for each row execute function core.f_consult_ping();

-- Realtime 발행 : crm.consult 는 빼고 신호 표만
do $$ begin
  if exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='crm' and tablename='consult') then
    alter publication supabase_realtime drop table crm.consult;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='consult_ping') then
    alter publication supabase_realtime add table public.consult_ping;
  end if;
end $$;

-- 신호는 30일만 보관
do $$ declare j int; begin
  select jobid into j from cron.job where jobname='consult-ping-prune';
  if j is not null then perform cron.unschedule(j); end if;
  perform cron.schedule('consult-ping-prune', '20 4 * * *', $c$delete from public.consult_ping where at < now() - interval '30 days'$c$);
end $$;
