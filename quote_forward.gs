/***********************************************************************
 * 구독 견적서 GAS → Datacenter 이중 적재  (시트 [견적내역] 는 그대로 두고 DB 에도 쌓는다)
 * ---------------------------------------------------------------------
 * ※ 이 프로젝트(견적서)에는 form_forward.gs 를 붙이면 안 된다.
 *    견적은 금액·구독료 항목이 따로 있어 전용 경로(fn_submit_quote)를 쓴다.
 *    이미 붙였다면 그 블록을 통째로 지운 뒤 이 파일을 넣을 것.
 *
 * 설치
 *   1) 이 내용을 견적 Code.gs 맨 아래에 붙여넣는다.
 *   2) saveQuote() 안, 마지막 return 바로 앞에 한 줄 추가:
 *
 *          dcForwardQuote_(no, version, nowStr(), sum, quote);
 *
 *      (원문 기준: s.getRange(r, 18, 1, 7).setNumberFormat('#,##0'); 다음 줄)
 *   3) 편집기에서 backfillQuotesToDatacenter 를 한 번 실행 → 기존 견적 전부 적재.
 *   4) [배포] → [배포 관리] → 연필 → 버전 '새 버전' · 액세스 '모든 사용자' → 배포
 *
 * 실패해도 시트 저장·응답에는 영향이 없다. 같은 (견적번호, 버전) 은 덮어쓰기라 재실행 안전.
 ***********************************************************************/
/* var 로 선언 — 다른 Datacenter 스니펫과 같은 프로젝트에 있어도 충돌하지 않는다.
   (const 로 두면 중복 선언이 되어 스크립트 전체가 로드에 실패하고,
    웹앱이 JSON 대신 HTML 오류 페이지를 돌려준다 → "Unexpected token '<'") */
var DC_URL  = typeof DC_URL  !== 'undefined' ? DC_URL  : 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
var DC_ANON = typeof DC_ANON !== 'undefined' ? DC_ANON : 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';
var DC_KEY  = typeof DC_KEY  !== 'undefined' ? DC_KEY  : 'dc_15a3039ac89b4cf5045b62688391e85099ea9a63';

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
    if (res.getResponseCode() !== 200) Logger.log('Datacenter quote ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
  } catch (e) { Logger.log('Datacenter quote 실패: ' + e); }
}

/** 시트 [견적내역] 전체를 Datacenter 로 올린다 (편집기에서 1회 실행) */
function backfillQuotesToDatacenter() {
  var s = sheet(SH_QUOTE, QUOTE_HEAD);
  var rows = rowsOf(s);
  var n = 0;
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i];
    if (!r[1]) continue;                       // 견적번호 없는 행은 건너뜀
    var q = null;
    try { q = JSON.parse(r[27] || 'null'); } catch (e) { q = null; }
    var sum = {
      type: r[3], date: r[4], until: r[5], name: r[6], phone: r[7], birth: r[8], addr: r[9],
      carrier: r[10], wedding: r[11], movein: r[12], proof: r[13], counselor: r[14],
      count: r[15], models: r[16], total: r[17], benefit: r[18], finalP: r[19],
      monthly: r[20], realM: r[21], prepayPct: r[22], prepayAmt: r[23],
      card: r[24], pointMode: r[25], memo: r[26]
    };
    dcForwardQuote_(r[1], r[2], r[0], sum, q);
    n++;
    if (n % 50 === 0) Utilities.sleep(500);    // 과호출 방지
  }
  Logger.log('견적 ' + n + '건 전송 완료');
}
