# 상품상세 구독탭 데이터 — 데이터센터에서 관리·배포 (mvp_246 · mvp_249 · 2026-10-27)

고도몰 상품상세(`goods/goods_view.html`)의 **일시불/구독 탭**이 읽는 파일을 데이터센터가 만들어 **`https://db.samsungat.co.kr/sdp/sub/`** 에 올린다.
요금표는 **DPS 올인원구독모델조회 수집분(`dps.sub_model` · mvp_240 · 매일)** 에서(mvp_249 · 2026-10-27부터), 카드 금액·정수기 본사 할인값은 SDP 판(`sdp.release` · mvp_245)에서, 정책·문구는 `sub.policy` 표에서 온다. 고도몰에는 HTML 과 예비 사본만 둔다.

## 요금표 원본 = DPS (mvp_249)
- `fn_sub_dps_export()`(service_role) 가 `dps.sub_model` 의 active 행 전부를 주고, `build_sub.mjs` 가 수집기 `export_products_js.mjs` 와 같은 규칙으로 요금표로 바꾼다.
  - 품목: 에어컨 중 세부유형이 천장형 실내기·전열교환기면 **시스템에어컨**, 세탁기·건조기·에어드레서 → 의류케어, 전기레인지·식기세척기·후드 → 조리기기.
  - 요금제 이름: SDP 엑셀판 표기 그대로 — `무상수리(재설치포함)`→`무상수리`, 방문케어 12개월 주기는 `방문케어`(그 밖은 `방문케어(36개월주기)`), 셀프케어는 항상 주기 표기, 갤럭시는 `파손보험+무상보증(36개월)` 꼴.
  - 선납 불가(`np`) = DPS 호버 표에 0% 말고 선납 비율이 없는 모델. 세부유형(`s`)은 DPS 원문.
  - DPS 목록에서 빠진 모델(active=false)은 자연히 빠진다 → 주문 불가 모델이 상세페이지에 안 나온다. SDP 엑셀판에만 있던 208개(묶음코드·B2B 코드 등)는 2026-10-27 전환 때 제외됐다.
- 안전장치(`publish.mjs`): 최신 수집이 **24시간** 넘게 없거나, 모델 수가 직전 배포판(`version.js` 의 `SUB_MODELS`)보다 **10% 넘게 줄거나 500 미만**이면 구독탭 파일을 안 바꾸고(이전 판 유지) `sdp.publish_log` 에 `sub_skipped` 로 남긴다. 이때는 정책 변경도 다음 정상 수집 뒤에 반영된다. DPS 를 아예 못 받으면 SDP 판 `DATA` 로 만든다(이전 방식).
- 판 번호: `SUB_VER = "<SDP 판>+<정책 판>+d<수집시각 YYMMDD-HHMM>"`, `version.js` 에 `SUB_DPS_VER`·`SUB_MODELS`, `sub_index.js` 에 `src: "dps"`.
- PC 에서 시험: `node tools/sub/build_sub.mjs <data_*.js 폴더> <출력> [sub_policy.json] --dps-rows <수집기 outputs/playwriter/구독모델/sub_model.json>`

```
SDP 판 (DATA · PREPAY_NO · CARD · WATER_POLICY) ─┐
                                                   ├─▶ Actions sdp-publish.yml (10분마다 · publish.mjs → build_sub.mjs) ─▶ sdp/sub/*.js ─▶ 상세페이지 구독탭
sub.policy · sub.card_policy · sub.promo ──────────┘      (관리자 [품목 › 구독 혜택 정책] · 매장 [견적서 › 구독 혜택 안내] 에서 고친다)
```

| 파일 (`sdp/sub/`) | 무엇 | 원본 |
|---|---|---|
| `version.js` | `SUB_VER = "<SDP 판>+<정책 판>"` — 상세페이지가 5분 단위로 읽어 바뀌면 아래 파일을 새로 받는다 | 자동 |
| `sub_index.js` | 모델번호 → [품목 키, 최저 월구독료, 최저 총구독료] (모든 상품상세가 받음 · 약 35KB) | DPS `dps.sub_model` (못 받으면 SDP `DATA`) |
| `sub_plans_<품목키>.js` | 품목별 요금표 + 선납 미운영 + 정수기 본사 할인값 (구독 모델일 때 1개) | DPS (요금·선납 불가) · SDP `WATER_POLICY` |
| `sub_cards.js` | 제휴카드 청구할인 표 | SDP `CARD` |
| `sub_policy.js` | 자동납부·선납 할인율, 품목별 선납 한도, 카드 유의사항·노출 기간, 행사 문구, 안내 문구, **공통 기준값 `defaults`**(처음 선택 카드·실적 구간 · 상담 신청 주소 · 전화 — 구독탭·구독센터 상세·목록이 같이 읽는다 · mvp_253) | `fn_sub_policy_export()` |
| `sub_tab.js` · `sub_tab.css` | 탭 화면 코드 (손으로 커밋 · 생성 아님) | 이 저장소 |

