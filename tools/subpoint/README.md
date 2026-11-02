# 구독 멤버십 포인트 — 삼성닷컴 모델별 수집 (mvp_258 · 2026-11-02)

상품상세 구독탭(`sdp/sub/sub_tab.js`)·구독센터(`/gudok/view.html`)·다품목 계산기는 결제 예상 내역에
**적립 예정 멤버십 포인트** 줄을 보여 주고 실제 구독료에서 뺀다. 이 값의 원본이 `sub.model_point` 다.

| 구분 | 어디서 오나 | 화면에서 |
|---|---|---|
| 행사 포인트 ("N개월 구독료 상당" · AI 구독 페스티벌) | `sub.promo` (관리자 › 구독 혜택 정책 › 행사 · mvp_257) — 삼성 가이드의 품목별 3/6개월 규칙은 행사에 `cats` 로 적는다 | "6개월 구독료 상당 포인트 지원" 줄 (최장 약정 선택 시) |
| 멤버십 포인트 (정률 + 기본 0.1% + 상품별 추가) | **이 수집기** → `sub.model_point` → `sub_policy.js` `points[모델]` | "적립 예정 멤버십 포인트" 줄 = 결제 예상액 × (rate+base)% + add |

둘은 중복 지급이므로 둘 다 보여 주고 둘 다 뺀다.

## 어디서 찾나

| 시도한 곳 | 결과 |
|---|---|
| DPS 올인원구독모델조회 (`dps.sub_model` · 매일 수집) | 포인트 항목 없음 |
| 삼성닷컴 구독 상품 페이지의 "N개월 구독료 상당" 배너 | 이미지 — 읽을 수 없음 → 행사(sub.promo)에 손으로 |
| **`https://www.samsung.com/sec/ai-subs-living/<모델>-subscribe2-d2c/<모델>/`** | 품목 slug 와 무관하게 **마지막 모델번호로 상품을 찾아 준다**. 서버가 그려 준 HTML 의 `StPrdtOptItemVO(goodsId=G00…, mdlCode=모델)` 쌍에 이 상품의 **모든 색상·옵션 모델 → goodsId** 가 있다. 없는 모델은 og:url 이 빈 공통 페이지(약 226KB) |
| **`POST /sec/xhr/goods/membershipPolicy`** | `goodsListStr=[{goodsId, mdlCode, price, cnt:1, mainGoodsYn:'Y'}]` 외 form 값 → `{totalPoint, basicRate 0.1, basicRatePoint, aplPoint(정률), mdlAddPoint(상품별 추가), aiscRate "6.0"}` (헤더 `X-Requested-With: XMLHttpRequest`) |

예: AI 콤보 WD90H25AHS 6년 총 6,066,720원 → 370,069P = 정률 6%(364,003) + 기본 0.1%(6,066) + 추가 0.

## 어떻게 돌아가나

```
GitHub Actions sub-point.yml (매주 월요일 09:00 KST · 수동 실행 · 관리자 [지금 수집] → Edge Function sub-deploy?wf=sub-point)
  └ node tools/subpoint/collect.mjs
      ├ fn_sub_point_targets(p_all, p_limit, p_key) : 활성 모델 + 최장 약정 최저 총액 + 캐시된 goods_id  (처음 보는 것 · 6일 지난 것 · 못 찾은 것은 7~30일 뒤)
      ├ goods_id 가 없으면 구독 상품 페이지 1번 (형제 모델 goodsId 도 캐시) → membershipPolicy 1번   (동시 3 · 0.4초 간격)
      └ fn_sub_point_upsert(p_rows, p_key, p_meta) : sub.model_point (src 'samsung.com' · 손 입력 행은 안 덮음) · sub.model_point_check · sub.model_point_fetch
            └ 저장 트리거 sub.f_deploy_kick → sub-deploy → sdp-publish.yml → sdp/sub/sub_policy.js 의 points 갱신
sub.f_policy_export() → points: {모델: {rate: 6.0, base: 0.1, add: 5000, total: 370069}}   (정률·추가 포인트가 하나라도 있는 모델만)
```

- **손 입력**: 관리자(admin.html › 품목 › 구독 혜택 정책 › 모델 포인트) `fn_sub_point_save` · 매장(store.html › 구독 › 구독 혜택 안내) `fn_store_sub_point_save(p_code, p_data)` — src 'manual' 이 되어 수집이 덮지 않는다. [수집값으로 되돌리기](release) 를 누르면 다음 수집이 다시 덮는다.
- **키**: 수집기는 서비스 롤 키(Actions Secrets `SUPABASE_SERVICE_ROLE_KEY`) 또는 API 키 `SUB_POINT_KEY`(core.api_key 'sub_point' · 해시만 DB 에 · 값은 `_secrets.local.md`) 로 부른다. 코드·표·git 에는 없다.
- 기준 총액은 DPS 최장 약정의 최저 total_fee(무상수리). 화면은 저장된 총 포인트가 아니라 **정률 × 고객이 고른 조건의 결제 예상액 + 추가 포인트** 로 다시 계산한다.

## PC 에서

```bash
node tools/subpoint/collect.mjs --models WD90H25AHS,WD90H25AHW --dry                 # DB 없이 (기준 총액 0 → 정률·추가 포인트만)
node tools/subpoint/collect.mjs --models WD90H25AHS --dry --price 6343920 --out out.json
```
DB 에 넣으려면 `SUPABASE_URL` · `SUPABASE_SERVICE_ROLE_KEY` 환경변수가 있어야 한다.

## 검증

- `tools/sub/build_sub.mjs` checkPolicy 가 `points` 모양(모델 키 · rate/base 0~100 · add/total 양의 정수)을 검사한다.
- 상품 1000000941 · 1000000827 구독탭, `db.samsungat.co.kr/gudok/view.html?model=WD90H25AHW` 결제 예상 내역에 "적립 예정 멤버십 포인트" 줄.
