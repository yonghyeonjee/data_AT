-- mvp_161 · 2026-09-21 · 발송 실패 건은 다음 발송에서도 뺀다
-- "발송목록 중에 실패목록도 다음에 보낼 필요는 없을 것 같은데" (9/18 한가위 LMS 결과: 'MMS를 미 지원 단말' · '발/착신 번호 에러')
-- ① fn_send_log_import: 센드온 '비고' 를 error_msg 로 저장 (화면 mapRows 가 error 키로 보냄, 실패 건만)
-- ② fn_crm_targets_v2: last_sent 가 실패도 센다(옵션 [이미 보낸 사람 제외] 가 실패 건도 뺌)
--    + 번호 오류·미지원 단말·수신거부 사유로 실패한 사람은 옵션과 무관하게 항상 제외 → summary.blocked_bad
-- 적용은 prosrc 부분 치환(지점 검증 pg_temp.chk). 검증: authenticated+admin 클레임으로 import → error_msg 저장 · targets blocked_bad=1 (롤백).
create or replace function pg_temp.chk(src text, needle text, nm text) returns void language plpgsql as $p$
begin if (length(src)-length(replace(src,needle,'')))/length(needle) <> 1 then raise exception '% 지점 %', nm, (length(src)-length(replace(src,needle,'')))/length(needle); end if; end $p$;
do $outer$
declare v_src text; v_args text; a text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_send_log_import';
  a := $a$         coalesce(nullif(r->>'status',''), 'sent')                         as status
    from jsonb_array_elements(p_rows) r;$a$;
  perform pg_temp.chk(v_src, a, 'status');
  v_src := replace(v_src, a, $n$         coalesce(nullif(r->>'status',''), 'sent')                         as status,
         nullif(left(trim(coalesce(r->>'error','')), 200), '')                 as err      /* 센드온 '비고' — 실패 사유 (2026-09-21) */
    from jsonb_array_elements(p_rows) r;$n$);
  a := $a$  select distinct on (i.d8) i.d8, c.buyer_key, i.sent_at, i.status$a$;
  perform pg_temp.chk(v_src, a, '_m');
  v_src := replace(v_src, a, $n$  select distinct on (i.d8) i.d8, c.buyer_key, i.sent_at, i.status, i.err$n$);
  a := $a$    insert into crm.send_log (buyer_key, channel, campaign, sent_at, status)
    select m.buyer_key, coalesce(nullif(p_channel,''),'sms'), p_campaign, m.sent_at, m.status$a$;
  perform pg_temp.chk(v_src, a, 'insert');
  v_src := replace(v_src, a, $n$    insert into crm.send_log (buyer_key, channel, campaign, sent_at, status, error_msg)
    select m.buyer_key, coalesce(nullif(p_channel,''),'sms'), p_campaign, m.sent_at, m.status, case when m.status = 'failed' then m.err end$n$);
  execute format('create or replace function public.fn_send_log_import(%s) returns jsonb language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);

  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.proname='fn_crm_targets_v2';
  a := $a$(select max(l.sent_at) from crm.send_log l where l.buyer_key = c.buyer_key and coalesce(l.status,'') <> 'failed') last_sent$a$;
  perform pg_temp.chk(v_src, a, 'last_sent');
  v_src := replace(v_src, a, $n$(select max(l.sent_at) from crm.send_log l where l.buyer_key = c.buyer_key) last_sent   /* 실패도 보낸 것으로 센다 — 다시 보내도 또 실패 (2026-09-21) */$n$);
  a := $a$declare v jsonb; v_role text; v_lim int; v_total int; v_blocked int := 0;$a$;
  perform pg_temp.chk(v_src, a, 'declare');
  v_src := replace(v_src, a, $n$declare v jsonb; v_role text; v_lim int; v_total int; v_blocked int := 0; v_bad int := 0;$n$);
  a := $a$  if p_no_send_days is not null then
    delete from _c where last_sent is not null and last_sent >= now() - (p_no_send_days||' days')::interval;
  end if;$a$;
  perform pg_temp.chk(v_src, a, 'nosend');
  v_src := replace(v_src, a, $n$  /* 발송 불가 — 번호 오류·미지원 단말·수신거부로 실패한 사람은 옵션과 무관하게 항상 뺀다 (2026-09-21) */
  delete from _c where buyer_key in (
    select l.buyer_key from crm.send_log l
     where l.status = 'failed' and coalesce(l.error_msg,'') ~ '번호|미 ?지원|수신 ?거부|결번|착신|없는');
  get diagnostics v_bad = row_count;
  if p_no_send_days is not null then
    delete from _c where last_sent is not null and last_sent >= now() - (p_no_send_days||' days')::interval;
  end if;$n$);
  a := $a$      'blocked_open', v_blocked,$a$;
  perform pg_temp.chk(v_src, a, 'summary');
  v_src := replace(v_src, a, $n$      'blocked_open', v_blocked,
      'blocked_bad', v_bad,$n$);
  execute format('create or replace function public.fn_crm_targets_v2(%s) returns jsonb language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L', v_args, v_src);
end $outer$;
