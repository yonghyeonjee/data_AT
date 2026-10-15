-- mvp_212 · 2026-10-15 · DPS 공용 고객 'DP'(customer_no 0012440257 · 서울대점 · 6명 담당자가 소모품 171건)를 사람으로 세지 않는다 + 내 고객 번호는 실번호
-- 적용: 2026-10-15 (MCP execute_sql · 서버 본문 치환 · 롤백 검증: 차효범 내 고객 480명 · DP 0 · 가린 번호 0 · 고객 찾기 'DP' 0)
alter table crm.customer add column if not exists is_placeholder boolean not null default false;
comment on column crm.customer.is_placeholder is 'DPS 공용 고객(DP 등)처럼 사람이 아닌 줄 — 내 고객·고객 찾기에서 뺀다 (mvp_212)';
update crm.customer set is_placeholder=true where buyer_key='47dc57d15461dd6c' and name='DP';
-- fn_store_my_customers: join crm.customer c on c.buyer_key = b.buyer_key  →  … and not coalesce(c.is_placeholder,false)
--                        'phone' 가림(left 3 ||'-****-'|| right 4) → 실번호 010-1234-5678 (내 고객은 이미 [전화] 버튼에 tel 이 실려 있어 가림이 이름뿐이었다)
-- fn_store_customer_search: where (c.name ilike …) or (… phone like …)  →  where not coalesce(c.is_placeholder,false) and ((…) or (…))
-- (치환 do 블록은 세션 기록 — 지점 개수 1 검증 뒤 execute)
