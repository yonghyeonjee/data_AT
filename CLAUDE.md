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
| 상담 흐름도 | `/flow/` | 사내 (대표님·점장님 설명용) |

`/admin/test/`, `/store/test/`, `/visit/test/` 는 같은 파일의 테스트본 (경로에 `/test/` 가 있으면 `DC_ENV='test'`).

**백엔드는 Supabase 하나** (project `wdahskrcpjooqhwwxjiu`, ap-northeast-2).
화면은 전부 정적 HTML + 브라우저에서 RPC 호출. 서버 코드는 전부 Postgres 함수.

---

## 저장소 구조 — 이것만 있어야 한다

```
CNAME  README.md  VERSION.txt  robots.txt  favicon.ico
index.html  admin.html  store.html  stock.html
.github/workflows/   admin/  customer/  dash/  flow/  q/  sql/  store/  tools/  visit/
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
node qpage.mjs [mobile]   # 고도몰 견적서 페이지 전달본 (데이터센터 직접 호출 · 발행→내역→고객 찾기→보내기)
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
40px 미만 버튼·글자 잘림·두 줄로 꺾인 메뉴를 센다. '크게'(1.6) 까지 12조합 전부 "✓ 이상 없음" 이어야 한다
(가로 스크롤 상자 안의 넓은 표는 '화면 밖' 검사에서 건너뛴다 — 카드 안에서 옆으로 넘기는 것은 원래 허용).

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
- **세션에 붙여넣은 GAS 원본에는 옛 키가 들어 있을 수 있다 (2026-09-14 사고).** 견적내역·구독문의 GAS 를 전달본으로 갈아끼웠더니 둘 다 2026-09-12 에 교체되기 전 `gas_forward` 키를 담고 있어 `fn_submit_quote`·`fn_submit_inquiry` 가 401(42501 '권한이 없습니다')로 거절 → 견적서는 시트에만 저장되고 [고객에게 보내기]가 "아직 저장되지 않았습니다", 구독 문의는 GAS 예비 경로(옛 순번·GAS 잔디 카드)로 빠진다.
  전달본의 `DC_KEY` 는 항상 `PASTE_DC_KEY_HERE` 로 비워 보내고, 사용자가 소모품렌탈·VMS 스크립트(손대지 않은 것)의 값을 복사해 넣는다. 현재 키 값은 이 컨테이너에 없다(해시만 DB). 견적내역 GAS `saveQuote` 응답의 `dc:{ok,error}` 와 견적서 페이지 경고가 이 실패를 바로 보여준다.
  GAS 경유 호출은 DC 쪽 처리시간이 500~900ms 로 찍히지만(미국 GAS → 서울 왕복), 브라우저 직접 호출은 15~90ms — 견적서 페이지가 느린 건 GAS 왕복 탓이다.
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
- **알림 내역 탭 (`alerts`, `fn_store_alerts`)** — 견적서 보냄·열람(quote_share) · 배정(consult_assign) · 새 문의(외부 접수) · 콜백, 최근 90일. 문자 알림은 '개발중' 표시(`.devtag`). 견적서 보내기의 [문자로 보내기 (mobile)] 는 개발중 태그를 뺐다 (2026-09-13) — 휴대폰이면 `sms:` 로 문자앱을 열고, PC 면 링크 복사.
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
- **문자 발송은 나중에 센드온(Sendon) API 로 붙인다 (예정)** — 붙일 자리: ① 견적서 보내기 창의 [문자로 보내기 (mobile)] (휴대폰은 `sms:` 문자앱, PC 는 `QS_CAN_SMS` 가 false 라 링크 복사. `qsMsg(d)` 가 문자 본문을 이미 만든다)
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
- **상담 흐름도 `/flow/`** — 5레인(문의 창구 → 통합 데이터센터 → 상담 처리 → 데이터 처리 후 수합 → CRM 발송(개발중)). 도면은 2100px 고정이고 ≥1000px 에서는 창 폭에 맞춰 `transform:scale` (상단 [화면 맞춤]/[100%]), 화살표는 `draw()` 가 배율로 나눠 다시 그린다. 폰(<1000px)은 레인을 세로로 쌓고 화살표 대신 "↓ 다음 단계". 인쇄는 A3 가로.
  카카오채널 상담은 흐름도에서 뺐다(대표님 지시). 4레인 초안(문의 수집→상담 처리→데이터센터→CRM)은 폐기. PNG·PDF 는 `ptest/flow_render.mjs`.
- **휴가 종류 + 휴가자 재배정 (mvp_132 · 2026-09-14, store.html 에 올림 09-14)** — `core.staff_leave.kind`(반차·휴무·교육·휴가·연차·매장휴무). `core.f_staff_on_leave` 는 매장휴무를 휴가로 안 보고, 반차는 15:00 KST 전까지만.
  `fn_store_leave_save` 에 `p_kind`(옛 시그니처 drop), `fn_store_leave_list` 가 `kind` 를 준다. 화면: [＋ 입력] → '휴가 입력' 창에 종류 select(`#lv_kind`) + 힌트, 목록 태그·달력 칩(반차 '·반', 매장휴무 회색).
  **배정 버그의 원인**: 구독 문의 폼 GAS 가 자기 순번으로 담당자를 골라 `assignedStaff` 로 보내고 `fn_submit_inquiry` 가 그대로 받으니 트리거(`core.f_consult_assign_default`)의 휴가 제외가 돌지 않았다 (09/14 권혁찬).
  이제 `fn_submit_inquiry` 가 그 담당자가 휴가면 `core.f_assign_next('구독·렌탈')` 로 다시 배정하고 notes 에 '휴가 재배정 A → B', 잔디(jandi_crm) 규칙 `assign_leave` 로 알린다.
  시트 수정(onMgmtEdit) 은 이제 DB 담당자가 있으면 덮지 않는다(`coalesce(crm.consult.handler, excluded.handler)`). GAS 의 잔디 카드는 여전히 GAS 가 고른 이름으로 나가므로 재배정 카드가 한 장 더 온다.
