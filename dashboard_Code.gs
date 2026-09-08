/***********************************************************************
 * 매출 대시보드 v4.1 · Google Apps Script  (보안 해제판)
 * ---------------------------------------------------------------------
 * v4 대비 변경 — 코드 로직은 그대로, 접근 제어만 해제
 *   · ALLOW_EMAILS(이메일 화이트리스트) 제거 → doGet / refreshFromUI 에서 계정 검사 안 함
 *   · /exec?json=1&pw=3166 → payload JSON 엔드포인트 추가
 *     (db.samsungat.co.kr/dash 의 [기존] 토글이 이 주소를 호출)
 *   · 갱신 횟수 카운터 키를 이메일 → 문서 단위로 변경 (익명 배포에서는 이메일이 빈 값)
 *   · 갱신 비밀번호(기본 3033 · 세션당 5회 무료)는 유지
 *     → 이것도 없애려면 refreshFromUI 안의 "── 비밀번호 검사" 블록만 지우면 됨
 *
 * 배포
 *   [배포] → [배포 관리] → 연필 → 버전 '새 버전' · 액세스 '모든 사용자(Anyone)' → 배포
 *   ※ 액세스가 '구글 계정 사용자' 로 남아 있으면 계속 로그인 창이 뜬다.
 *   ※ /exec URL 을 dash/index.html 의 SHARE_URL 에 넣는다.
 *
 * 소스
 *   ① 기존 원장 (SRC_ID · 온라인 매출_2026년, 가로형 월블록)
 *      = 채널 매출의 공식 숫자. 시흥점-매장매출/구독매출 행도 채널로 흡수
 *   ② 현재 시트의 주문 탭 (샵링커 58컬럼) = 상품 분해 전용 (채널 합계에 미포함)
 *   ③ 현재 시트의 VMS 탭 (이카운트 전표) = 채널 '통신판매(VMS)'
 *   ④ 렌탈 시트 (RENT_ID) = 채널 '렌탈' + 거래처/항목/유형 상세
 *   ⑤ 이벤트 시트 (선택) = 추이 차트 배경 밴드
 ***********************************************************************/
const SRC_ID    = '12L7yBInxWC4ChDWT6PmRoRqJGiIviTG2W49_yoW77XA';
const SRC_SHEET = '온라인 매출_2026년';
const RENT_ID   = '1VU08t8BKBnUTO9BNNAJyDzZeG3JjsfsUVxYjDjBDSrw';  // 렌탈 시트. 없으면 '' 로 두면 현재 시트에서 찾음
const EVT_ID    = '';        // 이벤트 시트가 별도 파일이면 ID, 같은 파일이면 '' 유지

const SNAP      = '_원본_매출';
const RAW       = '_raw';         // 날짜|채널|매출|환불|순매출        (①+③+④)
const RAW_P     = '_raw_상품';    // 날짜|채널|모델|카테고리|상품명|수량|매출|환불 (②)
const RAW_R     = '_raw_렌탈';    // 날짜|거래처|항목|유형|금액
const RAW_O     = '_raw_주문수';  // 날짜|채널|주문수                  (④)
const TZ        = 'Asia/Seoul';

const CH_ALIAS = {
  '삼성AT스토어': '가전시장',
  '시흥점-매장매출': '매장(시흥)',
  '시흥점-구독매출': '매장구독(시흥)'
};
const CH_GROUP = {
  'P몰':'고도몰','S몰':'고도몰','AT몰':'고도몰','시흥':'고도몰',
  'B2B':'직접/B2B','E스토어':'직접/B2B',
  '쿠팡':'오픈마켓','11번가':'오픈마켓','지마켓':'오픈마켓','옥션':'오픈마켓',
  'SSG':'오픈마켓','롯데온':'오픈마켓','가전시장':'오픈마켓','쿠팡이츠':'오픈마켓',
  '토스쇼핑':'오픈마켓','스마트스토어':'오픈마켓',
  'SK스토아':'홈쇼핑/T커머스','현대홈쇼핑':'홈쇼핑/T커머스',
  '통신판매(VMS)':'통신판매',
  '매장(시흥)':'오프라인','매장구독(시흥)':'오프라인','렌탈':'오프라인'
};
/** Manual 시트(가로형)의 컬럼명 → 원장 채널명 */
const MANUAL_ALIAS = {
  '매장-일시불': '매장(시흥)',
  '매장-구독':   '매장구독(시흥)',
  '매장 일시불': '매장(시흥)',
  '매장 구독':   '매장구독(시흥)'
};

/** 담당자·지점명이 붙어 여러 행으로 갈라진 채널을 하나로 합친다.
 *  합쳐진 뒤에도 원래 꼬리표(담당자)는 '세부'로 남아 상세 화면에서 분해된다.
 *  예) '직판-김차장' '직배송 이과장' → 채널 '직판' / 세부 '김차장' '이과장' */
const MERGE_RULES = [
  { rx: /직배송|직판|직배/, base: '직판' }
];
function mergeCh_(name) {
  const s0 = String(name).trim();
  for (let i = 0; i < MERGE_RULES.length; i++) {
    const m = s0.match(MERGE_RULES[i].rx);
    if (!m) continue;
    // 키워드가 앞이든 뒤든 상관없이 제거하고 남은 부분을 담당자로 본다
    let sub = (s0.slice(0, m.index) + ' ' + s0.slice(m.index + m[0].length))
      .replace(/[\-_·()\[\]]/g, ' ').replace(/\s+/g, ' ').trim();
    sub = sub.replace(/님$/, '').trim();
    return { name: MERGE_RULES[i].base, sub: sub || '미지정' };
  }
  return { name: s0, sub: '' };
}

/** 환불 개념이 없는 채널 — 대시보드의 '환불 미기록' 경고에서 제외 */
const NO_REFUND_CH = { '렌탈':1, '매장구독(시흥)':1 };

const ACC = {
  '고도몰5|pcnik35-P':'P몰',   '고도몰5|pcnik35-S':'S몰',
  '고도몰5|pcnik35-AT':'AT몰', '고도몰5|samsungsh':'시흥'
};
const MALL_NAME = { 'SSG몰':'SSG', '(주)옥션':'옥션', '(주)현대홈쇼핑':'현대홈쇼핑' };
const CANCELLED = {
  '배송전취소':1,'주문취소요청':1,'주문취소완료':1,'주문취소처리중':1,
  '입금전취소':1,'반품요청':1,'반품완료':1,'반품입고':1
};

/* =====================================================================
 * 0. 전체 갱신
 * ===================================================================*/
function refreshAll() {
  const t0 = Date.now();
  if (Session.getScriptTimeZone() !== TZ) {
    Logger.log('⚠ 프로젝트 시간대가 ' + Session.getScriptTimeZone()
      + ' 입니다. 날짜가 하루씩 밀릴 수 있습니다. [프로젝트 설정 → 시간대] 확인 필요.');
  }
  importSalesSheet();
  const r = buildRawTable();      // ① 원장 + ③ VMS + ④ 렌탈 → _raw
  const p = buildRawProducts();   // ② 주문 탭 + VMS 품목 → _raw_상품
  writeOrderCounts_([r.orders, p.orders]);
  const stamp = fmtStamp_(new Date());
  PropertiesService.getDocumentProperties().setProperty('lastRefresh', stamp);
  savePayloadCache_();
  const sec = ((Date.now() - t0) / 1000).toFixed(1);
  const msg = '원장 ' + r.ledger + ' · VMS ' + r.vms + ' · 렌탈 ' + r.rent + ' · 수기 ' + r.manual
    + ' → _raw / 상품 ' + p.rows + '행 (' + p.tabs.length + '개 탭) · ' + sec + '초';
  try { SpreadsheetApp.getActive().toast(msg, '갱신 완료 · ' + stamp, 8); } catch (e) {}
  Logger.log(msg);
  return msg;
}

/* =====================================================================
 * 1. 기존 원장 → 스냅샷
 * ===================================================================*/
function importSalesSheet() {
  const src = SpreadsheetApp.openById(SRC_ID).getSheetByName(SRC_SHEET);
  if (!src) throw new Error('원장에 "' + SRC_SHEET + '" 탭이 없습니다.');
  const values = src.getDataRange().getValues();
  const rows = values.length, cols = values[0].length;
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let dest = ss.getSheetByName(SNAP) || ss.insertSheet(SNAP);
  dest.clear();
  if (dest.getMaxRows()    < rows) dest.insertRowsAfter(dest.getMaxRows(), rows - dest.getMaxRows());
  if (dest.getMaxColumns() < cols) dest.insertColumnsAfter(dest.getMaxColumns(), cols - dest.getMaxColumns());
  dest.getRange(1, 1, rows, cols).setValues(values);
  return { rows: rows, cols: cols };
}

