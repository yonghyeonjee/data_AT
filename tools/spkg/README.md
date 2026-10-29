# 스마트 패키지 — 상품상세 가격 아래 안내 카드 (mvp_255 · 2026-10-29)

삼성전자 스마트 패키지(품목 수에 따라 멤버십 포인트) 대상 모델에, 고도몰 상품상세 가격 바로 아래 안내 카드를 띄운다.

```
관리자 /admin/spkg/ (엑셀 → 비교·미리보기 → 저장·반영) ─▶ spkg.release (판 = 한 달)
   └▶ Actions spkg-publish.yml (10분마다) ─▶ sdp/spkg/data.js ─▶ 고도몰 goods_view 의 sdp/spkg/spkg.js
```

| 파일 | 무엇 |
|---|---|
| `sdp/spkg/spkg.js` | 화면 로직 (모델 매칭 · 일반/구독/3만 문구 · 상담 문의 버튼 → 구독 문의 폼 자동 채움 · 전화). 고도몰 `goods_view.html` 은 이 파일을 부르는 script 한 줄만 둔다 |
| `sdp/spkg/data.js` | 반영된 판(아직 안 끝난 것). **손으로 고치지 말 것** — Actions 가 덮는다 |
| `tools/spkg/publish.mjs` | 판 → data.js |

- 판마다 기간이 있고, 화면이 오늘(KST) 기간의 판을 고른다 → **다음 달 엑셀을 미리 반영해 두면 1일 0시에 저절로 바뀐다**. 기간 밖이면 카드가 안 뜬다.
- 같은 기간과 겹치는 판을 반영하면 옛 판은 내려간다(고친 엑셀을 다시 올릴 때).
- 미리보기: 상품 URL 뒤 `&sp_preview=1`(기간 전이라도 다음 판) · `&sp_ver=2611-1`(판 지정).
- RPC: `fn_spkg_releases` · `fn_spkg_get` · `fn_spkg_save` · `fn_spkg_publish`(관리자) · `fn_spkg_export` · `fn_spkg_deployed`(service_role).
