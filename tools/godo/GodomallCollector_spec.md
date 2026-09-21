# GodomallCollector.exe — Datacenter 연동 확정본 (2026-09-21)

> 받는 사람: GodomallCollector.exe 를 만드는 쪽
> 보내는 사람: Datacenter(data_AT) · 지용현
> 요청서(2026-09-21)에 대한 회신. **Datacenter 쪽 자리는 만들어 두었다.** 아래 대로 exe 를 맞추면 된다.

## 1. 바뀐 것 — 먼저 읽을 것

| 항목 | 요청서 | 확정 |
|---|---|---|
| 대상 몰 | 4몰 | **P몰 · AT몰 · S몰 3몰만.** 시흥몰은 OpenAPI 로 Datacenter 가 직접 받는다(GitHub Actions). exe 몰 목록에서 `samsungsh70`(시흥몰)을 빼거나 기본 꺼짐으로 둘 것 |
| 로그인 아이디 | `uploader` | **`dbuploader`** (계정은 이것 하나뿐. `uploader` 는 없다). 이메일 형식은 `dbuploader@samsungat.local` 그대로 |
| RPC | `fn_godo_order_hist_upsert` | 그대로. 이름·인자·응답 키 안 바꿨다 |
| 해시 | `sha1(몰이름 + 행 JSON(키 정렬))` | 그대로. 시흥몰(API) 쪽은 다른 규칙을 쓰지만 몰이 달라 겹치지 않는다 |

## 2. 호출 규격 (요청서 그대로 · 확정)

```
POST {SUPABASE_URL}/rest/v1/rpc/fn_godo_order_hist_upsert
apikey: sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW
Authorization: Bearer <dbuploader 로그인으로 받은 access_token>
Content-Type: application/json

{ "p_mall": "P몰",            // 'P몰' | 'S몰' | 'AT몰' (시흥몰도 값은 받지만 exe 는 안 보낸다)
  "p_file": "P몰_samsungdmfp_20210101_20210430_101530_1.xlsx",
  "p_rows": [ { "h": "<sha1 40자>", "order_no": "…", "ordered_at": "2025-08-31 18:23" | null, "data": { …원본 행… } } ] }   // ≤ 500

응답 200: { "rows": 500, "new": 498, "dup": 2 }
```

- 로그인: `POST {SUPABASE_URL}/auth/v1/token?grant_type=password` · body `{ "email": "dbuploader@samsungat.local", "password": "<설정값>" }` · 헤더 `apikey`. 응답 `access_token` 을 위 Bearer 로. 토큰은 1시간이라 만료(401)면 다시 로그인.
- `ordered_at` 은 `YYYY-MM-DD` 로 시작하는 문자열만 날짜로 읽는다. 아니면 null 로 들어간다(오류 아님).
- 서버는 `h` 가 빈 행을 건너뛴다. `rows` 는 보낸 개수, `new`+`dup` 은 `h` 가 있는 행 수.
- 오류 응답: `42501 권한이 없습니다`(admin·uploader 가 아닌 계정) · `알 수 없는 몰: …`(p_mall 오타) · `PGRST202 Could not find the function`(배포 안 됨 — 현재는 배포돼 있음).
- 한 호출 8초 제한(authenticated). 500행 40컬럼은 1초 안쪽이다. 느리면 300으로 줄이면 된다.
- 같은 파일·같은 구간을 다시 보내도 `dup` 으로만 잡힌다. 재실행에 안전하다.

## 3. 적재 기록

- 호출마다 `raw.upload(source='godo_order_hist', file_name=p_file, note='P몰 · excel · 새 N · 중복 M')` 한 줄이 남고, 행에는 `upload_id` 가 붙는다. 관리자 화면 데이터 가져오기 › 적재 기록에 보인다.
- 되돌리기는 파일 단위: `delete from raw.godo_order_hist where source_file = '<p_file>'`. exe 가 할 일은 아니다.

## 4. 하지 말 것

- 관리자 화면(admin.html) 업로드로 이 엑셀을 올리지 말 것. 미입금 목록으로 오인식되던 구멍은 막았지만(결제상태가 입금대기가 아닌 행이 섞이면 거부) 그 경로는 쓰지 않는다.
- `core.orders`·`crm.customer` 로 가는 다른 RPC(`fn_orders_bulk_upsert` 등)를 부르지 말 것. 원장 변환은 검수 뒤 Datacenter 가 한다.
- RPC 이름·인자·응답 키를 바꾸지 말 것. 바꾸려면 먼저 말해 줄 것.

## 5. 확인 방법 (exe 쪽에서)

1. 첫 배치 응답이 `{"rows":N,"new":N,"dup":0}` 이면 정상. 같은 배치를 한 번 더 보내면 `new:0, dup:N`.
2. 401 이면 토큰 만료 → 재로그인. 403/42501 이면 계정이 uploader 가 아니거나 아이디가 틀림.
3. 적재 현황은 Datacenter 쪽에서 본다:
   `select mall, source, extract(year from ordered_at) y, count(*), count(distinct order_no) from raw.godo_order_hist group by 1,2,3 order by 1,2,3;`
