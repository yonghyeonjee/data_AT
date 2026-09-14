/***********************************************************************
 * 구독문의 GAS (v13) → Datacenter 연동  ── "v15" (2026-09-14)
 * ---------------------------------------------------------------------
 * v15 에서 바뀐 것: 담당자 배정과 잔디 카드를 GAS 가 하지 않는다. 둘 다 데이터센터가 한다.
 *   · 배정: 홈페이지 문의(지메일)와 구독 문의가 같은 순번표(core.assign_pool default)를 번갈아 쓴다. 휴가자(반차는 15시까지)는 자동으로 건너뛴다.
 *   · 카드: 데이터센터 규칙 inquiry_subscription 이 잔디에 한 장 보낸다 (배정 담당자 · 상담 정보 · 상담 확인하러가기).
 *   · 시트 '상담관리' H열(담당자)에는 데이터센터가 정한 이름을 이 스크립트가 적어 넣는다.
 *
 * 붙이는 법 (Code.gs 맨 아래에 이 파일 전체를 붙여 넣고, doPost 3곳만 손댄다)
 *
 *  ① doPost 에서 GAS 가 담당자 순번을 고르던 줄(assignedStaff = ...)을 지운다. 값이 필요하면 아래 ②의 반환값을 쓴다.
 *  ② 상담관리 시트에 행을 쓴 뒤(mgmtRow 가 정해진 뒤) 한 줄:
 *        var assignedStaff = dcAssignInquiry_(data, mgmtRow, isTest);
 *     (테스트 접수면 건너뜀 · 데이터센터가 배정한 이름을 H열에 적고 돌려준다 · 실패해도 접수 흐름은 안 끊김)
 *  ③ `sendJandiNotification(...)` 줄을 지운다 (카드는 데이터센터가 보낸다 — 남겨 두면 두 장 간다).
 *
 *  ④ 트리거 → onMgmtEdit · 스프레드시트 · 수정 시 (이미 있으면 그대로)
 *  ⑤ 배포 > 배포 관리 > 기존 배포 연필 > 새 버전 > 배포 (URL 유지)
 *  ⑥ 데이터센터 쪽 규칙 inquiry_subscription 을 켠다 (지용현)
 *
 * 시트 ↔ Datacenter 대응
 *   상담결과 미처리·부재중 → 진행전 / 상담완료-계약 → 구매완료 / 상담완료-보류 → 보류 / 상담거절·기타 → 종료
 *   시트에서 담당자(H)·상담결과(I)·사은품(J·K)을 고치면 onMgmtEdit 가 Datacenter 에 반영 · 테스트 접수는 저장하지 않음
 ***********************************************************************/
var DC_URL  = typeof DC_URL  !== 'undefined' ? DC_URL  : 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
var DC_ANON = typeof DC_ANON !== 'undefined' ? DC_ANON : 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';   // 공개키 (브라우저에도 있는 값)
var DC_KEY  = typeof DC_KEY  !== 'undefined' ? DC_KEY  : 'PASTE_DC_KEY_HERE';         // 서버간 전달 키 (Datacenter core.api_key 해시와 대조)

function dcRpc_(fn, payload) {
  const res = UrlFetchApp.fetch(DC_URL + fn, {
    method: 'post', contentType: 'application/json',
    headers: { apikey: DC_ANON, Authorization: 'Bearer ' + DC_ANON },
    payload: JSON.stringify({ p_key: DC_KEY, p_data: payload }),
    muteHttpExceptions: true
  });
  const code = res.getResponseCode(), body = res.getContentText();
  if (code !== 200) throw new Error('Datacenter ' + code + ': ' + body.slice(0, 200));
  return body;
}

/** 접수 직후: 데이터센터에 넣고 배정된 담당자를 받아 시트 H열에 적는다 (doPost 에서 호출) — v15 */
function dcAssignInquiry_(data, mgmtRow, isTest) {
  try {
    if (isTest) { logToSheet_('5b.Datacenter', '테스트 → 생략'); return ''; }
    const sheet = getOrCreateManagementSheet();
    const ts = mgmtRow ? String(sheet.getRange(mgmtRow, 1).getDisplayValue() || '') : '';
    const payload = Object.assign({}, data, {
      timestamp: ts || Utilities.formatDate(new Date(), 'Asia/Seoul', 'yyyy-MM-dd HH:mm:ss'),
      assignedStaff: '',                                   // 비워 보내면 데이터센터 순번표가 배정한다 (휴가자 제외)
      mgmtRow: mgmtRow || 0
    });
    const res = JSON.parse(dcRpc_('fn_submit_inquiry', payload));
    logToSheet_('5b.Datacenter', JSON.stringify(res));
    const handler = (res && res.handler) || '';
    if (handler && mgmtRow) sheet.getRange(mgmtRow, 8).setValue(handler);   // H열 = 담당자 (스크립트가 쓰면 onMgmtEdit 는 안 돈다)
    return handler;
  } catch (e) {
    logToSheet_('X.Datacenter', e);                       // 실패해도 접수 흐름은 그대로
    return '';
  }
}

