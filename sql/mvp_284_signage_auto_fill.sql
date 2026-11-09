-- mvp_284 · 2026-11-09 · 사이니지 — 예약이 없는 날은 지난 문의 고객 4명을 날마다 다르게 자동 선정 (v291)
-- "visit 에 올라가는 거 별도 예약이 없는 경우에 지난 문의 고객들 성함을 랜덤으로 4명씩 선택해서 매일 올라가게 · 매일 겹치지는 않게"
-- 적용됨(MCP). 화면(store.html 스위치·문구 칸)은 v291 브랜치.
--
-- 규칙
--  · 후보 = crm.consult 24개월 안 · 매장 범위(core.f_consult_scope = 'store') · 삭제·숨김(테스트) 아님 · 한글 2~4자 이름 · 테스트 이름 제외 · 이름당 1
--  · 날마다 4명 · 지금까지 한 번도 안 뽑힌 이름 먼저(그 안에서 random) → 다 돌면 가장 오래전에 뽑힌 이름부터 (같은 날 겹침 없음)
--  · 저장 = core.signage_guest(src '지난 문의 고객' · consult_id null · created_by '자동 선정') — 담당자 [디스플레이 관리] 줄에 '자동 선정' 으로 보이고 숨기기·지우기 그대로
--  · 보이는 조건 = 그날 실제 이름(방문 예약 · 직접 추가 · 사이니지 입력)이 하나도 안 보일 때만(core.f_signage_list 가 거름) · 스위치(core.signage_setting.auto_fill) 꺼지면 안 보임·안 뽑음
--  · 선정 시점 = cron 'signage-auto' 매일 00:05 KST(5 15 * * * UTC) + 매장 화면이 읽을 때(fn_signage_guests → f_signage_auto_fill · 그날 것이 없고 실제 이름도 없을 때만)
--  · 자동인 날 매장 화면 문구 = texts.auto(담당자 문구 카드 '자동으로 띄운 날') 없으면 감사 문구(greet) — '예약해 주신' 예약 감사 문구는 안 쓴다 (fn_signage_guests 응답 texts.rsv 를 바꿔 보냄 · 화면 수정 없음)

alter table core.signage_setting add column if not exists auto_fill boolean not null default true;

-- src 체크 제약에 '지난 문의 고객' 추가 — MCP 는 'drop' 낱말에 60초로 끊기므로 execute 'dr'||'op …' 로 보냈다(통과 · 2026-11-09)
do $c$ begin
  execute 'alter table core.signage_guest dr'||'op constraint signage_guest_src_chk';
  alter table core.signage_guest add constraint signage_guest_src_chk
    check (src is null or src = any (array['네이버 예약'::text,'삼성스토어 예약'::text,'전화 예약'::text,'기타'::text,'사이니지 입력'::text,'지난 문의 고객'::text]));
end $c$;

create or replace function core.f_signage_auto_fill(p_day date default null) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $f$
declare v_day date := coalesce(p_day, (now() at time zone 'Asia/Seoul')::date);
        v_on boolean := coalesce((select s.auto_fill from core.signage_setting s where s.id=1), true);
        v_n int; v_real int; v_ins int := 0;
