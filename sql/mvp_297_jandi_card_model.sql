-- mvp_297 · 2026-11-16 · 구독 문의 잔디 카드에 모델명 (DB 에 적용됨)
-- "잔디로 갈 때도 문의 내용이 같이 가나?" → "모델명 정도만 가도 되는데, 전체는 안 가도"
-- 진단 결과·구독 가격 탭 프리필의 1위 모델(raw_payload.diagRecommend)은 상담 content 에만 있고
-- 잔디 카드 '📦 상담 정보' 에는 고른 제품 칩(modelName · 예 'TV')만 갔다.
-- 일반 구독 문의 카드 상담 정보 맨 앞에 '모델 <diagRecommend>' 를 붙인다 (값이 없으면 전과 같음).
-- 메모 전문(구독 가격 탭 요약)은 카드에 넣지 않는다. B2B 구독 카드는 그대로.
-- 예: #1033 → '모델 KMR85RH9G-93L7 | TV · 구독 | 안양(카카오톡) | 없음(신규) · 있음 · 미정'

do $outer$
declare v_def text; v_old text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_submit_inquiry';
  v_old := $q$else concat_ws(' | ',$q$;
  v_new := $q$else concat_ws(' | ',
        case when nullif(p_data->>'diagRecommend','') is not null then '모델 ' || (p_data->>'diagRecommend') end,   /* 진단·구독 가격 탭 모델명 (mvp_297) */$q$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception '지점 개수 %', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $outer$;

-- 같은 날 2차: 다품목 계산기는 diagRecommend 에 모델을 쉼표로 붙여 보낸다(#996 · 5개 · 띄어쓰기 없음)
-- → 여러 개면 '모델 5대: A, B, C, D, E' (대수 + 쉼표 뒤 띄어쓰기). 하나면 '모델 A' 그대로.
-- 진단·가격 탭 없이 칩만 고른 다품목(#1030 '냉장고, 세탁건조기')은 모델 값이 없어 전과 같다.
do $outer$
declare v_def text; v_old text; v_new text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='fn_submit_inquiry';
  v_old := $q$'모델 ' || (p_data->>'diagRecommend') end,$q$;
  v_new := $q$'모델 ' || case when p_data->>'diagRecommend' like '%,%' then array_length(regexp_split_to_array(trim(p_data->>'diagRecommend'), '\s*,\s*'), 1)::text || '대: ' else '' end || regexp_replace(trim(p_data->>'diagRecommend'), '\s*,\s*', ', ', 'g') end,$q$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception '지점 개수 %', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $outer$;
