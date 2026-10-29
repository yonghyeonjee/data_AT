# 구독센터 제품 사진 — 삼성닷컴 대표 이미지 수집 (mvp_252 · 2026-10-29)

구독센터(`/data/gudok/view.html?model=…` · `airdresser.html` 등)와 상품상세 구독탭의 **제품 사진**은 데이터센터 `fn_sub_catalog` 가 준다.
전에는 고도몰 목록용 썸네일(`goods/<상품번호>/image/list/…` · 88px 짜리가 많음)이라 작게 보였다.
이제는 **삼성닷컴 대표 사진**을 먼저 쓰고, 못 찾은 모델만 고도몰 사진으로 둔다.

## 어디서 찾나

| 시도한 곳 | 결과 |
|---|---|
| `searchapi.samsung.com …/product/card/detail/global?siteCode=sec&modelList=` | 빈 목록 (sec 는 글로벌 검색 API 를 안 씀) |
| `www.samsung.com/sec/search/?searchvalue=모델` | JS 렌더 · 모델번호 검색은 "결과 없음" |
| `www.samsung.com/sec/sitemap.xml` 의 제품 주소 `/sec/<품목>/<slug>/<모델>/` | 모델 5,995개 중 구독 모델과 겹치는 건 **30개** (구독 전용 모델은 판매 페이지가 없다) · slug 를 모르면 못 연다 |
| `samsungaicare.co.kr/product/<모델>` (Edge Function `sub-image-sync` · 2026-10-28) | 341개 · 구독 인증점 페이지라 삼성닷컴 원본 주소를 미리 불러오는 걸 긁는다 |
| **`www.samsung.com/sec/support/model/<모델>/`** (고객지원 모델 페이지) | **모델번호만으로 열리고** 서버가 그려 준 HTML 에 대표 사진이 있다. 구독 전용 모델(…T·…Z)도 있다. 없는 모델은 500 |

고객지원 페이지의 `<div class="support-box-prod"><div class="prod-img"><img src="//images.samsung.com/kdp/goods/…png?$450_N_PNG$" alt="제품명">` 를 읽는다.
사진 주소는 `?imwidth=720` 을 붙여 720px 로 받는다 (`images.samsung.com` 은 `Access-Control-Allow-Origin: *` · `Cache-Control: max-age=3600` · Referer 로 막지 않음 — 핫링크 가능).

## 어떻게 돌아가나

```
GitHub Actions sub-image.yml (매일 05:40 KST · 수동 실행 가능)
  └ node tools/subimg/collect.mjs
      ├ fn_sub_image_samsung_targets(p_all)  : 활성 모델 중 미확인·오래된 것 (찾은 것 30일 · 못 찾은 것 7~30일 뒤 다시)
      ├ 삼성닷컴 고객지원 페이지 읽기 (동시 4 · 0.25초 간격 · 사진 HEAD 로 열리는지 확인)
      └ fn_sub_image_samsung_save(p_rows)    : 찾은 것 → core.sub_model_image (note 'auto:samsung.com/support · 제품명')
                                               확인 기록 → core.sub_model_image_check · 끝에 core.f_sub_model_image_refresh()
fn_sub_catalog : core.sub_model_image 가 있으면 그것(종류 'm') → 없으면 core.sub_model_image_auto (고도몰·대표 이미지)
```

- `core.sub_model_image` 의 **손으로 넣은 행**(note 가 `auto:` 로 시작하지 않음)은 수집기가 덮지 않는다. 관리자가 특정 모델 사진을 고정하려면 note 에 다른 말을 쓰면 된다.
- 모델번호에 `/` 가 있는 사운드바(`HW-Q800H/KR`)는 `/` 를 그대로 둔 주소(`…/model/HW-Q800H/KR/`)로 연다 (`%2F` 는 404).

## PC 에서

```bash
node tools/subimg/collect.mjs --models DF80H24R1D,KQ55QNH80AFXKR --dry --out out.json   # DB 없이 결과만
node tools/subimg/collect.mjs --models-file 모델목록.txt --dry --out out.json             # 공백·줄바꿈 구분 목록
```
DB 에 넣으려면 `SUPABASE_URL` · `SUPABASE_SERVICE_ROLE_KEY` 환경변수가 있어야 한다 (키는 Actions Secrets 에만).

## 2026-10-29 첫 수집 (PC 에서 --dry 로 확인)

활성 994 모델 중 **989개** 에서 삼성닷컴 사진을 찾았다 (12분). 못 찾은 5개(고객지원 페이지 없음 · 고도몰 사진 유지):
`AF60H17D12BT1 CC80F63W1Z CC80F63X1Z WA10CG5441BW WA16CG6441BY`.
DB 적재는 이 파일을 푸시하면 도는 Actions 가 한다. 지금 수는 `select count(*) from core.sub_model_image where note like 'auto:samsung.com%'`.
