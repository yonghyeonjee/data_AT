-- mvp_202 · 홈페이지 문의 메일 — 누락 되찾기(1시간 대조) · 표를 못 읽은 메일도 원문으로 들어온다 · GAS 심장박동 (2026-10-12 · v189)
-- 사건: 2026-10-12 11:07 KST 견적문의 메일(고객 1건)이 데이터센터에 안 들어왔다. 10-04 에도 담당자가 홈페이지 문의를 손으로 넣은 건(#511)이 있다.
--   지난 24시간 edge log 에 GAS(Google-Apps-Script UA)의 fn_inquiry_mail_ingest 호출이 0 (같은 시간 fn_leave_feed · fn_submit_inquiry 는 200) ·
--   Postgres ERROR 0 · fn_inquiry_mail_ingest 누적 호출 16회 = 적재 15건 → DB 가 거절한 게 아니라 GAS 가 메일을 DC 로 보내지 않았다.
-- 옛 GAS 의 구멍: ① 중복 방지를 스레드 라벨(DC적재)로 해서 지메일이 새 메일을 처리된 스레드에 묶으면(같은 제목) 영영 건너뛴다
--   ② 표를 못 읽은 메일은 DC확인필요 라벨만 붙이고 다시 안 본다(DC 호출 없음 · 로그에만) ③ DC 호출 실패만 다음 분에 재시도.
-- 고침(tools/gmail/gmail_inquiry.gs v2): 메일 한 통 단위(메시지 ID) · 1분 = 2일치 중 안 보낸 것 · 1시간 = 7일치 전부를 fn_inquiry_mail_check 로 대조해
--   빠진 것만 다시 보냄 · 표를 못 읽어도 raw(본문)로 보낸다 → 서버가 한 번 더 읽고, 그래도 없으면 '(이름 확인 필요)' 로 넣고 잔디로 알린다.

-- ─── 1. 심장박동 (GAS 가 1시간마다 대조하면서 찍는다 · 수집 미도착 감시가 이걸 본다) ───
create table if not exists core.heartbeat (key text primary key, at timestamptz not null default now(), note text);
alter table core.heartbeat enable row level security;

-- ─── 2. 메일 본문에서 '성함<TAB>홍길동' 줄 하나 꺼내기 (라벨 여러 개는 | 로) ───
create or replace function core.f_mail_field(p_raw text, p_labels text) returns text
language sql immutable as $$
  select nullif(btrim((regexp_match(p_raw,
           '(?n)^[ \t]*(?:' || p_labels || ')[ \t]*(?:[\t:：]|[ ]{2,})[ \t]*(.+?)[ \t]*$'))[1]), '')
$$;

-- ─── 3. 누락 대조 — GAS 가 최근 7일 메일 ID 전부를 보내면 DC 에 없는 것만 돌려준다 + 심장박동 ───
create or replace function public.fn_inquiry_mail_check(p_key text, p_ids jsonb) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_missing jsonb; v_n int;
begin
  if not core.f_api_ok('gmail_inquiry', p_key) then raise exception '키가 맞지 않습니다' using errcode='42501'; end if;
  insert into core.heartbeat (key, at, note) values ('gmail_inquiry', now(), 'GAS 1시간 대조')
    on conflict (key) do update set at = now(), note = excluded.note;
  select count(*) into v_n from jsonb_array_elements_text(coalesce(p_ids,'[]'::jsonb));
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_missing
    from jsonb_array_elements_text(coalesce(p_ids,'[]'::jsonb)) x
   where nullif(btrim(x),'') is not null
     and not exists (select 1 from crm.consult c where c.source = 'gmail_homepage' and c.source_ref = x);
  return jsonb_build_object('ok', true, 'checked', v_n, 'missing', v_missing,
                            'total', (select count(*) from crm.consult where source = 'gmail_homepage'));
end $$;
revoke all on function public.fn_inquiry_mail_check(text, jsonb) from public;
grant execute on function public.fn_inquiry_mail_check(text, jsonb) to anon, authenticated, service_role;

-- runOnce 자가진단에도 심장박동
create or replace function public.fn_inquiry_mail_status(p_key text) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_api_ok('gmail_inquiry', p_key) then raise exception '키가 맞지 않습니다' using errcode='42501'; end if;
  insert into core.heartbeat (key, at, note) values ('gmail_inquiry', now(), 'GAS runOnce')
    on conflict (key) do update set at = now(), note = excluded.note;
  return jsonb_build_object('ok', true,
    'total', (select count(*) from crm.consult where source='gmail_homepage'),
    'last', (select to_char(max(consult_at) at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI') from crm.consult where source='gmail_homepage'));
end $$;

-- ─── 4. 수집 미도착 감시: 홈페이지 문의 = 마지막 적재 또는 GAS 심장박동 (메일이 며칠 없어도 GAS 가 돌면 정상) ───
do $outer$
declare v_def text; v_old text := $a$(select max(created_at) from crm.consult where source = 'gmail_homepage'))$a$;
        v_new text := $b$(select max(created_at) from crm.consult where source = 'gmail_homepage'),
                                         (select max(at) from core.heartbeat where key = 'gmail_inquiry'))$b$;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'core' and p.proname = 'f_source_last';
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'f_source_last 지점 %', (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old); end if;
  execute replace(v_def, v_old, v_new);
end $outer$;
update core.data_source set how = '홈페이지(고도몰 게시판이 아니라 별도 서비스)의 문의 메일을 GAS gmail_inquiry 가 1분마다 읽어 fn_inquiry_mail_ingest 로 적재 · 1시간마다 최근 7일 메일을 fn_inquiry_mail_check 로 대조해 빠진 것을 다시 보냄(심장박동 core.heartbeat) · 표를 못 읽은 메일은 ''(이름 확인 필요)'' 로 들어오니 문의 관리에서 고칠 것 · 잔디 「웹 문의 수신」 카드와 같은 건'
 where key = 'web_inquiry';

-- ─── 5. fn_inquiry_mail_ingest — raw(본문) 가 오면 서버가 한 번 더 읽고, 이름이 끝내 없으면 '(이름 확인 필요)' (고객 표엔 안 넣음) ───
-- (빈 글자 '' 는 null 로 — 옛 판은 키가 없는 칸이 '' 로 남아 content 에 '구매옵션  · 아파트  ·' 처럼 빈 조각이 찍혔다. 상담방법·첨부도 raw 에서 보조 읽기)
do $outer$
declare v_def text; i int; n int;
  olds text[] := array[
    $o$v_route text; v_items text; v_model text; v_opt text; v_apt text; v_content text;$o$,
    $o$v_ref  := nullif(btrim(coalesce(r->>'msg_id','')),'');$o$,
    $o$if v_ref is null or v_name is null then v_skip := v_skip + 1; continue; end if;$o$,
    $o$v_route := nullif(btrim(coalesce(r->>'route','')),'-');$o$,
    $o$v_items := nullif(btrim(coalesce(r->>'items','')),'-');$o$,
    $o$v_model := nullif(upper(btrim(coalesce(r->>'model',''))),'-');$o$,
    $o$v_opt   := nullif(btrim(coalesce(r->>'option','')),'-');$o$,
    $o$v_apt   := nullif(btrim(coalesce(r->>'apt','')),'-');$o$,
    $o$nullif(btrim(coalesce(r->>'memo','')),''));$o$,
    $o$v_key := core.f_buyer_key(v_name, v_phone);$o$,
    $o$    v_method := case when$o$ ];
  news text[] := array[
    $n$v_route text; v_items text; v_model text; v_opt text; v_apt text; v_content text; v_raw text; v_raw_only boolean;$n$,
    $n$v_raw := nullif(btrim(coalesce(r->>'raw','')),''); v_raw_only := false;
    v_ref  := nullif(btrim(coalesce(r->>'msg_id','')),'');$n$,
    $n$/* mvp_202: GAS 가 표를 못 읽었으면 서버가 본문에서 한 번 더 찾고, 그래도 없으면 '(이름 확인 필요)' 로 넣는다 — 메일을 버리지 않는다 */
    if v_raw is not null then
      if v_name is null then v_name := core.f_mail_field(v_raw, '성함|이름|고객명|사업자명|상호명|상호|업체명|회사명'); end if;
      if v_phone is null then v_phone := nullif(regexp_replace(coalesce(core.f_mail_field(v_raw, '연락처|전화번호|휴대폰'),''),'\D','','g'),''); end if;
      if v_name is null then v_name := '(이름 확인 필요)'; v_raw_only := true; end if;
    end if;
    if v_ref is null or v_name is null then v_skip := v_skip + 1; continue; end if;$n$,
    $n$v_route := coalesce(nullif(nullif(btrim(coalesce(r->>'route','')),''),'-'), nullif(core.f_mail_field(v_raw,'방문경로|유입경로'),'-'));$n$,
    $n$v_items := coalesce(nullif(nullif(btrim(coalesce(r->>'items','')),''),'-'), nullif(core.f_mail_field(v_raw,'희망품목|희망 품목|관심품목'),'-'));$n$,
    $n$v_model := coalesce(nullif(nullif(upper(btrim(coalesce(r->>'model',''))),''),'-'), nullif(upper(core.f_mail_field(v_raw,'제품모델명|모델명')),'-'));$n$,
    $n$v_opt   := coalesce(nullif(nullif(btrim(coalesce(r->>'option','')),''),'-'), nullif(core.f_mail_field(v_raw,'구매옵션|구매 옵션'),'-'));$n$,
    $n$v_apt   := coalesce(nullif(nullif(btrim(coalesce(r->>'apt','')),''),'-'), nullif(core.f_mail_field(v_raw,'아파트명|아파트'),'-'));$n$,
    $n$coalesce(nullif(btrim(coalesce(r->>'memo','')),''), nullif(core.f_mail_field(v_raw,'문의내용|문의 내용|요청사항|메모'),'-')),
                   case when v_raw_only then '⚠ 메일 표를 못 읽어 원문 그대로 (이름·번호 확인 필요) — '||left(regexp_replace(v_raw,'\s+',' ','g'),1500) end);$n$,
    $n$v_key := case when v_raw_only then null else core.f_buyer_key(v_name, v_phone) end;$n$,
    $n$    if nullif(btrim(coalesce(r->>'method','')),'') is null and v_raw is not null then
      r := r || jsonb_strip_nulls(jsonb_build_object('method', core.f_mail_field(v_raw,'상담방법|상담 방법'), 'attach', coalesce(r->>'attach', core.f_mail_field(v_raw,'첨부파일'))));
    end if;
    v_method := case when$n$ ];
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_inquiry_mail_ingest';
  for i in 1..array_length(olds,1) loop
    n := (length(v_def) - length(replace(v_def, olds[i], ''))) / length(olds[i]);
    if n <> 1 then raise exception '지점 % 가 %개', i, n; end if;
    v_def := replace(v_def, olds[i], news[i]);
  end loop;
  execute v_def;   -- create or replace → ACL 그대로 (anon·authenticated·service_role)
end $outer$;

-- ─── 6. 확인 (롤백 블록 · 키 해시를 트랜잭션 안에서 임시로 바꾸고 notify_rule 을 끈 뒤 호출 · raise 로 되돌림 — 잔디로 안 나간다) ───
--   check: 4개 중 없는 2개만 missing · 심장박동 찍힘 / ingest: raw 만 온 표 → 이름·번호·경로·품목·모델·상담방법·첨부 전부 서버가 읽음 ·
--   표 없는 메일 → '(이름 확인 필요)' + 원문 · crm.customer 0 · web_inquiry 1 / 파싱된 줄 + memo → 그대로 / 같은 번호 10분 안 → duplicate (f_hp_dup)
--   서버 보조 읽기는 한 줄 값만 본다(여러 줄 문의내용은 GAS v2 가 memo 로 이어 붙여 보낸다).
-- GAS 는 사용자가 다시 붙여넣어야 한다: tools/gmail/gmail_inquiry.gs (runOnce → setupInquiryTrigger → setupRecheckTrigger)