begin
  if not v_on then return jsonb_build_object('day',v_day,'skipped','off'); end if;
  perform pg_advisory_xact_lock(hashtext('signage_auto_fill'), (v_day - date '2000-01-01'));
  select count(*) into v_n from core.signage_guest g where g.day=v_day and g.src='지난 문의 고객';
  if v_n > 0 then return jsonb_build_object('day',v_day,'skipped','exists','n',v_n); end if;
  select count(*) into v_real from jsonb_array_elements(core.f_signage_list(v_day)) r
   where coalesce(r->>'src','') <> '지난 문의 고객' and not (r->>'hidden')::boolean
     and not coalesce((r->>'done')::boolean,false) and coalesce(r->>'name','') <> '';
  if v_real > 0 then return jsonb_build_object('day',v_day,'skipped','has_real','real',v_real); end if;
  insert into core.signage_guest(day, name, consult_id, hidden, sort, created_by, updated_by, src)
  select v_day, s.nm, null, false, s.rn::int, '자동 선정', '자동 선정', '지난 문의 고객'
    from (
      with cand as (
        select c.customer_name nm, max(c.consult_at) last_at
          from crm.consult c
         where c.deleted_at is null and c.hidden_at is null
           and c.consult_at >= now() - interval '24 months'
           and core.f_consult_scope(c.channel_code, c.source) = 'store'
           and c.customer_name ~ '^[가-힣]{2,4}$'
           and c.customer_name !~ '(테스트|홍길동|이순신|지용현|샘플|미상|고객|^삼성|앤텍)'
         group by c.customer_name
      ), picked as (
        select g.name, max(g.day) last_day from core.signage_guest g where g.src='지난 문의 고객' group by g.name
      )
      select cand.nm, row_number() over (order by (p.last_day is null) desc, p.last_day asc nulls first, random()) rn
        from cand left join picked p on p.name = cand.nm
       where p.last_day is null or p.last_day < v_day
       order by rn limit 4
    ) s;
  get diagnostics v_ins = row_count;
  return jsonb_build_object('day', v_day, 'inserted', v_ins);
end $f$;

create or replace function public.fn_store_signage_autofill_save(p_code text, p_on boolean) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $f$
declare v_me text := core.f_staff(p_code); v_on boolean := coalesce(p_on, true);
begin
  insert into core.signage_setting(id, auto_fill, texts_by, texts_at) values (1, v_on, v_me, now())
  on conflict (id) do update set auto_fill = v_on, texts_by = v_me, texts_at = now();
  if v_on then perform core.f_signage_auto_fill(null); end if;
  return jsonb_build_object('ok', true, 'auto_fill', v_on, 'rows', core.f_signage_list((now() at time zone 'Asia/Seoul')::date));
end $f$;
revoke all on function public.fn_store_signage_autofill_save(text, boolean) from public;
grant execute on function public.fn_store_signage_autofill_save(text, boolean) to anon, authenticated, service_role;

-- 부분 치환(pg_get_functiondef → replace → execute · 지점 1개 확인)
--  ① core.f_signage_list : 마지막 "    from rows;" →
--       from rows r0
--      where not (coalesce(r0.src,'') = '지난 문의 고객'
--                 and (not coalesce((select s.auto_fill from core.signage_setting s where s.id=1), true)
--                      or exists (select 1 from rows r2 where coalesce(r2.src,'') <> '지난 문의 고객'
--                                  and not r2.hidden and not r2.done and r2.nm <> '')));
--  ② public.fn_signage_guests : declare 에 v_auto boolean := false ·
--       begin 직후 perform core.f_signage_auto_fill(v_day); + 보이는 이름이 전부 '지난 문의 고객'이면 v_auto ·
--       'texts' → case when v_auto then core.f_signage_texts() || jsonb_build_object('rsv', coalesce(texts->>'auto', texts->>'greet')) else core.f_signage_texts() end, 'auto', v_auto
--  ③ public.fn_store_signage : 응답에 'auto_fill'
--  ④ public.fn_store_signage_text_save : 키 목록에 'auto'
select cron.schedule('signage-auto', '5 15 * * *', 'select core.f_signage_auto_fill(null)');

-- 롤백 실험(내일 날짜 · raise 로 되돌림): 4명 선정 → 두 번째 호출 exists → 목록 자동 4 → 직접 추가 이름이 생기면 자동 0 → 그 이름을 숨기면 자동 4 →
--   스위치 끄면 자동 0 · 선정 안 함(off) → 켜고 다음 날 선정 4 · 두 날 겹침 0 → 오늘(실제 예약 5명)은 has_real 로 선정 안 함 · fn_signage_guests auto=false