- **구독 문의 접수 카드는 데이터센터가 보낸다 (mvp_133, 규칙 `inquiry_subscription` · 기본 꺼짐)** — `fn_submit_inquiry` 가 새 건(xmax=0)일 때 `inquiry.subscription` 으로 홈페이지 문의와 같은 카드(배정 담당자·상담 정보·상담 확인하러가기). 재배정이면 담당자 줄에 "(A 프로님 휴가 → 재배정)". `assign_leave` 규칙은 여기 합쳐서 껐다.
  **2026-09-14 전환 완료** — 구독문의 GAS v15(전체 Code.gs, 세션에서 전달) 배포 확인 → `inquiry_subscription` 켬, `assign_leave` 끔. 되돌리려면 반대로. v15 는 데이터센터 호출 실패 시에만 옛 순번+직접 잔디로 예비 동작. 휴가 캘린더 GAS(`leave_calendar.gs`)도 설치 완료.
  **배정은 데이터센터가 한다 (mvp_134)** — GAS 가 assignedStaff 를 비워 보내면 트리거가 `f_assign_next` 로 배정하고, 홈페이지 문의(`fn_inquiry_mail_ingest` 도 `f_assign_next('default')`)와 같은 순번표(`core.assign_pool` default · `assign_state` default)를 번갈아 쓴다. GAS v15 는 응답의 handler 를 시트 H열에 적는다.
  `fn_submit_inquiry` 는 returning 에서 실제 handler 를 받아 응답·카드에 쓰고, 시트 수정(onMgmtEdit)의 담당자는 다시 DB 를 덮는다(시트와 DB 가 같은 값이라 안전). 휴가 재배정은 새 접수에만.
  **잘못 배정된 건을 바꾸면 순번 커서가 따라간다 (mvp_135)** — 트리거 `trg_consult_assign_cursor`(after update of handler): 이전 담당자 = `assign_state.default.last_staff` 이고 새 담당자가 풀 인원이면 커서를 새 담당자로. 담당자 화면·관리자·시트 수정 어디서 바꿔도 같다. 풀 밖 사람·옛 건은 커서 그대로.
- **휴가 달력 → 구글 캘린더 구독 (mvp_133)** — Edge Function `leave-ics`(verify_jwt=false, 소스 `tools/edge/leave-ics.ts`) 가 `?k=토큰` 을 `core.api_key 'leave_ics'` 와 대조해 `public.fn_leave_ics`(service_role 만) 의 ICS 를 준다. 종일 일정, 제목 "이름 · 종류"(매장휴무는 "매장휴무"). **반차는 그날 09:00~15:00 KST 시간 일정**(하루씩, UID `leave-<id>-<날짜>`), UID `leave-<id>@db.samsungat.co.kr` 라 지우면 구글에서도 사라진다.
  한 방향(우리 → 구글). 구글은 보통 몇 시간~하루에 한 번 가져간다. 주소는 `_secrets.local.md`. 구글 캘린더 › 다른 캘린더 › URL 로 추가.
  **지정 캘린더에 직접 넣는 쪽은 GAS `tools/gas/leave_calendar.gs`** (CAL_ID = 매장 공유 캘린더, `fn_leave_feed(p_key)` JSON 을 15분마다 읽어 종일 일정 생성·수정·삭제, 반차는 09:00~15:00 시간 일정(태그 `id:날짜`), 태그 `dc_leave_id` 로 식별, 종류별 색). 키는 같은 leave_ics 토큰. 설치는 사용자가 붙여넣고 트리거 1회 실행.
