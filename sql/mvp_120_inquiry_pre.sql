-- mvp_120 · 온라인 문의 기본 상태 진행중 → 진행전 (연락 전) · 홈 '문의' 칸 기준
-- pg_get_functiondef 로 원본을 읽어 한 지점만 치환 (지점 수 1 확인). 임시 함수는 세션이 끝나면 사라진다.
create function pg_temp.patch_fn(p_schema text, p_name text, p_old text, p_new text) returns text language plpgsql as $p$
declare v_def text; n int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace and ns.nspname=p_schema where p.proname=p_name;
  if v_def is null then raise exception '% 없음', p_name; end if;
  n := (length(v_def)-length(replace(v_def,p_old,'')))/length(p_old);
  if n <> 1 then raise exception '%.% 지점 %개', p_schema, p_name, n; end if;
  execute replace(v_def, p_old, p_new);
  return p_name||' ok';
end $p$;
select pg_temp.patch_fn('public','fn_submit_inquiry', $x$when '기타' then '종료' else '진행중' end;$x$, $x$when '기타' then '종료' else '진행전' end;$x$);
select pg_temp.patch_fn('public','fn_consults_bulk_upsert', $x$case when r->>'result' in ('구매완료','진행중','보류','종료') then r->>'result' else '진행중' end$x$,
                                                   $x$case when r->>'result' in ('진행전','구매완료','진행중','보류','종료','상담완료','거절','확인완료') then r->>'result' else '진행전' end$x$);
select pg_temp.patch_fn('public','fn_submission_to_consult', $x$array_to_string(s.interests, ', ')), '진행중',$x$, $x$array_to_string(s.interests, ', ')), '진행전',$x$);
select pg_temp.patch_fn('core','f_submission_to_consult', $x$v_int, '진행중',$x$, $x$v_int, '진행전',$x$);
-- 홈 흐름 띠 '문의' = 오늘 밖에서 들어온 문의 전체(직접 입력 제외, KST) + 내 것
select pg_temp.patch_fn('public','fn_store_status',
    $x$'today_consults', (select count(*) from crm.consult_scoped
      where source = 'store' and created_at >= (current_date::timestamp at time zone 'Asia/Seoul')),$x$,
    $x$'today_consults', (select count(*) from crm.consult_scoped
      where source <> 'store' and (consult_at at time zone 'Asia/Seoul')::date = (v_now at time zone 'Asia/Seoul')::date),
    'today_mine', (select count(*) from crm.consult_scoped
      where source <> 'store' and handler = v_me and (consult_at at time zone 'Asia/Seoul')::date = (v_now at time zone 'Asia/Seoul')::date),$x$);
-- 아직 손 안 댄 외부 문의(메모·콜백·구매·주문 연결 없음) 10건 : 진행중 → 진행전
update crm.consult c set result='진행전', updated_at=now(), notes=concat_ws(' · ', nullif(c.notes,''), '2026-09-13 연락 전 상태로 정리(이전 진행중)')
 where c.id in (select id from crm.consult_live where result='진행중' and source<>'store' and coalesce(notes,'')='' and callback_at is null and purchase_item is null and linked_order_id is null);