/* =====================================================================
 * 2. 스냅샷 + VMS + 렌탈 → _raw
 * ===================================================================*/
function buildRawTable() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const snap = ss.getSheetByName(SNAP);
  if (!snap) throw new Error(SNAP + ' 탭이 없습니다. importSalesSheet() 먼저.');
  const v = snap.getDataRange().getValues();

  const starts = [];
  for (let i = 0; i < v.length; i++) {
    if (/^\d{1,2}월$/.test(String(v[i][1] || '').trim()) && toDate_(v[i][2])) starts.push(i);
  }
  if (!starts.length) throw new Error('월 블록을 찾지 못했습니다.');

  const out = [];
  let ledger = 0;
  const mergedLog = {};
  const ordSet = {};
  for (let b = 0; b < starts.length; b++) {
    const h = starts[b];
    const end = (b + 1 < starts.length) ? starts[b + 1] : v.length;
    const days = [];
    for (let j = 2; j < v[h].length; j++) {
      const dt = toDate_(v[h][j]);
      if (dt) days.push({ d: dt, j: j });
    }
    if (!days.length) continue;

    /* --- [수정] 이 블록이 실제로 몇 월인지 확정한다 ---------------------
     * v3는 월합계 전용 행을 days[0](= 블록의 첫 칸)에 찍었는데, 캘린더가
     * 주 단위로 정렬돼 있으면 첫 칸이 전월 말일(예: 1월 블록의 2025-12-31)이다.
     * 그래서 원본에서 12월을 지워도 12/31 데이터가 계속 되살아났다.
     * 블록 중앙 날짜로 월을 판정하고, 그 달 1일에 찍는다.               */
    const mid = days[Math.floor(days.length / 2)].d;
    const blockFirst = new Date(mid.getFullYear(), mid.getMonth(), 1);

    for (let i = h + 2; i < end; i++) {
      let name = String(v[i][0] || '').trim();
      if (!name || name === '전체' || name === '합계') continue;
      name = CH_ALIAS[name] || name;
      const mg = mergeCh_(name);
      if (mg.sub) { if (!mergedLog[name]) mergedLog[name] = mg.name; name = mg.name; }
      const sub = mg.sub;
      let daySum = 0, hit = 0;
      for (let k = 0; k < days.length; k++) {
        const j = days[k].j;
        const g = num_(v[i][j]);
        const rf = num_(v[i][j + 1]);
        if (!g && !rf) continue;
        out.push([days[k].d, name, g, rf, g - rf, sub]);
        daySum += g - rf; hit++; ledger++;
      }
      const monthTotal = num_(v[i][1]);
      if (hit === 0 && monthTotal !== 0) {
        out.push([blockFirst, name, monthTotal, 0, monthTotal, sub]);
        ledger++;
      }
    }
  }

  /* --- ③ VMS ---------------------------------------------------------
   * 시트 형식이 두 가지다. 둘 다 자동으로 처리한다.
   *   구형(~6월) : 주문 1건 = 1행,  금액 = 주문금액
   *   신형(7월~) : 품목 1건 = 1행,  금액 = 합계(J열, VAT 포함), 순번 컬럼 있음
   * 신형에서 doc 하나만으로 중복 제거하면 같은 주문의 2번째 품목부터 전부
   * 버려지므로, 순번이 있으면 doc+순번을 키로 쓴다.
   * -------------------------------------------------------------------*/
  let vms = 0;
  let vSheets = findSheetsByHeader_(['일자-No.', '거래처명']);
  if (!vSheets.length) vSheets = findSheetsByHeader_(['일자-No.']);          // 1차 완화
  if (!vSheets.length) {
    // 이름에 vms 가 들어간 탭을 직접 찾는다
    vSheets = ss.getSheets().filter(function (sh) {
      return /vms|통신/i.test(sh.getName()) && sh.getName().charAt(0) !== '_' && sh.getLastRow() > 1;
    });
    if (vSheets.length) Logger.log('VMS 헤더 매칭 실패 → 시트명으로 대체: '
      + vSheets.map(function (x) { return x.getName(); }).join(', '));
  }
  if (!vSheets.length) {
    Logger.log('!! VMS 시트를 찾지 못했습니다. 현재 스프레드시트의 탭 목록:');
    ss.getSheets().forEach(function (sh) {
      const n = sh.getLastColumn();
      Logger.log('   [' + sh.getName() + '] ' + sh.getLastRow() + '행 · 헤더: '
        + (n ? sh.getRange(1, 1, 1, Math.min(n, 12)).getValues()[0].join(' | ') : '(없음)'));
    });
  }
  const vSeen = {};
  for (let t = 0; t < vSheets.length; t++) {
    const w = vSheets[t].getDataRange().getValues();
    const H = colIndex_(w[0]);
    // 금액 컬럼: 합계(J·VAT포함) 우선 → 주문금액(구형) → 공급가액(VAT제외)
    const amtKey = (H['합계']     !== undefined) ? '합계'
                 : (H['주문금액'] !== undefined) ? '주문금액'
                 : (H['공급가액'] !== undefined) ? '공급가액' : null;
    if (amtKey === null) { Logger.log('VMS 금액 컬럼 없음 → 건너뜀: ' + vSheets[t].getName()); continue; }
    const amtCol = H[amtKey];          // [수정] 배열은 이름이 아니라 인덱스로 접근해야 한다
    const docCol = H['일자-No.'], seqCol = H['순번'];
    const hasSeq = seqCol !== undefined;
    let n = 0, skipD = 0, skipA = 0, skipK = 0;
    if (H['일자-No.'] === undefined) { Logger.log('일자-No. 컬럼 없음 → 건너뜀: ' + vSheets[t].getName()); continue; }
    for (let i = 1; i < w.length; i++) {
      const doc = String(w[i][docCol] || '').trim();
      if (!doc) continue;
      const dt = docDate_(doc);
      if (!dt) { skipD++; continue; }
      const key = hasSeq ? (doc + '#' + String(w[i][seqCol] || i)) : doc;
      if (vSeen[key]) { skipK++; continue; }
      vSeen[key] = 1;
      const amt = num_(w[i][amtCol]);
      if (!amt) { skipA++; continue; }
      // J열(합계)이 음수면 환불·할인이다. 매출이 아니라 환불 칸으로 보낸다.
      const g = amt > 0 ? amt : 0, rf = amt < 0 ? -amt : 0;
      out.push([dt, '통신판매(VMS)', g, rf, amt, '']);
      const ok = dkey_(dt) + '|통신판매(VMS)';
      if (!ordSet[ok]) ordSet[ok] = {};
      ordSet[ok][doc] = 1;                 // 전표번호 = 주문 1건
      vms++; n++;
    }
    Logger.log('VMS ' + vSheets[t].getName() + ' · ' + amtKey
      + ' · ' + (hasSeq ? '품목단위' : '주문단위') + ' · 적재 ' + n + '행'
      + ' (스킵 날짜 ' + skipD + ' / 금액0 ' + skipA + ' / 중복 ' + skipK + ')');
  }

  /* --- ④ 렌탈 : 상세는 _raw_렌탈, 일별 합계는 _raw 의 '렌탈' 채널 --- */
  const rent = buildRawRental_();
  const rDaily = {};
  for (let i = 0; i < rent.rows.length; i++) {
    const k = rent.rows[i][0].getTime();
    rDaily[k] = (rDaily[k] || 0) + rent.rows[i][4];
  }
  Object.keys(rDaily).forEach(function (k) {
    out.push([new Date(+k), '렌탈', rDaily[k], 0, rDaily[k], '']);
  });

  /* --- ⑤ Manual 시트 : 원장에 이미 있는 (날짜·채널·담당자) 는 건너뛴다 --- */
  const seenLK = {};
  for (let i = 0; i < out.length; i++) seenLK[dkey_(out[i][0]) + '|' + out[i][1] + '|' + (out[i][5] || '')] = 1;
  const man = readManual_();
  let manAdd = 0, manDup = 0;
  for (let i = 0; i < man.length; i++) {
    const k = dkey_(man[i][0]) + '|' + man[i][1] + '|' + (man[i][5] || '');
    if (seenLK[k]) { manDup++; continue; }
    seenLK[k] = 1;
    out.push(man[i]);
    manAdd++;
  }
  Logger.log('Manual 시트 → 추가 ' + manAdd + '행 / 원장과 중복이라 제외 ' + manDup + '행');

  out.sort(function (a, b) { return a[0] - b[0] || (a[1] < b[1] ? -1 : 1); });
  writeSheet_(RAW, ['날짜','채널','매출','환불','순매출','세부'], out, { dateCols: [1], numCols: [3, 3] });
  const mk = Object.keys(mergedLog);
  if (mk.length) Logger.log('채널 병합: ' + mk.map(function (k) { return k + ' → ' + mergedLog[k]; }).join(', '));
  const orders = {};
  Object.keys(ordSet).forEach(function (k) { orders[k] = Object.keys(ordSet[k]).length; });
  return { ledger: ledger, vms: vms, rent: rent.rows.length, manual: manAdd, orders: orders };
}