**공개 파일이다** — 제품 일시불가(`v`)·SPECS·인센티브·포인트 표는 넣지 않는다 (`build_sub.mjs` 가 애초에 읽지 않는다). 상세페이지 일시불가는 고도몰 판매가를 쓴다.

## 누가 무엇을 고치나

| 바뀐 것 | 어디서 | 누가 |
|---|---|---|
| 모델별 월요금·신모델·선납 미운영 모델 | DPS 올인원구독모델조회 (수집기가 매일 올림 · `dps.sub_model`) | 자동 |
| 정수기 본사 할인값, 카드 금액표 | SDP 판 (`tools/sdp/README_release.md`) | 온라인사업부 |
| 자동납부 할인율, 선납 비율별 할인율·품목별 한도·이름 규칙, 기본 문구 | 관리자 › 품목 › **구독 혜택 정책** | 관리자 |
| 카드 유의사항·노출 기간·숨김, 행사 문구(기간·대상 품목/모델/상품번호) | 관리자 › 구독 혜택 정책 **또는** 매장 › 견적서 › **구독 혜택 안내** | 관리자 · 점장님·대표님 |
| 모델·약정·케어별 월 구독료를 손으로 바꾸기 · 모델 숨기기 · DPS 에 없는 모델 넣기 (mvp_251) | 매장(store/test) › 견적서 › **구독 요금 직접 관리** — `sub.price_override` · 배포 때 `build_sub.mjs applyOverrides` 가 DPS 요금표에 덧씌움 · 끄면 DPS 값으로 | 점장님·대표님 |
| 한 상품만 급히 요금 수정 | 고도몰 상품 추가항목 `구독요금` | 쇼핑몰 담당 |

저장은 바로 DB 에 들어가고(`sub.policy_log` 에 앞·뒤 값), **배포는 10분 안에** Actions 가 한다. `fn_sub_policy().deployed` / 관리자 카드 머리의 "마지막 배포" 로 확인한다.
값 검사(`sub.f_policy_check`)는 저장할 때 막는다 — 비율은 0 이상 1 미만 소수(화면에서는 %), 날짜는 YYYY-MM-DD, 선납 단계마다 할인율이 있어야 한다. `build_sub.mjs` 가 배포 전에 같은 규칙으로 한 번 더 본다.

## 고도몰 쪽

`goods_view.html` 의 `SUB_TAB_CONFIG.dcBase` 가 `https://db.samsungat.co.kr/sdp/sub/` 이면 데이터센터에서 받고, 못 받으면(차단·장애) `dataBase`(`/data/js/sub/` 웹FTP 예비 사본)로 돌아간다.
`dcBase` 를 비우면 데이터센터를 쓰지 않는다 — 단계적으로 켤 때 쓴다. 예비 사본은 고도몰 패키지의 `build_sub_index.py` 로 만들며 오래될 수 있으니 판을 크게 바꾼 뒤엔 한 번 갈아 둔다.

## PC 에서 확인

```bash
node tools/sub/build_sub.mjs <data_*.js 폴더> <출력 폴더> [sub_policy.json]   # 배포 없이 파일만 만들어 본다
```
고도몰 패키지 `tools/build_sub_index.py` 와 같은 입력이면 같은 출력이 나와야 한다 (2026-10-27 · 261027-1 판 1,209 모델로 18개 파일 일치 확인).

## 새 품목이 생기면

`build_sub.mjs` 의 `CAT_KEYS` 에 영문 키를 넣고(고도몰 패키지 `build_sub_index.py` 도 같이), 관리자 구독 혜택 정책에서 그 품목의 최대 선납 비율을 적는다. 키가 없는 품목은 배포 로그에 "CAT_KEYS 에 없는 품목" 으로 찍히고 건너뛴다.