/** (v14 호환) 담당자를 GAS 가 정해 보내던 옛 방식 — v15 에서는 dcAssignInquiry_ 를 쓴다 */
function dcForwardInquiry_(data, assignedStaff, mgmtRow, isTest) {
  try {
    if (isTest) { logToSheet_('5b.Datacenter', '테스트 → 생략'); return; }
    const sheet = getOrCreateManagementSheet();
    const ts = mgmtRow ? String(sheet.getRange(mgmtRow, 1).getDisplayValue() || '') : '';
    const payload = Object.assign({}, data, {
      timestamp: ts || Utilities.formatDate(new Date(), 'Asia/Seoul', 'yyyy-MM-dd HH:mm:ss'),
      assignedStaff: assignedStaff || '',
      mgmtRow: mgmtRow || 0
    });
    const r = dcRpc_('fn_submit_inquiry', payload);
    logToSheet_('5b.Datacenter', r);
  } catch (e) {
    logToSheet_('X.Datacenter', e);                       // 실패해도 접수·잔디는 그대로 진행
  }
}

/** 상담관리 한 행 → payload */
function dcRowPayload_(row) {                            // row = [문의시간, 고객명, 연락처, 관심제품, 구매목적, 지역, 메모, 담당자, 상담결과, 상담완료사은품, 결제완료사은품]
  return {
    timestamp: String(row[0] || ''), customerName: String(row[1] || ''), phone: String(row[2] || ''),
    modelName: String(row[3] || ''), purchasePurpose: String(row[4] || ''), region: String(row[5] || ''),
    memo: String(row[6] || ''), assignedStaff: String(row[7] || ''), result: String(row[8] || ''),
    giftConsult: String(row[9] || ''), giftPaid: String(row[10] || ''), inquiryType: '구독'
  };
}

/** 시트에서 담당자/상담결과/사은품을 고치면 Datacenter 에도 반영 (설치형 트리거: onMgmtEdit · 수정 시) */
function onMgmtEdit(e) {
  try {
    const sh = e.range.getSheet();
    if (sh.getName() !== MANAGEMENT_SHEET_NAME) return;
    const row = e.range.getRow(); if (row < 2) return;
    const col = e.range.getColumn(); if (col < 8 || col > 11) return;     // H~K 만
    const vals = sh.getRange(row, 1, 1, 11).getDisplayValues()[0];
    if (!vals[0] || !vals[2]) return;
    const p = dcRowPayload_(vals);
    if (/test|테스트/i.test(p.customerName) || /test/i.test(p.assignedStaff)) return;
    dcRpc_('fn_submit_inquiry', p);
  } catch (err) { logToSheet_('X.DatacenterEdit', err); }
}

/** 편집기에서 1회 실행: 상담관리 전체를 Datacenter 로 (재실행해도 중복 없음) */
function backfillInquiryToDatacenter() {
  const sh = getOrCreateManagementSheet();
  const last = getRealLastRow_(sh);
  if (last < 2) { Logger.log('데이터 없음'); return; }
  const rows = sh.getRange(2, 1, last - 1, 11).getDisplayValues();
  let ok = 0, skip = 0, fail = 0;
  rows.forEach(function (r, i) {
    if (!r[0] || !r[2]) { skip++; return; }
    const p = dcRowPayload_(r);
    if (/test|테스트/i.test(p.customerName) || /test/i.test(p.assignedStaff)) { skip++; return; }
    try { const res = JSON.parse(dcRpc_('fn_submit_inquiry', p)); if (res.skipped) skip++; else ok++; }
    catch (e) { fail++; if (fail <= 5) Logger.log((i + 2) + '행 실패: ' + e); }
    if ((i + 1) % 50 === 0) Utilities.sleep(300);
  });
  Logger.log('완료: 적재 ' + ok + ' / 건너뜀 ' + skip + ' / 실패 ' + fail);
  logToSheet_('backfill', '적재 ' + ok + ' / 건너뜀 ' + skip + ' / 실패 ' + fail);
}
