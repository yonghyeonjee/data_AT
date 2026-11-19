-- mvp_280 · 2026-11-10 · 발송 대상 추출 — 채널 여러 개 · 추출은 캠페인명 없이
-- (적용됨 — 이 파일은 기록용)
--
-- 왜: "고도몰만 고를 수가 없네, 여러개를 고를 수가 없는데 채널을? · 추출단계에서는 일단 캠페인명을 필수로 하지 말자"
--
-- public.fn_crm_targets_v2 (서명·ACL 그대로 · 서버 원본을 읽어 세 곳만 치환)
--  ① p_channel = 쉼표로 이은 채널 여러 개('P몰,S몰,AT몰,시흥몰') — 하나라도 맞는 고객(source_channels 또는 customer_roll.chans 와 겹침).
--     한 개만 보내면 전과 같다. 채널 이름에 쉼표가 든 것은 없다(확인).
--  ② 캠페인명(p_reason)은 내보내기(p_export)·실번호 보기(p_unmask)일 때만 3자 이상 필수. 가린 번호 미리보기(추출)는 비워도 된다.
--  ③ 감사로그(crm.access_log.reason)는 비었으면 '(캠페인명 없음 · 조회)'.
--
-- 화면(admin.html): 채널 select → 여러 개 고르는 상자(#crmChBtn·#crmChBox · [전체][고도몰 전체] · 값은 숨은 #crmCh 에 쉼표로 —
--   저장 조건·조건 복사/붙여넣기·tgParams 그대로) · 캠페인명 '필수' 표시 뺌 · 실번호 보기·엑셀·문자 보내기는 캠페인명 요구.
--
-- 시험(롤백 블록 · 관리자 클레임): HAF-HIN 제품 기준 — 채널 없음 2,822 · P몰 1,910 · 고도몰 4곳 2,505 /
--   수신동의 · 고도몰 4곳 3,346 / 캠페인명 없이 내보내기 → 거절 / 감사로그 '(캠페인명 없음 · 조회)'.

do $outer$
declare v_def text; r record; v_n int;
begin
  v_def := pg_get_functiondef('public.fn_crm_targets_v2'::regproc);
  if position('mvp_280' in v_def) > 0 then raise exception '이미 적용됨'; end if;
  for r in select * from (values
    ($a$if p_reason is null or length(btrim(p_reason)) < 3 then raise exception '캠페인명을 3자 이상 입력하세요'; end if;$a$,
     $b$/* mvp_280: 추출(가린 번호 미리보기)은 캠페인명 없이도 된다 — 내보내기·실번호 보기는 그대로 필수 */
  if (p_export or p_unmask) and (p_reason is null or length(btrim(p_reason)) < 3) then raise exception '캠페인명을 3자 이상 입력하세요 (내보내기·실번호 보기는 감사로그에 남습니다)'; end if;$b$),
    ($a$c.source_channels @> array[p_channel] or o.chans @> array[p_channel]$a$,
     $b$c.source_channels && string_to_array(p_channel, ',') or o.chans && string_to_array(p_channel, ',')$b$),
    ($a$else least(v_total, v_lim) end, p_reason);$a$,
     $b$else least(v_total, v_lim) end, coalesce(nullif(btrim(p_reason), ''), '(캠페인명 없음 · 조회)'));$b$)
  ) t(a, b) loop
    v_n := (length(v_def) - length(replace(v_def, r.a, ''))) / length(r.a);
    if v_n <> 1 then raise exception '지점 % 개: %', v_n, left(r.a, 40); end if;
    v_def := replace(v_def, r.a, r.b);
  end loop;
  execute v_def;
end $outer$;
