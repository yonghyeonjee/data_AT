/**
 * ═══════════════════════════════════════════════════════════════════
 *  홈페이지 견적문의 (지메일) → Datacenter 상담 자동 등록   v2 (2026-10-12 · mvp_202)
 *  ───────────────────────────────────────────────────────────────────
 *  고도몰이 보내는 "[삼성스토어 시흥점] 견적문의 에 새글이 등록되었습니다" 메일을
 *  받은편지함에서 찾아 표(성함·연락처·방문경로…)를 읽고, Datacenter 에
 *  상담(진행전)으로 넣습니다. 담당자는 배정 순번(휴가자 제외)대로 자동 배정됩니다.
 *
 *  ▸ v2 에서 바뀐 것 — "빠지는 메일이 없게"
 *    · 메일 한 통(메시지 ID) 단위로 보낸 것을 기억합니다. 지메일이 새 메일을 이미 처리한
 *      스레드에 묶어도(제목이 전부 같아서 그럴 수 있다) 새 메일은 새 ID 라 빠지지 않습니다.
 *      (v1 은 스레드 라벨로 걸러서 그런 메일을 영영 건너뛰었다 — 2026-10-04 · 10-12 누락)
 *    · 1시간마다 recheckInquiries 가 최근 7일 메일 ID 전부를 Datacenter 와 대조해
 *      빠진 것만 다시 보냅니다 (fn_inquiry_mail_check). Datacenter 를 고치던 순간에 빠진 것도 한 시간 안에 들어갑니다.
 *    · 표를 못 읽은 메일도 버리지 않습니다 — 본문(raw)을 같이 보내면 Datacenter 가 한 번 더 읽고,
 *      그래도 이름이 없으면 '(이름 확인 필요)' 로 상담을 만들고 잔디 카드에 ⚠ 가 붙습니다.
 *    · 스팸함으로 간 알림 메일도 찾습니다(in:anywhere). 받은편지함에 없는데 데이터센터에 들어왔다면 스팸함을 보세요.
 *    · 대조할 때마다 심장박동을 찍어, 스크립트가 멈추면 아침 09:10 수집 미도착 감시가 잔디로 알립니다.
 *
 *  ▸ 설치 (받는 계정으로 로그인한 상태에서)
 *    1. script.google.com → 프로젝트 열기 → 이 파일로 통째로 바꾸기 (DC_KEY 는 기존 값 그대로)
 *    2. runOnce() 한 번 실행 → 권한 승인 · 실행 로그에 "✅ 연결 정상"
 *    3. setupInquiryTrigger() 한 번 (1분) + setupRecheckTrigger() 한 번 (1시간)
 *
 *  ▸ 라벨은 표시용입니다. "DC적재" = 보냄, "DC확인필요" = 표를 못 읽어 원문으로 보냄(Datacenter 문의 관리에서 이름·번호를 고칠 것).
 *    라벨을 떼도 다시 들어가지 않습니다 (Datacenter 가 메일 ID 로 중복을 막는다).
 *
 *  ▸ 이름·연락처는 Datacenter 로만 보내고 이 스크립트에는 남기지 않습니다 (보낸 메일 ID 만 기억).
 * ═══════════════════════════════════════════════════════════════════ */

var DC_URL   = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
var DC_ANON  = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';
var DC_KEY   = 'PASTE_DC_KEY_HERE';          // fn_inquiry_mail_ingest 전용 키
var LABEL    = 'DC적재';        // 넘긴 메일
var LABEL_NG = 'DC확인필요';     // 표를 못 읽어 원문으로 넘긴 메일 (Datacenter 에서 이름·번호 확인)
var QUERY    = 'in:anywhere -in:trash subject:견적문의';   // 스팸함에 들어간 알림 메일도 (기본 검색은 스팸을 빼고 찾는다)
var MAX_THREADS = 100;
var SENT_PROP = 'dc_sent_ids';   // 보낸 메시지 ID (최근 400개)
var SENT_KEEP = 400;
var RAW_MAX   = 4000;            // 본문 원문 최대 글자

