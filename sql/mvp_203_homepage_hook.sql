-- mvp_203 · 홈페이지 문의 웹훅 — 맑음(홈페이지 외주)이 잔디에 보내는 것과 같은 요청을 데이터센터가 직접 받는다 (2026-10-12 · v190)
-- 주소: https://wdahskrcpjooqhwwxjiu.supabase.co/functions/v1/homepage-hook?k=<키>   (Edge Function · verify_jwt=false · 소스 tools/edge/homepage-hook.ts)
--   키는 core.api_key 'homepage_hook' 의 sha256 · 값은 _secrets.local.md 에만.
--   받는 형식: 잔디 웹훅(body · connectInfo[{title,description}]) / 일반 JSON(성함·연락처… 또는 name·phone…) / data·fields·form 안쪽 / [{label,value}] 배열 /
--             form-urlencoded · multipart(첨부는 파일 이름) / text. &dry=1 이면 읽은 결과만 돌려주고 저장 안 함.
--   저장은 fn_homepage_inquiry 와 같은 core.f_homepage_inquiry → crm.consult(source homepage_api · channel homepage) + 순번 배정 + 잔디 카드.
--   항목을 못 읽어도 '(이름 확인 필요)' + 받은 내용 그대로로 넣는다(버리지 않는다). 받은 요청은 전부 raw.webhook_log 에 남는다(성공·실패·키 틀림).
--   메일 경로와 같은 건이 둘 다 오면 한 건 (f_hp_dup · 이름/번호 10분). 메일 1시간 대조(fn_inquiry_mail_check)는 합쳐진 건을 '있음' 으로 본다.

-- ─── 1. 키 (해시만) ───
insert into core.api_key (name, key_hash, note)
values ('homepage_hook', '<sha256 — _secrets.local.md 의 키>', '홈페이지(맑음) 문의 웹훅 → Edge Function homepage-hook → fn_homepage_hook (2026-10-12)')
on conflict (name) do update set key_hash = excluded.key_hash, note = excluded.note;

-- ─── 2. 받은 요청 기록 ───
create table if not exists raw.webhook_log (
  id bigserial primary key, at timestamptz not null default now(), hook text not null,
  ok boolean, dry boolean not null default false, ip text, ua text, ctype text,
  body jsonb, parsed jsonb, result jsonb, error text, consult_id bigint);
create index if not exists ix_webhook_log_at on raw.webhook_log (hook, at desc);
alter table raw.webhook_log enable row level security;

-- ─── 3. 라벨 → 필드 · 값 정리 ───
create or replace function core.f_hook_label(p text) returns text language sql immutable as $$
  select case lower(regexp_replace(coalesce(p,''), '[^가-힣A-Za-z0-9_]', '', 'g'))
    when '성함' then 'name' when '이름' then 'name' when '고객명' then 'name' when '성명' then 'name' when 'name' then 'name'
    when 'customername' then 'name' when 'customer_name' then 'name' when 'wr_name' then 'name' when '작성자' then 'name'
    when '사업자명' then 'name' when '상호' then 'name' when '상호명' then 'name' when '업체명' then 'name' when '회사명' then 'name'
    when '연락처' then 'phone' when '전화번호' then 'phone' when '휴대폰' then 'phone' when '휴대폰번호' then 'phone' when '핸드폰' then 'phone'
    when 'phone' then 'phone' when 'mobile' then 'phone' when 'tel' then 'phone' when 'hp' then 'phone' when 'wr_hp' then 'phone'
    when '방문경로' then 'route' when '유입경로' then 'route' when 'route' then 'route'
    when '구매옵션' then 'option' when 'option' then 'option'
    when '아파트명' then 'apt' when '아파트' then 'apt' when 'apt' then 'apt'
    when '희망품목' then 'items' when '관심품목' then 'items' when '품목' then 'items' when 'items' then 'items'
    when '제품모델명' then 'model' when '모델명' then 'model' when 'model' then 'model'
    when '상담방법' then 'method' when 'method' then 'method'
    when '첨부파일' then 'attach' when '첨부' then 'attach' when 'attach' then 'attach' when 'file' then 'attach' when 'files' then 'attach' when 'bf_file' then 'attach' when '사진' then 'attach'
    when '이메일' then 'email' when 'email' then 'email' when 'wr_email' then 'email'
    when '문의내용' then 'memo' when '내용' then 'memo' when '요청사항' then 'memo' when '메모' then 'memo' when '문의사항' then 'memo'
    when 'memo' then 'memo' when 'content' then 'memo' when 'wr_content' then 'memo' when 'message' then 'memo'
    when '게시글번호' then 'ref' when '글번호' then 'ref' when '접수번호' then 'ref' when 'ref' then 'ref' when 'wr_id' then 'ref'
    when '구분' then 'kind' when '문의구분' then 'kind' when 'kind' then 'kind'
    when '접수일시' then 'received_at' when '작성일' then 'received_at' when '작성일시' then 'received_at' when 'received_at' then 'received_at'
    when 'datetime' then 'received_at' when 'wr_datetime' then 'received_at'
  end
