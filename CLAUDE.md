# 삼성앤텍 Datacenter — 작업 지침

이 파일은 Claude Code 가 세션 시작 시 자동으로 읽습니다.
**비밀값은 이 파일에 절대 넣지 마세요.** 이 저장소는 `db.samsungat.co.kr` 로 공개 서비스됩니다.
키는 `_secrets.local.md`(gitignore 됨)에 있습니다.

---

## 이게 무엇인가

삼성스토어 시흥(㈜삼성앤텍)의 **통합 매출·CRM 시스템**.
23개 판매 채널의 주문·상담·견적을 한 곳에 모아 대시보드와 CRM 으로 쓴다.

| 화면 | 주소 | 누가 |
|---|---|---|
| 담당자 화면 | `/store.html` | 매장 프로·점장 (4자리 코드 로그인) |
| 관리자 화면 | `/admin.html` | 아이디 로그인 (Supabase Auth) |
| 고객 견적서 | `/q/?t=토큰` | 고객 (로그인 없음) |
| 외부 대시보드 | `/dash/` | 공유 비밀번호 |
| 방문 접수 | `/visit/` | 매장 태블릿 |
| 재고 조회 | `/stock.html` | 사내 |

`/admin/test/`, `/store/test/`, `/visit/test/` 는 같은 파일의 테스트본 (경로에 `/test/` 가 있으면 `DC_ENV='test'`).

**백엔드는 Supabase 하나** (project `wdahskrcpjooqhwwxjiu`, ap-northeast-2).
화면은 전부 정적 HTML + 브라우저에서 RPC 호출. 서버 코드는 전부 Postgres 함수.

---

## 저장소 구조 — 이것만 있어야 한다

```
CNAME  README.md  VERSION.txt  robots.txt  favicon.ico
index.html  admin.html  store.html  stock.html
.github/workflows/   admin/  customer/  dash/  q/  sql/  store/  tools/  visit/
```

**루트에 이것 말고 다른 파일이 있으면 잘못 올라간 것이다.**
특히 `.gs`(Apps Script 원본)·`.php`·`.mjs`·`.yml`·`mvp_*.sql` 은 **루트에 두면 웹으로 그대로 노출된다.**

- `.yml` 은 `.github/workflows/` 안에서만 동작한다
- `.gs` 는 Apps Script 편집기에 붙여넣는 원본 — 웹 서버에 있을 이유가 없다
- `sql/` 은 적용 기록용(DB 에는 이미 반영돼 있음)

---

## 작업 방식 (반드시 지킬 것)

### 1. 화면을 고치면 테스트 4조합을 전부 돌린다

```bash
cd ptest
node uat.mjs              # 담당자 · 데스크톱
node uat.mjs mobile       # 담당자 · 모바일 390px
node uat.mjs mgr          # 점장 · 데스크톱
node uat.mjs mgr mobile   # 점장 · 모바일
node qview.mjs            # 고객 견적서 (정상/기한지남/링크만료/잘못된주소)
```

**하나라도 실패하면 배포하지 않는다.** 23개 케이스에 터치 타깃 40px·색 대비 4.5:1·가로 넘침 0·
파괴적 버튼 이격 거리·홈 흐름 띠·필터 칩 단일 선택·스크립트 오류 0 이 들어 있다. "보기에 괜찮다"가 아니라 수치로 판정한다.

`ptest/` 는 gitignore 라 저장소에 없다. 새 컨테이너에서는 이렇게 되살린다:
```bash
mkdir -p ptest && for f in uat.mjs qview.mjs mock.js; do git show 01c627d:$f > ptest/$f; done   # 정리 전 마지막 커밋
sed -i "s#/home/claude/web#$PWD#; s#/home/claude/ptest#$PWD/ptest#" ptest/uat.mjs ptest/qview.mjs
cd ptest && npm i playwright@1.55 --no-save && UAT_PAGE=/store/test/ node uat.mjs   # 테스트본 먼저
```
(2026-09-12 이후 uat.mjs 는 이 세션에서 고친 판을 쓴다 — T19~T23 이 들어 있고 UAT_PAGE 로 대상을 고른다.
 크로미움은 /opt/pw-browsers/chromium, 외부 통신은 mock.js 가 supabase-js 를 통째로 대체하므로 프록시와 무관)

**uat.mjs 는 390px 세로 화면 하나만 본다. 폰은 그보다 다양하다** — `node audit.mjs drawer home` 이
360·412px × 글자 작게·중간·크게 × 담당자·점장 = 12조합으로 탭 12개와 서랍을 돌며 가로 넘침·화면 밖 요소·
40px 미만 버튼·글자 잘림·두 줄로 꺾인 메뉴를 센다. 기본·중간 글자에서 "✓ 이상 없음" 이어야 한다.
'크게'(1.6) 에서 우선 순위 표·처리현황 표가 카드 안에서 옆으로 스크롤되는 것은 허용.