/* =====================================================================
 * 2b. 렌탈 시트 → _raw_렌탈
 *     계약 단위가 아니라 '월 발생 청구' 단위. 청구시작일에 귀속시킨다.
 * ===================================================================*/
function buildRawRental_() {
  let sheets = [];
  if (RENT_ID) {
    const ss = SpreadsheetApp.openById(RENT_ID);
    sheets = ss.getSheets().filter(function (sh) {
      if (sh.getLastRow() < 2) return false;
      const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0]
        .map(function (x) { return String(x || '').replace(/\s/g, ''); });
      return head.indexOf('청구시작일') >= 0 && head.indexOf('금액') >= 0;
    });
  }
  if (!sheets.length) sheets = findSheetsByHeader_(['청구시작일', '거래처', '금액']);

  const rows = [], seen = {};
  let far = 0, noDate = 0;
  for (let t = 0; t < sheets.length; t++) {
    const v = sheets[t].getDataRange().getValues();
    const H = colIndex_(v[0]);
    for (let i = 1; i < v.length; i++) {
      const no = String(v[i][H['계약번호']] || '').trim();
      /* [중요] 귀속일은 계약번호 앞부분(전표 발생일)을 쓴다.
       * 청구시작일 = 계약 개시일이라 2018년처럼 과거로 튀고,
       * 청구종료일 = 계약 만료일이라 2031년처럼 미래로 튄다.
       * 둘 다 '이번 달에 발생한 청구'를 나타내지 못한다. */
      let dt = docDate_(no);
      const st = toDate_(v[i][H['청구시작일']]) || ymdToDate_(v[i][H['청구시작일']]);
      if (!dt) { dt = st; }              // 계약번호가 비면 청구시작일로 대체
      else if (st && Math.abs(dt - st) > 45 * 864e5) far++;   // 계약 개시일과 크게 다른 건수
      if (!dt) { noDate++; continue; }
      const amt = Math.round(num_(v[i][H['금액']]));
      if (!amt) continue;
      const cust = String(v[i][H['거래처']] || '미상').trim();
      const item = String(v[i][H['항목']] || '기타').trim();
      const type = String(v[i][H['유형']] || '미지정').trim();
      const key = no || (dkey_(dt) + '|' + cust + '|' + item + '|' + amt);
      if (seen[key]) continue;
      seen[key] = 1;
      rows.push([dt, cust, item, type, amt]);
    }
  }
  Logger.log('렌탈 ' + rows.length + '건 (계약번호 기준 귀속) · 청구시작일과 45일 이상 차이 '
    + far + '건 · 날짜 없음 ' + noDate + '건');
  rows.sort(function (a, b) { return a[0] - b[0]; });
  writeSheet_(RAW_R, ['날짜','거래처','항목','유형','금액'], rows, { dateCols: [1], numCols: [5, 1] });
  return { rows: rows };
}

/* =====================================================================
 * 2d. Manual 시트 (가로형: 날짜 | 매장-일시불 | 매장-구독 | OOO-직판 ...)
 *     원장에 없는 매장·직판 실적을 수기로 채우는 표. 세로로 펴서 _raw 에 넣는다.
 * ===================================================================*/
function readManual_() {
  let sheets = [];
  if (RENT_ID) {
    sheets = SpreadsheetApp.openById(RENT_ID).getSheets().filter(function (sh) {
      return /manual|매뉴얼|수기/i.test(sh.getName()) && sh.getLastRow() > 1;
    });
  }
  if (!sheets.length) {
    sheets = SpreadsheetApp.getActiveSpreadsheet().getSheets().filter(function (sh) {
      return /manual|매뉴얼|수기/i.test(sh.getName())
        && sh.getName().charAt(0) !== '_' && sh.getLastRow() > 1;
    });
  }
  const rows = [];
  for (let t = 0; t < sheets.length; t++) {
    const v = sheets[t].getDataRange().getValues();
    const head = v[0].map(function (x) { return String(x || '').trim(); });

    /* IMPORTRANGE 가드 — 로딩 중이거나 오류면 0 이 아니라 '읽지 않음' 으로 처리한다.
     * 그대로 진행하면 그 회차 갱신에서 매장·직판이 통째로 0 으로 들어간다. */
    let bad = '';
    for (let i = 0; i < Math.min(v.length, 400) && !bad; i++) {
      for (let j = 0; j < v[i].length; j++) {
        const c = String(v[i][j]);
        if (c === '#N/A' || c === '#REF!' || c === '#ERROR!' || /^Loading/i.test(c)) { bad = c; break; }
      }
    }
    if (bad) throw new Error('Manual 시트가 아직 준비되지 않았습니다 (' + bad + ').'
      + ' IMPORTRANGE 로딩이 끝난 뒤 다시 갱신하세요. 기존 데이터는 그대로 유지됩니다.');

    let dcol = -1;
    for (let j = 0; j < head.length; j++) if (/^(날짜|일자)/.test(head[j])) { dcol = j; break; }
    if (dcol < 0) { Logger.log('Manual [' + sheets[t].getName() + '] 날짜 컬럼 없음'); continue; }

    /* 컬럼 짝짓기 : 'X' = 매출, 'X_환불' = 환불 */
    const base = {};
    for (let j = 0; j < head.length; j++) {
      if (j === dcol || !head[j]) continue;
      const m = head[j].match(/^(.*?)[ _-]*환불$/);
      if (m && m[1]) {
        const k = m[1].trim();
        if (!base[k]) base[k] = {};
        base[k].r = j;
      } else {
        if (!base[head[j]]) base[head[j]] = {};
        base[head[j]].g = j;
      }
    }
    const cols = [];
    Object.keys(base).forEach(function (k) {
      if (base[k].g === undefined) return;            // 환불 열만 있고 매출 열이 없으면 무시
      const nm0 = MANUAL_ALIAS[k] || k;
      const mg = mergeCh_(nm0);
      cols.push({ g: base[k].g, r: base[k].r, name: mg.name, sub: mg.sub, raw: k });
    });

    for (let i = 1; i < v.length; i++) {
      const dt = toDate_(v[i][dcol]) || ymdToDate_(v[i][dcol]);
      if (!dt) continue;
      for (let c = 0; c < cols.length; c++) {
        const g = Math.round(num_(v[i][cols[c].g]));
        const rf = cols[c].r === undefined ? 0 : Math.round(num_(v[i][cols[c].r]));
        if (!g && !rf) continue;
        rows.push([dt, cols[c].name, g, rf, g - rf, cols[c].sub]);
      }
    }
    Logger.log('Manual [' + sheets[t].getName() + '] 컬럼: '
      + cols.map(function (c) {
          return c.raw + '→' + c.name + (c.sub ? '/' + c.sub : '')
            + (c.r === undefined ? ' (환불열 없음)' : '');
        }).join(', '));
  }
  return rows;
}

/* =====================================================================
 * 2c. 이벤트 시트 (선택) — 시작일|종료일|이벤트명|채널(선택)
 * ===================================================================*/