- **점장 권한을 관리자 권한 표에서 준다 (mvp_133)** — `core.perm_def 'mgr'`(기본 꺼짐, 맨 앞 열). `core.f_staff_is_mgr` = 직함(점장·대표·전체)·부서(대표·전체·개발) OR `f_has_perm('mgr')`. `fn_staff_perms` 의 `auto_mgr` 로 직함 자동인 사람은 체크가 잠겨 '직함' 표시. 담당자 화면은 서버 is_mgr 을 그대로 쓰므로 체크만 하면 배정·휴가·담당자별 현황이 열린다.
- **네임카드는 데이터센터가 원본 (mvp_137 · 2026-09-14)** — 견적서 페이지가 `fn_quote_nc_list/save/delete`(anon + 페이지 보안 코드 해시 `core.app_setting.quote_page_code_hash`) 로 `core.namecard` 를 읽고 쓴다. GAS `action=namecards/saveNamecard/deleteNamecard` 와 시트 [네임카드] 탭은 더 이상 안 쓴다(그대로 두면 됨). 첫 로드 때 브라우저 캐시에만 있던 카드를 데이터센터로 한 번 옮긴다. 세션 전달본 PHP 에 폰 레이아웃과 같이 들어 있다 — 고도몰에 올려야 동작.
  휴가 입력 창: '누구' → '담당자 선택', 위에 [매장]/[전체] 세그(`#lv_scope`, `lvFillStaff`). `fn_store_leave_list` 가 `staff_dept`(이름·부서, 테스트 계정 제외, 매장 먼저)를 준다.
- **고객 견적서 전화 버튼은 담당 네임카드 휴대폰 (2026-09-14)** — `fn_quote_public` 은 `quote->opt->namecardId` → 이름 → `core.staff.mobile` → 매장 번호 순. core.namecard 에 카드가 없으면 매장 번호로 떨어진다(지용현 카드가 없어서 031 로 나왔던 건). 지용현 카드(NC1788421248760)를 직접 넣었고, `fn_submit_quote` 가 payload `namecard` 를 받으면 core.namecard 를 upsert 한다 — 견적내역 GAS `dcForwardQuote_` 가 네임카드 탭에서 찾아 실어 보내도록 패치(`tools/gas/quote_forward.gs` 참고).
- **견적서 페이지가 데이터센터에 직접 저장한다 (mvp_138 · 2026-09-14)** — 발행·발행 내역·지난 견적 열기·기존 고객 찾기·[고객에게 보내기]가 GAS·시트를 거치지 않고
  anon + 페이지 보안 코드(`core.f_quote_page_ok`)로 `fn_quote_page_save/list/get/customer/share` 를 부른다. 번호(`core.f_quote_next_no`, SH+yyMMdd-NNN · advisory lock)·판(version)·발행 시각은 서버가 정한다.
  `fn_submit_quote`·`fn_quote_share_key`·`fn_quote_customer_lookup` 은 키 검사만 남기고 본문을 `core.f_quote_store`·`core.f_quote_share`·`core.f_quote_customer_lookup` 로 뺐다(원본 prosrc 에서 키 줄만 지워 생성).
  고객 찾기는 후보를 먼저 8건으로 줄인 뒤 주문·상담·지난 견적을 세도록 다시 짰다 (전엔 '김' 11,000명 전부에 하위 질의 → 2~7초. 이제 150ms, `ix_cust_name_trgm` gin). 코드가 틀리면 0.7초 쉬고 42501.
  시트 [견적내역]은 **거울**이 됐다 — GAS `pullQuotesFromDatacenter`(시간 트리거 15분)가 `fn_quote_feed(quote_lookup 키)` 로 없는 (번호,판)만 붙인다. 이름 없이 발행하면 서버가 '(미상)' 으로 저장(페이지는 이름·연락처·모델·월 구독료를 먼저 요구).
  테스트는 `ptest/qpage.mjs [mobile]` — 전달본 PHP 를 로컬 http 로 띄우고 supabase RPC 를 가짜로 받아 발행→내역→고객 찾기→보내기 를 돌린다 (GAS 호출 0·오류 0 이어야 함).
- **여러 건 · 표로 입력 (2026-09-15 · store.html 에 올림 09-15)** — 탭 맨 위 모드 세그가 **카드 밖**에 있고 모드마다 카드가 따로다 (상담과 판매가 같은 모양 — 판매 것이 카드 안에 있어 "판매 입력에는 없는데?" 소리를 들었다).
  판매 `#s_mode`(한 건씩 `#sLogCard` / 여러 건 `#sGridCard`) · 상담 `#c_mode`(상담 기록 `#cLogCard` / 여러 건 `#cGridCard` / 문의 접수·넘기기 `#hoCard`).
  표 카드는 공통 칸(판매 `sg_date`·`sg_handler` / 상담 `cg_date`·`cg_handler`)을 한 번 고르고
  `.gtbl` 표에 한 줄씩(구분·단계·문의 유형 같은 나머지는 줄마다 고른다). `GRID.s/.c` 를 `localStorage dc_grid_{s|c}_{CODE}` 에 두고 `start()` 의 `gridLoad()` 가 복원. 마지막 칸 Enter = 줄 추가.
  `gridSave` 가 빈 줄은 건너뛰고 빠진 줄은 `err` 로 빨갛게(저장 안 함), 통과하면 줄마다 `fn_store_sale_submit`/`fn_store_consult_submit` (`gridRowP`). 폰은 헤더를 숨기고 줄을 2열 카드로. 처음 만든 [담아두기] 버튼 방식은 "하단 버튼이 어렵고 표처럼 넣고 싶다"는 말에 걷어냈다.
  `saleCollect()`/`consultCollect()`/`consultSend()` 분리는 남아 있다(submit 이 씀).