**모바일 CSS 는 `<style>` 맨 끝의 "모바일 보정" 블록에만 쓴다.** 앞쪽에 넣으면 같은 특이도의 원래 규칙이
뒤에서 덮는다(한 번 그렇게 당했다). 서랍 폭 `--side-w` 는 넓은 화면 전용(34vw)이라 폰에서는 그 블록이
`min(86vw,340px)` 로 바꾼다. `fs-big` 은 글자 배율 1.5 이상에서 켜진다 ('크게'=1.6).

사용자는 **매장에서 대면 상담하는 비개발자**다. 모바일에서 쓰고, 오탭하면 데이터가 날아간다.

### 2. DB 함수는 본문을 다시 쓰지 않는다

긴 함수를 옮겨 적다 사고가 난다. **서버에서 원본을 읽어 부분만 치환**한다.

```sql
do $outer$
declare v_src text; v_args text;
begin
  select p.prosrc, pg_get_function_arguments(p.oid) into v_src, v_args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
   where p.proname='대상함수';
  if position('바꿀문구' in v_src) = 0 then raise exception '지점 없음'; end if;
  execute format('create or replace function public.대상함수(%s) returns jsonb
                  language plpgsql volatile security definer
                  set search_path to ''pg_catalog'',''public'' as %L',
                 v_args, replace(v_src, '바꿀문구', '새문구'));
end $outer$;
```

- `pg_get_function_arguments` 를 쓸 것. `pg_get_function_identity_arguments` 는 기본값을 빼먹어
  `cannot remove parameter defaults` 가 난다
- 치환 전 **지점 개수를 세어 검증**할 것 (0개면 중단)
- 여러 문을 한 번에 보내면 **하나라도 파싱 실패 시 전부 롤백**된다 — 이게 여러 번 사고를 막아줬다

### 3. 빌드·배포

```bash
/home/claude/build.sh "한 줄 설명"   # → data_AT_vNN_YYMMDD.zip
```

원본은 `/home/claude/web/`. zip 을 저장소 루트에 덮어쓴다.
**test 폴더를 먼저 올려 확인한 뒤** 본 파일을 올리는 것이 원칙.

---

## 알아둘 함정

- **Realtime 은 구독 롤에 SELECT 권한 + RLS 정책이 있어야 한다.** publication 등록만으로는 CHANNEL_ERROR.
  `crm` 표를 열지 말고 개인정보 없는 신호 표(`public.consult_ping`)를 따로 둔다
- **예외를 던지는 함수 안의 insert 는 함께 롤백된다.** 남겨야 하는 기록(실패 카운트 등)은
  자기호출(`extensions.http` → PostgREST)로 별도 커밋
- `now()` 는 트랜잭션 시작 시각 — 루프 안 간격은 `clock_timestamp()`
- STABLE 함수에서 insert 하면 오류 → VOLATILE
- Supabase API 롤은 `safeupdate` — 조건 없는 DELETE 는 `where true` 필요
- **이카운트 재고 API 는 몇 분에 3회를 넘기면 412** 로 끊고 몇 분 막는다. 0행 조회도 '연속 오류'로 센다
- 이카운트 `SaveSaleOrder` 는 `U_MEMO1` 필수, 특수문자 거부, `USER_PRICE_VAT` 는 숫자
- **잔디 카드(connectInfo)는 `Accept: application/vnd.tosslab.jandi-v2+json` 헤더가 있어야 그려진다.**
  본문은 마크다운 링크 `[글자](주소)` 를 읽는다
- `crm.consult.source` 는 CHECK 제약이다 — 새 출처를 넣으려면 제약을 먼저 고쳐야 한다
- 컨테이너에서 외부 HTTP 는 프록시가 막는다. Supabase 는 MCP 로, 잔디는 DB `extensions.http_post` 로

---

## 데이터 지도

| 스키마 | 무엇 |
|---|---|
| `core` | 설정·직원·메뉴·알림·주문·데이터소스. `staff` `menu_item` `menu_access` `namecard` `notify_rule` `orders` `app_setting` `api_key` |
| `crm` | 고객·상담·견적. `customer` `consult`(뷰 `consult_live`) `quote` `quote_share` |
| `inv` | 재고·품목·입출고 |
| `ec` | 이카운트 연동 (거래처·코드·전표·큐) |
| `public` | 화면이 부르는 RPC 만 (`fn_*`) |

**RPC 이름 규칙** — `fn_store_*` 담당자 화면(4자리 코드 인증), `fn_*` 관리자(Auth), `core.f_*` 내부 헬퍼.

**인증 방식 3가지**
1. Supabase Auth (관리자) — `core.f_role()`, `core.f_is_dev()`
2. 담당자 4자리 코드 — `p_code` 로 `core.staff` 조회
3. API 키 — `core.f_api_ok(name, key)`, SHA-256 해시 저장 (GAS·외주 개발사·GitHub Actions 용)