function readEvents_() {
  let sheets = [];
  if (EVT_ID) {
    sheets = SpreadsheetApp.openById(EVT_ID).getSheets().filter(function (sh) {
      if (sh.getLastRow() < 2) return false;
      const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0]
        .map(function (x) { return String(x || '').replace(/\s/g, ''); });
      return head.indexOf('시작일') >= 0 && head.indexOf('이벤트명') >= 0;
    });
  }
  if (!sheets.length) sheets = findSheetsByHeader_(['시작일', '이벤트명']);
  const out = [];
  for (let t = 0; t < sheets.length; t++) {
    const v = sheets[t].getDataRange().getValues();
    const H = colIndex_(v[0]);
    for (let i = 1; i < v.length; i++) {
      const s = toDate_(v[i][H['시작일']]);
      if (!s) continue;
      const e = toDate_(v[i][H['종료일']]) || s;
      const nm = String(v[i][H['이벤트명']] || '').trim();
      if (!nm) continue;
      out.push([dkey_(s), dkey_(e), nm, String(v[i][H['채널']] || '').trim()]);
    }
  }
  return out;
}

/* =====================================================================
 * 3. 주문 탭 → _raw_상품
 * ===================================================================*/
function buildRawProducts() {
  const oSheets = findSheetsByHeader_(['주문일자', '쇼핑몰', '상품코드', '주문금액']);
  const out = [], seen = {}, tabNames = [], ordSet = {};
  for (let t = 0; t < oSheets.length; t++) {
    tabNames.push(oSheets[t].getName());
    const v = oSheets[t].getDataRange().getValues();
    const H = colIndex_(v[0]);
    for (let i = 1; i < v.length; i++) {
      const r = v[i];
      const dt = ymdToDate_(r[H['주문일자']]);
      if (!dt) continue;
      const orderNo = String(r[H['주문번호']] || '').trim();
      const goods = String(r[H['상품코드']] || '').trim();
      const key = orderNo + '|' + goods + '|' + String(r[H['옵션']] || '');
      if (orderNo && seen[key]) continue;
      seen[key] = 1;
      const mall = String(r[H['쇼핑몰']] || '').trim();
      const acc = String(r[H['쇼핑몰아이디']] || '').trim();
      const ch = ACC[mall + '|' + acc] || MALL_NAME[mall] || mall || '기타';
      const name = String(r[H['자사 상품명']] || r[H['주문 상품명']] || '').trim();
      const model = resolveModel_(r[H['모델명']], r[H['거래처 상품코드']], name);
      if (!model) continue;
      const cat = classify_(name, model);
      const amt = num_(r[H['주문금액']]);
      const qty = Math.max(1, Math.round(num_(r[H['수량']])) || 1);
      const cancelled = !!CANCELLED[String(r[H['배송상태']] || '').trim()];
      out.push([dt, ch, model, cat, name.slice(0, 60),
                cancelled ? 0 : qty, amt, cancelled ? amt : 0]);
      if (orderNo) {                            // 주문번호 = 주문 1건
        const ok = dkey_(dt) + '|' + ch;
        if (!ordSet[ok]) ordSet[ok] = {};
        ordSet[ok][orderNo] = 1;
      }
    }
  }
  /* --- VMS 품목(E열)도 상품 분해에 넣는다. 모델코드가 그대로 들어있다 --- */
  const vSheets = findSheetsByHeader_(['일자-No.', '거래처명']);
  for (let t = 0; t < vSheets.length; t++) {
    const w = vSheets[t].getDataRange().getValues();
    const H = colIndex_(w[0]);
    const amtCol = (H['합계'] !== undefined) ? H['합계']
                 : (H['주문금액'] !== undefined) ? H['주문금액'] : H['공급가액'];
    if (amtCol === undefined) continue;
    const docCol = H['일자-No.'], seqCol = H['순번'];
    const nmCol = (H['품목명(규격)'] !== undefined) ? H['품목명(규격)'] : H['품목명(요약)'];
    if (nmCol === undefined) continue;
    const vSeen2 = {};
    let vn = 0;
    for (let i = 1; i < w.length; i++) {
      const doc = String(w[i][docCol] || '').trim();
      const dt = docDate_(doc);
      if (!dt) continue;
      const key = (seqCol !== undefined) ? (doc + '#' + String(w[i][seqCol] || i)) : (doc + '#' + i);
      if (vSeen2[key]) continue;
      vSeen2[key] = 1;
      const amt = num_(w[i][amtCol]);
      if (!amt) continue;
      const nm = String(w[i][nmCol] || '').trim();
      const model = resolveModel_('', '', nm);
      if (!model) continue;                      // 포인트할인 등 모델 없는 행은 제외
      const qty = Math.max(1, Math.round(num_(w[i][H['수량']])) || 1);
      out.push([dt, '통신판매(VMS)', model, classify_(nm, model), nm.slice(0, 60),
                amt > 0 ? qty : 0, amt > 0 ? amt : 0, amt < 0 ? -amt : 0]);
      vn++;
    }
    if (vn) { tabNames.push(vSheets[t].getName() + '(VMS)'); Logger.log('VMS 상품 ' + vn + '행'); }
  }

  out.sort(function (a, b) { return a[0] - b[0]; });
  writeSheet_(RAW_P, ['날짜','채널','모델','카테고리','상품명','수량','매출','환불'], out,
              { dateCols: [1], numCols: [6, 3] });
  const orders = {};
  Object.keys(ordSet).forEach(function (k) { orders[k] = Object.keys(ordSet[k]).length; });
  return { rows: out.length, tabs: tabNames, orders: orders };
}

/** 날짜×채널 주문 건수 → _raw_주문수 */
function writeOrderCounts_(maps) {
  const m = {};
  maps.forEach(function (o) {
    if (!o) return;
    Object.keys(o).forEach(function (k) { m[k] = (m[k] || 0) + o[k]; });
  });
  const rows = Object.keys(m).sort().map(function (k) {
    const p = k.split('|');
    return [new Date(p[0] + 'T00:00:00'), p[1], m[k]];
  });
  writeSheet_(RAW_O, ['날짜','채널','주문수'], rows, { dateCols: [1], numCols: [3, 1] });
  Logger.log('주문수 ' + rows.length + '행');
  return rows.length;
}

/* =====================================================================
 * 4. 모델코드 · 카테고리
 * ===================================================================*/
const RX_HYPHEN = /\b([A-Z]{2,4}-[A-Z0-9]{3,}(?:\/[A-Z0-9]{2,})?)\b/;
const RX_PLAIN  = /\b([A-Z]{2,3}\d{2,}[A-Z0-9]{2,}(?:\/[A-Z0-9]{2,})?)\b/;
const RX_UNIT   = /^\d+(KG|G|L|ML|MM|CM|M|GB|TB|W|EA|매|인치|형)$/i;
const STOPWORDS = {AI:1,TV:1,LED:1,QLED:1,OLED:1,UHD:1,FHD:1,HDMI:1,USB:1,WIFI:1,BESPOKE:1,SSD:1,NEW:1,MAX:1,PRO:1,PLUS:1,KR:1,TYPE:1,SET:1};
function looksModel_(v) {
  const s = String(v || '').trim().toUpperCase();
  if (!s || s === 'NAN' || /^\d+$/.test(s)) return '';
  if (s.length < 5 || !/[A-Z]/.test(s) || !/\d/.test(s)) return '';
  return s;
}
function fromName_(name) {
  const s = String(name || '').toUpperCase().replace(/[(),\[\]]/g, ' ');
  const rxs = [RX_HYPHEN, RX_PLAIN];
  for (let k = 0; k < rxs.length; k++) {
    const parts = s.split(/\s+/);
    for (let i = 0; i < parts.length; i++) {
      const m = parts[i].match(rxs[k]);
      if (m && !STOPWORDS[m[1]] && !RX_UNIT.test(m[1]) && m[1].length >= 5) return m[1];
    }
  }
  return '';
}
function resolveModel_(modelCol, vendorCode, name) {
  return looksModel_(modelCol) || looksModel_(vendorCode) || fromName_(name);
}
function classify_(name, model) {
  const s = String(name || ''), m = String(model || '');
  const has = function (arr) { for (let i = 0; i < arr.length; i++) if (s.indexOf(arr[i]) >= 0) return true; return false; };
  const pre = function (arr) { for (let i = 0; i < arr.length; i++) if (m.indexOf(arr[i]) === 0) return true; return false; };
  if (has(['토너','잉크','드럼']) || pre(['CLT-','MLT-','INK-'])) return '토너·잉크';
  if (s.indexOf('필터') >= 0 || pre(['HAF','SBF','PC4N'])) return '필터·소모품';
  if (s.indexOf('리모컨') >= 0 || pre(['AFR-','ARR-'])) return '리모컨·액세서리';
  if (has(['프린터','복합기']) || pre(['SL-'])) return '프린터·복합기';
  if (has(['냉장고','김치','4도어','양문형','하이브리드']) || pre(['RM','RS','RQ','RB','RF','RT','RR','RZ'])) return '냉장고·김치냉장고';
  if (has(['세탁','건조','콤보','원바디','에어드레서']) || pre(['WF','WA','WD','WH','DV','DF'])) return '세탁·건조';
  if (has(['TV','QLED','OLED','더 프레임','프로젝터','더 프리미어','사운드바']) || pre(['KQ','KU','SP-','HW-'])) return 'TV·영상·음향';
  if (has(['에어컨','공기청정기']) || pre(['AR','AF','AJ','AN','AP'])) return '에어컨·공청';
  if (has(['청소기','제트']) || pre(['VS','VR','VC'])) return '청소기';
  if (s.indexOf('정수기') >= 0 || pre(['RWP'])) return '정수기';
  if (has(['갤럭시','버즈','워치']) || pre(['SM-','EJ-'])) return '모바일·웨어러블';
  if (has(['식기세척','인덕션','전자레인지','오븐','쿡탑','큐커','전기레인지']) || pre(['DW','CC','MO','NQ','MG'])) return '주방가전';
  if (has(['노트북','데스크탑','모니터','갤럭시 북']) || pre(['NT','DM','LS','LC'])) return 'PC·모니터';
  return '기타';
}

