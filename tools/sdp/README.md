# SDP 구독 계산기 제품 정보 → 데이터센터 (mvp_194 · 2026-10-08)

견적서 페이지가 쓰는 `data_products.js`(SDP 구독 계산기 데이터 · `DATA`·`SPECS`·`PREPAY_NO`)를 `core.product` 에 넣는다.
모델마다 카테고리(`category_l1`) · 종류(`category_l2`) · 가격(`list_price` = `v`) · `attrs.sdp.plans`(기간·케어·총액·월 요금) ·
`attrs.features` · `attrs.sdp.prepay_no` 가 들어간다. **제품명은 기존 정보에서** — 원장(`core.orders`)에 그 모델로 가장 많이 적힌 상품명 →
재고 품목명(`inv.item`) → 없으면 `카테고리 종류`(`attrs.name_source` 로 어디서 왔는지 남긴다).

| 파일 | 무엇 |
|---|---|
| `products_sdp.json` | 0910 + 1001 두 판을 합친 적재용 JSON (`models`·`plans`·`feats`·`care`). DB 가 `fn_product_sdp_fetch` 로 raw.githubusercontent.com 에서 직접 가져간다 |
| `load_products.mjs` | PC 에서 새 `data_products.js` 를 받았을 때: JSON 으로 바꾸거나(`--json`) 관리자 로그인으로 `fn_product_sdp_upsert` 를 바로 부른다 |

새 달 파일이 오면 ① `node load_products.mjs data_products_YYMM.js --json products_sdp.json` 으로 이 파일을 갱신해 커밋 → main 머지 뒤
② Supabase SQL 편집기(또는 관리자 세션)에서 `select public.fn_product_sdp_fetch();` — 또는 ①을 건너뛰고 `node load_products.mjs data_products_YYMM.js` 로 바로 올린다.
같은 모델을 다시 넣어도 중복되지 않는다(모델 코드가 키 · 새 값이 덮고 이름은 기존 정보 우선).
