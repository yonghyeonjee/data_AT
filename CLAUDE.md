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
| 담당자 사용 안내 | `/store/guide/` | 매장 프로 (서랍 [사용 안내]) |

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

- **anon 롤은 `statement_timeout=3s`** (authenticated 8s). 담당자 화면 RPC 는 전부 anon 이라 1초 안에 끝나야 한다.
  `fn_store_status` 가 '내 고객'을 위해 `core.orders` 16.8만 건을 매번 group by 하다 2~7초로 늘어져 로그인이 57014 로 끊겼다
  (mvp_115 로 내 이름 이벤트만 먼저 뽑도록 고쳐 30ms). 큰 표를 통째로 훑는 조각을 `fn_store_*` 에 넣지 말 것.
  화면 쪽 `rpc()` 는 타임아웃·5xx 면 0.7초·1.4초 쉬고 두 번 더 보낸다 (연결 끊김은 읽기만).
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

## 지금 상태 (2026-09-13 · v99)

### 되는 것
- **담당자 화면이 탭으로 나뉜다 (v99 · store.html 에 올림)** — 홈(흐름 띠·챙길 것·찾기·콜백·우선 순위 상담) · 상담(내 상담·배정) ·
  견적서 · 내 고객 · 처리현황(+휴가). 배지는 `setTabBadge()` 하나로만 붙인다 (innerHTML 다시 쓰지 말 것)
- **찾는 법이 목록마다 같다** — 검색어 칸 + 기간 바(`periodBar(pfx)` : 캘린더 두 칸 + 전체·7일·30일·이 달, 값은 `periodOf(pfx)`)
  + 조건(상태·출처·담당 칩). 홈 [찾기] 는 상담·견적서를 한 번에. 내 고객 탭은 `fn_store_customer_search`.
  기간은 서버로 간다 — mvp_113 으로 `fn_store_consults_my` · `fn_store_consults_all` 에 `p_from` · `p_to` 를 붙였다
  (옛 시그니처 drop → 새로 create → grant, 한 트랜잭션). 견적서·처리현황은 원래 있던 인자/클라이언트 필터.
- **휴가는 달력** — 월 달력에 담당자 색 칩, 날짜 두 번 눌러 기간 입력, 1월 1일 든 주가 W1. 목록은 이 달·앞으로·전체.
- 배정 목록은 `consult_at desc` 하나로 (mvp_112). 내 상담은 급한 순 그대로.
- **상태 '확인완료' (버킷 `closed`)** — 실제 처리 여부를 모르는 옛 미완료를 정리해 두는 자리. 미완료도 완료도 아니다:
  우선 순위 표·배정 [진행중] 에서 빠지고, 처리현황 문의 수에는 들어가되 완료·전환에는 안 들어간다. 담당자 화면 [전체] 에만 회색 칩.
  mvp_114 로 2026-09-01 이전 진행전·진행중 46건을 일괄 처리했다 (메모에 이전 상태 남김, 되돌리기는 `crm.consult_result_backup_20260913`).
- 문의 접수(홈페이지·구독·매장·전화) → 상담 화면 + 잔디 알림 + 담당자 자동 배정
- 상담 목록 한 줄+펼치기, 급한 순 정렬(지난 콜백 → 오래 방치), 14일·30일 방치 뱃지
- [구매 확정] → 판매 입력 자동 채움 (견적서 금액 포함)
- 견적서 고객 공유 링크 `/q/?t=토큰` — 견적서 페이지와 **같은 양식** (php 의 CSS·렌더러를 이식)
- 점장 [담당자별 밀린 상담] 표
- 계정별 메뉴 노출 제어

- **로그인 지연 해소 (mvp_115)** — 위 함정 참고. PIN 화면은 서버가 느리면 "서버가 느려 다시 시도 중… (n)" 을 보이고,
  끝내 안 되면 코드를 지우지 않고 "서버 응답이 늦습니다 · 잠시 후 다시 시도해 주세요" 로 안내한다.