/* 메일 표의 항목 이름 → Datacenter 필드 */
var FIELD_MAP = {
  '성함': 'name', '이름': 'name', '고객명': 'name',
  '사업자명': 'name', '상호': 'name', '상호명': 'name', '업체명': 'name', '회사명': 'name',
  '연락처': 'phone', '전화번호': 'phone', '휴대폰': 'phone',
  '방문경로': 'route', '유입경로': 'route',
  '구매옵션': 'option', '구매 옵션': 'option',
  '아파트명': 'apt', '아파트': 'apt',
  '희망품목': 'items', '희망 품목': 'items', '관심품목': 'items',
  '제품모델명': 'model', '모델명': 'model',
  '상담방법': 'method', '상담 방법': 'method',
  '첨부파일': 'attach',
  '이메일': 'email', 'E-mail': 'email',
  '문의내용': 'memo', '문의 내용': 'memo', '요청사항': 'memo', '내용': 'memo', '메모': 'memo'
};
/* 사업자 견적문의는 게시판이 따로다 (/board/contact_business/). 제목으로 가른다. */
var BIZ_RE = /(사업자|법인|기업|B2B)/i;

/* ── 진입점 ─────────────────────────────────────────────── */
/* 1분 — 최근 2일 메일 중 아직 안 보낸 것 */
function collectInquiries(){ sync_(2, false); }
/* 1시간 — 최근 7일 메일 ID 전부를 Datacenter 와 대조해 빠진 것만 다시 보냄 (+ 심장박동) */
function recheckInquiries(){ sync_(7, true); }

function sync_(days, askDc){
  var threads = GmailApp.search(QUERY + ' newer_than:' + days + 'd', 0, MAX_THREADS);
  var msgs = [];
  threads.forEach(function(th){
    th.getMessages().forEach(function(m){ if(/견적문의/.test(String(m.getSubject() || ''))) msgs.push(m); });
  });
  var todo;
  if(askDc){
    var ids = msgs.map(function(m){ return m.getId(); });
    var chk = dcCall_('fn_inquiry_mail_check', { p_key: DC_KEY, p_ids: ids });
    if(!chk || !chk.ok){ Logger.log('❌ 대조 실패 — 다음 시간에 다시'); return; }
    var missing = {}; (chk.missing || []).forEach(function(id){ missing[id] = true; });
    todo = msgs.filter(function(m){ return missing[m.getId()]; });
    Logger.log('🔎 최근 ' + days + '일 메일 ' + ids.length + '통 대조 · Datacenter 에 없는 것 ' + todo.length + '통'
               + (todo.length ? ' → 다시 보냅니다' : ''));
  } else {
    var sent = loadSent_();
    todo = msgs.filter(function(m){ return !sent[m.getId()]; });
    if(!todo.length){ Logger.log('새 견적문의 메일 없음'); return; }
  }
  if(!todo.length) return;

  var rows = todo.map(buildRow_);
  var res = dcCall_('fn_inquiry_mail_ingest', { p_key: DC_KEY, p_rows: rows });
  if(!res || !res.ok){ Logger.log('❌ Datacenter 적재 실패 — 보낸 것으로 적지 않습니다. 다음 실행에 다시 시도합니다.'); return; }

  /* 보낸 ID 기억 + 라벨 (표시용) */
  var okLabel = getOrCreateLabel_(LABEL), ngLabel = getOrCreateLabel_(LABEL_NG);
  var sentNow = loadSent_();
  todo.forEach(function(m, i){
    sentNow[m.getId()] = 1;
    var th = m.getThread();
    th.addLabel(rows[i].name ? okLabel : ngLabel);
    if(!rows[i].name) Logger.log('⚠ 표를 못 읽음 — "' + rows[i].subject + '" → 원문으로 보냄 · Datacenter 문의 관리에서 이름·번호 확인');
  });
  saveSent_(sentNow);
  Logger.log('✅ 문의 ' + rows.length + '건 보냄 · 새로 등록 ' + res.inserted + ' · 이미 있음 ' + res.duplicate + ' · 건너뜀 ' + res.skipped
             + (res.inserted ? ' · 잔디 알림 나감' : ''));
  (res.rows || []).forEach(function(r){ Logger.log('   #' + r.id + ' ' + r.name + ' → ' + (r.handler || '미배정')); });
}

/* 처음 한 번 : 권한 승인 + 연결 확인 */
function runOnce(){
  var st = dcCall_('fn_inquiry_mail_status', { p_key: DC_KEY });
  if(st && st.ok) Logger.log('✅ 연결 정상 · 지금까지 지메일로 들어온 상담 ' + st.total + '건 · 마지막 ' + (st.last || '-'));
  else { Logger.log('❌ 연결 실패 — 바로 위 로그를 보세요'); return; }
  recheckInquiries();
}

