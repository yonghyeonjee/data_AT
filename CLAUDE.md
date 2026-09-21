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
| 단축 링크 착지 | `/r/?슬러그` | 문자 받은 고객 (클릭 기록 → 원래 주소로) |

`/admin/test/`, `/store/test/`, `/visit/test/` 는 같은 파일의 테스트본 (경로에 `/test/` 가 있으면 `DC_ENV='test'`).

**백엔드는 Supabase 하나** (project `wdahskrcpjooqhwwxjiu`, ap-northeast-2).
화면은 전부 정적 HTML + 브라우저에서 RPC 호출. 서버 코드는 전부 Postgres 함수.

---

## 저장소 구조 — 이것만 있어야 한다

```
CNAME  README.md  VERSION.txt  robots.txt  favicon.ico
index.html  admin.html  store.html  stock.html
.github/workflows/   admin/  customer/  dash/  flow/  q/  r/  sql/  store/  tools/  visit/
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
- **바깥으로 나간 HTTP(이카운트 전송)는 롤백되지 않는다 (2026-09-17 사고).** `core.f_ec_call` 은 호출 사이 1.2초를 쉬어 여러 장을 한 문장에 넣으면 anon 3초를 넘겨 57014 로 롤백 — DB 는 '대기'로 돌아가는데 이카운트엔 전표가 생긴다. `ec.api_log` 도 같이 사라져 흔적이 없다.
  게다가 화면 `rpc()` 의 타임아웃 재시도가 그걸 3번 반복했다. **바깥으로 나가는 RPC(`order_send`)는 `RPC_NO_RETRY`, 전표는 한 장씩(mvp_151).** 새로 바깥 호출을 만들 때 같은 규칙.
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

## 지금 상태 (2026-09-21 · v135)

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
  **상품 금액이 보이는 곳엔 전부 개수 (v115 · 2026-09-17)** — "각 몰 상세에서도 제품 갯수가 나와야지". 채널 탭 [이 채널 상위 상품] 줄 왼쪽 N개 · 오른쪽 '비중 %' · 머리에 '46종 · 312개' /
  상품 서랍 [판매 채널] 줄 N개·비중, [월별 순매출] 막대 툴팁 '9월 1,330만 · 3개' (`miniBars` 5번째 인자 `tips`) / 증감 원인(상품) 툴팁 '+N개'(`prodSum(mset,true)`) / 파레토 툴팁 N개 / 사실 요약 1위 상품 N개.
  금액은 언제나 그 상품의 판매액 합계(개수 포함)다. 테스트 `ptest/dashqty.mjs` Q1~Q3 (가짜 payload 로 채널 탭·서랍을 실제로 연다).
  **상품은 이제 일 단위 (mvp_156 · v116)** — "몰별로 기간에 맞게 나와야지 왜 월전체가 나오니". `f_dash_payload` pcells 첫 값이 월 → **일 인덱스**, 응답 `pgran:'d'`. 화면 `PDAY` 면 `selMonths()` 가 날짜 범위로 거른다(옛 월 단위 payload 도 그대로 읽음).
  12개월 payload 250KB → 656KB(pcells 15,043). '월 단위' 안내 문구는 전부 '기간 집계' 로. 테스트 dashqty.mjs Q1·Q2 가 기간 밖(9/06) 셀이 빠지는지 본다.
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
  `repeat` 은 **2026-08-14 콜랩 방식 그대로** (mvp_146): 주문 = 고객×날짜 합산 · 주기 = 간격의 **중앙값**(평균은 한 번의 긴 공백에 끌려간다) · **이탈(마지막 구매 365일 초과) 제외** · 예상재구매일(마지막 구매 + 주기) 기준 **D-30 ~ D+14**.
  **동의 여부를 안 본다** — 보낼 수 있는지는 사람이 판단한다는 안내를 세그 옆에 띄운다. `localStorage dc_tg_basis`.
  주기는 `crm.customer_roll.cycle_days` 에 materialize (`core.f_customer_roll` 이 percentile_cont 로 채운다). **cnt·평균을 주기로 쓰면 안 된다** — cnt 는 줄 수(인당 11.6줄)고 평균은 공백에 끌려간다.
  콜랩은 거래처×모델 3회+ 의 **모델 주기**를 1순위로 쓰는 3단 폴백(모델주기 상 / 주문주기 중 / 2회뿐이면 하)까지 했다. 우리는 아직 주문 주기만 — 모델 주기는 품목명 파싱이 붙은 뒤에 넣는다.
  8/14 콜랩 결과 발송 타겟 266건(문자 가능 263) · **2026-09-15 우리 DB 로 같은 규칙 383명**.
  `crm.customer_roll` 에 `first_at`·`buy_days`(산 날 수)를 materialize 하고 `core.f_customer_roll` 이 채운다 — cnt 는 줄 수라 주기 계산에 쓰면 안 된다(인당 평균 11.6줄).
  `last_sent` 는 `status <> 'failed'` 만 센다 (발송 실패 = 고객이 못 받음). 센드온 내려받기 열 이름(`실 발송 일시`·`상태`·`비고`)을 그대로 읽고 실패 건은 `status='failed'` 로 넣는다.
  **2026-09-15 숫자**: 동의 기준 3,741 · 재구매 주기 **383**. (mvp_146 전 셈법으로는 1,267 이었다 — 주기를 평균으로 잡고 '주기~주기×3 · 2년 안' 이라 너무 넓었다.)
  **미결제(입금 대기) 주문은 데이터센터에 없다** — 샵링커는 결제가 끝난 주문만 준다. 고도몰 관리자 화면의 '가/미'(가상계좌·미입금) 주문은 안 들어온다(9/14 KMR85RH 710만원 · 9/12 KQ85QNH80 352만원 둘 다 DB 에 없음).
  결제 안 한 고객에게 보내려면 **고도몰 관리자에서 미입금 주문 목록을 받아와야 한다**(붙여넣기 또는 새 데이터 소스).
- **미입금 주문 (고도몰) · 결제 안 한 고객 (mvp_145 · 2026-09-15)** — 샵링커는 **결제가 끝난 주문만** 준다. 고도몰 관리자의 '가/미'(가상계좌·무통장 미입금) 주문은 우리 DB 에 안 들어온다
  (9/14 KMR85RH 710만원 · 9/12 KQ85QNH80 352만원 둘 다 없음을 확인). 그래서 고도몰에서 입금 대기 목록을 받아 따로 쌓는다.
  데이터 소스 **[미입금 주문 (고도몰)]**(`unpaid_order`) — 양식은 `주문번호 · 상점구분 · 주문일시 · 주문자 · 주문자휴대폰 · 주문상품 · 수량 · 총 주문금액 · 결제방법 · 주문상태`.
  **`crm.unpaid_order` 는 스냅샷이다** — `fn_unpaid_upsert` 가 올릴 때마다 목록에 없는 열린 건에 `resolved_at` 을 찍어 내린다(= 결제됐거나 취소됨). 그래서 **입금 대기 전부**를 받아 올려야 한다. 적재 전에 확인창이 그렇게 경고한다.
  화면: 발송 대상 추출 아래 **[결제 안 한 고객 (미입금 주문)]** 카드(`#upCard`) — 캠페인명 필수 · 키워드 · 경과일 최소/최대 · 주문금액 이상 · 이미 보낸 사람 제외 · [실명·실번호] · 엑셀/CSV. `fn_unpaid_list` 는 첫 페이지·내보내기 때 `crm.access_log` 에 남긴다.
  **주문일시에 표준시가 안 붙어 있으면 KST 로 읽는다** — `core.f_ts` 는 UTC 로 읽어서 14:51 주문이 23:51 로 찍혔다. 화면 `mapRows` 도 `excelDate` 가 시각을 버리므로 `YYYY-MM-DD HH:MM` 은 직접 살린다.
  **temp table 이름은 `_uw`(upsert) / `_ur`(list) 로 나누고 `drop table if exists` 를 앞에 둔다** — 한 트랜잭션에서 둘을 같이 부르면 `_u` 가 겹쳐 터진다.
- **업로드 화면은 손이 필요한 것만 펼친다 (2026-09-15)** — 데이터 소스 카드가 열일곱 장이라 화면을 덮었다. 기본은 **state 가 '정상' 이 아닌 것(지연·없음·준비 중)만** 카드로 보이고,
  잘 들어오는 원천은 맨 아래 한 줄(`.src.dsfold`)에 태그로 접힌다. [전부 보기] 로 펼치고 `localStorage dc_ds_all` 에 기억. '형식별 매핑 규칙' 카드도 `<details>` 로 접었다.
