/***********************************************************************
 * 구독 견적서 GAS → Datacenter 이중 적재 패치
 * ---------------------------------------------------------------------
 * 견적 GAS(code.gs)의 saveQuote 처리부 — 시트 [견적내역] 에 저장하고 no/version 을 정한 뒤 —
 * 응답을 돌려주기 직전에 한 줄만 추가:
 *
 *     dcForwardQuote_(no, version, issuedAt, summary, quote);
 *
 *   no        : 견적번호 (예: SH260904-001)
 *   version   : 발행 버전 (1, 2, …)
 *   issuedAt  : 발행 시각 문자열 (예: "2026.09.04 10:20")
 *   summary   : 페이지가 보낸 body.summary (이름·연락처·상담사·모델·금액 요약)
 *   quote     : 페이지가 보낸 body.quote  (견적 전체 JSON — 재발행/불러오기용 그대로 보관)
 *
 * 실패해도 시트 저장·응답은 영향 없음. 같은 (견적번호, 버전) 은 덮어쓰기라 재실행 안전.
 * 과거 발행분 일괄 적재는 견적 code.gs 를 보고 backfill 함수를 붙여야 함 (시트 컬럼 확인 필요).
 ***********************************************************************/
const DC_URL  = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
const DC_ANON = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';
const DC_KEY  = 'dc_15a3039ac89b4cf5045b62688391e85099ea9a63';

function dcForwardQuote_(no, version, issuedAt, summary, quote) {
  try {
    const res = UrlFetchApp.fetch(DC_URL + 'fn_submit_quote', {
      method: 'post', contentType: 'application/json',
      headers: { apikey: DC_ANON, Authorization: 'Bearer ' + DC_ANON },
      payload: JSON.stringify({ p_key: DC_KEY, p_data: {
        no: String(no || ''), version: Number(version || 1), issuedAt: String(issuedAt || ''),
        summary: summary || {}, quote: quote || null } }),
      muteHttpExceptions: true
    });
    if (res.getResponseCode() !== 200) console.warn('Datacenter quote ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 200));
  } catch (e) { console.warn('Datacenter quote 실패: ' + e); }
}
