/**
 * ═══════════════════════════════════════════════════════════════════
 *  홈페이지 견적문의 (지메일) → Datacenter 상담 자동 등록
 *  ───────────────────────────────────────────────────────────────────
 *  고도몰이 보내는 "[삼성스토어 시흥점] 견적문의 에 새글이 등록되었습니다" 메일을
 *  받은편지함에서 찾아 표(성함·연락처·방문경로…)를 읽고, Datacenter 에
 *  상담(진행전)으로 넣습니다. 담당자는 배정 순번(휴가자 제외)대로 자동 배정됩니다.
 *
 *  ▸ 설치 (받는 계정으로 로그인한 상태에서)
 *    1. script.google.com → 새 프로젝트 → 이 파일 붙여넣기
 *    2. 프로젝트 설정 → appsscript.json 표시 → 같이 드린 appsscript.json 으로 교체
 *    3. runOnce() 한 번 실행 → 권한 승인 (Gmail 읽기 · 라벨 · 외부 호출)
 *    4. 실행 로그에 "✅ 연결 정상" 이 보이면 setupInquiryTrigger() 한 번 실행
 *       → 10분마다 자동으로 돕니다
 *
 *  ▸ 처리한 메일에는 라벨 "DC적재" 가 붙습니다. 라벨을 떼면 다음 번에 다시 넣습니다
 *    (Datacenter 쪽은 메일 ID 로 중복을 막으므로 두 번 들어가지 않습니다).
 *
 *  ▸ 이름·연락처는 Datacenter 로만 보내고 이 스크립트에는 남기지 않습니다.
 * ═══════════════════════════════════════════════════════════════════ */

var DC_URL   = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
var DC_ANON  = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';
var DC_KEY   = 'gm-inq-2f7c9a41d3e85b60';          // fn_inquiry_mail_ingest 전용 키
var LABEL    = 'DC적재';
var QUERY    = 'subject:(견적문의 새글) newer_than:30d -label:' + LABEL;
var MAX_PER_RUN = 30;

/* 메일 표의 항목 이름 → Datacenter 필드 */
var FIELD_MAP = {
  '성함': 'name', '이름': 'name', '고객명': 'name',
  '연락처': 'phone', '전화번호': 'phone', '휴대폰': 'phone',
  '방문경로': 'route', '유입경로': 'route',
  '구매옵션': 'option', '구매 옵션': 'option',
  '아파트명': 'apt', '아파트': 'apt',
  '희망품목': 'items', '희망 품목': 'items', '관심품목': 'items',
  '제품모델명': 'model', '모델명': 'model',
  '상담방법': 'method', '상담 방법': 'method',
  '첨부파일': 'attach',
  '문의내용': 'memo', '내용': 'memo', '메모': 'memo'
};

/* ── 진입점 ─────────────────────────────────────────────── */
function collectInquiries(){
  var label = getOrCreateLabel_(LABEL);
  var threads = GmailApp.search(QUERY, 0, MAX_PER_RUN);
  if(!threads.length){ Logger.log('새 견적문의 메일 없음'); return; }
  var rows = [], done = [];
  threads.forEach(function(th){
    th.getMessages().forEach(function(msg){
      var row = parseMessage_(msg);
      if(row){ rows.push(row); done.push(th); }
      else Logger.log('표를 못 읽음 — 메일 ' + msg.getId() + ' (' + msg.getSubject() + ')');
    });
  });
  if(!rows.length){ Logger.log('읽은 문의 0건'); return; }
  var res = dcCall_('fn_inquiry_mail_ingest', { p_key: DC_KEY, p_rows: rows });
  if(!res || !res.ok){ Logger.log('❌ Datacenter 적재 실패 — 라벨을 붙이지 않습니다. 다음 실행에 다시 시도합니다.'); return; }
  done.forEach(function(th){ th.addLabel(label); });
  Logger.log('✅ 문의 ' + rows.length + '건 보냄 · 새로 등록 ' + res.inserted + ' · 이미 있음 ' + res.duplicate + ' · 건너뜀 ' + res.skipped);
  (res.rows || []).forEach(function(r){ Logger.log('   #' + r.id + ' ' + r.name + ' → ' + (r.handler || '미배정')); });
}