- **8/14 발송분 적재 완료 · 월요일(9/21) 토너·정수기 필터 교체 알림 준비 (2026-09-15)** — 센드온 발송내역 261줄을 `fn_send_log_import` 로 넣었다:
  캠페인 `2026-08-14 토너·잉크 교체 안내 (LMS)` · 257명 매칭 · 실패 1 · 미매칭 4줄. **이 사람들은 이카운트 VMS 거래처**(256/257 source=ecount) — 고도몰 회원 풀과 다른 집단이라 3,741 에서는 3명만 빠지고, 재구매 주기 383 에서는 58명이 빠진다.
  `fn_send_log_import` 도 KST 버그를 고쳤다 — `실 발송 일시` 에 표준시가 없으면 KST 로 읽는다(전엔 16:09 가 다음 날 01:09 로 들어갔다).
  **'30일 내 제외' 로는 8/14 발송분이 안 빠진다**(월요일이면 38일). `setBasis('repeat')` 가 `#crmNoSend` 를 비어 있으면 `36500`(전부 제외)으로 미리 놓는다. 테스트 S13b.
  **D-30~D+14 창은 날짜에 따라 움직인다** — 9/15 기준 325, 9/21 기준 339(새로 50·빠짐 36). 보내는 날 아침에 뽑는다. 뽑은 뒤 실제 보낸 목록(센드온 내려받기)을 다시 [이미 보낸 고객] 에 올려야 다음 회차에 빠진다.
- **대상 기준 '제품 재구매' (mvp_147 · 2026-09-15)** — 정수기 필터·건조기 필터(WD-FLTR)·AI 콤보처럼 **특정 제품을 산 사람**에게 교체·연결 판매를 보내려면 제품으로 뽑을 수 있어야 한다.
  `repeat`(주문 주기)은 소모품에 안 맞는다 — 필터는 2회 이상 산 사람이 30명뿐이다.
  `fn_crm_targets_v2` 에 **`p_basis='product'` + `p_product`(정규식)** 추가. 그 제품을 `p_from ~ p_to` 사이에 산 적이 있으면 통과, **수신동의는 안 본다**.
  product 기준일 때 `p_from`·`p_to` 는 '마지막 구매일' 이 아니라 **'그 제품을 산 날'** 이다(`o.last_at` 조건을 건너뛴다). `core.orders` 에 품목명 trgm 인덱스(`ix_orders_pname_trgm`).
  화면: [대상 기준] 에 **[제품 재구매]** 세그 + 제품 칸(`#crmProd`) + 프리셋 4개(정수기 필터 `HAF-` · 건조기 필터 `WD-?FLTR` · AI 콤보 `콤보|WD9[0-9]H` · 토너·잉크 `MLT-|CLT-|INK-`).
  고르면 날짜 라벨이 '이 제품을 산 기간' 으로 바뀌고 '이미 보낸 사람 전부 제외' 가 자동으로 걸린다. 제품을 안 적으면 추출·내보내기를 막는다. 테스트 P1~P4.
  **2026-09-15 규모**: 정수기 필터 4,082 · 3~6개월 전 구매 **1,067** · WD-FLTR 101 · AI 콤보 248.
  **`samsung_pmall` 은 네이버 스마트스토어다** — `SHOP_MAP` 에서 `'스마트스토어|samsung_pmall' → 'B2B|오픈마켓'` 이라 채널 이름이 'B2B' 로 나와 자사몰처럼 보이지만 아니다.
  정수기 필터 구매자 4,390명 중 **3,279명이 스마트스토어**, 고도몰 자사몰(P·S·AT·시흥)은 251명뿐. 고도몰 회원 명부와 맞물리는 사람은 45명(수신동의 5명).
  쿠팡 551명은 전부 050 안심번호라 문자가 안 간다. 나머지는 010 실번호가 살아 있다 — **못 보내는 이유는 번호가 아니라 동의다.**
- **오픈마켓 고객은 발송 대상에서 아예 빠진다 (mvp_148 · 2026-09-15)** — 오픈마켓(스마트스토어·쿠팡·11번가·지마켓·옥션·SSG·롯데온 등)에서 받은
  주문자 정보는 **그 주문을 이행하는 데만** 쓸 수 있고 우리 이름으로 광고·안내를 보내는 근거가 아니다. 그런데 [제품 재구매] 기준이 오픈마켓 주문까지 세고 있었다.
  `fn_crm_targets_v2` 를 두 군데 고쳤다 — ① 제품 기준은 `po.channel_type <> '오픈마켓'` 인 주문만 근거로 센다
  ② 기준과 무관하게 **오픈마켓에서만 알게 된 고객을 통째로 뺀다**(남는 조건 = `consent_marketing`(자사몰 회원가입 동의) **또는** 자사몰·VMS·렌탈·매장 직접 거래).
  빠진 인원은 `summary.blocked_open` 으로 돌려주고 화면 요약 줄에 "오픈마켓 고객이라 제외 N명" 으로 보인다. 카드 맨 위에 `.callout.warn` 상시 안내.
  **숫자 변화**: 수신동의 3,742 → 3,742 · 재구매 주기 383 → **352** · 정수기 필터 HAF- 4,083 → **235**(자사몰 230·VMS 5, 3~6개월 창은 53) · WD-FLTR 101 → 63 · AI 콤보 248 → 123 · 토너·잉크 34,005 → 32,404.
  **정수기 필터 캠페인은 사실상 못 보낸다** — 필터 구매자의 94%가 오픈마켓(스마트스토어 2,996·쿠팡 551·E스토어 239)이다.
  **기간 뒤에 또 산 사람은 뺀다 (mvp_157 · 2026-09-17)** — "구매한지 90일은 지났어야지". 9/1 에 필터를 다시 산 오세훈이 3~12개월 창에 들어 있었다(기간 안 구매가 있으면 통과였음).
  product 기준은 이제 `p_to` 뒤에 같은 제품을 산 기록(채널 무관, 취소·환불 제외)이 있으면 제외하고, 화면 '최근 구매'·'최근 상품' 열은 그 제품의 마지막 구매를 보여준다(다른 제품 구매는 안 보임). 63 → 62.
- **누가 뽑아도 같은 수가 나와야 한다 (mvp_148)** — 두 가지가 깨져 있었다.
  ① 저장 조건(`crm.segment`)에 **대상 기준·제품이 안 담겨** 같은 버튼을 눌러도 사람마다 다른 수가 나왔다 → `saveSegment` 가 `basis`·`product`·`asof` 를 같이 저장하고
  `segToForm` 이 `setBasisQuiet()` 로 먼저 복원한다(`setBasisQuiet` = TG 를 잠시 비워 setBasis 가 추출을 다시 하지 않게 하는 판).
  ② [거래 재구매 주기] 가 `now()` 를 써서 **하루만 지나도 대상이 바뀌었다** → 새 인자 `p_asof date`(비우면 오늘). 화면에 `#asofBox`·`#crmAsof`(기준일, 재구매 주기일 때만 열림, 오늘로 자동)
  + 요약 줄·조건 칩에 기준일 표시. 응답 `summary.asof`.
  조건 칩 맨 앞에 **[기준]·[제품]·[기준일]** 을 붙여 화면만 보고 서로 같은 조건인지 맞춰볼 수 있다. **[조건 복사]/[조건 붙여넣기]**(`condOf`·`copyCond`·`pasteCond`) 로 조건 전체를 글로 주고받는다.
  `p_asof` 는 기본값 인자라 **옛 시그니처 drop → create → grant** 했고, 그때 **ACL 이 PUBLIC 으로 되돌아가 anon 이 붙었다** — `revoke ... from public, anon` 까지 해야 한다.
- **문자 링크 UTM 은 캠페인명에서 만든다 (mvp_148)** — 손으로 붙이면 사람마다 달라져 GA4 에서 한 캠페인으로 안 묶인다.
  캠페인명 옆 [링크 만들기](`utmBuild`) → `utm_source=sendon` · `utm_medium=lms|mms` · `utm_campaign=utmSlug(캠페인명)` · `utm_content=대상 기준`. 원래 쿼리(`bdId`·`sno`)는 그대로 둔다.
  **`utmSlug` 는 캠페인명 안의 영문 토큰을 쓴다** — '2026 추석 구독 할인 (chuseok2026)' → `chuseok2026`. 한글만이면 한글 슬러그가 되는데 `%EC%B6%94…` 로 길어져 문자 글자 수를 잡아먹으므로 창에서 영문 코드를 권한다.
  규칙이 캠페인명 하나에서만 나오므로 누가 만들어도 같은 링크다. 테스트 `ptest/sendlog.mjs` O1~O8 · T1~T5 (전체 39개).