- **받은 문의 접수 · 담당자 넘기기 (mvp_139 · 수기 상담 배정)** — 최지영 프로가 네이버톡 문의를 지용현에게 말로만 넘겨 상담에 없던 건. `#c_mode` [문의 접수 · 넘기기] → `#hoCard`(누구에게 칩 `ho_to`(asgDirs 부서 세그) · 고객명 · 휴대폰 · 어디로 온 문의 `ho_ch`(INQ.channels) · 내용 · 관심 제품) → `fn_store_consult_handoff(p_code, p_data{to,…})`
  = `fn_store_consult_submit`(handler=받는 사람, result='진행전', 품목 기본 '알 수 없음', notes '문의 접수 … A → B 넘김') + `crm.consult_assign` 기록 + `core.f_notify('consult.handoff')`(규칙 `consult_handoff`, jandi_crm, 본인이면 안 보냄). 받는 사람 홈 새 문의·[연락 전]·알림 내역 배정에 보인다.
  채널 `naver` 를 '네이버톡' 으로 켰다. 상담 기록 상태 세그에도 [연락 전] 버튼을 넣었다(`cResSync` 임시 버튼 불필요). `ocToConsult`·`pickMine` 은 `cMode('log')` 로 되돌린다.
  **주의: 받는 사람이 개발 계정(지용현)이면 `trg_consult_dev_is_test` 가 테스트 숨김을 붙인다** — 실제 건이면 관리자 문의 관리 [삭제됨]에서 복구해야 통계에 들어간다.
- **여러 건 표는 한 건씩 폼의 칸을 전부 가진다 (2026-09-15 두 번째 지적)** — `GCOLS.s/.c` 칸 정의([키,라벨,폭,플래그(req 필수·core 주요·wide 폰 두 칸),종류,선택지]) 로 `gridRender` 가 머리글·줄을 만든다. 필수 칸은 머리글 빨강 + 칸 테두리 연빨강.
  표는 `.gtbl{overflow-x:auto}` 안에서 옆으로 스크롤(문서 가로 넘침 0), [모든 칸]/[주요 칸만](`gridView`, localStorage `dc_grid_view_*`). 판매 줄 구분·단계는 위 세그가 새 줄 기본값. 상담 줄은 채널에 따라 유입경로 선택지가 바뀌고, 상태 구매함이면 구매 제품·금액 필수 → `consultSend` 로 판매까지.
  체크박스는 `appearance:none` 40px (터치 타깃). 상담 표 공통 칸은 상담일·상담사만(`cg_date`·`cg_handler`).
- **주문서 탭 목록 — 빠른 모드와 [단계별 모드] 2단계 둘 다 (2026-09-15)** — 두 화면이 같은 규칙을 쓴다.
  **한 주문 = 한 줄**(서버 `core.f_sl_range` 가 order_no 로 묶고 `lines` 배열을 준다). 제품이 여럿이면 품목 칸에 전부 쌓이고 수량·금액은 주문 합계. 최근 30일 2,571건 중 230건이 여러 제품, 최대 6줄.
  확인 필요(후보 여럿) 줄은 후보 **코드·품목명·규격을 전부** 보여 ③에서 고를 수 있게(`l.cands`). 후보 하나면 코드 + 이카운트 품목명 + "주문: 상품명".
  **정렬은 공용** — `SL_SORTS`·`slSortKey`·`slSortList`·`slSortSet`(열마다 기본 차례 `SL_SORT_DIR`: 번호·채널·상태 오름 / 금액·수량·일시 내림) 을 빠른 모드(`slVisible`)와 마법사(`rows2`)가 같이 쓰고 `localStorage dc_sl_sort` 하나에 남는다.
  필터 줄에 [정렬] select(`sl_sort`/`wzSort`) + 오름/내림 버튼, 빠른 모드는 머리글(`data-sk`) 클릭도 된다(주문 머리글 = **주문번호 순**). 빠른 모드 필터는 `SL_FLT_IDS` → `dc_sl_flt` 로 유지. 이 표는 `data-ownsort` 라 공용 표 정렬이 건너뛴다.
  **택배비 0원은 '무료배송'** 으로 쓴다 — '택배비 없음' 이 미수집과 헷갈린다는 지적. 최근 30일 샵링커 2,843건 중 2,241건(79%)이 배송비 미수집(주문 수집 시점엔 아직 안 붙는다)이라 '택배비 합계'는 일부만 보여준다.
  마법사 필터 줄 `.wiz-flt .in` 은 `width:auto` 라 한 줄에 여러 칸(전엔 `.in{width:100%}` 이라 줄마다 하나). 테스트 `ptest/sl.mjs`(빠른 모드) · `ptest/wz.mjs`(마법사 2단계, 가짜 `fn_store_sl_orders` 로 UI 를 실제로 눌러 본다).
