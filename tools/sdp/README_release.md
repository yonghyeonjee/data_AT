# SDP 계산기 데이터 — 데이터센터 판(release) 관리 (mvp_245 · 2026-10-27)

고도몰 계산기(`service/calc_subscribe.php`)·견적서 페이지가 읽는 `data_*.js` 를 **데이터센터가 원본으로 관리**하고,
반영한 판을 **`https://db.samsungat.co.kr/sdp/`** 에 올린다. 고도몰에는 HTML 만 두고, 데이터는 여기서 가져간다.

```
수집(엑셀·크롤러) ─▶ fn_sdp_release_save ─▶ sdp.release (판) ─▶ fn_sdp_publish(반영)
                                                         └▶ Actions sdp-publish.yml (10분마다) ─▶ sdp/*.js + version.js ─▶ 계산기
```

| 파일 | 무엇 |
|---|---|
| `sdp/version.js` | 지금 판 이름(`SDP_VER`). 계산기가 5분 단위로 새로 읽어 판이 바뀌면 data 파일을 새로 받는다 |
| `sdp/data_products.js` · `data_cards.js` · `data_discounts.js` · `data_appeals.js` · `data_extras.js` | 계산기 데이터. **직접 고치지 말 것** — 다음 배포가 덮는다 |
| `tools/sdp/js_to_release.mjs` | 받은 `data_*.js` → 판 JSON (`--inc data_inc.js` 로 INC 를 따로 뺌) |
| `tools/sdp/release_to_js.mjs` · `publish.mjs` | 판 → `sdp/*.js` (Actions 가 씀) |
| `tools/sdp/release/sdp_*.json` | 큰 판을 DB 가 직접 가져가게 둔 JSON (`fn_sdp_import_url`) |

**INC(모델별 판매 인센티브)는 공개 배포에서 뺀다** — 이 저장소는 공개라 올리면 누구나 본다(커밋 기록에도 남는다).
INC 는 고도몰 `/data/js/data_inc.js` 에만 두고 계산기가 고도몰에서 읽는다. `fn_sdp_release_save` 는 INC 가 들어 있으면 거절한다.
이미지(`data_images.js` 3.7MB)도 자주 안 바뀌어 고도몰에 둔다.

## 새 판 넣기

- **수집기(날마다)**: `POST /rest/v1/rpc/fn_sdp_release_save` `{p_payload:{note, files:[{file, head, tail, vars:[{name, lead, body}]}]}, p_key:<sdp_ingest 키>, p_publish:false}`
  — 바로 앞 판과 변수가 전부 같으면 새 판을 만들지 않는다(`same:true`). 판 이름을 안 주면 `YYMMDD-n`.
- **사람이 파일을 받았을 때**: `node tools/sdp/js_to_release.mjs data_*.js --out tools/sdp/release/sdp_<판>.json --inc data_inc.js` → 커밋 →
  관리자 세션에서 `select fn_sdp_import_url('https://raw.githubusercontent.com/yonghyeonjee/data_at/main/tools/sdp/release/sdp_<판>.json');`
- **비교**: `fn_sdp_diff(새 판 id)` — 지금 반영된 판과 변수별 더해짐·빠짐·바뀜(품목 › 모델 단위) · `fn_sdp_releases()` 목록
- **반영 / 되돌리기**: `fn_sdp_publish(판 id)` — 옛 판 id 를 주면 그 판으로 되돌아간다. 10분 안팎에 배포, `fn_sdp_releases().deployed` 로 확인

## 계산기 쪽

`tools/sdp/calc_loader.html` 의 블록을 계산기 HTML 의 data 스크립트 자리에 넣는다. 데이터센터를 못 읽으면 **고도몰 `/data/js/` 예비 사본**으로
돌아가고 머리 배지에 '예비 데이터' 를 띄운다(예비 사본은 오래될 수 있다 — 판을 크게 바꾼 뒤엔 고도몰 사본도 한 번 갈아 두면 좋다).

## 상품상세 구독탭 (mvp_246)

같은 Actions 가 이 판 + 구독 혜택 정책(`sub.policy` · 관리자 [구독 혜택 정책])으로 **`sdp/sub/*.js`** 도 만든다 — 고도몰 상품상세 일시불/구독 탭이 읽는다.
`tools/sub/README.md` 참고. 판을 반영하면 구독탭 요금표도 같이 바뀌고, 정책만 고쳐도 다음 실행(10분)에 `sub_policy.js` 가 바뀐다.
