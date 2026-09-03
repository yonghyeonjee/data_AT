# 샵링커 자동 수집

샵링커 주문 상세조회 API 를 하루 두 번 읽어 Supabase `core.orders` 에 넣습니다.
구글시트도, 대시보드 GAS 도 거치지 않습니다.

| 파일 | 역할 |
|---|---|
| `collect.mjs` | 수집기 본체. 조회 → 파싱 → Supabase RPC 적재 |
| `../../.github/workflows/shoplinker-sync.yml` | 정기 수집 (13:10 · 23:10 KST) |
| `../../.github/workflows/shoplinker-backfill.yml` | 과거분 채우기 (수동 실행) |
| `check-freshness.mjs` + `../../.github/workflows/data-freshness.yml` | 원천 7개 적재 점검 (평일 10시). 지연·미적재가 있으면 실패 → GitHub 이 메일 알림 |
| `sl_req.php` | GAS 를 대체할 조건 XML 응답기 (samsungat.co.kr 에 올리는 용도) |

---

## 1. 처음 한 번 — 저장소 Secrets 4개

GitHub → 저장소 → Settings → Secrets and variables → Actions → **New repository secret**

| 이름 | 값 |
|---|---|
| `SL_CUSTOMER_ID` | 샵링커 고객사 코드 |
| `SL_REQ_URL` | 조건 XML 을 응답하는 주소 (기존 GAS 웹앱의 `/exec` 주소) |
| `SUPABASE_URL` | `https://<프로젝트>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase → Settings → API → **service_role** 키 |

> `service_role` 키는 모든 권한을 가집니다. **Secrets 에만** 두고, 코드·이슈·로그 어디에도 붙여넣지 마세요.
> 유출되면 Supabase 대시보드에서 즉시 재발급하세요.

## 2. 점검

Actions → **샵링커 정기 수집** → Run workflow → `selftest` 체크 → 실행.

세 줄이 다 ✓ 면 준비 끝입니다.

```
① 조건 XML 주소 확인   ✓
② 샵링커가 그 주소를 읽을 수 있는지  ✓
③ Supabase 연결        ✓
```

②에서 `could not open` 이 나오면 샵링커 서버가 그 주소를 못 읽는 것입니다. `SL_REQ_URL` 을 바꿔야 합니다.

## 3. 과거분 채우기

Actions → **샵링커 과거분 채우기** → `start` = `202512` → 실행.
2025-12 부터 한 달씩 과거로 내려가며, 주문이 0건인 달이 2번 연속되면 스스로 멈춥니다.

먼저 `dry` 를 켜고 한 번 돌려 건수만 확인한 뒤, 실제 적재를 권합니다.

## 4. 왜 이렇게 만들었나 (2026-09-03 조사)

두 가지 외부 제약 때문에 구조가 이 모양입니다. 나중에 누가 "왜 Supabase 에서 바로 안 부르지?" 하고
다시 시도하지 않도록 남깁니다.

**① 샵링커 API 서버의 TLS 가 낡았습니다.**
`apiweb.shoplinker.co.kr` 의 HTTPS 는 취약한 DH 파라미터를 씁니다.

| 런타임 | 결과 |
|---|---|
| Deno (Supabase Edge Function) | `received fatal alert: HandshakeFailure` |
| OpenSSL 3.x (Postgres `http`) | `dh key too small` |
| Java (기존 GAS) | 연결됨 |
| Node (이 수집기) | 보안수준을 낮추면 연결됨 |

그래서 Supabase 안에서는 HTTPS 로 붙을 수 없고, Node 를 쓸 수 있는 GitHub Actions 로 왔습니다.
`collect.mjs` 는 기본값 → `SECLEVEL=1` → `SECLEVEL=0` 순으로 물러나며, **성공한 단계를 로그에 찍습니다.**
샵링커가 TLS 를 고치면 로그가 저절로 "기본값" 으로 돌아옵니다.

**② 샵링커 서버는 `*.supabase.co` 를 읽지 못합니다.**
이 API 는 조회 조건을 쿼리스트링이 아니라 "XML 문서의 URL"(`iteminfo_url`)로 받고,
샵링커 서버가 그 주소를 직접 가져갑니다. 그런데

| 주소 | 샵링커가 읽나 |
|---|---|
| `script.google.com/macros/s/…/exec` | O |
| `raw.githubusercontent.com` | O |
| `*.supabase.co` (functions · storage · rest 모두) | **X** — `could not open XML input` |

그래서 조건 XML 응답만 기존 GAS 웹앱에 남겼습니다. 그 GAS 에는 **로직이 없습니다** — 받은
쿼리를 XML 로 되돌려주는 15줄짜리 `doGet` 뿐입니다. 시트도 읽지 않고 외부 호출도 하지 않아
GAS 실행 시간·호출 할당량에 걸릴 일이 없습니다.

## 5. GAS 마저 없애기 (선택, 언제든)

`samsungat.co.kr` 이 Apache + PHP 로 돌고 있고, **샵링커가 이 도메인을 읽을 수 있는 것을 확인했습니다**
(https / http 둘 다 O). 그래서 같은 폴더의 `sl_req.php` 를 그 서버에 올리기만 하면 GAS 는 완전히 빠집니다.

1. `sl_req.php` 의 `KEY` 를 긴 임의 문자열로 바꾼다
2. `https://samsungat.co.kr/sl_req.php` 로 업로드
3. 저장소 Secrets 의 `SL_REQ_URL` 을 `https://samsungat.co.kr/sl_req.php?k=<그 KEY>` 로 변경
4. Actions → 정기 수집 → `selftest` 로 ✓ 확인
5. GAS 프로젝트 `shoplinker_api_input` 의 트리거를 끄고 배포를 보관 처리

AWS 를 붙이지 않아도 됩니다. 이 서버가 이미 조건만 만족합니다.

## 6. 알아둘 것 — 보안

- **이 API 는 고객사 코드 외에 인증이 없습니다.** 임의의 클라우드 IP에서 그 코드만으로 조회가
  됐습니다(IP 허용목록도 없는 것으로 보임). 즉 코드가 새면 주문자 이름·연락처·주소가 통째로 노출됩니다.
  → `SL_CUSTOMER_ID` 는 **공개 저장소에 절대 커밋하지 말고** Secrets 로만 두세요.
  → 샵링커에 ㉠ API 키 발급 ㉡ IP 허용목록 ㉢ DH 파라미터 2048bit 이상 교체를 요청할 가치가 있습니다.
- 조회 응답에 주문자 실명·휴대폰·주소가 들어옵니다. 워크플로 로그에 원문을 출력하지 마세요
  (현재 수집기는 건수만 찍습니다).
