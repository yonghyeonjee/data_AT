-- mvp_205 (2026-10-13) 홈페이지 견적 문의 폼 필드 이름 → 웹훅 이름표
-- 홈페이지(samsungat.co.kr)는 워드프레스가 아니라 맑음 자체 PHP (가비아 '워드프레스 호스팅' 상품 위 · /board/*.php · wp-content 없음)
-- 견적 문의 폼 board/contact/board_write.php → action board_proc.php (multipart · target 숨은 iframe)
--   subject=성함 · etc_2=연락처 · etc_5=방문경로(체크박스 합침, etc_5_temp/etc_5_etc 는 원본) · etc_6=구매옵션 · etc_7=아파트명
--   etc_8=희망품목 · etc_9=제품모델명 · etc_10=상담방법 · file_name=첨부 · user_agree · csrf_token
--   폼에 '문의내용' 칸이 없다 (메일로 들어온 건마다 문의내용이 비어 있던 이유)
-- 맑음이 $_POST 를 그대로 보내도 읽히게 core.f_hook_label 에 덧붙였다 (서버 원본에서 '구분' 줄 앞에 치환 · 지점 1개 확인)
do $outer$
declare v_def text; v_old text := 'when ''구분'' then ''kind''';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='core' and p.proname='f_hook_label';
  if position('etc_2' in v_def) > 0 then raise notice '이미 있음'; return; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception '지점 수가 1이 아님'; end if;
  execute replace(v_def, v_old,
    '/* 맑음 홈페이지 견적 문의 폼(board/contact/board_write.php) 필드 이름 */
    when ''subject'' then ''name'' when ''etc_2'' then ''phone'' when ''etc_5'' then ''route'' when ''etc_6'' then ''option''
    when ''etc_7'' then ''apt'' when ''etc_8'' then ''items'' when ''etc_9'' then ''model'' when ''etc_10'' then ''method''
    when ''file_name'' then ''attach''
    ' || v_old);
end $outer$;
-- 확인: 실제 주소에 form-urlencoded dry=1 → name·phone·route·option·items·model·method 전부 읽힘 (raw.webhook_log 15)
