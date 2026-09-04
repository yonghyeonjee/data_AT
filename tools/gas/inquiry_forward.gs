/***********************************************************************
 * 구독문의 GAS (v13) → Datacenter 이중 적재 패치  ── "v14"
 * ---------------------------------------------------------------------
 * 붙이는 법 (Code.gs 맨 아래에 이 파일 전체를 붙여 넣고, doPost 3곳만 손댄다)
 *
 *  ① doPost 안 `sendJandiNotification(...)` 바로 앞에 한 줄:
 *        dcForwardInquiry_(data, assignedStaff, mgmtRow, isTest);
 *     (isTest 면 함수가 알아서 건너뜀 · 실패해도 접수 흐름은 안 끊김)
 *
 *  ② 편집기에서 backfillDatacenter() 를 1회 실행 → '상담관리' 탭 전체를 Datacenter 에 적재
 *     (같은 문의는 문의시간+뒷4자리로 식별하므로 몇 번 돌려도 중복되지 않음)
 *
 *  ③ 트리거 → 트리거 추가 → 함수 onMgmtEdit · 이벤트 소스 '스프레드시트' · 유형 '수정 시'
 *     → 담당자가 시트에서 담당자/상담결과/사은품을 바꾸면 Datacenter 에도 반영됨
 *
 *  ④ 배포 > 배포 관리 > 기존 배포 연필 > 새 버전 > 배포 (URL 유지)
 *
 * 시트 ↔ Datacenter 대응
 *   상담결과 미처리·부재중 → 진행중 / 상담완료-계약 → 구매완료 / 상담완료-보류 → 보류 / 상담거절·기타 → 종료
 *   담당자 → 매장 화면(store) '내 고객'에 그 담당자 진행중 상담으로 표시 · 테스트 접수는 저장하지 않음
 ***********************************************************************/
const DC_URL  = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
const DC_ANON = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';   // 공개키 (브라우저에도 있는 값)
const DC_KEY  = 'dc_15a3039ac89b4cf5045b62688391e85099ea9a63';         // 서버간 전달 키 (Datacenter core.api_key 해시와 대조)

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

/** 접수 직후 전달 (doPost 에서 호출) */
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
function backfillDatacenter() {
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
