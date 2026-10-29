-- mvp_254 (2026-10-29) 매장에서 "특정 모델의 구독가 지정"을 할 사람을 권한으로 정한다 + 관리자 품목 메뉴 켜기
--   ① core.perm_def 'sub_price' (구독가 지정) — 관리자 › 옵션·권한 › 담당자 권한 표에 체크 칸이 생긴다 (기본 꺼짐). 점장·대표는 전처럼 자동.
--   ② fn_store_sub_price_list / fn_store_sub_price_save (mvp_251) 의 고치기 조건: 점장·대표 OR 'sub_price' 권한
--   ③ 매장 운영 화면 store.html 의 견적서 탭에 [구독 요금 직접 관리] 카드 (store/test 에만 있던 mvp_251 화면을 운영에 반영 — 파일은 저장소 커밋)
--   ④ 관리자 메뉴 core.menu_item 'items'(품목) 를 켠다 — 구독 혜택 정책·구독 요금·세트 구성이 이 화면에 있는데 '이카운트 연동 대기'로 꺼져 있어 주소로도 못 들어갔다
-- 고치는 길: 관리자 › 옵션·권한 › 담당자 권한 › [구독가 지정] 체크 → 그 사람이 매장 화면 › 견적서 › 구독 요금 직접 관리에서 모델·약정·케어별 월 구독료를 넣거나 숨긴다 → 배포 뒤 상세페이지·구독센터에 반영

-- ① 권한 정의
insert into core.perm_def (code, label, note, default_on, scope, sort)
values ('sub_price', '구독가 지정', '특정 모델의 월 구독료를 직접 정하거나 숨김 (상세페이지 구독탭·구독센터에 나가는 값). 점장·대표는 자동', false, 'store', 55)
on conflict (code) do update set label = excluded.label, note = excluded.note, scope = excluded.scope, sort = excluded.sort;

-- ② 매장 RPC — 보기는 담당자 누구나, 고치기는 점장·대표 또는 구독가 지정 권한
create or replace function core.f_can_sub_price(p_name text) returns boolean
language sql stable set search_path to 'pg_catalog','public' as $$
  select core.f_staff_is_mgr(p_name) or core.f_has_perm(p_name, 'sub_price');
$$;

create or replace function public.fn_store_sub_price_list(p_code text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  return sub.f_price_override_view() || jsonb_build_object('me', v_me, 'can_edit', core.f_can_sub_price(v_me));
end $$;

create or replace function public.fn_store_sub_price_save(p_code text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code);
begin
  if v_me is null then raise exception '담당자 코드가 올바르지 않습니다' using errcode = '42501'; end if;
  if not core.f_can_sub_price(v_me) then raise exception '구독 요금은 점장님·대표님 또는 [구독가 지정] 권한이 있는 담당자만 고칠 수 있습니다 (관리자 › 옵션·권한)' using errcode = '42501'; end if;
  return sub.f_price_override_save(p_data, v_me);
end $$;

revoke all on function core.f_can_sub_price(text) from public, anon, authenticated;
grant execute on function public.fn_store_sub_price_list(text) to anon, authenticated;
grant execute on function public.fn_store_sub_price_save(text, jsonb) to anon, authenticated;

-- ④ 관리자 품목 메뉴 켜기
update core.menu_item
   set state = 'on', note = '구독 혜택 정책 · 구독 요금 · 세트 구성 (품목 원장은 이카운트 연동 대기)', updated_at = now()
 where code = 'items';

-- 확인: select code, label, default_on from core.perm_def where code = 'sub_price';  select code, state from core.menu_item where code = 'items';
