-- mvp_270 (2026-11-03) 상품 안내 문구 — 이미지 · 상자 없음 · 삭제
-- "p몰도 기존 내용은 그대로 들어가있어야하고 수정하거나 삭제할 수 있게 · 고치기 말고 수정, 삭제, 저장"
--   img    : 이미지 주소 (https:// 만) — 프라자몰 네이버 프로모션 배너 같은 그림 문구
--   tone   : plain (상자 없이) 추가
--   status : gone (삭제 — 목록·상품 페이지에서 빠진다. 줄은 남겨 둔다)
--   문구(body)는 이미지가 있으면 비워도 된다
--   + 프라자몰 스킨에 박혀 있던 '삼성카드 할부 혜택' · '배송 안내' 상자와 네이버 프로모션 배너를 공통 문구 3개로 옮김 (시험으로 넣고 스킨에서 뺀 뒤 공개)

alter table sub.goods_note add column if not exists img text check (img is null or img ~ '^https://');
alter table sub.goods_note drop constraint if exists goods_note_tone_check;
alter table sub.goods_note add constraint goods_note_tone_check check (tone in ('blue','red','gray','yellow','plain'));
alter table sub.goods_note drop constraint if exists goods_note_status_check;
alter table sub.goods_note add constraint goods_note_status_check check (status in ('test','on','off','gone'));

do $$
declare v_src text; v_new text; a text[]; i int;
begin
  -- json: img
  select pg_get_functiondef('sub.f_goods_note_json(sub.goods_note)'::regprocedure) into v_src;
  if (length(v_src) - length(replace(v_src, $q$'scope', n.scope,$q$, ''))) / length($q$'scope', n.scope,$q$) <> 1 then raise exception 'json 고칠 곳'; end if;
  execute replace(v_src, $q$'scope', n.scope,$q$, $q$'scope', n.scope, 'img', n.img,$q$);

  -- 공개 함수: img
  select pg_get_functiondef('public.fn_goods_note(text, text, text[], boolean)'::regprocedure) into v_src;
  if (length(v_src) - length(replace(v_src, $q$'pos', n.pos,$q$, ''))) / length($q$'pos', n.pos,$q$) <> 1 then raise exception 'fn_goods_note 고칠 곳'; end if;
  execute replace(v_src, $q$'pos', n.pos,$q$, $q$'pos', n.pos, 'img', n.img,$q$);

  -- 목록: 삭제한 문구 빼기
  select pg_get_functiondef('public.fn_store_goods_note_list(text)'::regprocedure) into v_src;
  if (length(v_src) - length(replace(v_src, $q$from sub.goods_note n where n.mall = any(sub.f_gn_malls(v_me))));$q$, ''))) / length($q$from sub.goods_note n where n.mall = any(sub.f_gn_malls(v_me))));$q$) <> 1 then raise exception 'list 고칠 곳'; end if;
  execute replace(v_src, $q$from sub.goods_note n where n.mall = any(sub.f_gn_malls(v_me))));$q$, $q$from sub.goods_note n where n.mall = any(sub.f_gn_malls(v_me)) and n.status <> 'gone'));$q$);

  -- 저장: img 받기 · 이미지만 있어도 저장
  select pg_get_functiondef('public.fn_store_goods_note_save(text, jsonb)'::regprocedure) into v_src;
  v_new := v_src;
  a := array[
    $q$if v_body = '' then raise exception '문구를 적어 주세요' using errcode = '22023'; end if;$q$,
    $q$if v_body = '' and nullif(btrim(coalesce(p_data->>'img','')),'') is null then raise exception '문구나 이미지 주소를 넣어 주세요' using errcode = '22023'; end if;
  if nullif(btrim(coalesce(p_data->>'img','')),'') !~ '^https://' then raise exception '이미지 주소는 https:// 로 시작해야 합니다' using errcode = '22023'; end if;$q$,
    $q$insert into sub.goods_note (scope,$q$, $q$insert into sub.goods_note (img, scope,$q$,
    $q$values (v_scope,$q$, $q$values (nullif(btrim(coalesce(p_data->>'img','')),''), v_scope,$q$,
    $q$set scope = v_scope,$q$, $q$set img = nullif(btrim(coalesce(p_data->>'img','')),''), scope = v_scope,$q$];
  for i in 1..array_length(a,1) by 2 loop
    if (length(v_new) - length(replace(v_new, a[i], ''))) / length(a[i]) <> 1 then raise exception 'save 고칠 곳 %', a[i]; end if;
    v_new := replace(v_new, a[i], a[i+1]);
  end loop;
  execute v_new;
end $$;

-- 프라자몰 스킨에 박혀 있던 내용 → 공통 문구 (공개) — 스킨에서는 이 블록을 뺀다
insert into sub.goods_note (scope, mall, title, body, tone, btn_label, btn_url, btn_tone, pos, status, sort, note, updated_by)
select 'all', 'pm', '삼성카드 할부 혜택',
       E'**삼성카드 6개월 할부 시 추가할인**\n**24/36개월 무이자 할부**\n※ 100만원 이상 제품부터 적용되며, 전화주문 시 가능합니다.\n※ 자세한 문의는 전화 및 카카오톡 상담을 이용해주세요.',
       'blue', '카카오 상담 바로가기', 'https://open.kakao.com/o/sQFilWrg', 'kakao', 'price_below', 'test', 10, '프라자몰 스킨 custom-benefit-notice 에서 옮김', 'mvp_270'
where not exists (select 1 from sub.goods_note where mall = 'pm' and scope = 'all' and title = '삼성카드 할부 혜택');
insert into sub.goods_note (scope, mall, title, body, tone, pos, status, sort, note, updated_by)
select 'all', 'pm', '배송 안내',
       E'!!대형 가전 제품의 경우 삼성물류 직배송으로 전국배송 가능하며,!!\n!!배송기간은 본사 재고량에 따라 일정 안내 해 드립니다.!!\n※ 10월부터 제품 설치/폐가전 회수 시 상황에 따라 특수장비 비용 발생됩니다.\n※ 비용발생에 대한 자세한 문의는 전화 및 카카오톡 상담을 이용해 주세요.',
       'blue', 'price_below', 'test', 20, '프라자몰 스킨 custom-benefit-notice 에서 옮김', 'mvp_270'
where not exists (select 1 from sub.goods_note where mall = 'pm' and scope = 'all' and title = '배송 안내');
insert into sub.goods_note (scope, mall, title, body, img, tone, pos, status, sort, note, updated_by)
select 'all', 'pm', '네이버 프로모션 배너', '',
       'https://store.img11.co.kr/42182336/7ad5ffa7-e7fa-4b87-98fd-ae8da0bd7153_1788142957209.png',
       'plain', 'buy_above', 'test', 10, '프라자몰 스킨 naver-promo-banner 에서 옮김', 'mvp_270'
where not exists (select 1 from sub.goods_note where mall = 'pm' and scope = 'all' and title = '네이버 프로모션 배너');
