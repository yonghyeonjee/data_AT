/***********************************************************************
 * 홈페이지 폼 → Datacenter 이중 적재  (시트는 그대로 쓰고, 같은 행을 DB 에도 쌓는다)
 * ---------------------------------------------------------------------
 * 쓰는 곳 (각 폼의 Apps Script 프로젝트 Code.gs 맨 아래에 붙여넣는다)
 *   ① 삼성앤텍 소모품/렌탈 문의   → FORM_CODE = 'supply'   (시트 1R0-DjLq… · 접수번호 P/W/A-nnnn)
 *   ② 삼성앤텍_문의내역_VMS_ToJandi → FORM_CODE = 'b2b'     (시트 1GsuYZMG… · 탭 raw_B2B · B-nnnn)
 *
 * 설치
 *   1) 아래 전체를 Code.gs 맨 아래에 붙여넣는다.
 *   2) FORM_CODE 를 위 둘 중 하나로 맞춘다.
 *   3) 시트에 행을 쓰는 코드 바로 다음 줄에  dcForwardLastRow_();  한 줄을 넣는다.
 *      (잔디 발송 직전이 가장 안전하다. 실패해도 폼 접수는 절대 막지 않는다.)
 *   4) 편집기에서 backfillFormToDatacenter 를 한 번 실행 → 기존 행 전부 적재.
 *   5) 상태·처리메모를 나중에 고치는 것도 반영하려면
 *      [트리거] → onDcEdit · 스프레드시트 · 수정 시 를 추가한다.
 ***********************************************************************/
var FORM_CODE = 'b2b';          // ← 'supply' 또는 'b2b'
var DC_URL  = typeof DC_URL  !== 'undefined' ? DC_URL  : 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
var DC_ANON = typeof DC_ANON !== 'undefined' ? DC_ANON : 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';
var DC_KEY  = typeof DC_KEY  !== 'undefined' ? DC_KEY  : 'dc_15a3039ac89b4cf5045b62688391e85099ea9a63';

/* 폼별 컬럼 매핑 — 시트 헤더명 기준. 값은 헤더 후보들(먼저 맞는 것 사용) */
var DC_MAP = {
  supply: { sheet: null,       // null = 첫 번째 시트
            ref:['접수번호'], ts:['접수일시'], name:['사업자명','상호','고객명'],
            phone:['연락처','휴대폰'], category:['제품'], summary:['문의 요약','문의요약'],
            status:['상담 상태','상태'], handler:['상담자','담당자'], memo:['상담 메모','상담메모'] },
  b2b:    { sheet: 'raw_B2B',
            ref:['접수번호'], ts:['접수일시'], name:['상호','사업자명'],
            phone:['연락처','휴대폰'], category:['문의유형'], summary:['주문내역','문의내용'],
            status:['상태'], handler:['담당자'], memo:['처리메모'] }
};

function dcSheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const M = DC_MAP[String(FORM_CODE).trim()];
  if (!M) throw new Error('FORM_CODE 가 잘못되었습니다: ' + FORM_CODE + " (supply / b2b 중 하나)");
  const nm = M.sheet;
  return nm ? ss.getSheetByName(nm) : ss.getSheets()[0];
}
function dcPick_(head, cands) {
  for (let i = 0; i < cands.length; i++) {
    const j = head.indexOf(cands[i]);
    if (j >= 0) return j;
  }
  return -1;
}
/** 시트 한 행 → RPC 가 받는 정규화 객체 */
function dcRow_(head, row) {
  const M = DC_MAP[String(FORM_CODE).trim()], o = {};
  ['ref','ts','name','phone','category','summary','status','handler','memo'].forEach(function (k) {
    const j = dcPick_(head, M[k] || []);
    let v = (j >= 0) ? row[j] : '';
    if (v instanceof Date) v = Utilities.formatDate(v, 'Asia/Seoul', 'yyyy-MM-dd HH:mm:ss');
    o[k] = String(v == null ? '' : v).trim();
  });
  // 요약이 비면 문의내용으로 대체 (b2b)
  if (!o.summary) {
    const j = dcPick_(head, ['문의내용','문의 요약']);
    if (j >= 0) o.summary = String(row[j] || '').trim();
  }
  return o;
}
function dcPost_(rows) {
  if (!rows || !rows.length) return null;
  try {
    const res = UrlFetchApp.fetch(DC_URL + 'fn_submit_form', {
      method: 'post', contentType: 'application/json', muteHttpExceptions: true,
      headers: { apikey: DC_ANON, Authorization: 'Bearer ' + DC_ANON },
      payload: JSON.stringify({ p_key: DC_KEY, p_form: String(FORM_CODE).trim(), p_rows: rows })
    });
    const code = res.getResponseCode(), body = res.getContentText();
    if (code >= 300) Logger.log('Datacenter 적재 실패 ' + code + ' ' + body);
    else Logger.log('Datacenter ' + body);
    return body;
  } catch (e) {
    Logger.log('Datacenter 예외: ' + e);      // 폼 접수는 계속 진행
    return null;
  }
}

/** 방금 쓴 마지막 행 1건을 보낸다 — 시트 기록 직후에 호출 */
function dcForwardLastRow_() {
  try {
    const sh = dcSheet_();
    const n = sh.getLastRow();
    if (n < 2) return;
    const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(function (x) { return String(x || '').trim(); });
    const row = sh.getRange(n, 1, 1, sh.getLastColumn()).getValues()[0];
    dcPost_([dcRow_(head, row)]);
  } catch (e) { Logger.log('dcForwardLastRow_ 예외: ' + e); }
}

/** 상태·처리메모를 나중에 고쳤을 때 같은 행을 다시 보낸다 (수정 시 트리거) */
function onDcEdit(e) {
  try {
    if (!e || !e.range) return;
    const sh = e.range.getSheet();
    if (sh.getName() !== dcSheet_().getName()) return;
    const r = e.range.getRow();
    if (r < 2) return;
    const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(function (x) { return String(x || '').trim(); });
    const row = sh.getRange(r, 1, 1, sh.getLastColumn()).getValues()[0];
    dcPost_([dcRow_(head, row)]);
  } catch (err) { Logger.log('onDcEdit 예외: ' + err); }
}

/** 기존 데이터 전체 적재 (편집기에서 1회 실행) */
function backfillFormToDatacenter() {
  const sh = dcSheet_();
  const last = sh.getLastRow();
  if (last < 2) { Logger.log('보낼 행이 없습니다'); return; }
  const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(function (x) { return String(x || '').trim(); });
  const vals = sh.getRange(2, 1, last - 1, sh.getLastColumn()).getValues();
  const rows = [];
  for (let i = 0; i < vals.length; i++) {
    const o = dcRow_(head, vals[i]);
    if (o.ref) rows.push(o);
  }
  Logger.log('보낼 행 ' + rows.length + '건');
  for (let i = 0; i < rows.length; i += 100) dcPost_(rows.slice(i, i + 100));
}
