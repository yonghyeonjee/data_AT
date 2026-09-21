-- mvp_166 (2026-09-21 · v129) — 이미 DB 에 반영됨. 기록용.
-- ① 센드온 결과 파일: 실패는 사유와 무관하게 '발송 불가' — 다음 추출에서 항상 제외
-- ② 저장 조건: 고정(★) · 최근 사용 · 보관함 (칩 줄 → 검색되는 목록)

alter table crm.segment
  add column if not exists pinned boolean not null default false,
  add column if not exists last_used_at timestamptz,
  add column if not exists use_count int not null default 0;

-- 목록은 보관(active=false)까지 전부 준다 — 화면이 보관함으로 나눈다
create or replace function public.fn_crm_segments() returns jsonb
language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'code',code,'label',label,'note',note,'params',params,'builtin',builtin,'active',active,
      'pinned',pinned,'last_used_at',last_used_at,'use_count',use_count,'created_at',created_at,'created_by',created_by)
      order by active desc, pinned desc, sort, label), '[]'::jsonb)
    from crm.segment);
end $$;

-- 조건을 쓸 때마다 (최근 사용 순서)
create or replace function public.fn_crm_segment_touch(p_code text) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
begin
  if core.f_role() = 'anon' then raise exception '권한이 없습니다' using errcode='42501'; end if;
  update crm.segment set last_used_at = now(), use_count = use_count + 1 where code = p_code;
  return jsonb_build_object('ok', found);
end $$;
revoke all on function public.fn_crm_segment_touch(text) from public, anon;
grant execute on function public.fn_crm_segment_touch(text) to authenticated, service_role;

-- 이름·설명·고정·보관/복구 (관리자). delete=true 는 내장 조건이면 보관, 아니면 삭제
create or replace function public.fn_crm_segment_update(p_code text, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path to 'pg_catalog','public' as $$
declare v_builtin boolean;
begin
  if core.f_role() <> 'admin' then raise exception '관리자만 바꿀 수 있습니다' using errcode='42501'; end if;
  select builtin into v_builtin from crm.segment where code = p_code;
  if not found then raise exception '없는 조건입니다: %', p_code; end if;
  if coalesce((p_data->>'delete')::boolean, false) then
    if v_builtin then
      update crm.segment set active = false, pinned = false, updated_at = now() where code = p_code;
      return jsonb_build_object('ok', true, 'archived', true);
    end if;
    delete from crm.segment where code = p_code;
    return jsonb_build_object('ok', true, 'deleted', true);
  end if;
  update crm.segment set
    label  = coalesce(nullif(btrim(p_data->>'label'),''), label),
    note   = case when p_data ? 'note' then nullif(btrim(p_data->>'note'),'') else note end,
    pinned = coalesce((p_data->>'pinned')::boolean, pinned),
    active = coalesce((p_data->>'active')::boolean, active),
    updated_at = now()
  where code = p_code;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.fn_crm_segment_update(text, jsonb) from public, anon;
grant execute on function public.fn_crm_segment_update(text, jsonb) to authenticated, service_role;

-- fn_crm_targets_v2: 실패 이력은 사유와 무관하게 항상 제외 (pg_get_functiondef 통째 치환, 지점 1개 확인)
do $outer$
declare v_def text; v_old text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_crm_targets_v2';
  v_old := $q$where l.status = 'failed' and coalesce(l.error_msg,'') ~ '번호|미 ?지원|수신 ?거부|결번|착신|없는');$q$;
  v_new := $q$where l.status = 'failed');   /* mvp_166: 실패는 사유와 무관하게 발송 불가 — 다음에 보내도 또 실패 */$q$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'fn_crm_targets_v2 지점 %개', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $outer$;

-- fn_send_log_import: 응답에 sent / failed 건수, raw.upload note 에 실패 수
do $outer$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_send_log_import';
  if position('v_sample  jsonb;' in v_def)=0 or position('select count(*) into v_matched from _m;' in v_def)=0
     or position($q$'unmatched', v_unmatched, 'dup', v_dup,$q$ in v_def)=0
     or position($q$|| ' · 미매칭 ' || v_unmatched);$q$ in v_def)=0 then
    raise exception 'fn_send_log_import 지점 없음';
  end if;
  v_def := replace(v_def, 'v_sample  jsonb;', 'v_sample  jsonb; v_failed int := 0;');
  v_def := replace(v_def, 'select count(*) into v_matched from _m;',
                          $q$select count(*), count(*) filter (where status = 'failed') into v_matched, v_failed from _m;$q$);
  v_def := replace(v_def, $q$'unmatched', v_unmatched, 'dup', v_dup,$q$,
                          $q$'unmatched', v_unmatched, 'dup', v_dup, 'sent', v_matched - v_failed, 'failed', v_failed,$q$);
  v_def := replace(v_def, $q$|| ' · 미매칭 ' || v_unmatched);$q$,
                          $q$|| ' · 미매칭 ' || v_unmatched || ' · 실패(발송 불가) ' || v_failed);$q$);
  execute v_def;
end $outer$;

-- 롤백 블록으로 확인 (2026-09-21): 실패 1·성공 1 을 넣으면 sent 1 · failed 1, 수신동의 대상 3744 → 3743, blocked_bad 6 → 7.