- **이카운트 전표 IO_TYPE (mvp_140)** — "IO_TYPE 거래유형(자릿수)" 실패 = 거래유형에 'SSG' 같은 글자를 보낸 것. `core.f_order_body` 는 이제 거래유형이 숫자 코드일 때만 IO_TYPE 을 보내고, 아니면 빼서 이카운트가 거래처 기본값(오픈마켓 등)으로 채운다. `ec.code` io_type 글자 코드는 active=false. 실패한 3장(SSG·프라자몰·에스몰)은 화면에서 [재전송].
- **관리자 대시보드 캐시 (mvp_140)** — 느렸던 이유: 관리자 기본 12개월 키가 15분 워밍(`core.f_dash_warm`)에 없어 6시간마다 5~10초 콜드 빌드(8초 제한에 걸리기도). 12개월 키를 워밍에 넣고 `fn_dash_payload` 는 24시간 캐시를 바로 준다. '전체 기간'은 `f_dash_payload` 800일 제한이라 못 넣는다.
  화면: [캐시 지우고 새로고침](= `fn_dash_refresh`, 캐시 삭제 후 재집계) · [전체 화면 ⛶](`dashFullscreen`, `#dashFull` requestFullscreen, Esc). admin.html 과 admin/test 동일.
- **'오늘' 은 한국 날짜 (mvp_140)** — DB 가 UTC 라 자정~09시엔 `current_date` 가 어제였다 → 오늘 입력한 판매에 어제 것이 남아 보임(01:03 지적). `fn_store_status` 등 fn_store_* 8개의 `current_date` 를 `((now() at time zone 'Asia/Seoul')::date)` 로 치환(`pg_get_functiondef` 통째 치환).
- **태그 색을 뜻별로 나눴다 (2026-09-15 · store.html 에 올림 09-15)** — 배정·내 상담 줄의 관심 품목·문의 채널·문의 유형·담당자가 전부 청록이라 "구분이 안 된다"는 지적.
  `.tag.itm` 관심 품목=청록 · `.tag.src` 문의 채널=파랑 · `.tag.ty` 문의 유형=보라 테두리 · `.tag.via` 유입경로=회색 · `.tag.hd` 담당자=**진한 청록 채움**(미배정은 `.none` 빨강 테두리) ·
  `.tag.new` 연락 전=빨강 · `.tag.hold` 보류=노랑 · `.tag.mth-t` 상담 방법=슬레이트 · `.tag.re` 회차=주황 · `.tag.qt` 견적=금색. 인라인 style 로 박혀 있던 것들을 클래스로 뺐다.
  배정 카드 머리에 `.taglegend` 한 줄(각 뜻을 그 색 태그로) 을 넣었다. 테스트 `ptest/tagshot.mjs` — 한 줄 안 태그가 서로 다른 색인지 · 종류가 7가지 이상인지 · **글자 대비 4.5:1** 인지를 잰다.
- **폰에서 세그 버튼 글자가 한 자씩 쪼개지던 것 (2026-09-15 폰 사진)** — '연락 전' 이 연/락/전 으로 세로로 섰다. 범인은 모바일 보정의 `.seg button{overflow-wrap:anywhere}` — 칸이 좁으면 글자 사이에서 끊는다.
  `overflow-wrap:normal` 로 바꾸고 `.seg{flex-wrap:wrap}` + `.seg button{flex:1 1 auto}` 로 **버튼이 글자 폭만큼 잡고, 한 줄에 안 들어가면 버튼째로 다음 줄**. 반쪽 칸으로는 답이 없는 것은 `.f.wide-m` 을 붙여 폰에서 한 줄을 다 쓴다(상담 상태).
  상담 상태 버튼이 5개(연락 전 추가)가 되면서 드러났다. 확인은 `ptest/segshot.mjs` — 360·390·412px × 글자 1·1.3 에서 세그 버튼마다 **실제 줄 수(Range.getClientRects)** 와 44×40px 를 잰다.
- **상담 현황을 매장 / 매장 외로 나눈다 (mvp_142 · 2026-09-15)** — `core.inq_channel.scope`('store'|'out'): **매장** = 구독 문의 · 매장 직접 방문 · 홈페이지 문의 · 네이버톡 · 카카오채널 · 기타, **매장 외** = VMS · 렌탈(소모품).
  `core.f_consult_scope(channel_code, source)` 는 출처가 `web_b2b`·`web_supply`·`vms` 면 채널과 무관하게 매장 외 (B2B 문의는 채널 코드가 없을 때가 있다).
  `core.f_consult_stats` 에 `p_scope`(빈값=전체) — `c` CTE 에 scope 열, `cs` 로 거르고 나머지 CTE 는 `cs` 를 쓴다. 응답에 `scope`·`scope_n`{store,out}. 5인자 판은 drop(두 판이 있으면 호출이 모호).
  화면 `#st_scope` 세그 [매장 N][매장 외 N][전체 N] — **매장 직원(점장님 포함)은 매장이 기본**, dept 가 개발·온라인이면 전체. 고른 값은 `localStorage dc_st_scope`. 테스트 `ptest/scope.mjs`.
