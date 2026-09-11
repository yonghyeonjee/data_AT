# 외부 서비스 연동 가이드 — 데이터 꺼내 쓰기 · CRM 붙이기

이 시스템의 데이터는 전부 Supabase 에 있고, **밖에서는 `public` 스키마의 함수(RPC)만 부를 수 있습니다.**
테이블은 직접 열리지 않습니다(RLS 전면 차단). 그래서 연동은 "어떤 함수를, 어떤 키로 부르느냐"가 전부입니다.

```
POST https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/<함수명>
Headers: apikey: <키>   Authorization: Bearer <키 또는 로그인 토큰>   Content-Type: application/json
Body:    {"p_인자": 값, ...}
```

## 1. 키 세 가지 — 어느 것을 쓰나

| 키 | 어디서 | 할 수 있는 것 | 어디에 두나 |
|---|---|---|---|
| **publishable (anon)** | Settings → API | 고객 폼 접수(`fn_submit_customer`) · 매장 입력 4개. **조회는 전부 거부** | 웹페이지에 그대로 넣어도 됨 (지금 admin.html 이 이것) |
| **로그인 토큰** | 계정으로 로그인 후 받는 JWT | 그 계정의 권한만큼 조회. `admin` 이 아니면 실명·실번호 마스킹 해제 불가 | 사람이 쓰는 도구 |
| **service_role** | Settings → API | **전부.** RLS 를 우회 | **서버·자동화에만.** 브라우저·엑셀·문서에 절대 넣지 말 것 |

**외부 도구에 붙일 땐 전용 계정을 하나 만드는 것을 권합니다.**
Supabase → Authentication → Users → `integration@samsungat.local` 추가 → admin.html 설정에서 권한 `staff`.
그 계정으로 로그인해 토큰을 받으면, 마스킹된 값만 나가고 언마스킹 조회는 `crm.access_log` 에 남습니다.
service_role 을 도구에 주는 것보다 훨씬 안전합니다.

로그인해서 토큰 받기 (어느 언어든 이 한 번의 호출):

```bash
curl -s -X POST 'https://wdahskrcpjooqhwwxjiu.supabase.co/auth/v1/token?grant_type=password' \
  -H 'apikey: <publishable 키>' -H 'Content-Type: application/json' \
  -d '{"email":"integration@samsungat.local","password":"…"}'
# → {"access_token":"eyJ…", "expires_in":3600, ...}   이 access_token 을 Bearer 로 쓴다 (1시간)
```

## 2. 꺼낼 수 있는 것 — 함수 목록

| 함수 | 용도 | 주요 인자 | 반환 |
|---|---|---|---|
| `fn_dashboard_v2` | 매출 집계 전부 (당기·전기, 채널·상품·카테고리·요일시간) | `p_from, p_to, p_cfrom, p_cto, p_scope` | JSON 1개, 1~27KB |
| `fn_order_list` | 원장 목록 (50행 페이지) | `p_from, p_to, p_channel, p_handler, p_q, p_limit≤200, p_offset, p_unmask, p_sort` | 행 배열 |
| `fn_order_export` | 기간 원장 엑셀용 (최대 1년) | `p_from, p_to, p_unmask` | 행 배열 |
| `fn_customer_list` | 통합 고객 (구매횟수·누적·최근상품) | `p_q, p_source, p_freq, p_consent, p_sort, p_limit≤200, p_offset, p_unmask` | `{total, sum_net, rows[]}` |
| `fn_customer_stats` | 고객 통계 (재구매·다채널·휴면·동의) | 없음 | JSON |
| `fn_crm_targets` | **발송 대상** (수신동의 + 연락처) | `p_reason(캠페인명 필수), p_next_product, p_limit, p_q, p_channel` | 행 배열 · 감사로그 기록 |
| `fn_crm_funnel` | 발송 가능 인원 깔때기 | 없음 | JSON |
| `fn_consult_list` | 상담·가망고객 | `p_from, p_to, p_result, p_handler, p_route, p_q, …` | 행 배열 |
| `fn_data_status` | 원천별 적재 현황 | 없음 | JSON |
| `fn_send_log_add` | **발송 결과 되돌려 기록** | `p_campaign, p_channel, p_rows[{buyer_key, status, sent_at, error}]` | `{logged}` |

규칙 하나: **전건을 한 번에 당기는 함수는 없습니다.** 페이지네이션으로 받으세요. 무료 플랜 egress 를 지키는 장치입니다.

## 3. 예시

### 3-1. 이번 달 매출 한 줄 (Python)

```python
import requests
URL = "https://wdahskrcpjooqhwwxjiu.supabase.co"
H = {"apikey": KEY, "Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}
r = requests.post(f"{URL}/rest/v1/rpc/fn_dashboard_v2", headers=H,
                  json={"p_from": "2026-09-01", "p_to": "2026-09-30", "p_scope": "전체"}).json()
print(r["total"]["net"], r["by_type"])          # 순매출, 구분별
```

