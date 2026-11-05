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

## 여러 고도몰 (mvp_265 · 2026-11-03)

데이터센터 하나로 시흥몰(`sh` · www.samsungsh.co.kr)과 프라자몰(`pm` · www.samsungpmall.com) 상품상세 구독탭을 같이 운영한다. 몰 목록은 `sub.mall`.
- 요금표·할인·카드·포인트·스마트 패키지는 **모든 몰 공통**이다. 몰마다 다른 것은 **행사 문구**(`sub.promo.malls` · 비면 모든 몰)와 스킨 설정뿐이다.
- 배포 `sub_policy.js`: `promos` = 시흥몰에 나갈 행사(모든 몰 + sh) · `promosAll` = 전부(`malls` 표시). 구독탭은 스킨 `SUB_TAB_CONFIG.mall`(기본 `sh`)로 고른다 — 웹FTP 에 올라가 있는 예전 시흥몰 사본은 `promos` 만 읽으므로 그대로 맞다.
- 상품번호(`goods`)로 고른 행사는 몰마다 번호가 겹치므로 몰을 안 고르면 시흥몰(`sh`)로 저장된다.
- 스킨: 시흥몰 = `deploy/sub_tab_godo/sub_tab_v*_*.html`(웹FTP /data/js/sub/ 사본) · 프라자몰 = `deploy/sub_tab_godo/sub_tab_pmall.html`(`mall:'pm'` · 화면 파일을 데이터센터에서 바로 읽음 · 상품명 속 모델번호도 찾음).
- 몰을 더 붙이려면 `insert into sub.mall (code, name, domain, sort)` 한 줄 + 그 몰 스킨에 같은 모듈을 `mall:'<코드>'` 로.

## 누가 무엇을 고치나

| 바뀐 것 | 어디서 | 누가 |
|---|---|---|
| 모델별 월요금·신모델·선납 미운영 모델 | DPS 올인원구독모델조회 (수집기가 매일 올림 · `dps.sub_model`) | 자동 |
| 정수기 본사 할인값, 카드 금액표 | SDP 판 (`tools/sdp/README_release.md`) | 온라인사업부 |
| 자동납부 할인율, 선납 비율별 할인율·품목별 한도·이름 규칙, 기본 문구 | 관리자 › 품목 › **구독 혜택 정책** | 관리자 |
| 카드 유의사항·노출 기간·숨김, 행사 문구(기간·대상 품목/모델/상품번호·**대상 몰** mvp_265) | 관리자 › 구독 혜택 정책 **또는** 매장 › 견적서 › **구독 혜택 안내** | 관리자 · 점장님·대표님 |
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

## 구독료 지원 행사모델 (N개월 구독료 상당 포인트) — 매달 본사 엑셀을 행사 줄로

본사 가이드의 `□ N월 구독료 지원 행사모델 리스트_*.xlsx`(시트1 모델·약정·케어별 줄 + 시트2 '모델' 품목·모델명·지원개월)를 `sub.promo` 행사 줄로 옮긴다. 지원 금액은 **지원개월 × 월구독료**(최장 약정에서만)라 금액표를 넣지 않고 `months`·`models`·`maxTerm` 만 넣는다 — 구독센터·상품 구독탭·`/quote/` 견적서가 같은 식(`sub_tab.js pointsOf`)으로 금액을 낸다.

```bash
python tools/sub/promo_from_xlsx.py "<리스트.xlsx>" 2026-11 sql/mvp_277_sub_promo_202611.sql "--note=배송 '27.02.28까지" --by=mvp_277
```
- 만든 SQL 은 같은 달의 예전 줄(note `promo_xlsx:YYYYMM:%`)을 `active=false` 로 하고 (약정 년 · 지원 개월) 묶음마다 `sub.f_promo_save` 한 줄 — MCP `execute_sql` 로 실행(승인 뒤). 저장 트리거가 10분 안에 `sub_policy.js promos[]` 로 배포한다.
- 영업정책 게시판에서 받은 파일은 **NASCA DRM** 이라 openpyxl 이 못 읽는다(`BadZipFile`). 이 PC 의 Excel 은 DRM 을 풀어 열 수 있으므로 `tools/sub/xlsx_to_tsv.ps1` 로 시트를 TSV 로 뽑은 뒤 그 `.tsv` 를 넣는다 (`_s1.tsv`·`_s2.tsv` 두 장).
- 11월 판(2026-11-04): 모델 553 (시트1 522 + 시트2 PC·Tab 31) · 6년 6개월 152 · 6년 3개월 237 · 5년 6개월 12 · 4년 6개월 72 · 4년 3개월 49 · 시트2만 있는 모델 31 은 '최장 약정 시 6개월'. 10월 판과 460 모델 겹친다. 요금표(`sub_index.js`)에 없는 모델 66(TV KQ/KMR·모니터 LS·갤럭시)은 구독센터에 상품이 없어 그냥 지나간다.