/* =====================================================================
 * 5. payload
 *    [성능] Utilities.formatDate 전면 제거 → dkey_() 로컬 캐시
 * ===================================================================*/
function buildPayload() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const raw = ss.getSheetByName(RAW);
  if (!raw || raw.getLastRow() < 2) throw new Error(RAW + ' 이 비어 있습니다. refreshAll() 을 실행하세요.');
  const rv = raw.getRange(2, 1, raw.getLastRow() - 1, 6).getValues();
  const rp = ss.getSheetByName(RAW_P);
  const pv = (rp && rp.getLastRow() > 1) ? rp.getRange(2, 1, rp.getLastRow() - 1, 8).getValues() : [];
  const ro = ss.getSheetByName(RAW_O);
  const rvo = (ro && ro.getLastRow() > 1) ? ro.getRange(2, 1, ro.getLastRow() - 1, 3).getValues() : [];
  const rr = ss.getSheetByName(RAW_R);
  const rvr = (rr && rr.getLastRow() > 1) ? rr.getRange(2, 1, rr.getLastRow() - 1, 5).getValues() : [];

  // 날짜 합집합 (채널 + 렌탈. 상품은 월 단위라 제외)
  const daySet = {};
  for (let i = 0; i < rv.length; i++)  if (rv[i][0] instanceof Date)  daySet[dkey_(rv[i][0])] = 1;
  for (let i = 0; i < rvr.length; i++) if (rvr[i][0] instanceof Date) daySet[dkey_(rvr[i][0])] = 1;
  const days = Object.keys(daySet).sort();
  const dayIdx = {};
  for (let i = 0; i < days.length; i++) dayIdx[days[i]] = i;

  const chIdx = {}, chans = [];
  function ch(cn) {
    if (chIdx[cn] === undefined) {
      chIdx[cn] = chans.length;
      chans.push({ name: cn, group: CH_GROUP[cn] || '기타', norefund: !!NO_REFUND_CH[cn] });
    }
    return chIdx[cn];
  }

  const cellMap = {};
  const subNames = [], subIdx = {}, subMap = {};
  for (let i = 0; i < rv.length; i++) {
    const r = rv[i];
    if (!(r[0] instanceof Date)) continue;
    const di = dayIdx[dkey_(r[0])];
    const ci = ch(String(r[1]).trim());
    const g = Math.round(num_(r[2])), rf = Math.round(num_(r[3]));
    const k = di + '_' + ci;
    if (!cellMap[k]) cellMap[k] = [di, ci, 0, 0];
    cellMap[k][2] += g;
    cellMap[k][3] += rf;
    const sub = String(r[5] || '').trim();
    if (sub) {
      if (subIdx[sub] === undefined) { subIdx[sub] = subNames.length; subNames.push(sub); }
      const sk = di + '_' + ci + '_' + subIdx[sub];
      if (!subMap[sk]) subMap[sk] = [di, ci, subIdx[sub], 0, 0];
      subMap[sk][3] += g;
      subMap[sk][4] += rf;
    }
  }

  // 상품은 월 단위 압축
  const pmIdx = {}, pmonths = [], prIdx = {}, prods = [], pcellMap = {};
  for (let i = 0; i < pv.length; i++) {
    const r = pv[i];
    if (!(r[0] instanceof Date)) continue;
    const mo = dkey_(r[0]).slice(0, 7);
    if (pmIdx[mo] === undefined) { pmIdx[mo] = pmonths.length; pmonths.push(mo); }
    const mi = pmIdx[mo];
    const ci = ch(String(r[1]).trim());
    const model = String(r[2]).trim();
    if (!model) continue;
    if (prIdx[model] === undefined) {
      prIdx[model] = prods.length;
      prods.push([model, String(r[4] || model), String(r[3] || '기타')]);
    } else {
      const cur = prods[prIdx[model]];
      const nm = String(r[4] || '');
      if (nm && nm.length < cur[1].length) cur[1] = nm;
    }
    const k = mi + '_' + ci + '_' + prIdx[model];
    if (!pcellMap[k]) pcellMap[k] = [mi, ci, prIdx[model], 0, 0, 0];
    pcellMap[k][3] += num_(r[5]);
    pcellMap[k][4] += Math.round(num_(r[6]));
    pcellMap[k][5] += Math.round(num_(r[7]));
  }

  // 렌탈 상세 — 문자열은 사전으로 빼서 payload 축소
  const rItems = [], rTypes = [], rCusts = [], rRows = [];
  const ix = function (arr, map, v) {
    if (map[v] === undefined) { map[v] = arr.length; arr.push(v); }
    return map[v];
  };
  const mI = {}, mT = {}, mC = {};
  for (let i = 0; i < rvr.length; i++) {
    const r = rvr[i];
    if (!(r[0] instanceof Date)) continue;
    const di = dayIdx[dkey_(r[0])];
    if (di === undefined) continue;
    rRows.push([di, ix(rItems, mI, String(r[2] || '기타')),
                ix(rTypes, mT, String(r[3] || '미지정')),
                ix(rCusts, mC, String(r[1] || '미상')),
                Math.round(num_(r[4]))]);
  }

  return {
    days: days,
    channels: chans,
    cells: Object.keys(cellMap).map(function (k) { return cellMap[k]; }),
    products: prods,
    pmonths: pmonths,
    pcells: Object.keys(pcellMap).map(function (k) { return pcellMap[k]; }),
    rental: rRows.length ? { rows: rRows, items: rItems, types: rTypes, custs: rCusts } : null,
    ocells: (function () {
      const out2 = [];
      for (let i = 0; i < rvo.length; i++) {
        const r = rvo[i];
        if (!(r[0] instanceof Date)) continue;
        const di = dayIdx[dkey_(r[0])];
        if (di === undefined) continue;
        const cn = String(r[1]).trim();
        if (chIdx[cn] === undefined) continue;
        out2.push([di, chIdx[cn], Math.round(num_(r[2]))]);
      }
      return out2;
    })(),
    subs: subNames.length ? { names: subNames, rows: Object.keys(subMap).map(function (k) { return subMap[k]; }) } : null,
    events: readEvents_(),
    updated: PropertiesService.getDocumentProperties().getProperty('lastRefresh') || ''
  };
}

/* =====================================================================
 * 5b. payload 캐시
 *     CacheService 최대 TTL 이 6시간이라 갱신(06시) 후 18시간은 캐시가 빈다.
 *     → 4시간마다 워밍하는 트리거를 setDailyTrigger() 가 함께 건다.
 * ===================================================================*/
const CACHE_TTL = 21600;
const CHUNK = 90000;