- **상담 탭 배지 = [할 일] 칩과 같은 수 (mvp_141)** — `fn_store_requests.inbox.mine_open` 이 `진행중·보류` 를 세어 보류 5건이 든 배지 7 과 화면 [할 일] 2 가 달랐다. `진행전·진행중` 으로 맞췄다.
  같은 함수의 `unassigned`(배정 배지)도 `진행전` 이 빠져 있어 `진행전·진행중·보류` 로 고쳤다 (온라인 문의는 진행전으로 들어온다).
- **CRM 알림 내역 종류 필터는 체크박스** — `AL_KINDS`(Set, 기본 견적서·콜백) · `localStorage dc_al_kinds`. [전체] 칩은 뺐다. 예시 줄은 견적서를 켰을 때만.
  테스트 `ptest/grid.mjs [mobile]` G1~G9·C1~C3·H1~H5·A1~A3.
- **판매·상담 입력 [＋ 새 판매 입력]·[＋ 새 상담 입력]** (카드 제목 오른쪽) — `saleClearForm()`·`consultClearForm()` 이 저장 뒤 비우기와 같은 함수. 적던 게 있으면 confirm.
- **일 마감 기본 줄** — 그날 판매 입력이 없으면 일시불·구독 두 줄, 프로 = 로그인한 사람(전체 모드는 빈칸). 프로 빈 줄도 본인으로. 판매완료 입력 칸(`.drow .ds`)은 숨김 — 값은 판매 입력에서 자동, 저장은 그대로.
- **관리자 화면도 같은 상품명 규칙 + 수량** — 대시보드 상위 상품 랭크·표·파레토 툴팁·워터폴(상품), 주문 목록, 주문서 요청에서 모델 코드가 이름 앞. `rankHTML` 은 `q`(개) 가 있으면 "N개 · M건" 으로, 상위 상품·카테고리 랭크에 `qty` 를 넘긴다.
- **대시보드 `/dash/` 상위 상품은 모델 코드가 맨 앞** (`PR[id][0]+'  '+PR[id][1]`, 표 셀도 모델 먼저).
- **상단 [로그아웃] (2026-09-13)** — 이름 옆 `#btnLogout`(`.pill.btnp`, 폰은 아이콘만·40px) → `logoutStore()` = 확인 → staff_code·st_open 지우고 새로고침 (아래 "담당자 변경"과 같음).
- **견적서 마감일** — `crm.quote.summary->>'until'`('YYYY.MM.DD', 발행일+7일)을 `fn_store_quotes`·`fn_store_consults_my`(quotes)·`fn_store_consult_detail`(quotes)이 `until` 로 준다. 화면 `qUntil(u,small)` = 노란 [마감 M/D], 지났으면 빨간 [마감 지남 M/D] — 견적서 탭·홈 찾기·내 상담 줄 견적 목록·상세 팝업.
- **검색 칸은 청록 2px 테두리 + 연한 배경** (`.csearch .in, .csearchbox .in, #all_q`) — 홈·상담·배정·견적서·내 고객 모두.
- **로그인 화면 [QR 보기]** — 담당자 PIN 카드(`.pin-qr` → `qrShow()`, `#qrDlg` .lvmask) · 관리자 로그인 링크 줄(`#qrDlg` 인라인 스타일). QR 인코더는 외부 CDN 없이 **각 파일에 인라인**(`const QR=…` 안에 npm `qrcode-generator` 1.4.4 minified + `matrix/svg` 래퍼).
  **직접 짠 인코더는 폰 카메라에서 안 읽혔다 (2026-09-13)** — 같이 짠 파이썬 디코더로는 통과했지만 독립 리더(jsQR)로는 전부 실패. 교체 뒤 `ptest/qrfinal.mjs` 로 4파일×5주소 = 20/20 통과.
  검증은 반드시 **남이 만든 리더**(jsQR)로, 주소마다 **새 page** 로 할 것 (`page.setContent` 재사용 시 전 문서의 `const QR` 이 남아 스크립트가 조용히 죽고 이전 QR 이 그대로 찍힌다). 주소 = `location.origin+location.pathname`(쿼리 제외).