- **저장 조건이 조용히 어긋나던 것 (mvp_149 · 2026-09-15)** — [토너·잉크 재구매 주기] 를 누르니 95명이 나왔는데 목록에 냉장고·갤럭시 워치·식기세척기 구매자가 있었다. 토너가 한 명도 없었다.
  `crm.segment.params` 의 `kind_goods` 를 **화면이 읽지 않는다** (admin.html 어디에도 그런 키가 없다) → 실제로는 '최근 60~180일 전에 아무거나 산 수신동의 고객' 을 뽑고 있었다.
  같은 병이 `b2b_repeat` 에도 있었다 — `kind` 값이 `'사업자'` 인데 select 의 값은 `'business'` 라 **select 가 조용히 '전체' 로 떨어져** 사업자 조건이 통째로 빠졌다.
  `toner_repeat` 은 `active=false` 로 내리고, `b2b_repeat` 은 값을 고쳤다. 화면에는 `SEG_KEYS`(조건이 쓸 수 있는 키 전부) 를 두고 `segToForm` 이 **모르는 키·select 에 없는 값이면 토스트로 알린다** (테스트 N1~N3).
  **새 프리셋 4개는 `active=false` 로 넣어 뒀다** (`toner_repeat_v2` · `camp_chuseok_0918` · `camp_toner_0921` · `camp_filter_0923`) — **옛 화면은 `basis`·`product`·`asof` 를 못 읽어 엉뚱한 명단이 나오므로 새 admin.html 배포를 확인한 뒤 켤 것** (`sql/mvp_149` 마지막 줄).
  **2026-09-15 배포 완료** — `main` 을 v108(`cf2bbf5`)로 fast-forward 하고 `pages build and deployment` 성공을 확인한 뒤 프리셋 4개를 `active=true` 로 켰다.
  `db.samsungat.co.kr` 은 **main 을 서비스한다** — 관리자 화면 기능은 main 에 머지되기 전까지 실제로는 안 걸린다는 것을 이때 처음 겪었다(브랜치에만 올려 두고 며칠 썼다).
- **이카운트 전표 — 거래처명·특이사항 (mvp_150 · 2026-09-15)** — 고창재 프로님 테스트 3건에서 나온 지적.
  **① 재고부족은 타이밍이었다** — 테스트 17:05:10 / 재고 999 고정 17:17:37. 그 사이 `AT-00614`(HAF-CIN3/EXP)가 -67 이라 막혔다.
  **재고를 보는 곳은 `inv.v_stock` 이 아니라 `core.f_order_submit` 안의 `inv.v_ledger` 창고별 합계**(`warehouse = v_wh`, 기본 `00001` 본사창고)다. 재고를 손볼 때는 창고까지 맞출 것.
  **② 거래처명에 고객명이 찍혔다** — `core.f_sl_to_order` 가 `cust_code` 는 채널 거래처(`ec.channel_cust`)에서 가져오면서 `cust_name` 에는 구매자명을 넣고,
  `core.f_order_body` 가 그걸 그대로 `CUST_DES` 로 보냈다 → 이카운트 거래처명 칸에 '이흥노'·'삼덕초등학교'. **`CUST_DES` 는 이제 `ec.customer.name`(거래처코드 기준)에서 찾는다.**
  `ec.order_queue.cust_name` 은 우리 기록용으로 그대로 둔다(누가 산 건지는 남아야 한다).
  **③ 특이사항에 `010-0000-0000`** — `U_MEMO1` 은 이카운트 필수값인데 `ec_field_map` 이 `phone → U_MEMO1` 이고 샵링커 주문은 phone 이 null 이라 매핑이 건너뛰어져 가짜 번호가 박혔다(큐 9건 중 전화 있는 건 1건).
  이제 **적요(`q.remark`) → 전화 → 주문월** 순으로 채운다. 적요도 `'N월 주문건 / 날짜'` 에서 **`'N월 주문건'`** 으로 줄였다(변환일은 `ec.order_queue.created_at` 에 있다).
  **이미 나간 전표는 안 바뀐다** — 이카운트에서 지우고 다시 보내야 한다. 실패로 남은 건은 화면 [재전송] 으로 고쳐진 본문이 나간다.
