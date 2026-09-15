/* mvp_143 — 이미 보낸 고객(발송 이력) 가져오기 + CRM 발송 대상에서 제외
   2026-09-15

   왜: 지난 캠페인에서 한 번 보낸 사람에게 또 보내면 안 된다. 그런데 crm.send_log 는 0건이라
       [발송 대상 추출] 의 '최근 발송 제외' 가 아무것도 걸러내지 못했다.
       보낸 목록(휴대폰·이름·발송일)을 데이터 가져오기로 올려 send_log 에 쌓고,
       추출에서 '이미 보낸 사람 전부 제외' 로 뺀다.

   핵심: 매칭은 buyer_key 를 다시 계산하지 않고 **휴대폰 뒤 8자리**로 한다.
         core.f_buyer_key 는 이름+번호를 같이 해싱하므로, 이름이 없거나 다르게 적힌
         발송 목록으로는 같은 키가 안 나온다. 번호만 있는 목록도 받아야 한다. */

-- 같은 캠페인·같은 사람을 두 번 올려도 한 줄만 남는다 (파일을 다시 올려도 안전)
create unique index if not exists ux_send_camp_buyer
  on crm.send_log (campaign, buyer_key);

create or replace function public.fn_send_log_import(
  p_rows      jsonb,
  p_campaign  text,
  p_channel   text default 'sms',
  p_sent_at   date default null,     -- 줄마다 발송일이 없으면 이 날짜로
  p_file      text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog','public'
as $fn$
declare
  v_matched int := 0; v_unmatched int := 0; v_dup int := 0; v_rows int := 0;
  v_sample  jsonb;
begin
  if not core.f_is_service() and core.f_role() not in ('admin','staff') then
    raise exception '권한이 없습니다' using errcode='42501';
  end if;
  if coalesce(p_campaign,'') = '' then
    raise exception '캠페인명을 적어 주세요' using errcode='22023';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('rows',0,'matched',0,'unmatched',0,'dup',0);
  end if;

  create temp table _in on commit drop as
  select right(regexp_replace(coalesce(r->>'phone',''), '\D', '', 'g'), 8) as d8,
         nullif(trim(coalesce(r->>'name','')), '')                         as name,
         coalesce(core.f_ts(r->>'sent_at'),
                  case when p_sent_at is not null then p_sent_at::timestamptz end,
                  now())                                                   as sent_at,
         coalesce(nullif(r->>'status',''), 'sent')                         as status
    from jsonb_array_elements(p_rows) r;

  delete from _in where length(d8) < 8;          -- 번호가 없거나 마스킹된 줄은 버린다
  select count(*) into v_rows from _in;

  /* 번호 뒤 8자리로 고객 마스터와 맞춘다. 한 번호에 여러 고객이 있으면 (동명이인·중복 등록)
     이름이 같은 쪽을 먼저, 없으면 아무나 하나 — 어차피 같은 번호라 보내는 사람은 한 명이다 */
  create temp table _m on commit drop as
  select distinct on (i.d8) i.d8, c.buyer_key, i.sent_at, i.status
    from _in i
    join crm.customer c
      on right(regexp_replace(coalesce(c.phone,''), '\D', '', 'g'), 8) = i.d8
     and c.buyer_key is not null
   order by i.d8, (i.name is not null and c.name = i.name) desc, c.id;

  select count(*) into v_matched from _m;
  v_unmatched := v_rows - v_matched;

  with ins as (
    insert into crm.send_log (buyer_key, channel, campaign, sent_at, status)
    select m.buyer_key, coalesce(nullif(p_channel,''),'sms'), p_campaign, m.sent_at, m.status
      from _m m
    on conflict (campaign, buyer_key) do nothing
    returning 1
  ) select v_matched - count(*) into v_dup from ins;

  select jsonb_agg(x) into v_sample from (
    select i.name, '···'||right(i.d8,4) as phone from _in i
     where not exists (select 1 from _m m where m.d8 = i.d8) limit 5) x;

  insert into raw.upload (source, file_name, row_count, error_count, note)
  values ('send_log', p_file, v_rows, v_unmatched,
          p_campaign || ' · 매칭 ' || v_matched || ' · 미매칭 ' || v_unmatched);

  return jsonb_build_object('rows', v_rows, 'matched', v_matched,
                            'unmatched', v_unmatched, 'dup', v_dup,
                            'campaign', p_campaign, 'sample', coalesce(v_sample,'[]'::jsonb));
end $fn$;

revoke all on function public.fn_send_log_import(jsonb,text,text,date,text) from public, anon;
grant execute on function public.fn_send_log_import(jsonb,text,text,date,text) to authenticated, service_role;

-- 데이터 소스 카드 (관리자 › 데이터 가져오기)
insert into core.data_source (key, label, owner, expect_days, how, sort_no, active, auto_plan)
values ('send_log', '이미 보낸 고객 (발송 이력)', '온라인사업부', 365,
        '지난 캠페인에서 보낸 목록(휴대폰·이름·발송일)을 파일 올리기 또는 붙여넣기 · [발송 대상 추출]에서 제외됩니다',
        66, true,
        '센드온이 붙으면 발송할 때마다 자동으로 쌓인다 — 그때 이 카드는 수동 업로드용으로만 남는다')
on conflict (key) do update
  set label=excluded.label, owner=excluded.owner, expect_days=excluded.expect_days,
      how=excluded.how, sort_no=excluded.sort_no, active=true, auto_plan=excluded.auto_plan;

-- '마지막 적재' 에 send_log 를 태운다 (발송일이 아니라 올린 시각을 본다)
do $outer$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='core' and p.proname='f_source_last';
  if position('when ''send_log''' in v_def) > 0 then return; end if;
  if position('else null end;' in v_def) = 0 then raise exception '지점 없음'; end if;
  execute replace(v_def, 'else null end;',
    'when ''send_log''      then (select max(uploaded_at) from raw.upload where source=''send_log'')
    else null end;');
end $outer$;