$$;
create or replace function core.f_hook_clean(p text) returns text language sql immutable as $$
  select nullif(btrim(regexp_replace(regexp_replace(coalesce(p,''), '\*\*|__', '', 'g'), '\[([^\]]*)\]\(([^)]*)\)', '\1 \2', 'g')), '')
$$;

-- ─── 4. 아무 모양의 본문 → {name, phone, …, raw} ───
create or replace function core.f_hook_normalize(p_body jsonb) returns jsonb language plpgsql immutable as $$
declare o jsonb := '{}'::jsonb; e jsonb; s jsonb; k text; v text; f text; blob text := ''; ln text; m text[];
begin
  p_body := coalesce(p_body, '{}'::jsonb);
  if jsonb_typeof(p_body->'connectInfo') = 'array' then           -- 잔디 카드 형식
    for e in select x from jsonb_array_elements(p_body->'connectInfo') x where jsonb_typeof(x) = 'object' loop
      k := e->>'title'; v := core.f_hook_clean(e->>'description');
      blob := blob || coalesce(k,'') || E'\t' || coalesce(v,'') || E'\n';
      f := core.f_hook_label(k);
      if f is not null and v is not null and not o ? f then o := o || jsonb_build_object(f, v); end if;
    end loop;
  end if;
  for s in select x from (values (p_body),(p_body->'data'),(p_body->'fields'),(p_body->'form'),(p_body->'payload')) t(x) where jsonb_typeof(x) = 'object' loop
    for k, v in select key, case when jsonb_typeof(value) in ('string','number','boolean') then value #>> '{}'
                                 when jsonb_typeof(value) = 'array' then (select string_agg(a #>> '{}', ', ') from jsonb_array_elements(value) a where jsonb_typeof(a) in ('string','number')) end
                  from jsonb_each(s) loop
      continue when v is null or k in ('connectInfo','connectColor');
      v := core.f_hook_clean(v); continue when v is null;
      blob := blob || k || E'\t' || v || E'\n';
      f := core.f_hook_label(k);
      if f is not null and not o ? f then o := o || jsonb_build_object(f, v); end if;
    end loop;
  end loop;
  for s in select x from (values (p_body->'fields'),(p_body->'data'),(p_body->'items'),(p_body->'answers')) t(x) where jsonb_typeof(x) = 'array' loop
    for e in select x from jsonb_array_elements(s) x where jsonb_typeof(x) = 'object' loop
      k := coalesce(e->>'label', e->>'title', e->>'name', e->>'key');
      v := core.f_hook_clean(coalesce(e->>'value', e->>'description', e->>'answer'));
      continue when v is null;
      blob := blob || coalesce(k,'') || E'\t' || v || E'\n';
      f := core.f_hook_label(k);
      if f is not null and not o ? f then o := o || jsonb_build_object(f, v); end if;
    end loop;
  end loop;
  -- 한 칸 안에 '성함: 홍길동' 줄이 여러 개 든 경우
  for ln in select regexp_split_to_table(blob, E'\n') loop
    m := regexp_match(ln, '^[^\t]*\t?\s*([가-힣A-Za-z_ ]{2,15})\s*[:：]\s*(.+)$');
    if m is null then m := regexp_match(ln, '^\s*([가-힣A-Za-z_ ]{2,15})\s*[:：]\s*(.+)$'); end if;
    if m is not null then
      f := core.f_hook_label(m[1]);
      if f is not null and not o ? f and btrim(m[2]) <> '' then o := o || jsonb_build_object(f, btrim(m[2])); end if;
    end if;
  end loop;
  if not o ? 'phone' then
    m := regexp_match(blob, '(01[016789])[-. ]?(\d{3,4})[-. ]?(\d{4})');
    if m is not null then o := o || jsonb_build_object('phone', m[1]||m[2]||m[3]); end if;
  end if;
  if o ? 'received_at' and core.f_ts(o->>'received_at') is null then o := o - 'received_at'; end if;
  blob := btrim(blob || coalesce(p_body->>'body', ''));
  return o || jsonb_build_object('raw', left(coalesce(nullif(blob,''), p_body::text), 4000));
end $$;

-- ─── 5. 저장 본체 core.f_homepage_inquiry(p_data) — fn_homepage_inquiry 본문에서 키 검사만 빼고 (서버 원본 치환) ───
--   + 이름을 못 읽으면 '(이름 확인 필요)'(raw 가 있을 때 · 고객 표 X · 중복 판정 X · content 에 받은 내용) · 자동 접수번호에 raw 해시 · 잔디 카드에 #id
do $outer$
declare v_src text; v_args text; i int; n int;
  olds text[] := array[
    $o$if not core.f_api_ok('homepage_form', p_key) then
    raise exception '키가 맞지 않습니다' using errcode='42501'; end if;$o$,
    $o$if v_name is null then
    return jsonb_build_object('ok', false, 'reason', 'name is required'); end if;$o$,
    $o$concat_ws('|', v_name, coalesce(v_phone,''),$o$,
    $o$v_dup := core.f_hp_dup(v_name, v_phone, v_at);$o$,
    $o$nullif(btrim(coalesce(r->>'memo','')),''));$o$,
    $o$v_key := core.f_buyer_key(v_name, v_phone, nullif(btrim(coalesce(r->>'email','')),''));$o$,
    $o$'inquiry.homepage', jsonb_build_object($o$ ];
  news text[] := array[
    $n$/* 키 검사는 부르는 쪽(fn_homepage_inquiry · fn_homepage_hook)에서 */$n$,
    $n$if v_name is null and nullif(btrim(coalesce(r->>'raw','')),'') is not null then v_name := '(이름 확인 필요)'; end if;
  if v_name is null then
    return jsonb_build_object('ok', false, 'reason', 'name is required'); end if;$n$,
    $n$concat_ws('|', v_name, coalesce(v_phone,''), md5(coalesce(r->>'raw','')),$n$,
    $n$v_dup := case when v_name = '(이름 확인 필요)' then null else core.f_hp_dup(v_name, v_phone, v_at) end;$n$,
    $n$nullif(btrim(coalesce(r->>'memo','')),''),
                 case when v_name = '(이름 확인 필요)' then '⚠ 항목을 못 읽어 받은 내용 그대로 (이름·번호 확인 필요) — '||left(regexp_replace(r->>'raw','\s+',' ','g'),1500) end);$n$,
    $n$v_key := case when v_name = '(이름 확인 필요)' then null else core.f_buyer_key(v_name, v_phone, nullif(btrim(coalesce(r->>'email','')),'')) end;$n$,
    $n$'inquiry.homepage', jsonb_build_object('id', v_id, $n$ ];
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'fn_homepage_inquiry';
  for i in 1..array_length(olds,1) loop
    n := (length(v_src) - length(replace(v_src, olds[i], ''))) / length(olds[i]);
    if n <> 1 then raise exception '지점 % 가 %개', i, n; end if;
    v_src := replace(v_src, olds[i], news[i]);
  end loop;
  execute format('create or replace function core.f_homepage_inquiry(p_data jsonb) returns jsonb
                  language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_src);
end $outer$;
revoke all on function core.f_homepage_inquiry(jsonb) from public, anon, authenticated;

-- 개발사 직접 호출(fn_homepage_inquiry · 키 homepage_form)도 같은 본체로 — ACL 그대로
create or replace function public.fn_homepage_inquiry(p_key text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if not core.f_api_ok('homepage_form', p_key) then raise exception '키가 맞지 않습니다' using errcode='42501'; end if;
  return core.f_homepage_inquiry(p_data);
end $$;

-- ─── 6. 웹훅 입구 — Edge Function 이 service_role 로만 부른다 ───
create or replace function public.fn_homepage_hook(p_key text, p_body jsonb, p_meta jsonb default '{}'::jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_log bigint; v_r jsonb; v_res jsonb; v_dry boolean := coalesce(p_meta->>'dry','') in ('1','true','y');
begin
  insert into raw.webhook_log (hook, dry, ip, ua, ctype, body)
  values ('homepage', v_dry, left(p_meta->>'ip',80), left(p_meta->>'ua',300), left(p_meta->>'ctype',120), p_body)
  returning id into v_log;
  if not core.f_api_ok('homepage_hook', p_key) then
    update raw.webhook_log set ok = false, error = 'key' where id = v_log;
    return jsonb_build_object('ok', false, 'reason', 'key');
  end if;
  v_r := core.f_hook_normalize(p_body);
  if v_dry then
    update raw.webhook_log set ok = true, parsed = v_r where id = v_log;
    return jsonb_build_object('ok', true, 'dry', true, 'parsed', v_r - 'raw', 'log', v_log);
  end if;
  begin
    v_res := core.f_homepage_inquiry(v_r);
  exception when others then
    update raw.webhook_log set ok = false, parsed = v_r, error = left(sqlerrm, 500) where id = v_log;
    return jsonb_build_object('ok', false, 'reason', 'store', 'log', v_log);
  end;
  update raw.webhook_log set ok = coalesce((v_res->>'ok')::boolean, false), parsed = v_r, result = v_res,
         consult_id = (v_res->>'id')::bigint where id = v_log;
  return v_res || jsonb_build_object('log', v_log);
end $$;
revoke all on function public.fn_homepage_hook(text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fn_homepage_hook(text, jsonb, jsonb) to service_role;

-- ─── 7. 메일 경로와 합치기 — 메일이 늦게 와서 웹훅 건과 같은 건이면 그 메일 ID 를 기록 · 1시간 대조는 그 ID 도 '있음' ───
do $outer$
declare v_def text; i int; n int;
  olds text[] := array[
    $o$v_raw text; v_raw_only boolean;$o$,
    $o$if core.f_hp_dup(v_name, v_phone, v_at) is not null then v_dup := v_dup + 1; continue; end if;$o$ ];
  news text[] := array[
    $n$v_raw text; v_raw_only boolean; v_dupid bigint;$n$,
    $n$v_dupid := case when v_raw_only then null else core.f_hp_dup(v_name, v_phone, v_at) end;
    if v_dupid is not null then
      update crm.consult set raw_payload = coalesce(raw_payload,'{}'::jsonb) || jsonb_build_object('mail_msg_id', v_ref) where id = v_dupid;
      v_dup := v_dup + 1; continue;
    end if;$n$ ];
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'fn_inquiry_mail_ingest';
  for i in 1..array_length(olds,1) loop
    n := (length(v_def) - length(replace(v_def, olds[i], ''))) / length(olds[i]);
    if n <> 1 then raise exception '지점 % 가 %개', i, n; end if;
    v_def := replace(v_def, olds[i], news[i]);
  end loop;
  execute v_def;
end $outer$;

do $outer$
declare v_def text; n int;
  v_old text := $o$and not exists (select 1 from crm.consult c where c.source = 'gmail_homepage' and c.source_ref = x);$o$;
  v_new text := $n$and not exists (select 1 from crm.consult c where c.channel_code = 'homepage'
                       and (c.source_ref = x or c.raw_payload->>'msg_id' = x or c.raw_payload->>'mail_msg_id' = x));$n$;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'fn_inquiry_mail_check';
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if n <> 1 then raise exception 'check 지점 %개', n; end if;
  execute replace(v_def, v_old, v_new);
end $outer$;

update core.data_source set how = how || ' · 웹훅(맑음 → Edge Function homepage-hook → fn_homepage_hook · 기록 raw.webhook_log)이 붙으면 그쪽이 먼저 들어오고 메일은 예비'
 where key = 'web_inquiry' and how not like '%homepage-hook%';

-- ─── 5b. (롤백 실험에서 찾음) 빈 칸 '' 이 null 로 안 떨어져 content 에 '홈페이지 견적문의 ·  · 구매옵션  · 아파트  ·' 가 찍히던 것 · 첨부를 content 에 ───
do $outer$
declare v_src text; v_new text; n int; v_pat text := $p$nullif\((upper\()?btrim\(coalesce\(r->>'(route|items|model|option|apt|kind)',''\)\)(\))?,'-'\)$p$;
  v_old2 text := $o$case when nullif(btrim(coalesce(r->>'method','')),'-') is not null then '상담방법 '||btrim(r->>'method') end,$o$;
  v_new2 text := $n$case when nullif(nullif(btrim(coalesce(r->>'method','')),''),'-') is not null then '상담방법 '||btrim(r->>'method') end,
                 case when nullif(nullif(btrim(coalesce(r->>'attach','')),''),'-') is not null then '첨부 '||btrim(r->>'attach') end,$n$;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname='core' and p.proname='f_homepage_inquiry';
  select count(*) into n from regexp_matches(v_src, v_pat, 'g');
  if n <> 6 then raise exception '필드 지점 %개', n; end if;
  v_new := regexp_replace(v_src, v_pat, $r$nullif(nullif(\1btrim(coalesce(r->>'\2',''))\3,''),'-')$r$, 'g');
  n := (length(v_new) - length(replace(v_new, v_old2, ''))) / length(v_old2);
  if n <> 1 then raise exception 'method 지점 %개', n; end if;
  v_new := replace(v_new, v_old2, v_new2);
  execute format('create or replace function core.f_homepage_inquiry(p_data jsonb) returns jsonb
                  language plpgsql volatile security definer set search_path to ''pg_catalog'',''public'' as %L', v_new);
end $outer$;

-- ─── 8. 확인 (롤백 블록 · 키 해시 임시 교체 · notify_rule 끔 · raise) ───
--   A 잔디 카드 형식(이모지 붙은 제목 · 마크다운 링크·굵게) → 이름·번호·경로·옵션·품목·모델·상담방법·첨부·문의내용 전부 · 고객 키 O
--   A 를 다시 보냄 → 같은 건(merged) / B 한국어 키 평면 JSON(배열 값은 쉼표로) / C data.wr_name·wr_hp·wr_content·wr_id(접수번호 777)
--   D body 한 칸에 '성함: … / 연락처: …' 여러 줄 / E 못 읽는 글 → '(이름 확인 필요)' · 고객 키 X / F 키 틀림 → reason key (기록은 남음)
--   G dry → parsed 만 / 그 뒤 같은 사람 메일 → 중복 + mail_msg_id 기록 → fn_inquiry_mail_check 는 '있음'
--   실제 주소(DB extensions.http 로 · 컨테이너는 Supabase 로 못 나감): 키 틀림 403 · GET 200 · 잔디 JSON / form-urlencoded / multipart(첨부는 파일 이름) / text 전부 dry 로 읽힘
--   (multipart 의 bf_file 을 못 알아봐 라벨에 bf_file·사진 추가)