- **이카운트 전송은 한 장씩 (mvp_151 · 2026-09-17)** — "성공 0장 · 실패 20장 · 서버 응답이 늦습니다". `core.f_order_send` 가 한 문장에서 순서대로 보내는데 `f_ec_call` 이 장마다 1.2초를 쉬어 담당자 화면(anon 3초)에선 두 장쯤에서 끊긴다.
  롤백돼도 **이미 나간 HTTP 는 돌아오지 않아** 이카운트엔 전표가 생기고 우리 쪽엔 '대기'로 남는다. 화면 `rpc()` 가 타임아웃이면 두 번 더 보내 클릭 한 번에 3번. 매번 `io_date, id` 순 첫 장(#13 송영선·#10 윤만수)이 나갔을 수 있다 — **이카운트 판매주문서에서 9/17 자 중복을 눈으로 지워야 한다**(OpenAPI 에 판매주문 조회가 없다).
  서버: `f_order_send` 에 **1.0초 시간 예산** — 넘기면 새 장을 시작하지 않고 `remaining` 으로 반환. 화면: `ecSend` 가 **한 장씩 호출**(장 사이 `EC_SEND_GAP` 1.3초, 테스트는 짧게), 결과 합산·진행 표시, `remaining` 은 한 번만 뒤에 붙임, 권한 오류는 즉시 중단.
  `rpc()` 에 `RPC_NO_RETRY=/order_send/` — 바깥으로 나가는 호출은 절대 자동 재시도 안 함. 관리자 [전체 전송]은 `fn_order_queue`(ready·failed) 로 id 를 먼저 받아 한 장씩. `ecSend` 는 두 파일에 **같은 블록이 2번씩** 들어 있다(WIZ:SEND) — 고칠 때 둘 다.
  테스트 `ptest/ecsend.mjs` E1~E7(담당자)·A1~A2(관리자). 화면에 보이는 '· 김형주' 는 우리 기록(`cust_name`)이고 이카운트 거래처명은 mvp_150 대로 코드 기준('S몰 (에스몰)')으로 나간다 — 큐 25번으로 확인.
- **UTM 관리 — 캠페인 · 단축 링크 · 클릭 (mvp_152 · 2026-09-17)** — 관리자 메뉴 [UTM 관리](`core.menu_item 'utm'`, crm 그룹, 화면 `#v-utm`·`loadUtm`).
  **캠페인 코드(`crm.campaign.code`, `yymm_주제`, 예 `2609_chuseok`) 하나가 `utm_campaign` · `send_log.campaign` · `access_log.reason` 의 이름을 겸한다** — 같은 코드여야 추출→발송→클릭→구매가 한 줄로 이어진다.
  단축 링크 `https://db.samsungat.co.kr/r/?슬러그`(`crm.link`, 6자 `core.f_slug`) → `/r/index.html` 이 `fn_link_go`(anon) 로 `crm.link_hit` 에 클릭을 적고 `location.replace` 로 UTM 붙은 긴 주소로. **클릭은 GA4 없이 우리 DB 에서 센다**(GA4 수집은 여전히 pagePath 만 — `collect.mjs` 에 `sessionCampaignName` 을 붙여야 GA4 쪽도 보인다).
  캠페인 표 열: 발송(`send_log` 수신자) · 클릭(`link_hit`) · 구매(수신자 중 발송 뒤 주문) · 매출. 발송 이력이 있으면 [삭제] 대신 [접기], 링크는 지우지 않고 [끄기](이미 나간 문자의 주소가 죽으므로).
  **발송 대상 추출 [링크 만들기](`utmQuick`)** — 캠페인명의 코드로 그 캠페인의 링크 창(`utmLinkNew`)을 열고, 없으면 그 자리에서 등록(코드·이름·지금 걸린 저장 조건 미리 채움) 뒤 이어서 링크. 캠페인명 칸은 `#crmCampList` datalist. 옛 `utmBuild`(클라이언트에서 UTM 만들던 창)는 걷어냈다 — UTM 값은 서버 `core.f_utm_tok/f_utm_url` 이 만든다([a-z0-9_.-] 만, 인코딩 없음).
  [대상 조건] 버튼 → `utmExtract(code, seg)` = 캠페인명에 코드 넣고 `PENDING_SEG` 로 넘어가 `loadSegments` 끝에서 `applySegment`. [이미 보낸 고객] 캠페인 칸도 코드 목록(`utmCampListHtml`).
  8/14 발송 이력 257줄의 campaign 을 `2608_toner` 로 맞췄다. 테스트 `ptest/utm.mjs` U1~U10(관리자)·R1~R4(/r/ 착지). **Playwright 라이브러리는 동작 타임아웃 기본이 무한** — 테스트에 `setDefaultTimeout` 을 걸고, 모달을 여는 함수(`utmNew` 등)는 `evaluate` 안에서 **return 하지 말 것**(닫힐 때까지 안 끝나 교착).
- **단축 링크 앞부분은 고도몰 주소로 (mvp_152b · 2026-09-17)** — "db.samsungat.co.kr 이 문자에 노출되는 게 싫다" 는 지적. 앞부분은 `core.app_setting 'short_base'` 하나이고 `fn_utm_campaigns` 가 읽을 때 붙이므로
  바꾸면 **이미 만든 링크(2juqy8 등)도 전부 새 앞부분으로** 보인다(슬러그·긴 주소는 그대로). UTM 관리 '단축 링크 주소' 카드 [바꾸기] → `utmBaseEdit()` → `fn_utm_setting_save(p_base)`(관리자만, `^https://…\?(c=)?$` 검사).
  **착지 파일이 그 주소에 먼저 올라가 있어야 한다.** 고도몰은 `/r/index.php` 같은 경로에 파일을 못 올린다("그렇게는 못올려") — 가능한 곳은 `samsungsh.com/data/` 아래뿐이라 **결정: `tools/godo/r.html`(정적, `r/index.html` 과 같은 JS 착지)을 `/data/r.html` 로 올린다** → 앞부분 `https://www.samsungsh.com/data/r.html?`.
  **2026-09-17 전환 완료** — 사용자가 올린 `https://www.samsungsh.co.kr/data/r.html` 을 DB `extensions.http_get` 으로 확인(200 · 우리 파일 · text/html · no-store)하고 `short_base` 를 `https://www.samsungsh.co.kr/data/r.html?` 로 놓았다. `www.samsungsh.com` 은 443 이 안 열려 있어(연결 거부) https 앞부분으로 못 쓴다.
  파일 이름·폴더는 아무거나 된다(쿼리만 읽는다) — 올린 실제 주소 그대로 [바꾸기]에 넣으면 된다. `samsungsh.com`(103.142.103.237)과 `www.samsungsh.co.kr`(103.87.116.108)은 서버가 다르니 **올린 호스트와 앞부분 호스트를 똑같이** 맞출 것.
  다른 후보(보관만): `tools/godo/r.php`(진짜 302, 고도몰이 PHP 를 받을 때) · `tools/go/`(GitHub Pages 별도 저장소 + DNS `go.samsungat.co.kr`, README 참고) · buly.kr 같은 공용 단축기는 통신사 스팸 필터·수명 문제로 비추천.
  GitHub Pages 의 `r/index.html` 은 그대로 둔다(db.samsungat.co.kr 앞부분일 때의 착지). 컨테이너는 Supabase 로 나가는 HTTP 가 막혀 있어 착지 페이지는 가짜 RPC 로만 검증했다(`ptest/utm.mjs` R1~R4 · `ptest/go_chk.mjs`).
  **캠페인명에서 미리 채운 코드는 고칠 수 있다** — `utmForm(c, lock)` 의 readonly 는 [수정](`utmEdit`) 창에서만(발송 이력·UTM 이 그 이름으로 남아 있으므로). 새 캠페인·[링크 만들기] 등록 창은 열려 있다. 테스트 U11·U12.
- **utm_source 는 crm_manual 기본 · 고정하지 않는다 (mvp_152c · 2026-09-17)** — "나중에 센드온 안 쓰면 어쩌게". 단축 링크 창에 `utm_source`(`#ul_source`, 기본 `crm_manual`, datalist sendon·kakao·naver)와 `utm_campaign`(`#ul_campaign`, 캠페인 코드로 미리 채움) 칸이 있고 둘 다 고칠 수 있다.
  `fn_utm_link_save` 는 `p.source`(없으면 crm_manual)·`p.utm_campaign`(없으면 코드)을 받고, `core.f_utm_url`·`crm.link.utm_source` 기본값도 crm_manual. **값은 `core.f_utm_tok` 이 전부 소문자로 정리한다**(GA4 는 대소문자를 다른 값으로 세므로 `CRM_manual` 도 `crm_manual`).
  발송·클릭·구매 통계는 `crm.link.campaign`(fk) 에 붙으므로 utm_campaign 을 바꿔도 표는 그대로다. `fn_utm_campaigns` links 에 `utm_source`·`utm_campaign` 추가, 링크 줄에 utm_source 태그.
- **이카운트 전표 — 거래처는 이카운트 코드로만 · 샵링커 주문번호는 주문No. (mvp_153 · 2026-09-17)** — 고창재 프로님 지적 2건. 거래처 코드표(`ec.channel_cust` 15곳)는 전달받은 엑셀(기준코드·KEY1|:|KEY2|:|KEY3)과 15/15 같고 최근 큐 6건 전부 이카운트 코드로 나갔다.
  고친 것: ① `f_sl_to_order` 가 샵링커 쇼핑몰 계정(`channel_account` = 코드표 KEY3/KEY2)을 먼저, 채널명을 다음으로 맞추고 **둘 다 없으면 주문서를 안 만들고 skipped 사유**로 돌려준다 ② `f_order_body` 는 코드가 없거나 임시(`N:`)거나 우리 표에 없으면 raise — 이카운트가 구매자 이름으로 새 거래처를 만드는 길을 막았다
  ③ `f_order_send` 는 본문 오류를 그 장의 실패로 기록 ④ `ec_field_map` `order_ref`(샵링커 주문번호) `U_MEMO3`(이카운트 화면 '주소2') → **`DOC_NO`(주문No.)**. 쇼핑몰 주문번호는 줄 적요(REMARKS) 그대로.
  `ec.customer` 의 `N:이름` 43건은 이카운트 주문서 현황 업로드가 만든 임시 줄(거래처 엑셀을 올리면 같은 이름은 지워진다) — 전표에는 절대 안 나간다.
  **거래처명은 안 보낸다 (mvp_155)** — "코드만 넣고 명칭은 자동으로 따라오게". `f_order_body` 에서 `CUST_DES` 를 뺐다. 이카운트가 코드로 이름을 채우므로 우리 `ec.customer.name`('B2B (P몰 (B2B몰))')과 이카운트('스마트스토어 B2B')가 달라도 전표에는 이카운트 이름이 찍힌다.
  매핑 규칙(mvp_153): 샵링커 쇼핑몰 계정(코드표 KEY2/KEY3: pcnik35-AT·samsung_pmall…)이 있으면 계정으로, 없으면 스토어명(쿠팡·SSG·11번가…)으로 → 이카운트 코드. 이카운트 OpenAPI 에 거래처 조회는 없다(GetBasicCustomersList·GetBasicCust 404) — 이름 동기화는 거래처 엑셀 업로드뿐.
  **DOC_NO = '주문No.' 는 다음 전표에서 눈으로 확인할 것.** 9/7 필드 확인 전표(`ec.api_log` 117, 시흥몰(필드 확인 테스트))의 표식(M1~M5·T1·AT1~5·DOCNO·TTL·REFDES·RWIN·PR1~3·LT1)이 어느 칸에 보였는지가 매핑의 정답표다. 매핑은 관리자 이카운트 카드에서 바꿀 수 있다.
- **대시보드가 9/4 까지만 보이던 것 (2026-09-17)** — 대시보드 [수기입력] 모드는 `core.channel_daily`(온라인 채널 일매출 수기 대사표)를 읽는데 마지막 줄이 9/3 이다(9/4 이후 안 올림). 원장(`core.orders` 샵링커)은 9/16 까지 들어와 있다 — [원장] 모드로 보면 보인다.
  이카운트 판매현황(VMS)·렌탈도 업로드 원천이라 9/4 이 마지막이다. 자동 수집은 샵링커·매장 입력뿐. 헤더 '기간 …–2026.09.04' 는 수기 대사표의 마지막 날.
  **오프라인만 0 이던 것 (mvp_154)** — 매장 금액은 일 마감 snapshot(`core.store_daily.sales`)만 봤는데 9/14·15 줄이 `sales=0 · pending_sales` 였다(저장 당시 판매가 전부 '매출'=확정 대기, 그 뒤 확정돼도 snapshot 은 안 바뀜). 주문 수는 orders 라 12건. 
  원장 모드의 매장 일시불·구독은 이제 **판매 입력(`core.orders` store, 취소·환불·테스트 제외, 매출+판매완료)** 에서, 그날 그 구분의 판매 입력이 없을 때만 store_daily 로(8월 시트 자료). 직판은 두 모드 다 store_daily. 수기입력 모드는 그대로.
  **일 마감의 '판매완료 합계'는 저장 시점 snapshot 이라 대시보드 원천으로 쓰면 안 된다.**
  **기본 모드를 원장으로 바꿨다 (v114)** — `/dash/` `dashBasis()` 는 `?mode=manual` 이나 sessionStorage 가 manual 일 때만 수기입력, 관리자 `DASH_BASIS` 기본 'ledger'(localStorage `dash_basis` 로 바꾼 사람은 그대로). 테스트 `ptest/dashmode.mjs` D1~D3.
- **관리자 [상담 대시보드] (mvp_158 · v117 · 2026-09-17)** — "문의 처리현황도 대시보드처럼". crm 그룹 메뉴 `cdash`(`core.menu_item` sort 15, 문의 관리 다음). 화면 `#v-cdash`·`loadCdash`: 상단 기간 바(P) 그대로, 범위 세그(매장/매장 외/전체 · `localStorage dc_cd_scope`), 묶음(자동=45일 이하 일별·800일 이하 월별·그 위 연별 / 일 / 월), 상담사, 삭제 포함.
  KPI 6장(문의·구매(성공률)·구매 금액(건당)·진행 중(연락 전·상담중·보류)·완료(비구매)·거절) → 그래프 6개(`cdBars` 기간 막대: 연한 문의 위 진한 구매 + 초록 금액 / `cdHBars` 채널·관심 제품·구매 제품(금액순)·담당자·유입경로) → 채널×기간 표(문의 / 구매).
  **제품·금액은 `core.f_consult_stats` 에 넣었다** — `interests`(관심 카테고리, 쉼표 여러 개는 쪼개고 괄호 설명 제거) · `purchases`(구매 제품명 = 연결 주문 품목명 → purchase_item → 관심 모델 → 카테고리 → '(제품 미기록)', 금액 = 연결 주문 같은 주문번호 합계 → 예상 금액) · `total/periods/channels/handlers` 에 `amount`. 시그니처 그대로라 담당자 화면 상담 현황도 같은 함수를 쓴다.
  '(제품 미기록)' 이 많으면(7~9월 49건 중 18건 7,854만) 구매완료를 [구매 확정] 없이 상태만 바꾼 것 — 판매 입력과 연결돼야 제품·금액이 찍힌다. 테스트 `ptest/cdash.mjs` C1~C5 (가짜 fn_consult_stats · 화면 `reveal('app')` 뒤 스크린샷).
- **유입경로에 카카오채널 (mvp_171 · 2026-09-21)** — `core.inq_route 'kakao_ch'`(channel_code null · sort 190) → 상담 입력 유입경로 [공통] 묶음에 카카오채널·지인소개·기타. 목록은 `fn_inq_codes`(DB) 에서 오므로 화면 배포 없이 바로 보인다(새로고침). 유입경로를 더 넣을 때도 이 표에 한 줄.
- **캠페인 코드 칸이 크롬 저장 비밀번호 목록에 덮이던 것 (v135 · 2026-09-21)** — "캠페인 코드가 이상해". `#upCamp`(CRM 발송 고객 업로드)·`#crmReason`(발송 대상 추출)이 `list=` datalist 만 있고 autocomplete 가 없어 크롬이 로그인 칸으로 보고 DB 계정들을 띄웠다.
  `autocomplete="off" autocapitalize="off" spellcheck="false" name="dc_campaign_*"` 로 막고, 자리표시 문구를 `2609_toner`(값처럼 보였다) → "예: 2609_chuseok — 오른쪽 ▾ 에서 고르기" 로. 코드 목록은 datalist ▾ 그대로.
- **고도몰 과거 주문(2021~2025.07) 적재 자리 (v134 · mvp_170 · 2026-09-21)** — 요청서 "윈도우 수집기(GodomallCollector.exe)가 받아 오는데 받을 자리가 없다". **9/4~9/7 에 올린 P·S·AT·시흥몰 파일은 회원 명부(member_list)** 였고 자사몰 주문은 샵링커 2025-06-20 이후분만 있다(고도몰 회원 20,158 중 주문이 붙은 사람 982).
  `raw.godo_order_hist`(row_hash pk · mall · order_no · ordered_at · data jsonb 원본 · source excel|api · source_file · upload_id, RLS on·정책 없음) — **원장·고객에는 안 쓴다**(⑥ 판단 대기: 채널 매핑·2026 샵링커와의 경계·휴대폰 단독 키 합치기).
  두 입구: ① **`fn_godo_order_hist_upsert(p_mall,p_file,p_rows)`** = exe 용(P몰·AT몰·S몰, `dbuploader` 로그인, f_role admin|uploader). 이름·인자·응답 `{rows,new,dup}` 은 exe 와의 약속 — 바꾸지 말 것. 계정은 `dbuploader` 뿐(`uploader` 없음).
  ② **`fn_godo_order_hist_ingest(p_key,…)`** = 시흥몰 OpenAPI 용, `core.api_key 'godo_order_hist'`(값은 `_secrets.local.md`·GitHub Secrets `GODO_INGEST_KEY`). `tools/godo/collect.mjs`(29일 조각 · 커서 페이징 · 주문×상품줄 평탄화, 콜랩 스크립트와 같은 열 이름 · 해시 `sha1(몰|주문번호|상품번호|줄번호)`) + `.github/workflows/godo-orders.yml`(workflow_dispatch from/to/mall/dry, Secrets `GODO_PARTNER_KEY`·`GODO_KEY`). 컨테이너는 openhub 로 못 나가 `--selftest`(가짜 XML 파싱·해시)만 돌렸다 — 실제 호출은 Actions 에서.
  둘 다 `core.f_godo_order_hist_put` 이 본체: 호출마다 `raw.upload(source 'godo_order_hist')` 한 줄, `on conflict do nothing`. 롤백 확인: dbuploader new 2 → dup 2 · 잘못된 몰 오류 · anon/user 42501 · 키 맞음/틀림.
  **업로드 화면 오인식 방지(④)** — 주문통합리스트도 '주문번호·주문일시' 라 미입금으로 잡혀 `fn_unpaid_upsert` 가 미입금 목록을 통째로 내릴 수 있었다. `unpaidGuard(UP)`: 입금대기가 아닌 상태(배송완료 등)가 섞이면 빨간 안내 + [적재] 잠금 + runUpload 도 거부. 테스트 `sendlog.mjs` U1b·U1c (43/43).
  exe 쪽에 줄 확정본: `tools/godo/GodomallCollector_spec.md`(3몰만 · dbuploader · 규격 그대로 · 하지 말 것).
- **개발 계정이 맡은 건은 삭제·테스트로 가 안 되던 것 (v133 · mvp_169 · 2026-09-21)** — 구독 폼으로 넣은 "지용현" 건(#440)이 이수혁 → 지용현으로 넘어오며 트리거가 테스트 숨김을 붙였고, 목록엔 보이는데 [삭제]·[테스트로]·상태 버튼이 전부 400 '상담을 찾을 수 없습니다'.
  `fn_store_consult_update` 가 `hidden_at is null` 만 찾았기 때문 — 이제 `hidden_reason like '테스트%' and core.f_staff_is_dev(v_me)` 도 통과(목록과 같은 규칙). 같이 잡은 것: `fn_store_handler_load`(우선 순위 표)가 `role_note` 로만 점장을 판정해 개발 계정에 403 → `core.f_staff_is_mgr`.
  **구독 폼에 이름 `test`·`테스트`를 넣으면 `fn_submit_inquiry` 가 저장 없이 `skipped:'test'`** — 잔디도 안 간다. 폼→카드까지 보려면 테스트 글자 없는 이름으로 넣고 나중에 [테스트로].
- **배정·담당 변경도 잔디 카드 · 상담 카드마다 번호 (v132 · mvp_168 · 2026-09-21)** — "배정이나 넘기기 하면 잔디로 알림 · 이미 온 문의를 넘길 때 앞의 것과 헷갈리지 않게 번호를".
  카드 4종이 머리말·색으로 갈린다: 🌐 홈페이지 문의 #id(초록) · 📋 구독 문의 #id(청록) = 새로 들어온 문의 / 📨 수동 접수 #id · 채널 → 담당(청록) = 담당자가 직접 만든 건 / **📌 배정 #id · 미배정 → 담당** · **🔁 담당 변경 #id · 이전 담당 → 새 담당**(황토 #8A5D00, 규칙 `consult_assign`) = 이미 있던 건을 옮긴 것.
  번호는 `crm.consult.id`(`#392`). `fn_inquiry_mail_ingest`·`fn_submit_inquiry`·`fn_store_consult_handoff` 가 `id` 변수를 넣고, `fn_store_consult_assign`(배정 탭 [배정]/[담당 바꾸기] · 내 상담 [넘기기]) 이 건마다 `consult.assign` 카드를 보낸다 — 담당 줄 "이전 → 새 담당 · 바꾼 사람 · 사유", 문의 줄 "채널 · 처음 접수 MM-DD HH:MI · 상태(연락 전/상담중…)", 상담 정보(관심 품목·상세·모델·내용).
  **6건 넘게 한 번에 옮기면 요약 카드 한 장**(no='N건', 상담 정보에 줄마다 '#id 이름 · 채널 · 이전 담당'). 반환 `notified`, 화면 토스트 '· 잔디 알림 보냄'. **2026-09-21 CRM 방(jandi_crm)으로 전환 완료** — `consult_assign`·`consult_handoff` 모두. `jandi_test` 채널은 꺼 뒀다(필요하면 enabled=true 로).
  **execute_sql 한 호출 = 한 트랜잭션** — 함수 패치 do 블록과 롤백 테스트를 같은 호출에 넣었더니 패치까지 롤백됐다. 나눠서 보낼 것. loop alias `c` 가 record 변수 `c` 와 충돌(55000)해 `k` 로 바꿨다.
- **문의 접수·넘기기 → 잔디 카드에 채널·담당자 (v130 · mvp_167 · 2026-09-21)** — "여기서 문의 만들어 담당자 배정하면 JANDI 에 어떤 채널에서 어떤 담당자에게 배정되었는지 알림".
  `fn_store_consult_handoff` 가 이제 **본인 배정도** `core.f_notify('consult.handoff')` 를 부른다(전엔 넘길 때만). 변수 `channel`(inq_channel 라벨 · 기타 글), `phone`, `self`(' (본인 접수)'), `detail`(이름·번호·관심·내용).
  규칙 `consult_handoff` 본문 "📨 문의 접수 · {channel} → {handler} 프로님 배정 · {name} ({phone})" + 카드 줄 배정 담당자("{handler} 프로님 · 수동입력(생성자:{by})") / 문의 채널 / 상담 정보 / 상담 확인하러가기.
  테스트 방(`core.notify_channel 'jandi_test'`, 웹훅 주소는 DB 에만)에서 확인한 뒤 **2026-09-21 CRM 방(jandi_crm)으로 전환**. 테스트 채널은 꺼 둠.
  **문의 접수 카드에도 관심 품목 (v131)** — "이 페이지도 관심품목을 상세히 넣을 수 있도록". `#hoCard` 의 '관심 제품' 한 칸 → 상담 기록과 같은 세 칸: 관심 품목 칩 `#ho_cat`(`CATS` 11개, `hoRenderCat`, '알 수 없음' 단독·'기타' → `#ho_cat_etc` 글로 저장) · 상세 `#ho_detail` · 관심 모델 `#ho_model`+`#ho_models` 칩(`hoModelAdd/Flush`, Enter·쉼표).
  필수는 아니다 — 비우면 서버가 '알 수 없음'. `hoSubmit` 이 `interest_category`·`interest_model_code` 를 실어 보내고 접수 뒤 `hoClearInterest()`. 잔디 카드 '상담 정보' 에 모델도 붙는다. 테스트 `ptest/grid.mjs` H6·H6b·H7·H7b, UAT 4조합·tour 폰 13탭 ✓.
- **센드온 결과 파일 = 성공은 발송 이력 · 실패는 발송 불가 목록 (v129 · mvp_166 · 2026-09-21)** — "발송 목록은 한번에 넣어서 성공 실패는 분류하고 실패는 다음에도 못낼꺼니까 … 제외되게".
  파일을 통째로 [CRM 발송 고객] 에 올리면 '상태' 열로 서버가 나눈다. **실패(`status='failed'`)는 사유와 무관하게 `fn_crm_targets_v2` 가 항상 뺀다**(전엔 번호 오류·미지원 단말 같은 사유만 항상 제외, 나머지 실패는 [이미 보낸 사람 제외] 옵션에만 걸렸다).
  `fn_send_log_import` 응답에 `sent`·`failed`, 화면 결과 '발송 성공 (발송 이력) N · 발송 실패 (발송 불가 목록) N', 붙여넣기 안내도 성공/실패를 갈라 보여준다. 요약 줄 "발송 실패 이력이 있어 제외 N명 (발송 불가 목록)".
  **9/18 한가위 LMS 전체 결과(3,731줄 · 실패 377)는 아직 안 올라왔다** — `crm.send_log` 2609_chuseok 은 실패 6건뿐. 올리면 6건은 '이미 올린 건' 으로 건너뛴다.
- **저장 조건은 칩 줄이 아니라 목록 (v129 · mvp_166)** — "발송조건 명 계속 늘어날 텐데 이렇게는 보기 어려울 것 같아". `#segChips` 를 걷어내고 [저장 조건 N ▾](`segToggle`) → `#segPanel`: 검색 칸(`segQ`, 이름·설명·제품·코드) + 묶음
  **고정(★)** / **최근 사용**(마지막 5개, `last_used_at`) / **반복 조건**(오늘 기준으로 뽑히는 것) / **캠페인 조건**(asof·from·to 가 고정이거나 이름이 `[` 로 시작 → `segKind`) / **보관함**(체크, active=false, [복구]).
  줄 = 이름 + 기준 태그(`SEG_BASIS_NM` 수신동의·재구매 주기·제품 재구매, 제품·기준일 포함) + 설명 + '마지막 M/D · N회' + [★][수정][보관]. 누르면 `applySegment` 가 `fn_crm_segment_touch` 로 쓴 기록을 남기고 목록을 닫는다.
  `crm.segment` 에 `pinned`·`last_used_at`·`use_count`. `fn_crm_segments` 는 보관까지 전부 주고(active 로 구분) `fn_crm_segment_update(p_code,p_data{label,note,pinned,active,delete})` 는 관리자만(내장 조건은 delete 해도 보관). 조건 자체를 바꾸는 건 그대로 "같은 이름으로 저장"(덮어씀).
  폰(≤720px)은 줄이 두 층으로 접히고 버튼 40px. 테스트 `ptest/segpick.mjs` G1~G11 × PC·폰 = 24, `sendlog.mjs` S15·S16 (41/41), `ovf_admin.mjs` 전부 ✓.
- **온라인 채널 일매출은 구글 시트에서 자동으로 (v128 · mvp_165 · 2026-09-21)** — "여기는 시트에서 가져와야지". 원본 = 「삼성앤텍_상품/주문관리 파일」(gid 1654024467) 의 **`온라인 매출_YYYY년` 탭**: 월별 블록(`N월` 줄에 날짜가 3칸마다 · 아래 줄 매출/환불/합계 · 채널 줄 P몰…한퓨어 · 매장 줄 3개 · 전체).
  `_raw` 탭(날짜·채널·매출·환불 세로 표)은 8/17 까지만 있는 파생물이라 안 쓴다. Drive MCP 로 xlsx 를 받아(`download_file_content` → base64 → openpyxl) 9월 1~17일 147줄을 `fn_channel_daily_upsert` 로 넣었다(1~8월은 시트 합계와 DB 가 원 단위까지 같아 그대로). 9월 매출 5.65억 · 환불 1.25억.
  자동화: `core.api_key 'channel_daily'`(값은 `_secrets.local.md` 에 적을 것 — 세션에서 한 번 보여줌) + **`fn_channel_daily_ingest(p_key, p_rows, p_file)`**(anon 허용, 키 검사, source `sheet_gas`, **값이 같으면 updated_at 도 안 건드린다**) + **`tools/gas/channel_daily_sync.gs`**(시트에 바인딩, 매시간 최근 45일을 다시 보냄 · `setupTrigger()` 1회). 설치 전까지는 붙여넣기.
  매장 줄(시흥점-매장매출·구독매출·프로-직판)은 안 보낸다 — 매장은 담당자 화면 일 마감이 원본.
  **CRM 발송 고객 업로드 안내문 정정** — "실패는 제외 대상에서 빠집니다" 라고 옛 문구가 남아 있었다(mvp_161 뒤 실제 동작은 반대). 이제 "실패도 보낸 사람으로 기록 · 번호 오류·미지원 단말·수신거부·결번은 항상 제외" 로. 미리보기 ERROR 열은 실패 줄에만 비고를 보인다.
- **업로드 전용 계정 `dbuploader` (v127 · mvp_164 · 2026-09-21)** — `public.profiles.role` 에 **`uploader`** 추가(check 제약). 허용 = 데이터 가져오기 적재 함수 13개(`fn_orders/consults/customers_bulk_upsert` · `fn_sl_refund_apply` · `fn_ec_customers_upsert` · `fn_channel_daily/settlement/listing_request/inv_items_upsert` · `fn_send_log_import` · `fn_unpaid_upsert` · `fn_sub_plan_upsert` · 캠페인 목록 `fn_utm_campaigns`) — 각 함수의 `f_role()` 검사 줄만 `pg_get_functiondef` 치환.
  **되돌리기(`fn_upload_rollback`)·설정·주문·CRM 추출은 그대로 admin 만.** 메뉴는 `core.menu_access` 에 home·upload 빼고 전부 숨김(20/22). 계정은 `auth.users`+`auth.identities` 에 SQL 로 직접 만들었다(`extensions.crypt(bf)`, 이메일 `dbuploader@samsungat.local`, 로그인 아이디 `dbuploader`, 비밀번호는 사용자 지정 — 이 문서엔 안 적는다). 관리자 계정·권한 카드 select 에 `uploader` 추가.
  **9월 샵링커 환불은 API 에 없다** — `core.sl_log` 취소/교환/반품(8/22~9/21) fetched 0. 웹 주문목록을 올리기 전엔 그대로 둔다.
- **문의 관리의 별도 [홈페이지 문의] 카드를 없앴다 (v126 · 2026-09-21)** — "홈페이지 문의는 별도 관리할 이유가 없는데?". 홈페이지 문의는 지메일 자동 적재로 `crm.consult`(channel homepage) 에 들어와 문의 관리 [홈페이지](옛 [견적], `fn_inquiry_list` 폼 라벨 '견적 문의'→'홈페이지 문의') 칩으로 보이므로
  `crm.web_inquiry` 목록 카드(`#wiCard`·붙여넣기 모달·`loadWebInq`·`fn_web_inquiries` 호출)는 걷어냈다. 데이터 소스 `web_inquiry` 카드는 자동 적재 감시용으로 남기되 올리기·붙여넣기 버튼은 없다(`SRC_KIND` 에서 제외, 붙여넣기 종류·감지 제거).
  `crm.web_inquiry` 표와 `fn_inquiry_mail_ingest` 의 `f_web_inq_upsert` 거울 쓰기는 그대로(해 없음). 그 카드의 '번호' 칸에 해시가 겹쳐 보이던 것도 같이 사라졌다.
  **9월 환불이 0 인 것은 파일이 아직 안 올라와서다** — `raw.upload(shoplinker_refund)` 0건. API 999 는 9월 주문 취소를 하나도 안 줬다(60일 21건 전부 8월 주문). 샵링커 웹 주문목록(취소/반품 상태 포함)을 [샵링커 주문]→[취소·환불만 대조] 로 올려야 대시보드에 환불이 생긴다.
- **데이터 상태 카드가 자동 적재 원천을 제대로 센다 · CRM 발송 고객 · 샵링커 취소·환불 대조 (mvp_163 · v125 · 2026-09-21)** — 사용자 지적 5건.
  ① **홈페이지 문의는 고도몰 견적 게시판이 아니라 별도 서비스** — 문의 메일 → `gmail_inquiry.gs`(1분) → `fn_inquiry_mail_ingest` → `crm.consult(source='gmail_homepage', channel_code='homepage')` 로 이미 자동 적재되고 잔디 「웹 문의 수신」 카드가 그것. 데이터 소스 라벨 '홈페이지 문의 (자동 적재)', `f_source_last('web_inquiry')` 는 gmail_homepage 도 본다. 붙여넣기(`crm.web_inquiry`)는 예비.
  ② **구독·소모품·VMS/B2B 문의 카드가 '없음'이던 이유** — `fn_data_status` 의 stat CTE 에 이 원천들이 아예 없어 행 0 이었다(감시용 `f_source_last` 만 있었음). 이제 `crm.consult` 의 source 로 행·기간·**최근 30일(`n30`)** 을 센다. 라벨은 전부 '(자동 적재)'. `web_supply`·`web_b2b` 는 드문 폼이라 expect_days 30.
  ③ **'이미 보낸 고객' → 'CRM 발송 고객 (발송 이력)'** — 카드 `detail` 에 발송완료·실패 합계, 캠페인별(코드·이름·마지막 발송일·발송·실패), 실패 사유 분포. 화면 `dsDetail(x)`. 9/18 한가위 LMS 실패 6건(MMS 미지원·번호 에러·일시정지·착신가입자 없음·이통사 기타·expired)을 `2609_chuseok` 으로 적재했다(6/6 매칭). **성공분은 아직 안 올렸다** — 센드온 전체 결과 파일을 [CRM 발송 고객] 로 올려야 다음 추출에서 빠진다.
  ④ **샵링커 취소·환불은 주문번호 대조 (`fn_sl_refund_apply(p_rows, p_file)`)** — 샵링커 웹 주문목록(취소/반품 상태)을 올리면 `order_no`(몰 주문번호) 또는 `alt_order_no`(자사주문번호 = `source_ref`)로 원장을 찾아 **취소·반품 완료 줄만** `refund_amount=gross_amount`·status·cancelled_at 으로. 새 줄은 절대 안 만든다. 주문에 줄이 여럿이고 파일이 모델·상품명을 주면 그 줄만. '요청' 상태는 status 글자만. 반영이 있으면 `core.dash_cache` 를 비워 대시보드에 바로 보인다. 기록은 `raw.upload(source='shoplinker_refund')`.
  화면: 샵링커 파일을 올리면 [취소·환불만 대조] 체크(기본 ON, `localStorage dc_sl_refund_only`) · 끄면 옛 전체 적재(`fn_orders_bulk_upsert`, 주문번호+줄 순번 키라 API 로 들어온 여러 줄 주문과 순번이 어긋나면 중복 줄 위험 → API 이전 기간에만). 데이터 상태 샵링커 카드에 '최근 30일 취소·환불 N줄 · 원 · 마지막 대조' + [취소·환불 대조] 버튼. 롤백 테스트: 배송전취소·없는 번호·반품요청(2줄)·자사주문번호 → found 2 · updated 1 · status_only 2 · notfound 1. 테스트 `ptest/slrefund.mjs` R1~R7.
  ⑤ **경과일 = 자료 마지막 날과 마지막 적재 중 가까운 쪽** — 샵링커가 주말마다 '지연' 으로 뜨던 것(금요일 주문이 마지막). `alert=false` 원천(미입금·거래처)은 늦어도 '정상'.
  **테이블·카드 글자 넘침 점검 (`ptest/ovf_admin.mjs`)** — 관리자 22개 화면을 1280·390px 에서 돌며 카드 밖으로 나간 요소 · 글자 넘침 · **한 단어가 세로로 쪼개짐('경/과')** · overflow hidden 에 잘린 글자 · **nowrap 인데 360px 넘는 표 칸** · 문서 가로 넘침을 센다(가짜 RPC 에 긴 주소·상품명·캠페인명을 넣어 본다). 고친 것: 데이터 소스 카드 `.nums` 가 '경과'·'30일' 을 세로로 쪼개던 것(칸 nowrap + flex-wrap) · `.cols` 34px 에서 뚝 잘리던 것(line-clamp 2 + title) · 버튼 4개 줄바꿈 · UTM 링크 줄의 긴 주소가 td nowrap 을 물려받아 표를 늘리던 것 ·
  **모든 표 공통 `autoWrap()`** — td 는 기본 nowrap 이라 주소·상품명이 표를 옆으로 늘리고 다른 칸이 세로로 길어졌다. MutationObserver 로 표가 그려질 때마다 26자 넘고 띄어쓰기·구분점이 있는 칸에 `.wrap`(max-width 320px) 을 붙인다(숫자·mono·버튼 칸 제외).
  **주문 목록 → 데이터 가져오기 → 주문 목록 이 깨지던 버그** — 공통 바가 없는 화면으로 갈 때 `placeCbar` 가 기간 바(`#periodBar`)를 공통 바 안에 든 채로 지워(`el.remove()`) 다음 목록 화면에서 `$('periodBar')` 가 null → 화면이 안 그려졌다. 기간 바를 원래 자리(`PB_HOME`)로 돌려놓고 지운다. 점검 스크립트가 처음 잡았다.
- **수집 미도착 알림 5건 정리 · 샵링커 API 한계 확인 (mvp_162 · 2026-09-21)** — 09-21 09:10 잔디 알림에 사용자 메모("정상 수집중으로 보임 / 환불없음 / 시트에서 가져오는 것 / 필수 아님 / API 로 적재").
  ① **샵링커 '2.6일째'는 헛알림** — 수집기는 하루 5번 정상(Actions 성공, `core.sl_log` DONE · fetched 86~168). 원인은 주말: 샵링커 API 는 **002(발주확인 대상)·003(송장전송완료)·015(송장등록)·999(취소/교환/반품) 넷만 받고**('신규주문' 코드 없음 — `--flags` 탐색으로 001·004~014·016~020 전부 거부 확인), 주말 주문은 샵링커가 월요일 아침에야 몰에서 가져와 그 전엔 어느 코드로도 안 보인다. 금요일 17:43 이 마지막 → 월요일 09:10 마다 헛알림.
  → `core.f_source_last('shoplinker')` = greatest(마지막 주문 적재, **마지막 성공 수집(sl_log DONE·fetched>0)**). 자동 수집은 '수집기가 돌고 샵링커가 응답했는가' 로 본다. 기준 2일 그대로.
  ② **취소·환불이 9월에 0인 이유 = API 한계** — 999 는 취소완료(013)·반품완료(008)만 준다. 60일(7/23~9/21) 주문 5,500건 중 **22건**. 배송전취소·주문취소요청·반품요청 같은 중간 상태는 API 에 없다(옛 원장 시트 = 샵링커 웹 내려받기엔 월 100~265건). 9월 주문 취소 0건은 못 잡은 것이지 없는 게 아니다.
  할 수 있는 것: 999 창을 30→90일(취소완료가 몇 주 뒤 찍힘). **못 하는 것: 배송전취소는 샵링커 웹 주문목록(취소/반품 상태) 내려받기를 올려야만 들어온다** — 옛 시트 방식. 대시보드 '환불 미기록' 경고는 그래서 맞는 말이다.
  `tools/shoplinker/collect.mjs --flags [--codes 002,999 --dtypes 001,002,005 --days 60]` (workflow_dispatch `flags`+`probe_args`) 가 코드별 건수·order_flag 분포·상태성 필드를 찍는다(적재 안 함). **컨테이너에선 샵링커로 못 나가므로 이렇게 Actions 로 돌려 로그를 읽는다.**
  ③ 이카운트 주문서 현황: 원천 = 데이터센터가 API 로 보낸 전표 → `f_source_last('ec_slip')` 에 `ec.order_queue sent_at` 포함(9/17 전송 → 정상). ④ 미입금 주문: `alert=false`(필수 아님·주 1회). ⑤ 온라인 채널 일매출: how 에 원천 시트 주소(온라인=시트, 매장=일 마감). 자동화하려면 GAS 한 장(시트 → `fn_channel_daily_upsert`). ⑥ 소모품·렌탈 문의 12.7일은 GAS 살아 있음 — 손 안 댐.
- **발송 실패 건은 다음에도 안 보낸다 (mvp_161 · v123 · 2026-09-21)** — 9/18 한가위 LMS 결과에 '실패 · MMS를 미 지원 단말' · '실패 · 발/착신 번호 에러' 가 있었다. "실패목록도 다음에 보낼 필요는 없을 것 같은데".
  전엔 `last_sent` 가 `status <> 'failed'` 만 세서 실패한 사람이 다음 추출에 다시 들어왔다(고객이 못 받았으니 다시 보내자는 생각이었음). 이제 ① **실패도 보낸 것으로 센다**([이미 보낸 사람 제외] 가 실패 건도 뺌)
  ② `fn_send_log_import` 가 센드온 **'비고'(실패 사유)를 `error_msg` 에 저장**(화면 `mapRows` send_log 가 `error` 키로 보냄, 실패 건만) ③ **번호 오류·미지원 단말·수신거부·결번·착신 사유는 옵션과 무관하게 항상 제외** → `summary.blocked_bad`, 요약 줄 "발송 불가(번호 오류·미지원 단말) 제외 N명".
  8/14 이력의 실패 1건은 비고 없이 올라와 error_msg 가 비어 있다(항상 제외엔 안 걸리고 '보낸 사람' 으로만 빠짐). **MCP 로는 `fn_send_log_import`·`fn_crm_targets_v2` 를 못 부른다(f_role=anon)** — `set_config('request.jwt.claims', {role:authenticated, sub:관리자 uuid})` + `set_config('role','authenticated')` 를 트랜잭션 안에서 걸면 부를 수 있다(롤백 블록으로 검증). 테스트 `ptest/sendlog.mjs` 39/39 그대로.
- **대시보드 발표용 4건 (mvp_160 · v122 · 2026-09-19)** — "각 몰 담당자가 발표할 건데 더 필요한 정보?" → 1·4·5·6 을 먼저.
  ① **전년 동기 비교** — 기간 칸 아래 [비교] 세그 `#cmpmode` (전기(자동) / 전년 동기, `sessionStorage dash_cmp`). `cmpRange()` 가 `yoy` 면 같은 날짜를 1년 전으로(`shiftYear`, 2/29 는 말일), 자료 없으면 '비교 기간 없음'.
  그래서 **`DC_MONTHS` 12 → 24** (payload 656KB → 1.07MB) — `f_dash_warm` 에 24개월 키를 넣어 15분마다 굽는다(빌드 5~12초 · anon 3초라 캐시 필수). 월 칩은 최근 13개월만. 비교 기간에 자료 있는 날이 당기의 절반 미만이면 "수집 공백 주의"(2025-10~12 샵링커가 거의 비어 있다: 206·50·17건).
  ② **채널 화면 [증감 원인 · 상품]** — 워터폴을 `wfSteps(prodMode)`(데이터)·`wfSvg`(그림)·`wfBind` 로 나눠 개요 `#wf` 와 채널 `#cvwf` 가 같이 쓴다. 채널 화면은 `focus` 가 걸려 있어 `prodSum` 이 그 채널만 센다.
  ③ **채널 화면 [카테고리 구성]** — `prodAgg(useFilters, ci)` 에 채널 인자. `drawCvCat(ci)` 가 카테고리 막대 + 줄 클릭 시 그 채널 안 상위 상품 10종(`CV_CAT_OPEN`, `catSubHtml` 재사용).
  ④ **신규 vs 재구매** — `f_dash_payload` 에 `ccells` [일, 채널, 구매 고객(고객×구매일), 그중 첫 구매]. 신규 = buyer_key 의 첫 구매일(전 채널·전 기간, 취소·환불 제외)이 그날. `agg()` 가 `b`·`nb` 를 더해 채널 KPI '구매 고객 N명·일'·'재구매 N명 · %'. **오픈마켓(group='오픈마켓')은 '식별 불가 (안심번호)'** — 쿠팡은 주문마다 번호가 달라 전부 신규로 보인다.
  최근 90일 샵링커는 buyer_key 가 다 있다(옛 2025년 자료만 64% null). 테스트 `ptest/dashpres.mjs` P1~P9 × PC·폰 = 18 (2025-08~2026-09 가짜 payload 로 전년 동기·채널 KPI·카테고리·워터폴 값을 맞춘다). 기존 dashcat 16·dashqty 3·dashmode 3 그대로.
- **대시보드 `/dash/` 카테고리 줄 펼침 · 상품 목록 정렬 (v121 · 2026-09-18)** — 대표님 요청 2건. ① 개요 [상위 상품 | 카테고리] 카드에서 **카테고리 줄을 누르면 바로 아래에 그 카테고리 상위 상품 10종**(`catSubHtml`, `.rk-sub`, 줄마다 금액·N개·카테고리 내 비중, 11종 이상이면 "외 N종") — 상세로 안 들어가고 개요에서 본다. 펼친 상품을 누르면 상품 서랍. 펼친 카테고리는 `CAT_OPEN`(Set)에 남아 기간을 바꿔도 유지.
  ② 상세 [상품 목록] 카드에 **[금액순][수량순] 탭(`#psort`) + 머리글 수량·금액 클릭**(`th.sortable`, 켜진 쪽 "▼"). `pSort`('n'|'q', `sessionStorage dash_psort`), 동률은 다른 쪽 값으로. 기본은 금액순 그대로. 테스트 `ptest/dashcat.mjs` K1~K8 × PC·폰 = 16.
- **상담 대시보드에 기간 UI (v120 · 2026-09-18)** — "여기도 날짜 검색 UI 넣어줘야지". `loadCdash` 는 처음부터 `P.from`·`P.to` 를 썼는데 `PERIOD_VIEWS` 에 `cdash` 가 빠져 있어 **기간 바가 안 보였다** (안내문은 '위 기간 바의 기간을 그대로 따르고' 라 적혀 있었는데 정작 바가 없었다).
  `PERIOD_VIEWS` 에 `cdash` 추가 → `placePeriodBar` 의 일반 경로(`#v-cdash .card` 맨 앞에 끼움)가 처음으로 쓰인다. 다른 기간 화면은 전부 `CB_VIEWS` 라 공통 바 안으로 들어갔었다.
  **상담은 월 단위로 보므로 빠른 버튼 [3개월]·[6개월]·[12개월](`#cd_span`)** 을 필터 줄 맨 앞에 넣고 `setPreset('m3'|'m6'|'m12')`(= 그 달 1일부터 오늘까지, `PRESET_NM` m3/m6/m12)로 연결했다. 공용 프리셋은 90일·올해가 최대였다.
  `loadCdash` 가 `PRESET` 으로 빠른 버튼 on 상태를 맞추고, 날짜를 직접 넣고 [적용] 하면 빠른 버튼은 꺼진다. 테스트 `ptest/cdash.mjs` C6~C8 · `ptest/cdnav.mjs` N1~N5(화면을 오가도 기간 바가 제자리 · 통합 원장에서는 공통 바 안으로 · 1100px 넘침 0).
- **상담을 [연락 전]으로 되돌린다 (mvp_159 · v118 · 2026-09-18)** — 이수혁 프로가 안현지 건에 콜백(09-19 14:00)을 잡자 `fn_store_consult_update` 의 callback 이 `진행전`→`진행중` 으로 올려 버렸고, 상태 바의 [연락 전]은 `act:null` 이라 되돌릴 길이 없었다("연락전으로 돌리려면 어떻게 해").
  ① `p_action='pre'` 추가 — result=`진행전`, **콜백 약속도 지운다**(callback_at·callback_done_at null, notes '연락 전으로 되돌림 (콜백 MM-DD HH:MI 지움) MM-DD HH:MI 이름'). 처음엔 콜백을 남겼는데 "내일 오후 02:00 이 그대로 나와있어" 로 바로 잡혔다 — 연락 전 = 약속도 없는 상태.
  ③ `p_action='callback_clear'` — 콜백 약속만 지운다(상태 그대로). 화면 콜백 창(`ocpick_`)에 콜백이 있을 때만 [콜백 지우기](`ocClear`, confirm, `.mini.warn`). 홈 콜백 약속 줄의 [완료](`fn_store_callback`)는 callback_done_at 만 찍고 약속은 남긴다 — 지우는 건 이 버튼뿐. ② callback 의 승격 case 에서 `진행전` 을 뺐다 — **연락 전에 콜백만 잡으면 연락 전 그대로**(종료·거절→진행중은 유지).
  화면 `STATE_STEPS[진행전].act='pre'`(버튼 켜짐, `msg` 로 토스트 문구), 힌트에 되돌리기 안내. 안내서 상태 줄·상태 표에도 한 줄. id 390(안현지)은 손으로 진행전으로 돌렸다. 확인은 `ptest/pre_probe.mjs`(데스크톱·폰, 버튼 활성·p_action pre·40px) · `ptest/cb_probe.mjs`(콜백 있는 줄에만 [콜백 지우기]·callback_clear·40px) + UAT 4조합.
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
4. GitHub Secrets `GA_PROPERTY_ID` · `GA_SA_JSON` · `GA_INGEST_KEY` — 없으면 GA4 수집이 건너뛴다. **2026-09-17 확인: 셋 다 비어 있어 `ga-traffic.yml` 이 매일 12:10 '건너뜁니다' 로 0초에 끝난다(성공으로 보임).** 값을 넣으면 다음 날부터 `core.web_traffic` 이 찬다. `GA_INGEST_KEY` 는 `core.api_key 'ga_traffic'` 의 값(`_secrets.local.md`).

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
