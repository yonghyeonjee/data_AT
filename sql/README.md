# SQL 마이그레이션

Supabase 프로젝트 `wdahskrcpjooqhwwxjiu` 에 적용된 순서대로.

| 파일 | 내용 |
|---|---|
| mvp_29 / mvp_31 | 기본 스키마 · 업로드 · 대시보드 v2 |
| mvp_35_web_inquiry_quote | 홈페이지 구독문의 · 구독 견적서 적재 (`fn_submit_inquiry`, `fn_submit_quote`, `crm.quote`) |
| mvp_36_online_ops | 온라인 채널 일매출(`core.channel_daily`) · 정산 · 등록요청 |
| mvp_37_dash_payload | 매출 대시보드 v4 payload (`core.f_dash_payload`, `fn_dash_payload`, `fn_dash_payload_pub`) |
| **mvp_38** *(파일 없음)* | 업로드 되돌리기 (`raw.upload_touch`, `fn_upload_rollback`) — Supabase → Database → Migrations 에서 확인 |
| **mvp_39** *(파일 없음)* | 매장 화면 온라인 탭 (`fn_store_channel_day`, `fn_store_channel_save`) — 위와 동일 |
| mvp_40_form_intake | 홈페이지 폼 공용 적재 (`core.form_def`, `fn_submit_form`) |
| mvp_41_ecount_master | 이카운트 기준코드 (`ec.warehouse`, `ec.channel_cust`, `ec.product_alias`) |
| mvp_42_fixes | safeupdate DELETE 오류 수정 + 스마트스토어 채널 매핑 정정 |
| mvp_43_48_query_ui_cache | (요약) 대시보드 GAS 동일화 · payload 캐시 · 조회 UI 요약통계 · KST 기간창 수정 |
| mvp_49_inventory | 재고 스키마 `inv` + 관리자/담당자 RPC |
| mvp_50_home | 시스템 홈 `fn_home` (요약) |

이후 `fn_dash_payload(p_from, p_to, p_mode)` / `fn_dash_payload_pub(p_pw, p_from, p_to, p_mode)` 로
`p_mode = 'manual'`(담당자 수기입력) / `'ledger'`(원장) 집계 기준 토글이 추가되었다.