/* 자동 실행 — 1분(수집) + 1시간(대조). 둘 다 켜 둘 것.
   ※ 일반 gmail.com 계정은 스크립트 실행시간이 하루 90분. 1분 주기 한 번에 1~2초라 넉넉하지만
     "초과" 경고 메일이 오면 setupInquiryTrigger5() 로 바꾸세요. (Workspace 계정은 6시간) */
function setupInquiryTrigger(){ setTrigger_('collectInquiries', 1); }
function setupInquiryTrigger5(){ setTrigger_('collectInquiries', 5); }
function setupRecheckTrigger(){ setTrigger_('recheckInquiries', 60); }
function setTrigger_(fn, min){
  ScriptApp.getProjectTriggers().forEach(function(t){ if(t.getHandlerFunction() === fn) ScriptApp.deleteTrigger(t); });
  var tb = ScriptApp.newTrigger(fn).timeBased();
  if(min >= 60) tb.everyHours(Math.round(min / 60)); else tb.everyMinutes(min);
  tb.create();
  Logger.log('✅ ' + (min >= 60 ? Math.round(min / 60) + '시간' : min + '분') + '마다 ' + fn + ' 가 돕니다');
}
/* 자동 실행 끄기 (둘 다) */
function stopInquiryTrigger(){
  var n = 0;
  ScriptApp.getProjectTriggers().forEach(function(t){
    if(t.getHandlerFunction() === 'collectInquiries' || t.getHandlerFunction() === 'recheckInquiries'){ ScriptApp.deleteTrigger(t); n++; }
  });
  Logger.log(n ? '멈췄습니다 (' + n + '개 삭제)' : '켜져 있던 자동 실행이 없습니다');
}

/* ── 메일 한 통 → 한 줄 (표를 못 읽어도 raw 로 보낸다) ─────────── */
function buildRow_(msg){
  var plain = String(msg.getPlainBody() || '');
  var obj = parseTable_(plain);
  if(!obj.name) obj = mergeObj_(obj, parseHtml_(msg.getBody() || ''));
  obj.msg_id = msg.getId();
  obj.received_at = msg.getDate().toISOString();
  obj.subject = String(msg.getSubject() || '').slice(0, 120);
  if(BIZ_RE.test(obj.subject)) obj.kind = '사업자';
  obj.raw = (plain || strip_(msg.getBody() || '')).replace(/\r/g, '').slice(0, RAW_MAX);
  return obj;
}
function mergeObj_(a, b){ Object.keys(b).forEach(function(k){ if(!a[k]) a[k] = b[k]; }); return a; }

/* 텍스트 본문 : "성함\t지용현" 또는 "성함  지용현" 한 줄씩.
   라벨만 있고 값이 다음 줄부터 오는 칸(문의내용)은 다음 라벨 전까지 이어 붙인다. */
function parseTable_(text){
  var out = {}, pending = null;
  String(text).split(/\r?\n/).forEach(function(line){
    var m = line.match(/^\s*([가-힣A-Za-z\- ]{2,12})\s*[\t:：]\s*(.*)$/) || line.match(/^\s*([가-힣A-Za-z\- ]{2,12})\s{2,}(.*)$/)
         || line.match(/^\s*([가-힣A-Za-z\- ]{2,12})\s*()$/);   /* 라벨만 있는 줄 (값은 다음 줄부터) */
    var key = m ? FIELD_MAP[m[1].trim()] : null;
    if(key){
      var val = m[2].trim();
      if(val !== ''){ if(!out[key]) out[key] = val; pending = null; }
      else pending = out[key] ? null : key;
      return;
    }
    if(pending && line.trim() !== ''){ out[pending] = (out[pending] ? out[pending] + ' ' : '') + line.trim(); }
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
  return String(s || '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(tr|p|div|li)>/gi, '\n').replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/[ \t]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
}

/* ── 보낸 메시지 ID 기억 (이름·번호는 남기지 않는다) ─────────── */
function loadSent_(){
  try { var s = PropertiesService.getScriptProperties().getProperty(SENT_PROP); var arr = s ? JSON.parse(s) : [];
        var o = {}; arr.forEach(function(id){ o[id] = 1; }); return o; } catch(e){ return {}; }
}
function saveSent_(o){
  var arr = Object.keys(o); if(arr.length > SENT_KEEP) arr = arr.slice(arr.length - SENT_KEEP);
  PropertiesService.getScriptProperties().setProperty(SENT_PROP, JSON.stringify(arr));
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
