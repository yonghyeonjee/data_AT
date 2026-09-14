-- mvp_137 · 2026-09-14 — 네임카드 저장소를 시트 → 데이터센터(core.namecard)로
-- 견적서 페이지(고도몰 quote_subscribe.php)가 GAS 대신 아래 RPC 를 공개키(anon)로 부른다. 서버는 페이지 보안 코드(SH_CODE)의 SHA-256 을
-- core.app_setting 'quote_page_code_hash' 와 대조한다 (페이지 잠금과 같은 수준). 페이지는 첫 로드 때 브라우저 캐시에만 있던 카드를 한 번 옮긴다.
insert into core.app_setting (key, value) values ('quote_page_code_hash', '<페이지 보안 코드 SHA-256 — DB 에만>') on conflict (key) do nothing;
create or replace function core.f_quote_page_ok(p_code text) returns boolean
language sql stable set search_path to 'pg_catalog','public' as $$
  select encode(extensions.digest(coalesce(p_code,''), 'sha256'), 'hex') = coalesce((select value from core.app_setting where key = 'quote_page_code_hash'), 'x');
$$;
-- public.fn_quote_nc_list(p_code) → {ok, cards[]} · fn_quote_nc_save(p_code, p_card) → {ok, card} (id 없으면 'NC'+epoch ms 발급, staff.mobile 도 갱신)
-- · fn_quote_nc_delete(p_code, p_id) → {ok}. 셋 다 anon 에 grant. 본문은 DB 참고.
-- fn_submit_quote 의 namecard upsert 는 on conflict do nothing 으로 바꿈 — 시트 판(옛 GAS listCards)이 데이터센터 카드를 덮지 않게.