- **대시보드 판매 개수** — 채널 순위 금액 옆 `.rk-q` "N개"(샵링커 상품 셀 `PC[c][3]` 합, 상품 데이터 있는 채널만) · 채널 드로어 상위 상품 q "N개" + 카테고리 sub.
- **탭 13개 전수 점검 (2026-09-15 · `ptest/tour.mjs`, store.html 에 올림 09-15)** — 홈·상담·배정·상담 입력·견적서·내 고객·알림·재고·주문서·일 마감·판매 입력·상담 현황·휴가를 폰(390px)·데스크톱(1280px) 두 벌로 돌며
  가로 넘침 · 화면 밖 요소 · 40px 미만 버튼 · 굵은 글씨 4.5:1 미만 · overflow 로 잘린 글자 · 한 줄에 같은 색 태그 3개 이상을 센다. 폰 13탭 전부 ✓ 여야 한다.
  거기서 고친 것: ① 주문서 마법사 세그·버튼과 주문서 편집 품목 도구([+ 줄 추가]·[붙여넣기 칸]·[비우기]·[+ 추가]·표의 ×)가 폰에서 17~36px → 40px
  ② 일 마감 줄 빼기 × 가 24×27 → 40×40 (`.drow` 폰 4번째 열 24px → 40px) ③ 대비 : 상담 입력 힌트 굵은 글씨·휴가 달력 주차(W36…)·주문서 ① 안내 굵은 글씨가 2.4~2.6:1 →
  `.f label .hint` 를 `--muted` 로, 그 안의 `<b>` 는 `--ink-2`, `.lvcal .wk` 를 `--muted`, `.wiz .sub` 를 #6B7484(굵은 글씨 #2E3542).
  **`--faint`(#98A1B0)는 흰 바탕에서 2.6:1 이라 굵은 글씨에 쓰면 안 된다** — 가는 글씨 장식에만.
  **가로 스크롤 상자 안의 넓은 표는 넘쳐도 된다** — `tour.mjs`·`audit.mjs` 의 '화면 밖' 검사가 overflow-x:auto/scroll 조상을 만나면 건너뛰도록 고쳤다
  (`.tw`·`.hlbox`·`.gtbl`·`.of-tw`). 이걸 넣고 `audit.mjs drawer home` 12조합이 글자 '크게'(1.6)까지 전부 ✓ 가 됐다.
  데스크톱의 `.mini`(29~38px)는 원래 데스크톱 디자인이라 그대로 둔다 — 40px 규칙은 폰에만 건다.
- **이미 보낸 고객 (발송 이력) 가져오기 + 발송 대상에서 제외 (mvp_143 · 2026-09-15)** — `crm.send_log` 가 0건이라 [발송 대상 추출]의 '최근 발송 제외' 가 아무도 걸러내지 못하고 있었다.
  관리자 › 데이터 가져오기에 카드 **[이미 보낸 고객 (발송 이력)]**(`core.data_source 'send_log'`) 추가 — 파일 올리기·붙여넣기 둘 다.
  양식은 `수신번호 · 이름 · 발송일` 3열(이름은 없어도 된다). 올릴 때 **캠페인명이 필수**라 안 적으면 [적재] 가 잠긴다(`renderSendOpts`/`sendOptsChanged`), 줄에 발송일이 없으면 화면에서 고른 날짜로 들어간다.
  **매칭은 휴대폰 뒤 8자리로 한다** — `core.f_buyer_key` 는 이름+번호를 같이 해싱하므로 이름이 없거나 다르게 적힌 발송 목록으로는 같은 키가 안 나온다. 번호만 있는 목록도 받아야 한다.
  `fn_send_log_import(p_rows,p_campaign,p_channel,p_sent_at,p_file)` 가 `읽은 줄 · 고객 찾음 · 마스터에 없음 · 이미 올린 건` 을 돌려주고 못 찾은 번호 예시를 보여준다.
  같은 (캠페인, 고객) 은 `ux_send_camp_buyer` 로 한 줄만 — **같은 파일을 다시 올려도 중복되지 않는다**.
  [발송 대상 추출]의 '최근 발송 제외' 를 **[이미 보낸 사람 제외]** 로 바꾸고 `한 번이라도 보낸 사람 전부 제외`(= `p_no_send_days` 36500) 를 넣었다 — `fn_crm_targets_v2` 는 안 고쳤다(기존 인자로 그대로 된다).
  센드온이 붙으면 발송할 때마다 `fn_send_log_add` 가 자동으로 쌓으므로 이 카드는 그때 수동 업로드용으로만 남는다. 테스트 `ptest/sendlog.mjs` S1~S11.
  **2026-09-15 기준 당장 발송 가능 3,741명** (전체 고객 62,647 · 수신동의 6,905 중 휴대폰까지 있는 사람). 개인 3,686 · 기업 55.
  유입은 S몰 1,783 · AT몰 1,068 · P몰 823 · 시흥몰 153 · 샵링커 131 · 이카운트 61 · 매장 8.
  **이 중 구매 이력이 있는 사람은 195명뿐**(최근 90일 116 · 90일~1년 27 · 1년 이상 휴면 52)이고 3,546명은 동의만 한 고도몰 회원이다 — 재구매 메시지와 신규 안내를 같은 문구로 보내면 안 된다.
- **대상 기준 두 가지 · 센드온 파일 그대로 (mvp_144 · 2026-09-15)** — 2026-08-14 센드온 발송 내역(261줄)을 맞춰 보니 **259개 번호 중 257명이 고객 마스터에 있는데 수신동의 표시는 3명뿐**이었다.
  이 사람들은 **이카운트 거래처(소모품·VMS)** 라 동의가 거래 관계에서 나오고 `crm.customer.consent_marketing` 은 false 다 — 이카운트 고객 32,826명 중 동의 표시는 61명뿐.
  그래서 [발송 대상 추출]이 동의 고객만 보면 실제로 보내는 사람들을 아예 못 뽑는다.
  **[대상 기준] 세그 추가** — `수신동의 고객`(기본, 지금까지와 같음) / `거래 재구매 주기`. `fn_crm_targets_v2` 에 `p_basis`(옛 시그니처 drop → 새로 create → grant).
  `repeat` = 주기(= (마지막-처음) / (산 날 수 - 1))를 넘겼고 주기의 3배 안, 마지막 거래 2년 안. **동의 여부를 안 본다** — 보낼 수 있는지는 사람이 판단한다는 안내를 세그 옆에 띄운다. `localStorage dc_tg_basis`.
  `crm.customer_roll` 에 `first_at`·`buy_days`(산 날 수)를 materialize 하고 `core.f_customer_roll` 이 채운다 — cnt 는 줄 수라 주기 계산에 쓰면 안 된다(인당 평균 11.6줄).
  `last_sent` 는 `status <> 'failed'` 만 센다 (발송 실패 = 고객이 못 받음). 센드온 내려받기 열 이름(`실 발송 일시`·`상태`·`비고`)을 그대로 읽고 실패 건은 `status='failed'` 로 넣는다.
  **2026-09-15 숫자**: 동의 기준 3,741 · 재구매 주기 1,267(채널 VMS 1,231) · 8/14 발송분 빼면 **1,123명**. 그 1,123명의 마지막 거래는 6개월 이내 130 · 6개월 초과 993 (평균 경과 390일 · 평균 주기 243일).
  **미결제(입금 대기) 주문은 데이터센터에 없다** — 샵링커는 결제가 끝난 주문만 준다. 고도몰 관리자 화면의 '가/미'(가상계좌·미입금) 주문은 안 들어온다(9/14 KMR85RH 710만원 · 9/12 KQ85QNH80 352만원 둘 다 DB 에 없음).
  결제 안 한 고객에게 보내려면 **고도몰 관리자에서 미입금 주문 목록을 받아와야 한다**(붙여넣기 또는 새 데이터 소스).
- **담당자 사용 안내 `/store/guide/`** — 17장: 시작 · 화면 구성 · 상황 4개(온라인 문의/매장 방문/콜백→견적서→구매/지난 상담 찾기) · 화면별(홈·상담·상담 입력·견적서·내 고객·알림 내역·판매 입력/일 마감/월 마감·현황) · 점장이 하는 일 · 찾는 법 · 문제 시.
  화면을 고치면 여기도 같이 고친다. PDF 는 `ptest/guide_pdf.mjs` 로 뽑는다.

### 미배포 (올려야 동작)
- `quote_subscribe.php` (고도몰) — **데이터센터 직접 호출 (mvp_138 · 2026-09-14, 세션 전달본)** + [📨 고객에게 보내기] + **폰 레이아웃 개편 (2026-09-13)**: ≤880px 에서 기본은 견적서만,
  패널(고객·옵션·표시 항목·네임카드·발행 내역·임시 저장)은 바텀 시트(`#quoteModal.sheet-open`), 아래 탭바 `.q-mtab`
  [설정·메뉴]·[견적서]·[발행]·[보내기], 툴바는 제목+[금액 수정]+[⋯](새 견적·발행 내역·PDF·인쇄). 편집 모드 견적서 머리는 세로로 쌓아 100% 폭.
  데스크톱은 그대로. 파일은 저장소에 두지 않는다(보안 코드 해시·GAS 주소 포함) — 세션 전달본을 고도몰에 올릴 것.
- `1_quote_Code.gs` (Apps Script · 견적내역) — 세션 전달본(`견적내역_Code_namecard.gs`)에 `pullQuotesFromDatacenter()` 가 들어 있다. 붙여넣고 DC_KEY 채운 뒤 **트리거 15분** 등록.
  전환 순서: ① GAS 에 새 키 넣고 재배포 → ② 메뉴 [Datacenter 일괄 적재] 1회(시트에만 있던 SH260914-007~009 등을 DC 로) → ③ PHP 업로드 → ④ 트리거 등록. ②를 건너뛰면 DC 가 매기는 다음 번호가 시트 번호와 겹칠 수 있다.
- ~~`gmail_inquiry.gs` 1분 트리거~~ — **2026-09-13 설치 완료** (사용자 확인). 게시판 문의가 지메일 → 1분마다 `fn_inquiry_mail_ingest` 로 들어온다.
  멈추면 수집 미도착 감시(09:10 잔디)에 잡힌다.

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
   견적은 2026-09-14 부터 데이터센터가 저장소다(mvp_138). `1_quote_Code.gs` 는 시트 거울(`pullQuotesFromDatacenter`)과 계산기 API 만 남았다.
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