function savePayloadCache_() {
  const json = JSON.stringify(buildPayload());
  const cache = CacheService.getDocumentCache();
  const parts = {};
  let n = 0;
  for (let i = 0; i < json.length; i += CHUNK) { parts['pl_' + n] = json.substr(i, CHUNK); n++; }
  parts['pl_meta'] = String(n);
  cache.putAll(parts, CACHE_TTL);
  Logger.log('payload cached: ' + (json.length / 1048576).toFixed(2) + ' MB / ' + n + ' chunk');
  return json;
}
function loadPayloadJson_() {
  const cache = CacheService.getDocumentCache();
  const meta = cache.get('pl_meta');
  if (meta) {
    const n = parseInt(meta, 10), keys = [];
    for (let i = 0; i < n; i++) keys.push('pl_' + i);
    const got = cache.getAll(keys);
    let json = '', ok = true;
    for (let i = 0; i < n; i++) {
      const p = got['pl_' + i];
      if (p === undefined || p === null) { ok = false; break; }
      json += p;
    }
    if (ok) return json;
  }
  return savePayloadCache_();
}

/* =====================================================================
 * 6. Web app / 메뉴 / 트리거
 *    ※ v4.1: ALLOW_EMAILS 화이트리스트 제거. URL 을 아는 사람은 누구나 열람.
 * ===================================================================*/
/** 외부 사이트(db.samsungat.co.kr/dash)가 payload 를 받아갈 때 쓰는 비밀번호.
 *  변경하려면 [프로젝트 설정 → 스크립트 속성] 에 sharePassword 를 추가한다. */
const SHARE_PW_KEY     = 'sharePassword';
const SHARE_PW_DEFAULT = '3166';
function sharePw_() {
  return PropertiesService.getScriptProperties().getProperty(SHARE_PW_KEY) || SHARE_PW_DEFAULT;
}

function renderDashboard_() {
  const json = loadPayloadJson_();
  // [수정] 문자열 인자를 쓰면 json 안의 $& $' $1 이 치환 패턴으로 해석돼
  //        상품명·거래처명에 $ 가 하나만 있어도 payload 가 조용히 깨진다.
  return HtmlService.createHtmlOutputFromFile('Dashboard').getContent()
    .replace('__DATA__', function () { return json; });
}

