/**
 * 채널별 일매출 → 데이터센터 자동 적재 (channel_daily_sync.gs · 2026-09-21)
 *
 * 이 스크립트는 「삼성앤텍_상품/주문관리 파일」 시트(온라인 채널 일매출 원본)에 **바인딩된 Apps Script** 로 넣는다.
 *   시트 › 확장 프로그램 › Apps Script › 이 파일 붙여넣기 → DC_KEY 채우기 → setupTrigger() 한 번 실행 (시간 트리거 1시간)
 *
 * 읽는 탭: '온라인 매출_YYYY년' (올해 · 12월엔 다음 해 탭도). 탭 구조는 월별 블록:
 *   [ , 'N월', 날짜1, , , 날짜2, , , …]      ← 날짜가 3칸마다
 *   [ , '합계', '매출', '환불', '합계', …]
 *   [채널명, 월합계, 매출, 환불, 합계, 매출, 환불, 합계, …]
 *   … '전체' 줄까지
 * 매장 줄(시흥점-매장매출·구독매출·프로-직판)은 보내지 않는다 — 매장은 담당자 화면 일 마감이 원본.
 *
 * 보내는 것: 최근 DAYS_BACK 일 안의 (날짜, 채널, 매출, 환불). 값이 없는 칸은 건너뛴다.
 * 데이터센터 fn_channel_daily_ingest 는 같은 값이면 건드리지 않고, 바뀐 값만 덮어쓴다(마지막 적재 시각 = 실제 변경).
 * 키는 core.api_key 'channel_daily' 의 값 — 여기 말고 어디에도 적지 말 것 (이 파일은 공개 저장소에 있음).
 */
var DC_URL   = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
var DC_ANON  = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';
var DC_KEY   = 'PASTE_DC_KEY_HERE';     // core.api_key 'channel_daily'
var DAYS_BACK = 45;                      // 지난 45일만 매번 다시 보낸다 (수정분 반영)
var SKIP_ROWS = /^(전체|시흥점-|.*프로-직판)/;

function syncChannelDaily() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var today = new Date(), since = new Date(today.getTime() - DAYS_BACK * 86400000);
  var years = [today.getFullYear()];
  if (today.getMonth() === 0) years.push(today.getFullYear() - 1);      // 1월엔 지난해 탭도
  var rows = [];
  years.forEach(function (y) {
    var sh = ss.getSheetByName('온라인 매출_' + y + '년'); if (!sh) return;
    rows = rows.concat(parseSheet_(sh, since));
  });
  if (!rows.length) { Logger.log('보낼 줄 없음'); return; }
  var total = { upserted: 0, skipped: 0 };
  for (var i = 0; i < rows.length; i += 400) {
    var res = callDc_('fn_channel_daily_ingest', { p_key: DC_KEY, p_rows: rows.slice(i, i + 400), p_file: 'GAS 온라인 매출 ' + Utilities.formatDate(today, 'Asia/Seoul', 'yyyy-MM-dd HH:mm') });
    total.upserted += res.upserted || 0; total.skipped += res.skipped || 0;
  }
  Logger.log('보냄 ' + rows.length + '줄 · 반영 ' + total.upserted + ' · 건너뜀 ' + total.skipped);
}

function parseSheet_(sh, since) {
  var v = sh.getDataRange().getValues(), out = [];
  for (var i = 0; i < v.length; i++) {
    var r = v[i];
    if (!(typeof r[1] === 'string' && /^\d+월$/.test(r[1].trim()) && r[2] instanceof Date)) continue;
    var dcols = [];
    for (var j = 2; j < r.length; j++) if (r[j] instanceof Date) dcols.push([j, r[j]]);
    for (var k = i + 2; k < v.length; k++) {
      var cr = v[k], ch = cr[0] == null ? '' : String(cr[0]).trim();
      if (!ch) break;
      if (SKIP_ROWS.test(ch)) continue;
      dcols.forEach(function (dc) {
        var d = dc[1], s = cr[dc[0]], rf = cr[dc[0] + 1];
        if (d < since) return;
        if ((s === '' || s == null) && (rf === '' || rf == null)) return;
        out.push({ date: Utilities.formatDate(d, 'Asia/Seoul', 'yyyy-MM-dd'), channel: ch, sales: Number(s) || 0, refund: Number(rf) || 0 });
      });
    }
  }
  return out;
}

function callDc_(fn, body) {
  var res = UrlFetchApp.fetch(DC_URL + fn, {
    method: 'post', contentType: 'application/json', payload: JSON.stringify(body), muteHttpExceptions: true,
    headers: { apikey: DC_ANON, Authorization: 'Bearer ' + DC_ANON }
  });
  var code = res.getResponseCode(), txt = res.getContentText();
  if (code >= 300) throw new Error(fn + ' HTTP ' + code + ' ' + txt.slice(0, 200));
  return JSON.parse(txt);
}

/** 시간 트리거 등록 (한 번만 실행) */
function setupTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (t.getHandlerFunction() === 'syncChannelDaily') ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('syncChannelDaily').timeBased().everyHours(1).create();
  Logger.log('트리거 등록: syncChannelDaily 매시간');
}