- **관리자 문의 관리 상태·담당 체크박스 (mvp_116)** — 여러 개 고를 수 있고 검색어·기간과 함께 걸린다. `fn_inquiry_list` 의
  `p_status` 는 쉼표 목록('(없음)'=미기재), 새 인자 `p_handler` 도 쉼표 목록('(미배정)'). ACL 은 원래대로 authenticated·service_role 만.
- **문의 관리 줄 체크박스 → 일괄 처리** — 숨기기·테스트 표시·실제로 되돌리기·복구. 폼이 섞여 있으면 폼별로 나눠 `fn_inquiry_flag` 를 부른다.
  2026-09-13 에 테스트 문의 40건(홍길동·이순신·지용현·무의미 이름·이름 없음·매장 접수 전부)을 `crm.inquiry_flag` hidden+is_test 로 숨겼다
  (note '테스트 일괄 숨김 … 2026-09-13'). 되돌리려면 [삭제됨] 탭에서 골라 [복구].
- **내 고객 탭 (mvp_117)** — `fn_store_my_customers`(내가 상담·판매한 고객 전부, 마지막 상태·상담 횟수·지난 날짜·마지막 채널, 검색어·기간·채널 조건)
  + `fn_store_customer_detail`(상담·구매 이력) 로 아코디언. `fn_store_status.my_customers` 는 더 이상 화면에서 쓰지 않는다.
  상담 줄의 [후속 상담] 은 [＋ 새 상담] 으로 바꿨다 (상담완료 = 이 건 끝, 새 상담 = 같은 고객으로 한 건 더).
- **상담 입력 폼은 7개 영역(`.fgrp.a/.b` 배경 교차)** — 언제·누가 / 고객 / 어떻게 들어온 문의인지(상담 방법·채널·유형·유입경로) / 무엇에 관심 / 어디까지 갔나 / 다음에 살 것 / 메모·약속·동의.
  문의 채널 힌트에 "혹시 어디서 보고 오셨는지 물어봐주시면 좋습니다" 가 항상 보인다 (말풍선은 뺐다).
- **홈 [찾기] 는 `fn_store_consult_find` (mvp_118)** — 담당자 누구나 전체 상담에서 찾는다. 내 것·점장만 [상담 열기], 남의 것은 담당 이름.
  `fn_store_consults_all` 의 p_q 는 숫자가 없으면 phone like '%%' 로 전부 통과하던 버그가 있었다 (mvp_118 로 고침 — 숫자 3자리 이상일 때만 번호 조건).
  테스트 상담 19건(지용현·홍길동·이순신·test 등)은 `crm.consult.hidden_*` 로 숨겼다 (사유 '테스트 일괄 숨김 2026-09-13').
- **VMS·B2B 는 매장 화면에 안 보인다 (mvp_119)** — `crm.consult_scoped` 뷰가 `dc.me`(각 fn_store_* 가 begin 직후 set_config) 로
  `core.f_staff_sees_b2b`(dept ~ 온라인|개발|B2B|VMS) 또는 내 담당 건만 통과시킨다. 새 fn_store_* 를 만들면 **consult_live 대신 consult_scoped + set_config** 를 쓸 것.
  B2B 문의(web_b2b) 자동 배정은 박은지 프로 고정 (`core.f_consult_assign_default`). 박은지는 core.staff 에 비활성이라 담당자 화면은 못 쓰고 관리자 문의 관리에서 본다.
- **상담사 시나리오 워크스루 (2026-09-13)** — `ptest/scenario.mjs` 가 담당자·점장 × 데스크톱·폰으로 홈·찾기·상담·상담 입력·견적서·내 고객·처리현황·판매 입력을 돌며
  스크린샷과 카드 제목·가로 넘침·오류를 남긴다. 거기서 고친 것: 홈 KPI 줄 제거(흐름 띠와 중복), 폰에서 내 상담·배정의 찾기·기간 도구를
  `.tools-toggle` 로 접어 목록이 먼저 보이게(값이 있으면 자동 펼침), 배정 줄 [상담 이동]→[＋ 새 상담]·[배정]→[담당 바꾸기](담당 있을 때)·날짜 fmtAt, 견적서 탭 검색·기간을 카드 안으로.
