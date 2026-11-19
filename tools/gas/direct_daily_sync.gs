/**
 * 직판 일매출 → 데이터센터 자동 적재 (direct_daily_sync.gs · 2026-11-19 · mvp_300)
 *
 * 「삼성앤텍_상품/주문관리 파일」 시트에 **바인딩된 Apps Script** 로 넣는다.
 *   시트 › 확장 프로그램 › Apps Script › 파일 추가 › 이 내용 붙여넣기 → DD_KEY 채우기 → setupDirectTrigger() 한 번 실행(권한 승인)
 *
 * 읽는 탭: '온라인 매출_YYYY년'. 월별 블록의 채널 줄 가운데 이름이 '…-직판' 으로 끝나는 줄(예: 장은희프로-직판)만 읽는다.
 *   [ , 'N월', 날짜1, , , 날짜2, , , …]      ← 날짜가 3칸마다 (매출 · 환불 · 합계)
 * 보내는 것: 최근 DD_DAYS_BACK 일의 (날짜, 프로 이름, 매출, 환불). 값이 0 인 칸은 보내지 않는다.
 * 데이터센터 fn_direct_daily_ingest 는 같은 값이면 건드리지 않고, 그 기간에 시트에서 지워진 칸은 0 으로 맞춘다.
 * 받은 줄이 전보다 절반 아래로 줄면(탭 구조가 깨진 경우) 반영하지 않고 기록만 남긴다.
 * 키는 core.api_key 'direct_daily' 의 값 — 여기 말고 어디에도 적지 말 것 (이 파일은 공개 저장소에 있음).
 */
var DD_URL  = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/fn_direct_daily_ingest';
var DD_ANON = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';
var DD_KEY  = 'PASTE_DC_KEY_HERE';     // core.api_key 'direct_daily'
var DD_DAYS_BACK = 60;                  // 지난 60일을 매번 다시 보낸다 (수정분 반영)
var DD_TZ = 'Asia/Seoul';

function syncDirectDaily() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var today = new Date(), since = new Date(today.getTime() - DD_DAYS_BACK * 86400000);
  since.setHours(0, 0, 0, 0);
  var years = [today.getFullYear()];
  if (since.getFullYear() !== today.getFullYear()) years.push(since.getFullYear());
  var rows = [];
  years.forEach(function (y) {
    var sh = ss.getSheetByName('온라인 매출_' + y + '년'); if (!sh) return;
    rows = rows.concat(ddParse_(sh, since, today));
  });
  var body = { p_key: DD_KEY, p_rows: rows,
               p_from: Utilities.formatDate(since, DD_TZ, 'yyyy-MM-dd'), p_to: Utilities.formatDate(today, DD_TZ, 'yyyy-MM-dd') };
  var res = UrlFetchApp.fetch(DD_URL, {
    method: 'post', contentType: 'application/json', payload: JSON.stringify(body), muteHttpExceptions: true,
    headers: { apikey: DD_ANON, Authorization: 'Bearer ' + DD_ANON }
  });
  var code = res.getResponseCode(), txt = res.getContentText();
  if (code >= 300) throw new Error('fn_direct_daily_ingest HTTP ' + code + ' ' + txt.slice(0, 200));
  Logger.log('직판 보냄 ' + rows.length + '줄 · ' + txt);
  return txt;
}

function ddParse_(sh, since, until) {
  var v = sh.getDataRange().getValues(), out = [];
  for (var i = 0; i < v.length; i++) {
    var r = v[i];
    if (!(typeof r[1] === 'string' && /^\d+월$/.test(r[1].trim()) && r[2] instanceof Date)) continue;
    var dcols = [];
    for (var j = 2; j < r.length; j++) if (r[j] instanceof Date) dcols.push([j, r[j]]);
    for (var k = i + 2; k < v.length; k++) {
      var cr = v[k], ch = cr[0] == null ? '' : String(cr[0]).trim();
      if (!ch) break;
      if (!/직판$/.test(ch)) continue;
      var handler = ch.replace(/(프로)?-직판$/, '');
      dcols.forEach(function (dc) {
        var d = dc[1], s = Number(cr[dc[0]]) || 0, rf = Number(cr[dc[0] + 1]) || 0;
        if (d < since || d > until) return;
        if (!s && !rf) return;
        out.push({ date: Utilities.formatDate(d, DD_TZ, 'yyyy-MM-dd'), handler: handler, sales: s, refund: rf });
      });
    }
  }
  return out;
}

/** 시간 트리거 등록 (한 번만 실행) */
function setupDirectTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (t.getHandlerFunction() === 'syncDirectDaily') ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('syncDirectDaily').timeBased().everyHours(1).create();
  Logger.log('트리거 등록: syncDirectDaily 매시간 · 첫 실행 결과 ' + syncDirectDaily());
}
