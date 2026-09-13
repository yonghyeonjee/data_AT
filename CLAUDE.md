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

## 지금 상태 (2026-09-13 · v100)

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
- **펼친 상담 줄은 3줄** — 하는 일(전화·콜백·견적서·구매 확정) / 상태 바(`stateBar`·`STATE_STEPS`: 연락 전·상담중·보류·완료·거절, 지금 상태 켜짐, 누르면 `mcAct` start/resume/hold/done/reject, 아래 한 줄 뜻 설명) / 새 상담·넘기기·(떨어져서)삭제.
  '재연락' 이라는 말은 화면에서 전부 '콜백' 으로 통일했다. UAT T8 은 이제 [삭제]↔[구매 확정]·[완료] 거리를 잰다.
- **견적서 [테스트로] (`fn_store_quote_flag`)** — 견적서 줄에 개발·온라인 계정만 보임. 그 견적번호의 모든 판을 `crm.inquiry_flag` hidden+is_test 로. 서버도 dept 를 검사한다.
- **담당자 화면은 청록(#0F766E), 관리자는 남색(#1428A0)** — 두 화면이 같은 색이라 헷갈린다는 지적. `--navy/--accent` 와 하드코딩 남색(#1428A0·#EEF2FF·#2F5BEA)을 전부 청록 계열로, 서랍 배경 #0B2E2C. 구매 태그는 초록(#2E7D32).
- **내 상담 칩 = 할 일(open, 기본) · 연락 전(pre) · 상담중(ing) · 보류 · 완료 · 전체 · 휴지통** — `fn_store_consults_my` 에 p_filter 'pre'(result=진행전)·'ing'(open 버킷 중 진행전 제외) 와 counts pre/ing 추가.
  홈 흐름 띠 새 문의 → [연락 전], 내 상담(상담중만, 보류는 작은 글씨) → [상담중] 으로 가서 숫자가 그대로 맞는다. '거절' 칩은 뺐다([전체]에서 보임).
- **배정은 점장님 전용 사이드바 메뉴 (`assign` 탭)** — 상담 탭에 있던 `#allCard`(전체 상담 · 배정)를 `#tab-assign` 으로 옮겼다. 탭 버튼 `data-mgr="1"` 은 `applyPerms` 가 is_mgr 아니면 숨긴다.
  배지: 상담 = 내 할 일, 배정 = 미배정(빨강). 흐름 띠 [배정]·챙길 것 [미배정]·홈 찾기(점장님)·CRM [상담 열기](점장님)·우선 순위 표 이름 클릭이 전부 배정 탭으로 간다. 목록은 탭을 열 때 불러온다.
- **알림 탭 이름은 'CRM'** (대표님이 좋아하는 이름. '알림 내역'→'알림 보내기'→'CRM' 순으로 바뀜). 목록 맨 위에 항상 (예시) 줄 하나 — 자동 알림이 쌓이는 모양 + [상담 열기]·[메시지 보내기].
  **문서·화면의 호칭은 존대**: 점장님 · 대표님 · 프로님 (담당자·고객은 그대로).
- (옛 이름) — 줄마다 [메시지 보내기] → `#msgDlg` "개발 전" 안내창. '자동 알림 (개발 전)' 카드에 예정 템플릿 3개(견적서 유효기한 안내 · 콜백 당일 안내 · 상담 뒤 감사 메시지). 센드온이 붙으면 여기서 템플릿을 고르고 보내며, 보낸 내역은 같은 목록에 쌓인다.
- **알림 내역 탭 (`alerts`, `fn_store_alerts`)** — 견적서 보냄·열람(quote_share) · 배정(consult_assign) · 새 문의(외부 접수) · 콜백, 최근 90일. 문자 알림은 '개발중' 표시(`.devtag`), 견적서 보내기의 [문자로 보내기]도 개발중 태그.
- **상담 [테스트로] (mvp_121)** — 펼친 줄 맨 아래, dept 가 개발·온라인인 담당자에게만. `fn_store_consult_update` p_action='test' 가 hidden_*='테스트' 로 숨겨 목록·통계에서 뺀다. 복구는 관리자 문의 관리 [삭제됨].
  **담당자가 개발 계정(dept='개발': 지용현·test)이면 자동으로 테스트 숨김** — 트리거 `trg_consult_dev_is_test`(BEFORE insert/update of handler).
  **개발 계정은 테스트 숨김 건을 자기 화면에서 본다 (mvp_123)** — `crm.consult_scoped`(이제 crm.consult 직접) 와 `fn_store_consults_my` 가 `hidden_reason like '테스트%'` 를 `core.f_staff_is_dev(dc.me)` 일 때만 통과.
  테스트 견적도 개발 계정에게는 보인다. 통계·매장 담당자에게는 여전히 안 보임. 내 상담 범례에 "개발 계정이라 테스트 건도 보입니다" 가 붙는다.
  실제 건을 지용현이 맡게 되면 담당을 바꿔도 숨김이 풀리진 않으니 관리자 문의 관리 [삭제됨]에서 [복구]까지 해야 한다.
- **테스트 이름 견적서도 저장된다 (mvp_124)** — 전엔 `fn_submit_quote` 가 이름에 test·테스트 가 있으면 건너뛰어(skipped) [고객에게 보내기]가 notfound 였다.
  이제 저장하고 트리거 `trg_quote_test_flag` 가 문의 관리 플래그(hidden+is_test)를 자동으로 붙인다. 발행 직후 링크가 안 만들어지면 사유가 "견적서가 아직 저장되지 않았습니다 — [발행 (시트 저장)]…" 로 나온다.
- **테스트 견적서 제외 (mvp_122)** — `core.f_quote_is_test(quote_no,name,counselor)`: 문의 관리 플래그(hidden/is_test) | 이름 테스트 패턴(홍길동·이순신·지용현·테스트·test·자음만·숫자만) | 담당이 개발 계정.
  `fn_store_quotes`(견적서 탭·홈 찾기) 와 `fn_store_alerts` 견적서 줄에서 뺀다. 견적서를 테스트로 넘기려면 관리자 문의 관리 [견적] 에서 [테스트로 표시]/[숨기기].
- **휴가 입력은 팝업** — 달력 날짜를 누르면 `#lvAdd`(.lvmask/.lvdlg) 창이 뜨고 누구·시작·종료·메모를 넣는다. 두 번 눌러 기간 잡던 방식은 없앴다(LV_PICK 은 표시용).
- **문자 발송은 나중에 센드온(Sendon) API 로 붙인다 (예정)** — 붙일 자리: ① 견적서 보내기 창의 [문자로 보내기] (`QS_CAN_SMS` 가 false 라 지금은 링크 복사, `qsMsg(d)` 가 문자 본문을 이미 만든다)
  ② 알림 내역 탭의 '문자 알림' 카드 (`fn_store_alerts` 의 `sms` 키가 상태를 준다 — 지금은 '개발중') ③ 보낸 기록은 `crm.send_log`(buyer_key·channel·campaign·sent_at·status·error_msg, 현재 0건) 에 쌓아 알림 내역에 'sms' kind 로 합친다.
  키는 `core.api_key` 방식이 아니라 서버(Edge Function 또는 DB `extensions.http_post`) 쪽에 두고 화면에는 절대 넣지 않는다. 컨테이너에서 외부 HTTP 는 막히므로 실제 연동 테스트는 Supabase 쪽에서 한다.
- **상담 상세 보기 팝업 + 상담 입력 고객 고정 헤더 (mvp_126)** — `fn_store_consult_detail(p_code,p_id)` 가 한 건의 전부(완료일 `done_at` = 결과가 상담완료·거절·구매완료·확인완료·종료일 때 updated_at, `journal` = notes 를 ' / ' 로 나눈 진행 기록, 배정 이력, 견적서, 연결 주문, `others` = 같은 고객(buyer_key 또는 번호 10자리 일치)의 다른 상담)를 준다.
  화면 `cdOpen(id)` → `#cdDlg`(전역, `.lvdlg.wide.dv`). 내 상담 줄 첫 줄 [상세 보기] · 배정 줄 [상세 보기]·이름 클릭 · 내 고객 아코디언 상담 줄 [상세] · 홈 찾기 [상세]. 팝업 안 다른 상담 [상세] 는 그 건으로 넘어간다.
  **`ocToConsult(id,ref,name,tel,interest)`** (첫 인자 id 추가) — 상담 내용에 "이전 상담 … 이어서" 를 더 이상 안 넣는다. 대신 `#c_stick`(position:sticky, top = `--tb-h` 상단 바 높이) 에 이름·번호·N회째 + [이전 상담 N건 보기](`csRow`: 날짜·상태·완료일·채널·담당·내용·[상세]). 넓은 화면은 자동 펼침, 폰은 접힘. `pickMine(key,name)` 은 `fn_store_customer_detail`(consults 에 phone·done_at 추가) 로 같은 헤더. `custClear('c')` 가 헤더도 숨긴다.
  **기존 고객 찾기는 접혀 있다** — `#c_findBtn`(`.foldbtn`) → `cFindToggle()` 로 `#c_findBox` 펼침.
  같은 고객 추가 상담은 **`crm.consult` 에 줄이 하나 더 생길 뿐** 이전 줄은 절대 지워지지 않는다 (삭제는 [삭제]로만, 7일 안 복구). 묶는 키는 buyer_key(LINK.c)·전화번호. `_secrets` 없음.
- **하단 탭바 [상담 입력]이 안 눌리던 버그 (2026-09-13)** — `.toast` 가 사라진 뒤에도 opacity:0 으로 bottom:28px 자리에 남아(z-index 99) 하단 탭바 가운데 버튼의 탭을 먹었다.
  `.toast{pointer-events:none}` + 폰(≤999px)에서는 `bottom:calc(84px + safe-area)` 로 탭바 위에 뜬다. UAT T30(폰)이 토스트를 띄운 채 탭바를 실제로 탭해 잡는다.
- **판매 [테스트로] (mvp_127)** — 판매 입력 탭의 오늘 판매·확정 대기 줄에 개발·온라인 계정만 보임. `fn_store_sale_flag(p_code,p_id,p_test)` 가 같은 주문번호 줄 전부 `core.orders.is_test` 로.
  `fn_store_status`(오늘 판매·확정 대기·open_count·미마감 날·상품명 추천) · `fn_store_report` · `fn_store_daily_prefill` 이 이제 `is_test` 를 뺀다 (전엔 관리자만 표시할 수 있고 담당자 화면은 안 봤다).
  해제는 관리자 [주문·판매·매출 흐름] › 테스트 카드 [선택 → 해제]. 2026-09-13 에 홍길동·지용현·담당 test 판매 4건을 일괄 표시했다.
- **같은 고객의 열린 상담은 하나만 (mvp_128)** — `fn_store_consult_submit` 이 저장 직후 같은 고객(buyer_key·번호)의 진행전·진행중·보류 중 내(새 건 담당)·미배정 건을 `상담완료` 로 정리하고 notes 에 '새 상담 SC… 로 이어짐' 을 남긴다. 반환 `closed[]`.
  다른 담당자 건은 안 건드린다(헤더에 담당 이름으로 보임). 상담 입력 고정 헤더 `#cs_note` 가 "진행 중인 이전 상담 N건은 상담완료로 정리" 를 미리 알린다.
- **이어진 상담은 통계에서 한 건 (mvp_129)** — `crm.consult.superseded_by`(이전 건 → 잇는 건 id). `fn_store_consult_submit` 자동 정리가 채우고, `core.f_consult_stats`(처리현황·관리자 통계 공용)가
  recursive CTE 로 체인을 묶어 **root(처음 문의)의 날짜·채널·경로 + final(마지막)의 결과·방법** 으로 한 건 센다. 상세 팝업 [언제·누가] 에 "SC… 으로 이어짐" 버튼.
  원본 시트(구독 상담 성과 대시보드)의 셈법 = 문의 1줄, 상담결과(계약·보류·거절·기타·부재중·미처리)를 제자리에서 갱신. 우리 버킷 대응: 계약=bought, 보류=hold, 거절=reject, 기타·상담완료=done, 부재중·미처리=open.
  2026-08 구독 문의: 우리 27건(구매 4) vs 시트 26건(계약 5) — 줄 단위 대조는 안 했다.
- **상담 현황 (옛 처리현황) · 휴가 분리 (2026-09-13)** — `stats` 탭 이름 '상담 현황', 휴가는 별도 `leave` 탭(`data-mgr="1"`, `#tab-leave` 에 `#lvCard`, 탭 열 때 `loadLeave`).
  상담 현황 = 월 칩(`stMonthChips`: 이 달·지난달·최근 5개월·올해·전체, 한 달을 고르면 일별로) + 기간 바 + KPI 4(문의·구매·성공률·진행 중) + 비계약 한 줄 + 그래프 2개(`stBars` 기간별 문의/구매 SVG · `stHBars` 채널별) + 표(기간·채널·**담당자별**(점장님 [전체]) · 채널×기간 · 유입경로).
  `core.f_consult_stats` 에 `handlers` 키 추가 (mvp_130). 원본 시트(구독 상담 성과 대시보드)와 8월 대조 완료 — 구독 문의 26·계약 5·보류 12·거절 2 일치, 홈페이지 문의 20 일치. 시트 상담결과 29건을 DB 에 반영했다(sql/mvp_130).
  **시트의 상담결과는 시트에서만 고쳐지고 DB 로 안 온다** — GAS 는 접수만 넣는다. 담당자가 이 시스템에서 상태를 바꾸기 전까지는 월말에 같은 방식으로 맞춰야 한다 ('판단 대기' 항목).
- **대시보드 `/dash/` 상위 상품은 모델 코드가 맨 앞** (`PR[id][0]+'  '+PR[id][1]`, 표 셀도 모델 먼저).
- **상단 [로그아웃] (2026-09-13)** — 이름 옆 `#btnLogout`(`.pill.btnp`, 폰은 아이콘만·40px) → `logoutStore()` = 확인 → staff_code·st_open 지우고 새로고침 (아래 "담당자 변경"과 같음).
- **견적서 마감일** — `crm.quote.summary->>'until'`('YYYY.MM.DD', 발행일+7일)을 `fn_store_quotes`·`fn_store_consults_my`(quotes)·`fn_store_consult_detail`(quotes)이 `until` 로 준다. 화면 `qUntil(u,small)` = 노란 [마감 M/D], 지났으면 빨간 [마감 지남 M/D] — 견적서 탭·홈 찾기·내 상담 줄 견적 목록·상세 팝업.
- **검색 칸은 청록 2px 테두리 + 연한 배경** (`.csearch .in, .csearchbox .in, #all_q`) — 홈·상담·배정·견적서·내 고객 모두.
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