- **온라인 문의는 `진행전`으로 들어온다 (mvp_120)** — `fn_submit_inquiry`(GAS 폼) · `fn_consults_bulk_upsert`(CSV·메일) · `fn_submission_to_consult`/`core.f_submission_to_consult`(방문 접수)의
  기본값을 `진행중`→`진행전`으로. 화면 '진행 전' = 아직 연락 안 함, '상담중' = 담당자가 연락한 뒤. 손 안 댄 `진행중` 10건을 `진행전`으로 되돌렸다(메모에 남김).
  홈 흐름 띠는 **내 일의 단계**: '새 문의' = 내 미완료 중 `진행전`(날짜 무관, 작은 글씨 "오늘 +today_mine") → '내 상담' = 상담중+보류 → 콜백 → 견적서 → 구매 확정.
  (처음엔 '접수 = 오늘 들어온 문의'로 했다가, 어제 새벽 온 건이 접수 0·연락 전 2로 갈려 헷갈린다는 지적으로 바꿈. `today_consults`/`today_mine` 은 status 에 남아 있다.)
  화면 라벨: `진행전` → **연락 전**, 상담 시작 버튼은 [연락함 → 상담중], 내 상담 칩 아래 상태 범례 한 줄(`.legend`).
- **부가 기능은 보이되 재촉하지 않는다 (2026-09-13)** — 재고·주문서·온라인은 권한(perm)으로 온라인사업부·개발만. `daily`(일 마감) 권한은 기본 ON, 활성 담당자 전원.
  홈 '마감 안 한 날' 알림·상단 미마감 배지·탭 배지는 뺐다. 미마감은 일 마감 탭 안에서만 조용히 보인다.
  **판매 입력 → 일 마감 → 일일 업무 텍스트(`dailyText`, 복사) → 월 마감(`fn_store_month_close`, 날짜별 표+합계+프로별+안 한 날, `monthText` 복사)** 로 이어진다.
- **상담 입력 상태는 버튼 4개** (`#c_res_seg`: 상담중·보류·완료·구매함) — 숨은 `#c_result` select 가 실제 값을 갖고 저장 코드는 그대로. 값이 4개 밖(연락 전·거절)이면 임시 버튼을 붙인다(`cResSync`).
- **알림 내역 탭 (`alerts`, `fn_store_alerts`)** — 견적서 보냄·열람(quote_share) · 배정(consult_assign) · 새 문의(외부 접수) · 콜백, 최근 90일. 문자 알림은 '개발중' 표시(`.devtag`), 견적서 보내기의 [문자로 보내기]도 개발중 태그.
- **담당자 사용 안내 `/store/guide/`** — 17장: 시작 · 화면 구성 · 상황 4개(온라인 문의/매장 방문/콜백→견적서→구매/지난 상담 찾기) · 화면별(홈·상담·상담 입력·견적서·내 고객·알림 내역·판매 입력/일 마감/월 마감·현황) · 점장이 하는 일 · 찾는 법 · 문제 시.
  화면을 고치면 여기도 같이 고친다. PDF 는 `ptest/guide_pdf.mjs` 로 뽑는다.

### 미배포 (올려야 동작)
- `quote_subscribe.php` (고도몰) — [📨 고객에게 보내기]
- `1_quote_Code.gs` (Apps Script) — `action=share`, `syncNamecards()`. 붙여넣고 **재배포** 필요
- `gmail_inquiry.gs` — 홈페이지 문의 지메일 수집. **스크립트는 붙어 있고 9/11 에 손으로 3건 넣었지만 1분 트리거가 안 걸려 있다**
  (9/12~13 하루 동안 `fn_inquiry_mail_ingest` 호출 0건). 편집기에서 `runOnce` → `setupInquiryTrigger` 를 실행해야 게시판 문의가 자동으로 들어온다.
  키는 새 `gmail_inquiry` 값이어야 한다.

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