function doGet(e) {
  e = e || { parameter: {} };
  const p = e.parameter || {};

  /* ── 외부 공유 JSON : /exec?json=1&pw=3166 ─────────────────────── */
  if (String(p.json || '') === '1') {
    const ok = String(p.pw || '') === sharePw_();
    const body = ok ? loadPayloadJson_() : JSON.stringify({ error: 'unauthorized' });
    return ContentService.createTextOutput(body).setMimeType(ContentService.MimeType.JSON);
  }

  /* ── 대시보드 HTML : 계정 검사 없음 ───────────────────────────── */
  return HtmlService.createHtmlOutput(renderDashboard_())
    .setTitle('매출 대시보드')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

/* =====================================================================
 * 6c. 대시보드에서 갱신 실행 (비밀번호)
 *   · 비밀번호는 HTML 에 두지 않는다. 스크립트 속성에 저장하고 서버에서만 비교한다.
 *   · 최초 1회 메뉴 [갱신 비밀번호 설정] 으로 지정.
 *   · v4.1: 익명 배포에서는 접속자 이메일이 빈 값이므로 횟수 카운터를
 *           이메일별 → 문서 공용 키로 바꿨다.
 * ===================================================================*/
const PW_KEY   = 'refreshPassword';
const PW_DEFAULT = '3033';     // 메뉴에서 설정하지 않았을 때 쓰는 기본값
const FREE_RUNS  = 5;          // 이 횟수까지는 비밀번호 없이 실행
const SESSION_TTL = 21600;     // 세션 기준 6시간 (CacheService 최대)

function currentPw_() {
  return PropertiesService.getDocumentProperties().getProperty(PW_KEY) || PW_DEFAULT;
}
/** 갱신 횟수 카운터 키. 로그인 사용자는 계정별, 익명은 공용. */
function rfKey_() {
  // 익명(모든 사용자) 배포에서는 이메일이 빈 값이거나 조회 자체가 막힐 수 있다.
  let who = '';
  try { who = String(Session.getActiveUser().getEmail() || '').toLowerCase(); } catch (e) { who = ''; }
  return 'rfN_' + (who || 'anon');
}
function setRefreshPassword() {
  const ui = SpreadsheetApp.getUi();
  const r = ui.prompt('갱신 비밀번호 설정',
    '한 세션에 ' + FREE_RUNS + '회를 넘겨 갱신할 때 요구할 비밀번호입니다.\n'
    + '(빈칸으로 두면 기본값 ' + PW_DEFAULT + ' 이 사용됩니다)',
    ui.ButtonSet.OK_CANCEL);
  if (r.getSelectedButton() !== ui.Button.OK) return;
  const pw = String(r.getResponseText() || '').trim();
  const props = PropertiesService.getDocumentProperties();
  if (!pw) { props.deleteProperty(PW_KEY); ui.alert('기본값(' + PW_DEFAULT + ')으로 되돌렸습니다.'); return; }
  props.setProperty(PW_KEY, pw);
  ui.alert('설정되었습니다.');
}
/** 사용 횟수 초기화 (메뉴) */
function resetRefreshCount() {
  const cache = CacheService.getDocumentCache();
  cache.remove(rfKey_());
  cache.remove('rfN_anon');
  try { SpreadsheetApp.getActive().toast('갱신 횟수를 초기화했습니다.', '완료', 5); } catch (e) {}
}

/** 대시보드에서 호출 (google.script.run)
 *  · 세션(6시간) 기준 FREE_RUNS 회까지는 비밀번호 없이 실행
 *  · 초과하면 needPw 를 돌려주고, 올바른 비밀번호가 와야 실행
 *  · v4.1: 계정 화이트리스트 검사 삭제 */
function refreshFromUI(pw) {
  const cache = CacheService.getDocumentCache();
  const key = rfKey_();
  const used = parseInt(cache.get(key) || '0', 10);

  /* ── 비밀번호 검사 (완전히 없애려면 이 블록만 삭제) ────────────── */
  if (used >= FREE_RUNS) {
    if (String(pw || '') !== currentPw_()) {
      return { ok: false, needPw: true, used: used, free: FREE_RUNS,
        msg: pw ? '비밀번호가 올바르지 않습니다.'
                : '이 세션에서 ' + used + '회 갱신했습니다. 계속하려면 비밀번호를 입력하세요.' };
    }
  }
  /* ─────────────────────────────────────────────────────────────── */

  const lock = LockService.getDocumentLock();
  if (!lock.tryLock(2000)) return { ok: false, msg: '다른 사용자가 갱신 중입니다. 잠시 후 다시 시도하세요.' };
  try {
    const msg = refreshAll();
    cache.put(key, String(used + 1), SESSION_TTL);
    return { ok: true, msg: msg, used: used + 1, free: FREE_RUNS,
      remain: Math.max(0, FREE_RUNS - (used + 1)),
      updated: PropertiesService.getDocumentProperties().getProperty('lastRefresh') || '' };
  } catch (e) {
    return { ok: false, msg: '갱신 중 오류: ' + (e && e.message ? e.message : e) };
  } finally {
    lock.releaseLock();
  }
}

function onOpen() {
  SpreadsheetApp.getUi().createMenu('매출 대시보드')
    .addItem('📊 대시보드 보기', 'showDashboardInSheet')
    .addSeparator()
    .addItem('데이터 갱신', 'refreshAll')
    .addItem('🔑 갱신 비밀번호 설정', 'setRefreshPassword')
    .addItem('갱신 횟수 초기화', 'resetRefreshCount')
    .addItem('자동 갱신 켜기 (한국시간 06시 + 워밍)', 'setDailyTrigger')
    .addItem('시간대·트리거 점검', 'tzCheck')
    .addItem('payload 크기 확인', 'sizeCheck')
    .addItem('채널 목록 확인', 'chList')
    .addItem('VMS 추출 점검', 'vmsProbe')
    .addItem('VMS 월별 검증', 'vmsCheck')
    .addItem('렌탈 시트 점검', 'rentCheck')
    .addItem('Manual 시트 점검', 'manualCheck')
    .addItem('이상 날짜 점검', 'outlierCheck')
    .addToUi();
}
function showDashboardInSheet() {
  SpreadsheetApp.getUi().showModalDialog(
    HtmlService.createHtmlOutput(renderDashboard_()).setWidth(1600).setHeight(1000), '매출 대시보드');
}
/** 갱신 06시 + 캐시 워밍 5회. 전부 한국 시각 기준으로 고정한다.
 *  everyHours() 는 시간대를 못 받고 생성 시점부터 흘러가며 밀리므로 쓰지 않는다.
 *  CacheService TTL 이 6시간이라 4시간 간격이면 빈틈이 없다. */
const WARM_HOURS = [2, 10, 14, 18, 22];

function setDailyTrigger() {
  const tz = Session.getScriptTimeZone();
  if (tz !== TZ) {
    const msg = '프로젝트 시간대가 ' + tz + ' 입니다.\n'
      + '[프로젝트 설정 → 시간대] 를 (GMT+09:00) 한국 표준시로 바꾼 뒤 다시 실행하세요.\n'
      + '그대로 두면 트리거 시각이 어긋나고, 저장되는 날짜도 하루씩 밀립니다.';
    Logger.log(msg);
    try { SpreadsheetApp.getUi().alert(msg); } catch (e) {}
    return;
  }
  ScriptApp.getProjectTriggers().forEach(function (t) {
    const f = t.getHandlerFunction();
    if (f === 'refreshAll' || f === 'savePayloadCache_') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('refreshAll').timeBased()
    .atHour(6).nearMinute(10).everyDays(1).inTimezone(TZ).create();
  WARM_HOURS.forEach(function (h) {
    ScriptApp.newTrigger('savePayloadCache_').timeBased()
      .atHour(h).nearMinute(10).everyDays(1).inTimezone(TZ).create();
  });
  const msg = '한국 시각 기준 · 갱신 06시 · 캐시 워밍 ' + WARM_HOURS.join('/') + '시';
  Logger.log(msg);
  try { SpreadsheetApp.getActive().toast(msg, '트리거 등록 완료', 8); } catch (e) {}
}

/** 시간대와 등록된 트리거를 한 번에 점검한다 */
function tzCheck() {
  const stz = Session.getScriptTimeZone();
  const ftz = SpreadsheetApp.getActive().getSpreadsheetTimeZone();
  Logger.log('스크립트 시간대 : ' + stz + (stz === TZ ? '  ✓' : '  ✗ 한국 표준시로 변경 필요'));
  Logger.log('스프레드시트    : ' + ftz + (ftz === TZ ? '  ✓' : '  ✗ 권장: 한국 표준시'));
  const now = new Date();
  Logger.log('스크립트가 보는 현재 시각 : ' + fmtStamp_(now) + ' (' + now.getHours() + '시)');
  Logger.log('실제 한국 시각           : ' + Utilities.formatDate(now, TZ, 'yyyy-MM-dd HH:mm'));
  const ts = ScriptApp.getProjectTriggers();
  Logger.log('등록된 트리거 ' + ts.length + '개');
  ts.forEach(function (t) {
    Logger.log('  · ' + t.getHandlerFunction() + ' / ' + t.getEventType());
  });
  Logger.log('참고: GAS 시간 트리거는 지정 시각 전후 약 15분 창에서 실행됩니다. 분 단위 정시 실행은 보장되지 않습니다.');
}

function sizeCheck() {
  const t0 = Date.now();
  const p = buildPayload();
  const json = JSON.stringify(p);
  Logger.log('buildPayload: ' + ((Date.now() - t0) / 1000).toFixed(1) + '초');
  Logger.log('payload: ' + (json.length / 1048576).toFixed(2) + ' MB');
  Logger.log('days ' + p.days.length + ' / ch ' + p.channels.length + ' / cells ' + p.cells.length
    + ' / prod ' + p.products.length + ' / pcells ' + p.pcells.length
    + ' / rental ' + (p.rental ? p.rental.rows.length : 0) + ' / events ' + p.events.length
    + ' / orders ' + p.ocells.length
    + ' / subs ' + (p.subs ? p.subs.names.length + '종 ' + p.subs.rows.length + '행' : '0'));
}

/* =====================================================================
 * 6b. 진단
 * ===================================================================*/
/** VMS 추출만 따로 돌려서 어디서 끊기는지 본다. _raw 는 건드리지 않는다. */
function vmsProbe() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  Logger.log('활성 파일: ' + ss.getName());
  let v1 = findSheetsByHeader_(['일자-No.', '거래처명']);
  Logger.log('1차 헤더매칭(일자-No.+거래처명): ' + v1.length + '개 '
    + v1.map(function (x) { return x.getName(); }).join(','));
  if (!v1.length) {
    ss.getSheets().forEach(function (sh) {
      const n = sh.getLastColumn();
      Logger.log('   [' + sh.getName() + '] ' + sh.getLastRow() + '행 · '
        + (n ? sh.getRange(1, 1, 1, Math.min(n, 12)).getValues()[0].join(' | ') : '(헤더없음)'));
    });
    return;
  }
  const seen = {};
  let total = 0, sum = 0;
  v1.forEach(function (sh) {
    const w = sh.getDataRange().getValues();
    const H = colIndex_(w[0]);
    const amtKey = (H['합계'] !== undefined) ? '합계'
                 : (H['주문금액'] !== undefined) ? '주문금액'
                 : (H['공급가액'] !== undefined) ? '공급가액' : null;
    const hasSeq = H['순번'] !== undefined;
    Logger.log('시트[' + sh.getName() + '] ' + (w.length - 1) + '행 · 금액컬럼=' + amtKey
      + ' · 순번=' + (hasSeq ? '있음' : '없음'));
    if (amtKey === null) return;
    let n = 0, sD = 0, sA = 0, sK = 0, sE = 0, s2 = 0;
    for (let i = 1; i < w.length; i++) {
      const doc = String(w[i][H['일자-No.']] || '').trim();
      if (!doc) { sE++; continue; }
      const dt = docDate_(doc);
      if (!dt) { sD++; continue; }
      const key = hasSeq ? (doc + '#' + String(w[i][H['순번']] || i)) : doc;
      if (seen[key]) { sK++; continue; }
      seen[key] = 1;
      const amt = num_(w[i][H[amtKey]]);
      if (!amt) { sA++; continue; }
      n++; s2 += amt;
    }
    Logger.log('  → 적재가능 ' + n + '행 / 금액 ' + Math.round(s2).toLocaleString()
      + '  (빈전표 ' + sE + ' · 날짜불가 ' + sD + ' · 중복 ' + sK + ' · 금액0 ' + sA + ')');
    total += n; sum += s2;
  });
  Logger.log('합계: ' + total + '행 / ' + Math.round(sum).toLocaleString() + '원');
  // _raw 현황
  const raw = ss.getSheetByName(RAW);
  if (raw && raw.getLastRow() > 1) {
    const rv = raw.getRange(2, 2, raw.getLastRow() - 1, 1).getValues();
    let c = 0;
    for (let i = 0; i < rv.length; i++) if (rv[i][0] === '통신판매(VMS)') c++;
    Logger.log('_raw 안의 통신판매(VMS) 행: ' + c + (c ? ' ✓' : ' ✗ → refreshAll() 재실행 필요'));
  }
}
/** _raw 에 어떤 채널이 몇 행/얼마로 들어있는지 전부 나열 */
function chList() {
  const sh = SpreadsheetApp.getActive().getSheetByName(RAW);
  if (!sh || sh.getLastRow() < 2) { Logger.log(RAW + ' 비어 있음 — refreshAll() 필요'); return; }
  const v = sh.getDataRange().getValues();
  const o = {};
  for (let i = 1; i < v.length; i++) {
    const c = String(v[i][1] || '');
    if (!o[c]) o[c] = { n: 0, g: 0, r: 0 };
    o[c].n++; o[c].g += num_(v[i][2]); o[c].r += num_(v[i][3]);
  }
  const keys = Object.keys(o).sort(function (x, y) { return (o[y].g - o[y].r) - (o[x].g - o[x].r); });
  Logger.log('_raw 채널 ' + keys.length + '개 / 총 ' + (v.length - 1) + '행');
  keys.forEach(function (k) {
    Logger.log('  ' + k + '  ' + o[k].n + '행  순 ' + Math.round(o[k].g - o[k].r).toLocaleString());
  });
  Logger.log(o['통신판매(VMS)'] ? '→ VMS 있음 ✓' : '→ VMS 없음 ✗  buildRawTable 의 VMS 블록 확인 필요');
  // 캐시된 payload 와 비교
  const cached = CacheService.getDocumentCache().get('pl_meta');
  Logger.log('payload 캐시: ' + (cached ? '있음(' + cached + '조각)' : '없음'));
  Logger.log('마지막 refreshAll: '
    + (PropertiesService.getDocumentProperties().getProperty('lastRefresh') || '기록 없음'));
}
function vmsCheck() {
  const v = SpreadsheetApp.getActive().getSheetByName(RAW).getDataRange().getValues();
  const byM = {};
  for (let i = 1; i < v.length; i++) {
    if (v[i][1] !== '통신판매(VMS)') continue;
    const m = dkey_(v[i][0]).slice(0, 7);
    byM[m] = (byM[m] || 0) + num_(v[i][2]);
  }
  let tot = 0;
  Object.keys(byM).sort().forEach(function (m) {
    tot += byM[m];
    Logger.log(m + '   ' + Math.round(byM[m]).toLocaleString());
  });
  Logger.log('VMS 합계  ' + Math.round(tot).toLocaleString());
}
/** VMS 시트가 왜 안 읽히는지 원본 값을 그대로 확인한다 */
function vmsDebug() {
  const sheets = findSheetsByHeader_(['일자-No.', '거래처명']);
  Logger.log('매칭된 시트 수: ' + sheets.length);
  sheets.forEach(function (sh) {
    const w = sh.getDataRange().getValues();
    Logger.log('── ' + sh.getName() + ' · ' + w.length + '행');
    Logger.log('헤더: ' + w[0].join(' | '));
    const H = colIndex_(w[0]);
    Logger.log('인덱스  일자-No.=' + H['일자-No.'] + '  순번=' + H['순번']
      + '  합계=' + H['합계'] + '  공급가액=' + H['공급가액']);
    for (let i = 1; i < Math.min(4, w.length); i++) {
      const doc = w[i][H['일자-No.']];
      Logger.log('행' + i + '  원본=[' + doc + '] type=' + typeof doc
        + '  → 날짜=' + docDate_(doc)
        + '  금액=[' + w[i][H['합계']] + '] → ' + num_(w[i][H['합계']]));
    }
  });
}
/** _raw 에 연도가 튀는 행이 있는지 확인 */
function outlierCheck() {
  const v = SpreadsheetApp.getActive().getSheetByName(RAW).getDataRange().getValues();
  const nowY = new Date().getFullYear();
  let n = 0;
  for (let i = 1; i < v.length; i++) {
    if (!(v[i][0] instanceof Date)) continue;
    const y = v[i][0].getFullYear();
    if (y < nowY - 1 || y > nowY + 1) {
      Logger.log(dkey_(v[i][0]) + ' | ' + v[i][1] + ' | ' + Math.round(num_(v[i][2])).toLocaleString());
      n++;
    }
  }
  Logger.log(n ? '이상 날짜 ' + n + '건' : '이상 날짜 없음 ✓');
}
/** Manual 시트가 어떻게 읽히는지 확인 */
function manualCheck() {
  const rows = readManual_();
  Logger.log('파싱된 행: ' + rows.length);
  const o = {};
  rows.forEach(function (r) {
    const k = r[1] + (r[5] ? ' / ' + r[5] : '');
    if (!o[k]) o[k] = { n: 0, v: 0, rf: 0, min: '9999', max: '0' };
    o[k].n++; o[k].v += r[4]; o[k].rf += r[3];
    const d = dkey_(r[0]);
    if (d < o[k].min) o[k].min = d;
    if (d > o[k].max) o[k].max = d;
  });
  Object.keys(o).forEach(function (k) {
    Logger.log('  ' + k + '  ' + o[k].n + '행  순 ' + Math.round(o[k].v).toLocaleString()
      + ' / 환불 ' + Math.round(o[k].rf).toLocaleString()
      + '  (' + o[k].min + ' ~ ' + o[k].max + ')');
  });
}
function rentCheck() {
  if (!RENT_ID) { Logger.log('RENT_ID 미설정'); return; }
  const ss = SpreadsheetApp.openById(RENT_ID);
  Logger.log('파일: ' + ss.getName());
  ss.getSheets().forEach(function (sh) {
    if (sh.getLastRow() < 1 || sh.getLastColumn() < 1) { Logger.log(sh.getName() + ' — 비어 있음'); return; }
    Logger.log(sh.getName() + ' (' + sh.getLastRow() + '행) 헤더: '
      + sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].join(' | '));
  });
  const r = buildRawRental_();
  Logger.log('파싱된 렌탈 행: ' + r.rows.length);
}

/* =====================================================================
 * 7. 유틸
 * ===================================================================*/
/** [성능 핵심] Utilities.formatDate 는 호출마다 Java 서비스로 넘어가 ~1ms 든다.
 *  수만 행 × 2회면 수십 초. 순수 JS + 타임스탬프 캐시로 대체한다.
 *  주의: 프로젝트 시간대가 한국 표준시인지 확인할 것. */
const _DK = {};
function dkey_(d) {
  const t = d.getTime();
  const c = _DK[t];
  if (c) return c;
  const m = d.getMonth() + 1, dd = d.getDate();
  const s = d.getFullYear() + '-' + (m < 10 ? '0' : '') + m + '-' + (dd < 10 ? '0' : '') + dd;
  _DK[t] = s;
  return s;
}
function fmtStamp_(d) {
  const p = function (n) { return (n < 10 ? '0' : '') + n; };
  return dkey_(d) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
}
function writeSheet_(name, header, rows, opt) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(name) || ss.insertSheet(name);
  sh.clear();
  sh.getRange(1, 1, 1, header.length).setValues([header]).setFontWeight('bold');
  if (rows.length) {
    if (sh.getMaxRows() < rows.length + 1) sh.insertRowsAfter(sh.getMaxRows(), rows.length + 1 - sh.getMaxRows());
    sh.getRange(2, 1, rows.length, header.length).setValues(rows);
    if (opt && opt.dateCols) opt.dateCols.forEach(function (c) {
      sh.getRange(2, c, rows.length, 1).setNumberFormat('yyyy-mm-dd'); });
    if (opt && opt.numCols) sh.getRange(2, opt.numCols[0], rows.length, opt.numCols[1]).setNumberFormat('#,##0');
  }
  sh.setFrozenRows(1);
  return sh;
}
function findSheetsByHeader_(mustHave) {
  const found = [];
  const sheets = SpreadsheetApp.getActiveSpreadsheet().getSheets();
  for (let s = 0; s < sheets.length; s++) {
    const sh = sheets[s];
    if (sh.getName().charAt(0) === '_') continue;
    if (sh.getLastRow() < 2 || sh.getLastColumn() < 3) continue;
    const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0]
      .map(function (v) { return String(v || '').replace(/\s/g, ''); });
    let ok = true;
    for (let i = 0; i < mustHave.length; i++) {
      if (head.indexOf(mustHave[i].replace(/\s/g, '')) < 0) { ok = false; break; }
    }
    if (ok) found.push(sh);
  }
  return found;
}
function colIndex_(headRow) {
  const H = {};
  for (let j = 0; j < headRow.length; j++) {
    const k = String(headRow[j] || '').trim();
    H[k] = j;
    H[k.replace(/\s/g, '')] = j;
  }
  return H;
}
function toDate_(x) {
  if (x instanceof Date && !isNaN(x)) return x;
  const s = String(x || '').trim();
  if (/^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}/.test(s)) {
    const d = new Date(s.replace(/[/.]/g, '-'));
    if (!isNaN(d)) return d;
  }
  return null;
}
/** 전표번호에서 날짜를 뽑는다. 구분자가 무엇이든(20260102-2, 2026-01-02-2,
 *  2026/01/02 -2) 숫자만 남긴 뒤 앞 8자리를 yyyymmdd 로 해석한다. */
function docDate_(doc) {
  if (doc instanceof Date && !isNaN(doc)) return doc;
  const s = String(doc || '').replace(/\D/g, '');
  if (s.length < 8) return null;
  const y = +s.slice(0, 4), m = +s.slice(4, 6), d = +s.slice(6, 8);
  if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  const dt = new Date(y, m - 1, d);
  return isNaN(dt) ? null : dt;
}
function ymdToDate_(x) {
  if (x instanceof Date && !isNaN(x)) return x;
  const s = String(x || '').replace(/\D/g, '');
  if (s.length >= 8) {
    const d = new Date(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8));
    if (!isNaN(d) && +s.slice(0, 4) > 2000) return d;
  }
  return null;
}
function num_(x) {
  if (typeof x === 'number') return x;
  const n = parseFloat(String(x || '').replace(/[,\s₩원]/g, ''));
  return isNaN(n) ? 0 : n;
}
