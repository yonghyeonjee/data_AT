# 구독 페이지 봇 차단 붙이기 (SUB v1.6.3 · mvp_254)

2026-10-29 오후 인스타그램 광고 주소로 자급제 문의 21건이 15~40초 간격으로 들어온 일(스팸) 뒤에 만든 것.
**Cloudflare Turnstile**(무료 · 사람 확인) + 숨은 칸 · 제출 시간 · 같은 브라우저 반복 검사.

## 붙이는 곳 (test_subscribe.php 에 먼저)
1. `sub_turnstile.html` 의 주석과 `<script>` 블록 전체를 페이지 맨 아래 `{ # footer }` 바로 위에 붙인다.
2. **v1.6.2 봇 차단 블록을 붙였다면 지우고 이것으로 바꾼다** (v1.6.3 이 v1.6.2 를 다 포함한다 · 둘 다 두면 숨은 칸 검사가 두 번 돈다).
3. 다른 코드(신청서·간편·B2B·자급제·렌탈 폼의 `fetch`)는 고치지 않는다 — 이 블록이 `window.fetch` 를 감싸
   `script.google.com` 으로 가는 접수에 `cfToken`(Turnstile 토큰) 과 `botCheck` 를 싣는다. GAS 는 받은 칸을 그대로 넘긴다.

## 고객에게 보이는 것
- 평소엔 아무것도 안 보인다. 첫 터치 때 뒤에서 확인을 받아 두므로 [신청] 이 늦어지지 않는다.
- Cloudflare 가 의심할 때만 화면 아래에 "문의 접수 전에 사람인지 확인해 주세요" 상자 + 체크 칸. 체크하면 접수가 이어진다.
- 숨은 칸이 채워졌거나 · 페이지를 연 지 4초 안 제출 · 터치/키 입력 0 · 같은 브라우저 10분에 4번째 → 보내지 않고 '완료' 화면만.

## 서버 (데이터센터 · 적용됨)
- `core.turnstile_config` 한 줄 — site_key · secret(**DB 에만**) · `mode` off | log | enforce · timeout_ms(1500).
- `core.f_turnstile_verify(token)` → Cloudflare siteverify. 응답 없음·오류면 `ok:null`(막지 않음).
- `fn_submit_inquiry` 가 **새 접수만** 확인하고 결과를 `crm.consult.raw_payload.botVerify` 에 남긴다(토큰 자체는 저장 안 함).
  - `log`(지금): 기록만.
  - `enforce`: 토큰 없음·실패면 저장은 하되 숨김 '봇 확인 실패 (사유)' · 담당 지용현 · 순번 안 돎 · 고객 표 X · 카드는 잔디 테스트 방(자급제는 카드 없음).
    숨긴 건은 관리자 문의 관리 [삭제됨] 에서 보이고 [복구] 된다.

## 켜는 순서
1. test 페이지에 붙이고 신청 1건 → `raw_payload->'botVerify'->>'reason'` 이 `pass` 인지 확인.
2. 본 페이지에 붙이고 며칠 `log` 로 둔다 — 실제 고객 접수의 reason 이 거의 전부 `pass` 인지 본다
   (`no_token` 이 많으면 옛 캐시 · 광고 차단 · 등록 안 된 도메인(`ts: error:110200`) 을 의심).
3. 괜찮으면 `update core.turnstile_config set mode = 'enforce' where id = 1;`
   그 뒤 자급제 '인스타그램 광고 주소면 숨김' 규칙을 푼다(진짜 광고 문의를 받으려고).

## Cloudflare 위젯
- 대시보드 › Application security › Turnstile › '구독 페이지 문의' (Managed · Pre-clearance 끔).
- Hostnames: `samsungsh.co.kr` — 구독 페이지를 다른 도메인에서도 열면 거기에도 추가해야 한다(안 하면 110200 오류 → 토큰 없음).
- Site key 는 공개값(페이지에 들어감). Secret 은 저장소·문서에 두지 않는다 — 바꾸면 `core.turnstile_config.secret` 만 갱신.

## 시험
`ptest/turnstile.mjs` (가짜 Turnstile API · PC·폰 20개): 미리 받은 토큰을 실어 보냄 · 두 번째 제출 새 토큰 · 체크 상자 뜨고 체크 뒤 보냄 ·
Cloudflare 오류/스크립트 막힘이면 토큰 없이 사유와 함께 보냄 · 숨은 칸·4초 안 제출은 안 보냄 · 다른 fetch 그대로.