### 3-2. 고객을 전부 받아 CRM 으로 (JavaScript · 페이지 돌리기)

```js
const sb = createClient(URL, PUBLISHABLE_KEY);
await sb.auth.signInWithPassword({ email: "integration@samsungat.local", password: PW });
let all = [], off = 0;
for (;;) {
  const { data } = await sb.rpc("fn_customer_list", { p_sort: "new", p_limit: 200, p_offset: off, p_unmask: false });
  all.push(...data.rows); if (data.rows.length < 200) break; off += 200;
}
// all[i] = { key, name(마스킹), phone(마스킹), chans[], cnt, net, last_at, last_product, consent }
```

`key`(buyer_key)가 **외부 시스템에서 이 고객을 가리키는 ID** 입니다. CRM 쪽 "외부 ID" 필드에 이 값을 넣어 두면
양쪽이 같은 사람을 가리킵니다. 실명·실번호는 마스킹된 채로 넘어가므로, 실제 발송에 번호가 필요하면
아래 3-3 처럼 `admin` 권한 + `p_unmask` 로 뽑고 그 조회는 감사로그에 남습니다.

### 3-3. 발송 대상 뽑아서 문자 보내고, 결과 되돌리기 (자동화 도구 한 사이클)

```js
// ① 대상 (admin 토큰 · 캠페인명 필수 · 감사로그 기록됨)
const { data: targets } = await sb.rpc("fn_crm_targets",
  { p_reason: "9월 정수기필터 재구매", p_next_product: false, p_q: "필터", p_limit: 500 });

// ② 발송 — 여기만 쓰는 서비스에 맞게 바꾼다 (솔라피·알리고·NHN 알림톡·채널톡 …)
const results = [];
for (const t of targets) {
  const ok = await sendSms(t.phone, `…`);            // 각 서비스의 API
  results.push({ buyer_key: t.buyer_key, status: ok ? "sent" : "failed" });
}

// ③ 결과 되돌리기 → 발송 통계 · 같은 사람 중복 발송 방지의 근거
await sb.rpc("fn_send_log_add", { p_campaign: "9월 정수기필터 재구매", p_channel: "sms", p_rows: results });
```

### 3-4. Google Sheets / Apps Script 에서 (기존 대시보드 팀이 익숙한 방식)

```js
function pullSales() {
  const res = UrlFetchApp.fetch(URL + "/rest/v1/rpc/fn_dashboard_v2", {
    method: "post", contentType: "application/json",
    headers: { apikey: KEY, Authorization: "Bearer " + TOKEN },
    payload: JSON.stringify({ p_from: "2026-09-01", p_to: "2026-09-30" }),
  });
  const d = JSON.parse(res.getContentText());
  const sh = SpreadsheetApp.getActive().getSheetByName("채널");
  sh.getRange(2, 1, d.by_name.length, 3).setValues(d.by_name.map(x => [x.k, x.net, x.cnt]));
}
```

## 4. CRM 도구에 붙이는 두 가지 방식

**A. 도구가 우리 쪽을 읽어간다 (Pull)** — Zapier · Make · n8n 의 "HTTP Request" 모듈에 위 RPC 를 넣고,
결과를 CRM 의 "연락처 만들기/갱신" 모듈로 넘깁니다. 외부 ID = `key`. 코드 없이 됩니다.
매일 새벽 `fn_customer_list(p_sort:'new')` 로 신규만 받아가면 트래픽도 작습니다.

**B. 우리가 도구로 밀어넣는다 (Push)** — GitHub Actions 에 워크플로 하나 더:
`fn_customer_list` → CRM API 로 upsert → 끝. 지금 샵링커 수집기(`tools/shoplinker/collect.mjs`)와 같은 자리에
같은 Secrets 로 돌립니다. 도구 쪽 API 키만 Secrets 에 추가하면 됩니다.

어느 쪽이든 **연락처 실번호가 CRM 으로 나가는 순간부터는 그 도구의 보안이 우리 보안이 됩니다.**
그래서 처음엔 A 방식 + 마스킹된 값으로 시작하고, 실발송은 3-3 처럼 우리 쪽에서 뽑아 보내는 것을 권합니다.

## 5. 하지 말 것

- service_role 키를 Zapier·엑셀·구글시트에 넣지 말 것 — 그 키는 모든 데이터를 여는 열쇠입니다
- 전건 조회 코드를 새로 만들지 말 것 — 페이지네이션으로
- 마스킹 해제(`p_unmask`)를 자동화에 걸어두지 말 것 — 사람이 캠페인명을 적고 뽑는 흐름을 유지