/* 처음 한 번 : 권한 승인 + 연결 확인 */
function runOnce(){
  var st = dcCall_('fn_inquiry_mail_status', { p_key: DC_KEY });
  if(st && st.ok) Logger.log('✅ 연결 정상 · 지금까지 지메일로 들어온 상담 ' + st.total + '건 · 마지막 ' + (st.last || '-'));
  else { Logger.log('❌ 연결 실패 — 바로 위 로그를 보세요'); return; }
  collectInquiries();
}

/* 10분마다 */
function setupInquiryTrigger(){
  ScriptApp.getProjectTriggers().forEach(function(t){ if(t.getHandlerFunction() === 'collectInquiries') ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('collectInquiries').timeBased().everyMinutes(10).create();
  Logger.log('✅ 10분마다 collectInquiries 가 돕니다');
}

/* ── 메일 한 통 → 한 줄 ────────────────────────────────── */
function parseMessage_(msg){
  var obj = parseTable_(msg.getPlainBody() || '');
  if(!obj.name) obj = mergeObj_(obj, parseHtml_(msg.getBody() || ''));
  if(!obj.name) return null;
  obj.msg_id = msg.getId();
  obj.received_at = msg.getDate().toISOString();
  obj.subject = String(msg.getSubject() || '').slice(0, 120);
  return obj;
}
function mergeObj_(a, b){ Object.keys(b).forEach(function(k){ if(!a[k]) a[k] = b[k]; }); return a; }

/* 텍스트 본문 : "성함\t지용현" 또는 "성함  지용현" 한 줄씩 */
function parseTable_(text){
  var out = {};
  String(text).split(/\r?\n/).forEach(function(line){
    var m = line.match(/^\s*([가-힣A-Za-z ]{2,12})\s*[\t:：]\s*(.*)$/) || line.match(/^\s*([가-힣A-Za-z ]{2,12})\s{2,}(.*)$/);
    if(!m) return;
    var key = FIELD_MAP[m[1].trim()]; if(!key) return;
    var val = m[2].trim();
    if(!out[key] && val !== '') out[key] = val;
  });
  return out;
}
/* HTML 본문 : <tr><th>성함</th><td>지용현</td></tr> 꼴 */
function parseHtml_(html){
  var out = {};
  var re = /<tr[^>]*>\s*<t[hd][^>]*>([\s\S]*?)<\/t[hd]>\s*<td[^>]*>([\s\S]*?)<\/td>/gi, m;
  while((m = re.exec(html))){
    var k = strip_(m[1]), v = strip_(m[2]);
    var key = FIELD_MAP[k]; if(key && !out[key] && v) out[key] = v;
  }
  return out;
}
function strip_(s){
  return String(s || '').replace(/<br\s*\/?>/gi, ' ').replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/\s+/g, ' ').trim();
}

/* ── Datacenter 호출 ───────────────────────────────────── */
function dcCall_(fn, body){
  var res;
  try {
    res = UrlFetchApp.fetch(DC_URL + fn, {
      method: 'post', contentType: 'application/json',
      headers: { apikey: DC_ANON, Authorization: 'Bearer ' + DC_ANON },
      payload: JSON.stringify(body), muteHttpExceptions: true
    });
  } catch(e){
    if(String(e).indexOf('external_request') >= 0 || String(e).indexOf('UrlFetchApp') >= 0)
      Logger.log('❌ 외부 호출 권한이 없습니다. appsscript.json 의 oauthScopes 를 확인하고 권한을 다시 승인하세요.');
    else Logger.log('Datacenter ' + fn + ' 호출 실패: ' + e);
    return null;
  }
  var code = res.getResponseCode(), txt = res.getContentText();
  if(code !== 200){ Logger.log('Datacenter ' + fn + ' ' + code + ': ' + txt.slice(0, 300)); return null; }
  try { return JSON.parse(txt); } catch(e){ Logger.log('응답 파싱 실패'); return null; }
}
function getOrCreateLabel_(name){ return GmailApp.getUserLabelByName(name) || GmailApp.createLabel(name); }