---

## 지금 상태 (2026-09-11 · v98)

### 되는 것
- **담당자 화면이 탭으로 나뉜다 (v99, store/test 먼저)** — 홈(흐름 띠·챙길 것·콜백·우선 순위 상담) · 상담(내 상담·배정) ·
  견적서 · 내 고객 · 처리현황(+휴가). 배지는 `setTabBadge()` 하나로만 붙인다 (innerHTML 다시 쓰지 말 것)
- 문의 접수(홈페이지·구독·매장·전화) → 상담 화면 + 잔디 알림 + 담당자 자동 배정
- 상담 목록 한 줄+펼치기, 급한 순 정렬(지난 콜백 → 오래 방치), 14일·30일 방치 뱃지
- [구매 확정] → 판매 입력 자동 채움 (견적서 금액 포함)
- 견적서 고객 공유 링크 `/q/?t=토큰` — 견적서 페이지와 **같은 양식** (php 의 CSS·렌더러를 이식)
- 점장 [담당자별 밀린 상담] 표
- 계정별 메뉴 노출 제어

### 미배포 (올려야 동작)
- `quote_subscribe.php` (고도몰) — [📨 고객에게 보내기]
- `1_quote_Code.gs` (Apps Script) — `action=share`, `syncNamecards()`. 붙여넣고 **재배포** 필요
- `gmail_inquiry.gs` — 홈페이지 문의 지메일 수집

### 즉시 할 일
1. ~~저장소 루트 정리~~ — 완료 (v98)
2. ~~노출된 키 교체~~ — 완료 (2026-09-12). `gas_forward` · `gmail_inquiry` 둘 다 새 값으로 바꿨고
   GAS 4개(견적내역·구독문의·소모품렌탈·VMS) 재배포까지 확인했다.
   저장소 안 `tools/` 의 값은 `PASTE_DC_KEY_HERE` 자리표시자다. **실제 값을 다시 넣지 않는다.**
   `gmail_inquiry` 는 아직 미설치라 값만 발급해 둔 상태. `_secrets.local.md` 참고
3. 담당 프로 휴대폰 — Apps Script 에서 `syncNamecards` 1회 실행하면 네임카드에서 자동으로 채워진다
4. GitHub Secrets `GA_PROPERTY_ID` · `GA_SA_JSON` · `GA_INGEST_KEY` — 없으면 GA4 수집이 건너뛴다

### 알아둘 것 — GAS 를 왜 쓰고 있나

고도몰 페이지는 소스가 그대로 노출되므로 거기에 `DC_KEY` 를 넣을 수 없다.
그래서 페이지 → GAS → Supabase 로 돌린다. **GAS 의 유일한 존재 이유가 이것이다.**

시트 기록·담당자 배정·잔디·접수번호는 Datacenter 가 이미 하거나 할 수 있다
(`fn_submit_inquiry` 에 배정 로직이 있고, `core.notify_rule` 에 폼 알림 4개가 꺼진 채로 있다).
`core.api_key` 의 `homepage_form` 이 "외주 개발사 직접 적재" 용으로 이미 발급돼 있다.

**GAS 는 조용히 실패한다.** 예외를 전부 삼키고 Logger 에만 남긴다. 적재만 멈추면
잔디는 계속 오고 시트도 쌓이므로 상담 화면만 비어 간다.
→ mvp_111 로 `web_subscription` · `web_supply` · `web_b2b` 를 수집 미도착 감시에 넣었다.
   멈추면 다음 날 아침 09:10 에 잔디로 알려준다. 그래서 지금은 GAS 를 그대로 둔다.

→ 문의 폼 3개는 고도몰 PHP 한 장이나 Edge Function 으로 옮기면 GAS 를 걷어낼 수 있다.
   견적(`1_quote_Code.gs`)은 계산기 API 전체이고 시트가 실제 저장소라 그대로 둔다.
   **중간 단계(키를 스크립트 속성으로 빼기 등)는 하지 않기로 했다. 옮길 거면 한 번에 옮긴다.**

### 판단 대기 (사람이 정해야 함)
- 담당자·상담상태를 **개발사 관리자에 계속 적을지, 이 시스템으로 옮길지** — 성공률 통계가 여기 달려 있다
- 홈페이지 문의 POST 연동 (외주 개발사에 요청서 전달됨)
- 휴가 Google Calendar 연동 방향 — 한 방향(우리 → 구글, 보기용) 권장

---

## 사용자에 대해

- 온라인사업부 **지용현**. 그로스해커이고 **직접 개발한다**
- 짧고 직설적인 지시를 선호. 긴 사전 설명보다 빨리 만들고 고치는 쪽
- 디자인은 "촌스럽지 않게, 전문적으로" — 운영 화면도 예외 없이
- 실제로 써 보고 문제를 잡는 것을 중요하게 여긴다. **테스트를 건너뛰지 말 것**
