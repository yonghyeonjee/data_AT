-- mvp_296 (2026-11-12) 상담 견적 /quote/ — 들어갈 때마다 담당자 확인 창이 뜨던 문제 · 기존 견적서 링크로 열어서 수정
--
-- ① fn_quote_page_me 를 VOLATILE 로 (DB 이름 mvp_294_quote_page_me_volatile 로 적용)
--    mvp_276 에서 STABLE 로 만들었는데 본문이 세션 last_seen 을 UPDATE 한다.
--    로그인이 살아 있으면 "UPDATE is not allowed in a non-volatile function" → PostgREST 400 → 화면 auth() 가 실패로 보고
--    매번 이름+비밀번호 창을 띄웠다 (60분 유지·뒷번호 4자리도 안 먹었다). 세션이 없을 때는 UPDATE 를 안 타서 200 이라 눈에 안 띄었다.
alter function public.fn_quote_page_me(text) volatile;

-- ② fn_quote_page_resolve(p_code, p_ref) — 고객 링크(…/q/?t=토큰) · 토큰만 · 견적번호(SH261111-004) · 옛 시흥몰 견적서 주소(&no=SH…)
--    → {ok, no, version, name, counselor}. 담당자 세션 또는 견적서 페이지 코드가 있어야 한다 (fn_quote_page_get 과 같은 문).
create or replace function public.fn_quote_page_resolve(p_code text, p_ref text)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public' as $$
declare v_ref text := btrim(coalesce(p_ref,'')); v_tok text; v_no text; v_q crm.quote;
begin
  if not core.f_quote_page_ok(p_code) then perform pg_sleep(0.7); raise exception '권한이 없습니다' using errcode='42501'; end if;
  v_tok := substring(v_ref from '[?&]t=([0-9a-fA-F]{16,64})');
  if v_tok is null and v_ref ~ '^[0-9a-fA-F]{32}$' then v_tok := v_ref; end if;
  if v_tok is not null then
    select quote_no into v_no from crm.quote_share where token = lower(v_tok);
    if v_no is null then return jsonb_build_object('ok', false, 'reason', '이 링크의 견적서를 찾지 못했습니다'); end if;
  else
    v_no := upper(substring(v_ref from '(?i)(SH\d{6}-\d{3,4})'));
    if v_no is null then v_no := upper(substring(v_ref from '[?&]no=([A-Za-z0-9\-]+)')); end if;
    if v_no is null then return jsonb_build_object('ok', false, 'reason', '견적서 링크나 견적번호(SH…)를 넣어 주세요'); end if;
  end if;
  select * into v_q from crm.quote where quote_no = v_no order by version desc limit 1;
  if v_q.quote_no is null then return jsonb_build_object('ok', false, 'reason', '견적 '||v_no||' 을 찾지 못했습니다'); end if;
  return jsonb_build_object('ok', true, 'no', v_q.quote_no, 'version', v_q.version, 'name', v_q.customer_name, 'counselor', v_q.counselor);
end $$;
revoke all on function public.fn_quote_page_resolve(text, text) from public;
grant execute on function public.fn_quote_page_resolve(text, text) to anon, authenticated, service_role;

-- 화면 (v303)
--   quote/index.html : [내역] 창 맨 위 "견적서 링크 또는 견적번호 붙여넣기 → [열어서 수정]" · 모델 찾기 칸에 링크를 붙여 넣어도 열림
--                      /quote/?t=토큰 · ?ref=… 로 들어와도 열림 (로그인 전이면 담당자 확인 뒤 이어서) · 저장하면 같은 번호의 다음 차수
--   q/index.html     : 담당자 로그인이 살아 있는 브라우저에서 고객 링크를 열면 오른쪽 아래 [✏️ 이 견적 수정] (고객 폰에는 안 보임)
--   store.html       : 내 견적서 · 홈 찾기 결과 줄 [열기 ↗](옛 시흥몰) 옆에 [수정 ↗](상담 견적)
--
-- 같은 실수(STABLE 인데 쓰기)가 남은 곳: public.fn_sms_log — p_unmask 일 때 접근 기록 insert 가 막힐 수 있다 (따로 확인할 것)
