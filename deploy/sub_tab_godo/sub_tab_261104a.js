/* ===== 상품상세 일시불/구독 탭 | 모듈 goods/_sub_tab.html 에서 SUB_TAB_CONFIG 설정 후 로드 =====
   동작 순서
   1) 모델번호 결정: 옵션의 자체옵션코드 → 추가항목 "구독모델" → 상품 모델번호 → 자체상품코드
   2) SUB_INDEX(모델→카테고리) 에 있으면 탭 표시(자리 #subTabRoot 가 없으면 가격 박스 위에 만든다), 없으면 아무것도 하지 않음 (일반 상품 영향 없음)
   3) 구독 모델이면 해당 카테고리 요금표(sub_plans_<키>.js)와 카드표(sub_cards.js)를 추가 로드
   4) 추가항목 "구독요금" 이 있으면 파일 요금보다 우선 적용
        구독요금            = 6년 무상수리 13420 / 6년 방문케어 20,020 / 6년 방문케어36 15840 / 3년 무상수리 0
        구독요금 RP20C3111S9 = (옵션 모델별로 따로 지정할 때)
      같은 약정+케어는 덮어쓰고, 없던 조합은 추가, 0 은 그 요금제를 숨김
   5) 할인율·선납 한도·카드 유의사항·행사 문구·공통 기준값(처음 선택 카드·실적 구간, 상담 주소, 전화 = defaults)은 sub_policy.js(SUB_POLICY) 에서 읽는다
      파일이 없거나 못 불러오면 아래 DEFAULT_POLICY(현재 정책값)로 계산한다. 스킨 SUB_TAB_CONFIG 에 같은 항목이 있으면 스킨 값이 먼저다
   ※ 금액 계산은 calc_subscribe.html 과 같은 식을 쓴다
      - 구독료 할인(자동납부)·선납 할인: calcDiscount  (정수기는 본사 사전계산값 WATER_POLICY)
      - 선납금: ROUND(총구독료 × 선납비율 / 1.1 / 개월, -2) × 개월 × 1.1
      - 제휴카드: 월 혜택 × 계약 개월 (삼성카드 70만↑ 구간은 월구독료 7만원 미만이면 기본할인만)
        단, 고객 화면에서는 월 납부액을 넘는 카드 할인은 월 납부액까지만 반영한다 (카드사 약관)
===== */
/* 부르는 방법 두 가지
   1) 데이터를 먼저 넣고 부른다 (sub_view.js · 구독센터): window.SUB_INDEX 가 있으면 바로 시작
   2) 고도몰 상품상세(_sub_tab.html): SUB_TAB_CONFIG 만 두고 이 파일을 부르면 아래 부트가 데이터센터(dcBase)의 version.js → sub_index.js 를
      읽고 시작한다. 데이터센터를 못 읽으면 dataBase(고도몰 예비 사본)로 돌아간다 — 화면 파일은 고도몰에, 요금·정책은 데이터센터에 */
function main() {
  'use strict';
  var CFG = window.SUB_TAB_CONFIG || {};
  var IDX = window.SUB_INDEX;
  if (!IDX || !IDX.m) return;

  var TYPE_ORDER = ['무상수리', '셀프케어', '방문케어 라이트', '방문케어'];
  var TYPE_LABEL = { '무상수리': '무상수리 서비스', '셀프케어': '무상수리 + 셀프케어', '방문케어 라이트': '무상수리 + 방문케어 라이트', '방문케어': '무상수리 + 방문케어' };
  // sub_policy.js 를 못 불러왔을 때 쓰는 기본 정책 (tools/sub_policy.json 과 같은 구조)
  var DEFAULT_POLICY = {
    autopay: { rate: 0.05, label: '구독료 {rate} 할인 (자동납부)' },
    prepay: {
      steps: [0.2, 0.3, 0.4, 0.5], rates: { '0.2': 0.03, '0.3': 0.04, '0.4': 0.05, '0.5': 0.05 }, defaultMax: 0.5,
      maxByCat: { '에어컨': 0.5, '시스템에어컨': 0.5, 'TV': 0.5, '모니터': 0.5, '냉장고': 0.4, '김치냉장고': 0.4, '청소기': 0.4,
        '공기청정기': 0.3, '정수기': 0.3, '오디오': 0.3, '의류케어': 0.4, '조리기기': 0.5 },
      maxByName: [{ cat: '의류케어', contains: '에어드레서', max: 0.5 }, { cat: '조리기기', contains: '후드', max: 0.3 }],
      notes: ['선납금은 구독 신청 시에만 선택할 수 있으며, 구독 기간 중에는 변경이 어렵습니다.'],
      // 처음 선택되는 선납 비율(품목 한도 안에서 이 값을 넘지 않는 가장 큰 단계) · 선납금 옆 ? 아이콘을 누르면 보이는 안내 (2026-11-02 · 모든 구독 기본 = 6년·무상수리·삼성카드 30만↑·선납 40%)
      initial: 0.4, help: '일시불 구매보다 일부 선납후 구독 전환하면 A/S 기간 및 추가 할인이 가능합니다.'
    },
    // 공통 기준값 — 처음 선택되는 카드·실적 구간, 상담 신청 주소, 전화 (관리자 › 구독 혜택 정책 › 기본 기준·상담 연락처 · mvp_253). 스킨 CFG 가 비어 있을 때 쓴다
    // tierByModel: 모델(또는 모델 앞글자) → 처음 선택할 실적 구간 (예: AI 콤보 WD90H25 → 70만↑ · 2026-11-02 본사 제시 월 구독료 기준)
    defaults: { card: '삼성카드', tier: '30만↑', tierByModel: {}, consultUrl: '/main/html.php?htmid=service/SamSungSubscription.html', tel: '' },
    cards: {}, cardNotes: [], promos: [], points: {},   // points: 모델 → {rate, base, add, total} 적립 예정 멤버십 포인트 (mvp_258)
    bundle: null,   // 다품목 혜택 (mvp_264 · 스마트 패키지 품목 수별 정액 {kind:'package', tiers, min, cats, models, from, to}) — 다품목 계산기(sub_bundle.js)만 쓴다
    texts: {
      points: ['목돈 없이 월 납부 · 약정 기간 동안 무상수리'],
      notice: '* 월 구독료는 VAT 포함 기준이며, 카드 혜택은 카드사 조건(전월 실적·정기결제 등)에 따라 달라질 수 있습니다. ' +
        '결제 예상액은 위 혜택을 모두 받았을 때의 예상 금액으로 실제 청구 금액과 다를 수 있습니다. 정확한 금액은 상담 시 안내해 드립니다.'
    }
  };
  var POL = DEFAULT_POLICY;
  // 받은 정책에 빠진 항목은 기본값으로 채운다 (한 단계 깊이까지)
  function usePolicy(p) {
    if (!p || typeof p !== 'object') return;
    var out = {};
    for (var k in DEFAULT_POLICY) {
      var d = DEFAULT_POLICY[k], v = p[k];
      if (v === undefined || v === null) out[k] = d;
      else if (d && typeof d === 'object' && !(d instanceof Array) && typeof v === 'object' && !(v instanceof Array)) {
        out[k] = {};
        for (var j in d) out[k][j] = d[j];
        for (var j2 in v) out[k][j2] = v[j2];
      } else out[k] = v;
    }
    POL = out;
  }

  var state = {
    tab: 'lump', model: '', info: null, min: 0, best: 0,
    subPage: false,   // 구독 전용 상품 페이지(대표 카테고리가 구독상품 012): 일시불 탭·일시불 비교 없이 계산기만 띄운다 (2026-11-02)
    year: 0, type: '', cycle: 0, prepay: 0,
    prepaySet: false, tierSet: false,   // 고객이 선납·실적 구간을 직접 골랐는가 — 고르기 전엔 모델이 바뀔 때마다 정책 기본값을 다시 넣는다 (2026-11-02)
    help: {},                           // 펼친 ? 안내 (help.prepay)
    card: '', tier: '', cardOn: true,
    ptMode: CFG.pointMode === 'cash' ? 'cash' : 'melt',   // 포인트 받는 방법 (2026-11-04): melt = 구독료에 매월 나눠 반영해 보기 · cash = 실제 결제는 그대로, 포인트는 따로 적립(현금처럼 사용)
    open: !!CFG.openConditions    // [조건별 구독가 확인하기] 펼침 — 상품상세는 요약만, 구독 전용 페이지(sub_view)는 CFG.openConditions 로 처음부터 펼침
  };
  var root, els = {};
  var OVR = {};      // 모델 → 추가항목 "구독요금" 파싱 결과 { set: [[y,care,total,monthly]], del: ['y|care'] }
  var merged = {};   // 모델 → 파일 + 구독요금 병합 결과 캐시

  function fmt(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function norm(s) { return String(s || '').replace(/\s+/g, '').toUpperCase(); }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function pct(r) { return Math.round(r * 1000) / 10 + '%'; }
  // 정책 항목의 적용 기간 (from/to: YYYY-MM-DD, 둘 다 포함). CFG.today 로 날짜를 바꿔 미리볼 수 있다
  function today() {
    if (CFG.today) return CFG.today;
    var d = new Date(), z = function (n) { return (n < 10 ? '0' : '') + n; };
    return d.getFullYear() + '-' + z(d.getMonth() + 1) + '-' + z(d.getDate());
  }
  function inPeriod(o) {
    var t = today();
    return !(o.hidden || (o.from && t < o.from) || (o.to && t > o.to));
  }
  function track(name, extra) {
    var ev = { event: name, sub_model: state.model, goods_no: CFG.goodsNo };
    for (var k in extra) ev[k] = extra[k];
    if (window.dataLayer) window.dataLayer.push(ev);
  }

  /* ---------- 금액 계산 (calc_subscribe.html 과 동일한 식) ---------- */
  // ROUNDUP(V+ × rate / 1.1 / months, -2) × months × 1.1
  function calcDiscount(total, rate, months) {
    var inner = total * rate / 1.1 / months;
    var rounded = Math.ceil(Math.round(inner * 1000000) / 1000000 / 100) * 100;
    return Math.round(rounded * months * 1.1);
  }
  function tierLabel(t) { return String(t).replace('↑', '원 이상'); }
  function cardMonthly(name, tier, baseMonthly) {
    var cd = window.SUB_CARDS && window.SUB_CARDS[name];
    if (!cd) return { md: 0, base: 0, extra: 0, promoOff: false };
    var md = cd.t[tier] || 0, base = cd.base ? (cd.base[tier] || md) : md, promoOff = false;
    // 삼성카드 추가 캐시백은 할인 전 월 구독료가 기준금액(7만원) 이상일 때만
    if (cd.minMonthly && cd.minMonthly[tier] && baseMonthly < cd.minMonthly[tier]) { md = base; promoOff = true; }
    return { md: md, base: base, extra: md - base, promoOff: promoOff, min: cd.minMonthly && cd.minMonthly[tier] };
  }
  // 품목별 최대 선납 비율 — 이름 규칙(예: 의류케어 중 에어드레서) → 품목 → 기본값
  function prepayMax(info) {
    if (info.np) return 0;
    var pp = POL.prepay, rules = pp.maxByName || [];
    for (var i = 0; i < rules.length; i++) {
      if (rules[i].cat === info.cat && String(info.s || '').indexOf(rules[i].contains) >= 0) return rules[i].max;
    }
    var m = (pp.maxByCat || {})[info.cat];
    return m !== undefined ? m : (pp.defaultMax || 0.5);
  }
  function prepayRate(s) { return (POL.prepay.rates || {})[String(s)] || 0; }
  // 처음 선택되는 선납 비율 — 스킨 CFG.defaultPrepay 또는 정책 prepay.initial(40%)을 넘지 않는, 품목 한도(prepayMax) 안의 가장 큰 단계 (없으면 선납 없음) · 2026-11-02
  function defaultPrepay(info) {
    var want = (CFG.defaultPrepay !== undefined && CFG.defaultPrepay !== '' && CFG.defaultPrepay !== null) ? +CFG.defaultPrepay : +(POL.prepay.initial || 0);
    var cap = Math.min(want || 0, prepayMax(info)), best = 0;
    (POL.prepay.steps || []).forEach(function (st) { if (st <= cap + 1e-9 && st > best) best = st; });
    return best;
  }
  function autopayLabel() { return String(POL.autopay.label || '구독료 {rate} 할인 (자동납부)').replace('{rate}', pct(POL.autopay.rate)); }
  // 노출할 카드: 카드표에 있고, 정책에서 숨김·기간 밖이 아닌 카드
  function cardNames() {
    var cards = window.SUB_CARDS || {}, pc = POL.cards || {};
    return Object.keys(cards).filter(function (n) { return !pc[n] || inPeriod(pc[n]); });
  }
  // 이 상품에 해당하는 행사 (기간 + 대상 품목/모델/상품번호) — 문구 노출과 포인트 지원 금액 계산이 같은 조건을 쓴다
  function promoHits(info) {
    var model = (info && info.model) || state.model;
    return (POL.promos || []).filter(function (p) {
      if (!p || !inPeriod(p)) return false;
      if (p.cats && p.cats.length && p.cats.indexOf(info.cat) < 0) return false;
      if (p.models && p.models.length && p.models.map(norm).indexOf(model) < 0) return false;
      if (p.goods && p.goods.length && p.goods.map(String).indexOf(String(CFG.goodsNo)) < 0) return false;
      return true;
    });
  }
  function promoTexts(info) { return promoHits(info).filter(function (p) { return !!p.text; }).map(function (p) { return p.text; }); }
  /* N개월 구독료 상당 포인트 지원 (삼성 AI 구독 페스티벌 · 관리자 › 구독 혜택 정책 › 행사 문구에 개월 수·금액을 적으면 켜진다 · mvp_257)
     금액 = 모델별 금액표(amounts[모델]) → 모델 공통 금액(amount) → 개월 수 × 선택 요금제의 월 구독료(할인 전)
     maxTerm(기본 true) 이면 그 모델의 최장 약정을 골랐을 때만 지급 (삼성 기준 "최장 계약기간 적용") */
  function pointPromos(info) {
    return promoHits(info).filter(function (p) { return (p.months > 0) || (p.amount > 0) || (p.amounts && typeof p.amounts === 'object'); });
  }
  function maxYears(info) { var y = 0; info.p.forEach(function (x) { if (x[0] > y) y = x[0]; }); return y; }
  function pointsOf(info, plan) {
    var ps = pointPromos(info); if (!ps.length) return null;
    var model = (info && info.model) || state.model, my = maxYears(info), best = null;
    ps.forEach(function (p) {
      if (p.maxTerm !== false && plan[0] !== my) return;
      var amt = (p.amounts && +p.amounts[model]) || (+p.amount) || (p.months > 0 ? Math.round(p.months * plan[3]) : 0);
      if (amt > 0 && (!best || amt > best.amt)) best = { amt: amt, months: +p.months || 0, text: p.text || '', maxTerm: p.maxTerm !== false };
    });
    return best;
  }
  /* 적립 예정 멤버십 포인트 (mvp_258) — 삼성닷컴 구독 상품의 정률(rate %) + 기본(base %) 을 제품분 금액에 곱하고 상품별 추가 포인트(add)를 더한다.
     원본은 sub.model_point (수집기 tools/subpoint/collect.mjs 가 매일 삼성닷컴에서 받아 온다 · 관리자·매장에서 손 입력 가능) → sub_policy.js points[모델]
     행사 포인트(pointsOf · N개월 구독료 상당)와는 중복 지급이라 둘 다 보여 주고 둘 다 뺀다.
     기준금액(base)은 요금제 행의 제품분 금액(plan[4] · 총 구독금액에서 무상수리료를 뺀 DPS product_fee) — 삼성닷컴 계산기와 같이 선납·카드를 바꿔도 변하지 않는다 (mvp_264 · 2026-11-03 AI 콤보 6년 6,066,720 × 6.1% = 370,069P 로 확인).
     제품분이 없는 행(요금 직접 관리로 넣은 요금제)은 총 구독금액으로 */
  function modelPointOf(model) { var pts = POL.points || {}; return pts[norm(model)] || null; }
  function memberPoints(model, base) {
    var mp = modelPointOf(model); if (!mp) return null;
    var rate = (+mp.rate || 0) + (+mp.base || 0), add = +mp.add || 0;
    var amt = Math.floor(Math.max(0, base || 0) * rate / 100) + add;
    return amt > 0 ? { amt: amt, rate: rate, add: add, pct: Math.round(rate * 100) / 100 } : null;
  }
  // 일시불 비교에 쓸 가격 — 상품 페이지의 모델일 때만 (같은 모델 다른 색상·구독 전용 모델로 바꾸면 이 상품의 일시불가와 비교하지 않는다)
  function lumpFor(model) { return (pageModel && model && model !== pageModel) ? 0 : (CFG.lumpPrice || 0); }

  // 한 요금제의 모든 혜택 계산
  function calc(info, plan, o) {
    var y = plan[0], care = plan[1], total = plan[2], monthly = plan[3], months = y * 12;
    var w = info.w && info.w[y + '_' + care];
    var r = { years: y, care: care, total: total, monthly: monthly, months: months };
    r.autoDisc = w ? w[0] : calcDiscount(total, POL.autopay.rate, months);
    r.prepay = (o.prepay > 0 && o.prepay <= prepayMax(info) + 1e-9) ? o.prepay : 0;
    r.prepayRate = prepayRate(r.prepay);
    r.prepayAmt = r.prepay ? Math.round(Math.round((total * r.prepay / 1.1 / months) / 100) * 100 * months * 1.1) : 0;
    // 정수기 w[1] 은 본사가 선납 할인 5% 기준으로 계산해 둔 값
    r.prepayDisc = !r.prepay ? 0 : w ? (r.prepayRate >= 0.05 ? w[1] : Math.round(w[1] * r.prepayRate / 0.05)) : calcDiscount(total, r.prepayRate, months);
    // 선납 후 월 납부액 (자동납부 할인 전 / 후)
    r.monthlyPre = (total - r.prepayAmt - r.prepayDisc) / months;
    r.monthlyPay = r.monthlyPre - r.autoDisc / months;
    r.cardInfo = (o.cardOn && o.card) ? cardMonthly(o.card, o.tier, monthly) : { md: 0 };
    r.cardMonthly = Math.min(r.cardInfo.md, Math.max(0, r.monthlyPay));
    r.cardCapped = r.cardInfo.md > r.cardMonthly;
    r.cardTotal = Math.round(r.cardMonthly * months);
    r.finalMonthly = Math.max(0, r.monthlyPay - r.cardMonthly);
    r.expected = total - r.prepayDisc - r.autoDisc - r.cardTotal;   // 선납금 포함 실제 결제 총액
    // N개월 구독료 상당 포인트 지원 (mvp_257) — 결제 총액에서 빼서 "실제 구독료" 로 보여준다 (포인트는 결제 뒤 지급되므로 월 납부액은 그대로)
    var pt = pointsOf(info, plan);
    r.points = pt ? pt.amt : 0; r.pointsInfo = pt;
    // 적립 예정 멤버십 포인트 (mvp_258) — 행사 포인트와 별도로 더 뺀다. 기준은 제품분 금액(plan[4] · 없으면 총 구독금액) — 삼성닷컴과 같이 선납·카드와 무관 (mvp_264)
    r.pointBase = plan[4] > 0 ? plan[4] : total;
    var mpt = memberPoints(info && info.model, r.pointBase);
    r.mpoints = mpt ? mpt.amt : 0; r.mpointsInfo = mpt;
    r.pointsAll = r.points + r.mpoints;
    r.expectedNet = r.expected - r.pointsAll;
    // 포인트 받는 방법 (2026-11-04) — cash: 보여 주는 총액·월액 = 실제 결제액(포인트는 따로 적립) · melt(기본): 포인트를 약정 개월로 나눠 월 구독료에서 뺀 실부담
    r.ptMode = o.ptMode === 'cash' ? 'cash' : 'melt';
    r.netTotal = r.ptMode === 'cash' ? r.expected : r.expectedNet;
    r.netMonthly = r.ptMode === 'cash' ? r.finalMonthly : Math.max(0, r.finalMonthly - r.pointsAll / months);
    var lump = lumpFor(info && info.model);
    r.saving = (lump > 0 && r.netTotal < lump && CFG.lumpCompare !== 'never') ? lump - r.netTotal : 0;
    return r;
  }
  function opts() { return { prepay: state.prepay, card: state.card, tier: state.tier, cardOn: state.cardOn, ptMode: state.ptMode }; }

  /* ---------- 세부유형 표시 이름 ---------- */
  // DPS 세부유형 원문(Entry_75-79 · Premium_4K_-49 · SD Sound Device (4,5,6) …) → 고객용 (sub_find.js · sub_view.js 의 SEG_LABEL_RULES 와 같아야 한다)
  var SEG_LABEL_RULES = [
    [/^Entry_-(\d+)_더무빙$/, '$1형 이하 · 더 무빙스타일'],
    [/ \+ 4K_-(\d+)$/, ' + 보조 TV $1형 이하'],
    [/\(2인\)/, '(2인 설치)'],
    [/^Premium_4K_/, '프리미엄 4K '],
    [/^Premium_/, '프리미엄 '],
    [/^Entry_/, ''],
    [/^일반모니터 /, '일반 '],
    [/(\d+)이하/, '$1형 이하'],
    [/(\d+)이상 \((\d+)-(\d+)\)/, '$2~$3형'],
    [/(^|[ (])(\d{2,3})-(\d{2,3})(?=$|[ )(])/, '$1$2~$3형'],
    [/(^|[ _])-(\d{2,3})$/, '$1$2형 이하'],
    [/_M1\/M7$/, ' · 스마트 M1/M7'],
    [/_OLED$/, ' · OLED'],
    [/^SD Sound Device /, '사운드바 '],
    [/^AI로봇청소기_26신제품/, 'AI 로봇청소기 2026'],
    [/_/g, ' ']
  ];
  function segLabel(seg) {
    var t = String(seg || '');
    for (var i = 0; i < SEG_LABEL_RULES.length; i++) t = t.replace(SEG_LABEL_RULES[i][0], SEG_LABEL_RULES[i][1]);
    return t.replace(/\s+/g, ' ').replace(/^\s|\s$/g, '');
  }

  /* ---------- 케어 유형 / 주기 ---------- */
  function splitCare(c) {
    if (c === '무상수리') return ['무상수리', 0];
    var m = String(c).match(/^(방문케어 라이트|방문케어|셀프케어)(?:\((\d+)개월주기\))?$/);
    if (!m) return [c, 0];
    return [m[1], m[2] ? +m[2] : 12];
  }
  function joinCare(type, cycle) {
    if (type === '무상수리') return '무상수리';
    if ((type === '방문케어' || type === '방문케어 라이트') && cycle === 12) return type;
    if (!cycle) return type;               // 주기 없는 유형(갤럭시 파손보험·보증 등)은 이름 그대로
    return type + '(' + cycle + '개월주기)';
  }
  function careLabel(c) {
    var s = splitCare(c);
    if (s[0] === '무상수리' || !s[1]) return TYPE_LABEL[s[0]] || s[0];
    return (TYPE_LABEL[s[0]] || s[0]) + ' (' + s[1] + '개월)';
  }

  /* ---------- 모델번호 결정 ---------- */
  // goods_view.html 의 #subTabSrc(숨김) 에 고도몰 치환값이 들어 있다
  function readSource() {
    var src = document.getElementById('subTabSrc');
    var addTitle = CFG.addInfoTitle || '구독모델';
    var feeTitle = CFG.feeInfoTitle || '구독요금';
    var fromAdd = [], base = [], opt = {}, fees = [];
    if (src) {
      var items = src.getElementsByTagName('i');
      for (var i = 0; i < items.length; i++) {
        var k = items[i].getAttribute('data-k'), v = items[i].getAttribute('data-v') || '';
        var t = (items[i].getAttribute('data-t') || '').replace(/^\s+|\s+$/g, '');
        if (!v) continue;
        if (k === 'add' && t === addTitle) fromAdd.push(v);
        else if (k === 'add' && t.indexOf(feeTitle) === 0) fees.push([norm(t.slice(feeTitle.length).replace(/[()\[\]:]/g, '')), v]);
        else if (k === 'model') base.push(v);
        else if (k === 'opt') opt[items[i].getAttribute('data-sno')] = v;
      }
    }
    CFG.models = fromAdd.concat(base, CFG.models || []);
    CFG.optionModels = CFG.optionModels || opt;

    // "구독요금" (모델 표기 없음) 은 상품 대표 모델에 적용
    var baseModel = '';
    for (var j = 0; j < CFG.models.length && !baseModel; j++) baseModel = norm(CFG.models[j]);
    if (!baseModel && CFG.goodsNo) { baseModel = 'GOODS-' + CFG.goodsNo; CFG.models.push(baseModel); }
    fees.forEach(function (f) {
      var model = f[0] || baseModel;
      if (model) OVR[model] = parseFees(f[1], model, OVR[model]);
    });
  }

  /* ---------- 추가항목 "구독요금" 파싱 ---------- */
  // 표기 예: 무상수리 / 방문케어 / 방문케어36 / 방문케어(36개월) / 셀프케어12 / 방문케어(36개월주기)
  function normCare(raw) {
    var s = String(raw).replace(/\s+/g, '').replace(/^무상수리\+/, '').replace(/[()]/g, '').replace(/개월|주기/g, '');
    if (s === '무상수리' || s === '무상수리서비스') return '무상수리';
    var m = s.match(/^(방문케어라이트|방문케어|셀프케어)(\d*)$/);
    if (!m) return '';
    return joinCare(m[1] === '방문케어라이트' ? '방문케어 라이트' : m[1], m[2] ? +m[2] : 12);
  }
  function parseFees(text, model, into) {
    var o = into || { set: [], del: [] };
    String(text).split(/[\/;|\n]+/).forEach(function (part) {
      part = part.replace(/^\s+|\s+$/g, '');
      if (!part) return;
      var m = part.match(/^(\d+)\s*년\s*(.+?)\s*[:=]?\s*([\d,]+)\s*원?$/);
      var care = m && normCare(m[2]);
      if (!m || !care) { if (window.console) console.warn('[구독탭] 구독요금 해석 실패 (' + model + '): "' + part + '"'); return; }
      var y = +m[1], monthly = +m[3].replace(/,/g, '');
      o.del.push(y + '|' + care);
      // 총구독료 = 월구독료 × 개월수 (요금 데이터와 동일한 관계)
      if (monthly > 0) o.set.push([y, care, monthly * y * 12, monthly]);
    });
    return o;
  }

  function selectedOptionSno() {
    var rows = document.querySelectorAll('#frmView input[name="optionSno[]"]');
    for (var i = rows.length - 1; i >= 0; i--) if (rows[i].value) return rows[i].value;
    var sel = document.querySelector('#frmView select[name="optionSnoInput"]');
    var m = sel && sel.value && sel.value.match(/^\d+/);
    return m ? m[0] : '';
  }
  function resolveModel() {
    var sno = selectedOptionSno();
    var byOpt = sno && CFG.optionModels && CFG.optionModels[sno];
    // 선택한 옵션에 자체옵션코드가 있으면 그 코드만 본다 (구독 모델이 아니면 탭 숨김)
    var list = byOpt ? [byOpt] : (CFG.models || []);
    for (var i = 0; i < list.length; i++) {
      var m = norm(list[i]);
      if (m && (IDX.m[m] || OVR[m])) return m;
    }
    return '';
  }

  /* ---------- 데이터 로드 ---------- */
  var loading = {};
  // onFail 이 있으면 실패 시 그쪽으로 넘기고 오류 문구는 띄우지 않는다
  function loadScript(file, ready, cb, onFail) {
    if (ready()) return cb();
    if (loading[file]) return loading[file].push(cb);
    loading[file] = [cb];
    var s = document.createElement('script');
    s.src = (CFG.dataBase || '/data/js/sub/') + file + (CFG.noVer ? '' : '?v=' + (CFG.ver || IDX.ver));   // noVer: 구독센터가 데이터센터 파일을 ?v= 없이 쓸 때
    s.onload = function () { var q = loading[file]; loading[file] = null; q.forEach(function (f) { f(); }); };
    s.onerror = function () {
      var q = loading[file]; loading[file] = null;
      if (onFail) return q.forEach(function () { onFail(); });
      if (els.panel) els.panel.innerHTML = '<p class="subtab-note">요금 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.</p>';
    };
    document.head.appendChild(s);
  }
  function loadCards(cb) { loadScript('sub_cards.js', function () { return !!window.SUB_CARDS; }, cb); }
  // 정책 파일은 없어도 기본 정책으로 계속 동작
  var policyDone = false;
  function loadPolicy(cb) {
    if (policyDone) return cb();
    function done() {
      if (!policyDone) {
        policyDone = true;
        if (window.SUB_POLICY) usePolicy(window.SUB_POLICY);
        else if (window.console) console.warn('[구독탭] sub_policy.js 를 불러오지 못해 기본 정책값으로 계산합니다');
      }
      cb();
    }
    loadScript('sub_policy.js', function () { return !!window.SUB_POLICY; }, done, done);
  }

  // 파일 요금 + 구독요금(우선) 병합. 결과 요금제가 하나도 없으면 null
  function mergeInfo(file, o, cat) {
    var p = file ? file.p.slice() : [];
    if (o) {
      p = p.filter(function (x) { return o.del.indexOf(x[0] + '|' + x[1]) < 0; }).concat(o.set);
      if (window.console) console.info('[구독탭] 추가항목 구독요금 적용: ' + o.set.length + '건 반영, ' + (o.del.length - o.set.length) + '건 숨김');
    }
    if (!p.length) return null;
    return { s: file ? file.s : '', p: p, np: file && file.np, w: file && file.w, cat: cat || CFG.productCat || '' };
  }
  function getInfo(model, cb) {
    if (merged.hasOwnProperty(model)) return cb(merged[model]);
    var e = IDX.m[model];
    function done(file) { merged[model] = mergeInfo(file, OVR[model], e && IDX.cats[e[0]]); if (merged[model]) merged[model].model = model; cb(merged[model]); }
    if (!e) return done(null);
    loadScript('sub_plans_' + e[0] + '.js', function () { return !!(window.SUB_PLANS && window.SUB_PLANS[e[0]]); },
      function () { done(window.SUB_PLANS[e[0]][model]); });
  }
  function findPlan(info, y, c) {
    for (var i = 0; i < info.p.length; i++) if (info.p[i][0] === y && info.p[i][1] === c) return info.p[i];
    return null;
  }
  // 기본 카드 혜택만 적용했을 때(선납 없음) 일시불 대비 최대 절감액 — 탭 배지용
  function bestSaving(info) {
    var dc = cardNames().indexOf(defaultCard()) >= 0 ? defaultCard() : '';
    var o = { prepay: 0, card: dc, tier: defaultTier(dc, info && info.model, 0), cardOn: !!dc }, best = 0;
    info.p.forEach(function (p) { best = Math.max(best, calc(info, p, o).saving); });
    return best;
  }
  // 처음 선택된 카드·실적 구간 — 스킨 SUB_TAB_CONFIG 의 defaultCard · defaultTier 가 비어 있으면 데이터센터 정책 SUB_POLICY.defaults (관리자 › 구독 혜택 정책 › 기본 기준)
  function defaultCard() { return CFG.defaultCard || (POL.defaults && POL.defaults.card) || ''; }
  // 선납 40% 이상이면 모델별 구간(예: AI 콤보 70만↑)을 쓰지 않고 기본 구간(30만↑) — 선납으로 월 구독료가 낮아져 높은 실적 구간이 맞지 않는다 (2026-11-03)
  //   prepay 를 넘기지 않으면 지금 고른 선납 비율(state.prepay)
  function defaultTier(name, model, prepay) {
    var cd = window.SUB_CARDS && window.SUB_CARDS[name];
    if (!cd) return '';
    var tiers = Object.keys(cd.t);
    var pp = prepay === undefined ? state.prepay : prepay, hiPre = +pp >= 0.4 - 1e-9;
    var want = CFG.defaultTier || (hiPre ? '' : tierByModel(model || state.model)) || (POL.defaults && POL.defaults.tier) || '';
    return tiers.indexOf(want) >= 0 ? want : tiers[0];
  }
  // 모델별 처음 실적 구간 — 정책 defaults.tierByModel { 모델 또는 모델 앞글자: 구간 } 에서 가장 길게 맞는 것 (예: 'WD90H25': '70만↑' → AI 콤보 전 색상·수납함) · 2026-11-02
  function tierByModel(model) {
    var map = (POL.defaults && POL.defaults.tierByModel) || {}, m = norm(model || ''), best = '', len = -1;
    if (!m) return '';
    for (var k in map) { var kk = norm(k); if (kk && m.indexOf(kk) === 0 && kk.length > len) { best = String(map[k] || ''); len = kk.length; } }
    return best;
  }
  function setModel(m, cb) {
    state.model = m; state.info = null; state.year = 0; state.type = ''; state.cycle = 0;
    state.min = IDX.m[m] ? IDX.m[m][1] : 0; state.best = 0;
    getInfo(m, function (info) {
      if (state.model !== m) return;
      loadCards(function () { loadPolicy(function () {
        if (state.model !== m) return;
        state.info = info;
        if (info) {
          state.min = Math.min.apply(null, info.p.map(function (x) { return x[3]; }));
          state.best = bestSaving(info);
        } else state.min = 0;
        if (state.card && cardNames().indexOf(state.card) < 0) state.card = '';
        var defCard = defaultCard();
        if (!state.card && cardNames().indexOf(defCard) >= 0) { state.card = defCard; state.tier = defaultTier(defCard, m); }
        else if (state.card && !state.tierSet) state.tier = defaultTier(state.card, m);   // 실적 구간을 직접 고르기 전엔 모델별 기본 구간을 따라간다
        if (cb) cb();
      }); });
    });
  }

  /* ---------- 선택값 정리 ---------- */
  function plansOf(info, y) { return info.p.filter(function (p) { return p[0] === y; }); }

  /* ---------- 다른 화면이 쓰는 계산 API (구독센터 다품목 계산기 sub_bundle.js · 2026-10-30) ----------
     금액 식이 한 곳(이 파일)에만 있도록, 요금표 읽기·정책·카드·선납 규칙을 그대로 내준다. CFG.apiOnly 면 화면은 그리지 않는다 */
  window.SUB_CALC = {
    policy: function () { return POL; },
    getInfo: getInfo, calc: calc, plansOf: plansOf, findPlan: findPlan,
    prepayMax: prepayMax, prepayRate: prepayRate, defaultPrepay: defaultPrepay, tierByModel: tierByModel, cardNames: cardNames, cardMonthly: cardMonthly,
    splitCare: splitCare, joinCare: joinCare, typeOrder: TYPE_ORDER, typeLabel: TYPE_LABEL,
    defaultCard: function () { return defaultCard(); }, defaultTier: function (c) { return defaultTier(c); },
    autopayLabel: autopayLabel, inPeriod: inPeriod, fmt: fmt, pointsOf: pointsOf, pointPromos: pointPromos, memberPoints: memberPoints, modelPointOf: modelPointOf, siblings: siblings, siblingList: siblingList, cheapestOf: cheapestOf, subOnlyOf: subOnlyOf,
    ready: function (cb) { loadCards(function () { loadPolicy(cb); }); }   // 카드표·정책을 받은 뒤 계산해야 금액이 구독탭과 같다
  };
  if (CFG.apiOnly) return;
  function normalizeSelection(info) {
    var years = [];
    info.p.forEach(function (p) { if (years.indexOf(p[0]) < 0) years.push(p[0]); });
    years.sort(function (a, b) { return a - b; });
    if (years.indexOf(state.year) < 0) {
      // 최장 약정 중 가장 저렴한 케어 (탭 라벨의 "월 X원~" 과 맞춘다)
      state.year = years[years.length - 1];
      var inY = plansOf(info, state.year).sort(function (a, b) { return a[3] - b[3]; });
      var free = inY.filter(function (p) { return splitCare(p[1])[0] === '무상수리'; });   // 기본 케어 = 무상수리 (없는 모델은 가장 저렴한 케어)
      var cheap = (free.length ? free : inY)[0];
      var sc = splitCare(cheap[1]); state.type = sc[0]; state.cycle = sc[1];
    }
    var inYear = plansOf(info, state.year);
    var types = [];
    inYear.forEach(function (p) { var t = splitCare(p[1])[0]; if (types.indexOf(t) < 0) types.push(t); });
    var ord = function (t) { var i = TYPE_ORDER.indexOf(t); return i < 0 ? 99 : i; };   // 표에 없는 유형(갤럭시)은 뒤로
    types.sort(function (a, b) { return ord(a) - ord(b); });
    if (types.indexOf(state.type) < 0) state.type = types[0];
    var cycles = [];
    inYear.forEach(function (p) { var s = splitCare(p[1]); if (s[0] === state.type && s[1] && cycles.indexOf(s[1]) < 0) cycles.push(s[1]); });
    cycles.sort(function (a, b) { return a - b; });
    if (state.type === '무상수리' || !cycles.length) state.cycle = 0;   // 주기가 없는 유형은 0
    else if (cycles.indexOf(state.cycle) < 0) state.cycle = cycles.indexOf(12) >= 0 ? 12 : cycles[0];
    var maxR = prepayMax(info);
    if (!state.prepaySet) state.prepay = defaultPrepay(info);   // 고객이 고르기 전엔 정책 기본값(선납 40% · 품목 한도 안) — 모델이 바뀌어도 다시 계산
    else if (state.prepay > maxR + 1e-9) state.prepay = 0;
    if (state.card && !state.tierSet) state.tier = defaultTier(state.card, state.model);   // 실적 구간을 직접 고르기 전엔 선납 비율을 따라간다 (선납 40% → 30만↑)
    return { years: years, types: types, cycles: cycles, inYear: inYear };
  }

  /* ---------- 렌더 ---------- */
  function build() {
    root = document.getElementById('subTabRoot');
    if (!root) {                      // 스킨에 자리를 안 만들었으면 가격 박스(lumpOnly 첫 선택자) 바로 위에 만든다
      var anchor = null, sels = CFG.lumpOnly || ['.price-box'];
      for (var a = 0; a < sels.length && !anchor; a++) { try { anchor = document.querySelector(sels[a]); } catch (e) {} }
      if (!anchor) return false;
      root = document.createElement('div'); root.id = 'subTabRoot'; root.hidden = true;
      anchor.parentNode.insertBefore(root, anchor);
    }
    root.innerHTML =
      '<div class="subtab-head" role="tablist" aria-label="구매방식">' +
      '<button type="button" role="tab" class="subtab-btn" data-tab="lump"><span>일시불</span><strong data-slot="lump-price"></strong></button>' +
      '<button type="button" role="tab" class="subtab-btn" data-tab="sub"><span>구독<em class="subtab-badge">혜택</em></span><strong data-slot="sub-price"></strong><small data-slot="sub-month"></small>' +
      '<em class="subtab-save" data-slot="sub-save" hidden></em></button>' +
      '</div><div class="subtab-panel" data-slot="panel" hidden></div>';
    els.lumpPrice = root.querySelector('[data-slot="lump-price"]');
    els.subPrice = root.querySelector('[data-slot="sub-price"]');
    els.subMonth = root.querySelector('[data-slot="sub-month"]');
    els.subSave = root.querySelector('[data-slot="sub-save"]');
    els.panel = root.querySelector('[data-slot="panel"]');
    els.lumpPrice.textContent = CFG.lumpPrice > 0 ? fmt(CFG.lumpPrice) + '원' : '';
    root.classList.toggle('is-subpage', !!state.subPage);   // 구독 전용 페이지: 일시불 탭 숨김(css) · 페이지 가격 영역은 그대로 둔다
    root.addEventListener('click', onClick);
    root.addEventListener('change', onChange);
    return true;
  }

  // 탭 머리: 총 구독액(결제 예상액)을 크게, 월 납부액은 작게
  // 탭 머리는 "총 ○○○원 (○○만원 저렴)" 만 — 월 납부액·조건은 패널에서 (2026-10-29)
  function shortWon(v) { return v >= 10000 ? fmt(Math.floor(v / 10000)) + '만원' : fmt(v) + '원'; }
  function setHeadPrice(r) {
    els.subPrice.textContent = '총 ' + fmt(r.netTotal) + '원';
    els.subMonth.textContent = r.saving > 0 ? '(' + shortWon(r.saving) + ' 저렴)' : '';
  }
  function renderHead() {
    var cur = current();   // 선택한 조건(약정·케어·선납·카드) 그대로의 월 납부 예상금액 — 아래 요약·하단 바와 같은 값
    if (cur) setHeadPrice(cur);
    else { els.subPrice.textContent = state.min ? '월 ' + fmt(state.min) + '원~' : ''; els.subMonth.textContent = ''; }
    els.subSave.hidden = true;   // 빨간 배지는 쓰지 않는다 — 절감액은 총액 옆 "(○○만원 저렴)" 으로
    root.classList.toggle('is-cheaper', !!state.best);
    var btns = root.querySelectorAll('.subtab-btn');
    for (var i = 0; i < btns.length; i++) {
      var on = btns[i].getAttribute('data-tab') === state.tab;
      btns[i].classList.toggle('is-active', on);
      btns[i].setAttribute('aria-selected', on ? 'true' : 'false');
    }
    if (!state.subPage) {   // 구독 전용 페이지에선 페이지의 가격·신청 영역을 건드리지 않는다
    // 구독 탭일 때는 일시불 전용 영역(가격·장바구니·간편결제)을 숨긴다
    (CFG.lumpOnly || []).forEach(function (sel) {
      var nodes = document.querySelectorAll(sel);
      for (var j = 0; j < nodes.length; j++) nodes[j].classList.toggle('subtab-hide', state.tab === 'sub');
    });
    // 상품 정보(브랜드·상품코드·배송비·카드 할인 문구·옵션 선택)도 구독 탭에선 숨긴다 — CFG.subHide 로 바꿀 수 있다
    // 옵션 선택은 고를 옵션이 2개 이상이면 남긴다 (옵션마다 구독 모델이 다를 수 있음)
    (CFG.subHide || ['.item_detail_list > dl', '.item_detail_list > .item_add_option_box']).forEach(function (sel) {
      var nodes = []; try { nodes = document.querySelectorAll(sel); } catch (e) {}
      for (var j = 0; j < nodes.length; j++) {
        var s = nodes[j].querySelector('select');
        if (s && s.options.length > 2) continue;
        nodes[j].classList.toggle('subtab-hide', state.tab === 'sub');
      }
    });
    }
    els.panel.hidden = state.tab !== 'sub';
  }

  function optBtn(attrs, active, inner, extraCls) {
    return '<button type="button" class="subtab-opt' + (extraCls ? ' ' + extraCls : '') + (active ? ' is-active' : '') + '" ' + attrs + '>' + inner + '</button>';
  }
  function row(label, value, cls) {
    return '<div' + (cls ? ' class="' + cls + '"' : '') + '><dt>' + label + '</dt><dd>' + value + '</dd></div>';
  }

  function current() {
    var info = state.info;
    if (!info) return null;
    normalizeSelection(info);
    return calc(info, findPlan(info, state.year, joinCare(state.type, state.cycle)), opts());
  }

  function renderPanel() {
    var info = state.info;
    if (!info) { els.panel.innerHTML = '<p class="subtab-note">요금 정보를 불러오는 중…</p>'; return; }
    var sel = normalizeSelection(info);
    var plan = findPlan(info, state.year, joinCare(state.type, state.cycle));
    var r = calc(info, plan, opts());
    var lump = lumpFor(state.model), maxYear = sel.years[sel.years.length - 1];
    var h = '';

    h += siblingsHtml(info);
    // 요약(저렴한 금액 또는 월 구독료)만 먼저 보여주고, 약정·케어·선납·카드 선택과 결제 예상 내역은 [조건별 구독가 확인하기] 안에 접어 둔다
    var top = h; h = '';

    // 약정 기간
    h += '<fieldset class="subtab-field"><legend>약정 기간</legend><div class="subtab-grid subtab-grid--years">';
    sel.years.forEach(function (y) {
      h += optBtn('data-year="' + y + '"', y === state.year,
        (y === maxYear ? '<i class="subtab-rec">추천</i>' : '') + '<b>' + y + '년</b><span>' + (y * 12) + '개월</span>', 'subtab-opt--center');
    });
    var pps = pointPromos(info);
    if (pps.length && !r.points) {
      var pm = 0; pps.forEach(function (p) { if (p.months > pm) pm = +p.months; });
      h += '<p class="subtab-sub subtab-sub--point">★ ' + maxYear + '년 약정 선택 시 ' + (pm ? pm + '개월 구독료 상당 ' : '') + '포인트를 지원받을 수 있습니다.</p>';
    }
    h += '</div></fieldset>';

    // 구독 케어 유형
    h += '<fieldset class="subtab-field"><legend>구독 케어 유형</legend><div class="subtab-grid subtab-grid--1">';
    sel.types.forEach(function (t) {
      var low = Math.min.apply(null, sel.inYear.filter(function (p) { return splitCare(p[1])[0] === t; }).map(function (p) { return p[3]; }));
      h += optBtn('data-type="' + t + '"', t === state.type, '<b>' + (TYPE_LABEL[t] || t) + '</b><span>월 ' + fmt(low) + '원~</span>', 'subtab-opt--row');
    });
    h += '</div></fieldset>';

    // 구독 케어 주기
    var allCycles = [];
    sel.inYear.forEach(function (p) { var c = splitCare(p[1])[1]; if (c && allCycles.indexOf(c) < 0) allCycles.push(c); });
    allCycles.sort(function (a, b) { return a - b; });
    if (allCycles.length) {
      h += '<fieldset class="subtab-field"><legend>구독 케어 주기</legend>';
      if (state.type === '무상수리') h += '<p class="subtab-sub">※ 선택하신 케어 유형은 구독케어 주기 선택이 필요하지 않습니다.</p>';
      h += '<div class="subtab-grid subtab-grid--2">';
      (state.type === '무상수리' ? allCycles : sel.cycles).forEach(function (c) {
        var dis = state.type === '무상수리';
        h += '<button type="button" class="subtab-opt subtab-opt--center' + (!dis && c === state.cycle ? ' is-active' : '') + '"' +
          (dis ? ' disabled' : ' data-cycle="' + c + '"') + '><b>' + c + '개월</b></button>';
      });
      h += '</div></fieldset>';
    }

    // 선납금
    var maxR = prepayMax(info);
    var helpTxt = String(POL.prepay.help || '');
    h += '<fieldset class="subtab-field"><legend>선납금' +
      (helpTxt ? '<button type="button" class="subtab-help" data-help="prepay" aria-label="선납금 안내 보기" aria-expanded="' + (state.help.prepay ? 'true' : 'false') + '">?</button>' : '') +
      '<small>선납 시 월 구독료가 즉시 낮아집니다</small></legend>' +
      (helpTxt && state.help.prepay ? '<p class="subtab-sub subtab-help-text" role="note">' + esc(helpTxt) + '</p>' : '') +
      '<div class="subtab-grid subtab-grid--2">';
    [0].concat((POL.prepay.steps || []).filter(function (s) { return s <= maxR + 1e-9; })).forEach(function (s) {
      var rr = calc(info, plan, { prepay: s, cardOn: false });
      var title = s ? '선납 ' + Math.round(s * 100) + '%<em class="subtab-tag">할인 ' + Math.round(rr.prepayRate * 100) + '%</em>' : '선납 없음';
      var sub = '월 ' + fmt(rr.monthlyPre) + '원' + (s ? ' · 선납 ' + fmt(rr.prepayAmt) + '원' : '');
      h += optBtn('data-prepay="' + s + '"', s === r.prepay, '<b>' + title + '</b><span>' + sub + '</span>');
    });
    h += '</div>' + (info.np ? '<p class="subtab-sub">선택한 모델은 선납 옵션이 제공되지 않습니다.</p>' : '') +
      (POL.prepay.notes || []).map(function (t) { return '<p class="subtab-sub">* ' + esc(t) + '</p>'; }).join('') + '</fieldset>';

    // 카드 혜택
    var cards = window.SUB_CARDS || {}, names = cardNames();
    h += '<section class="subtab-field"><div class="subtab-legend">카드 혜택' +
      (CFG.cardGuideUrl ? '<a href="' + esc(CFG.cardGuideUrl) + '" target="_blank">혜택 받는 방법</a>' : '') + '</div>' +
      '<div class="subtab-card"><select data-card aria-label="제휴카드 선택"><option value="">제휴카드를 선택하세요</option>';
    names.forEach(function (n) { h += '<option value="' + esc(n) + '"' + (n === state.card ? ' selected' : '') + '>' + esc(n) + '</option>'; });
    h += '</select>';
    if (state.card && cards[state.card] && names.indexOf(state.card) >= 0) {
      var cd = cards[state.card];
      h += '<p class="subtab-sub">' + esc(state.card) + ' 결제 시 (전월 실적)</p><select data-tier aria-label="전월 실적 구간">';
      Object.keys(cd.t).forEach(function (t) {
        var ci = cardMonthly(state.card, t, 1e12), txt = tierLabel(t) + ' · 월 -' + fmt(ci.base) + '원' + (ci.extra ? ' + 캐시백 ' + fmt(ci.extra) + '원' : '');
        h += '<option value="' + esc(t) + '"' + (t === state.tier ? ' selected' : '') + '>' + txt + '</option>';
      });
      h += '</select><label class="subtab-check"><input type="checkbox" data-cardon' + (state.cardOn ? ' checked' : '') + '>' +
        '<span>제휴카드 혜택 적용</span><strong>' + (state.cardOn ? '월 -' + fmt(r.cardMonthly) + '원' : '미적용') + '</strong></label>';
      if (state.cardOn) {
        var ci2 = r.cardInfo;
        h += '<dl class="subtab-cardbreak">' + row('기본 청구할인', '월 -' + fmt(ci2.base) + '원') +
          (ci2.extra ? row('추가 캐시백 (최대 ' + cd.m + '개월)', '월 -' + fmt(ci2.extra) + '원') : '') + '</dl>';
        if (ci2.promoOff) h += '<p class="subtab-sub">※ 이 구간의 추가 캐시백은 월 구독료 ' + fmt(ci2.min) + '원 이상일 때 적용되어 기본 청구할인만 반영했습니다.</p>';
        if (r.cardCapped) h += '<p class="subtab-sub">※ 할인은 월 납부액(' + fmt(r.monthlyPay) + '원)까지만 적용됩니다.</p>';
      }
    }
    // 카드 유의사항: 선택한 카드 전용 + 공통
    var notes = ((state.card && POL.cards && POL.cards[state.card] && POL.cards[state.card].notes) || []).concat(POL.cardNotes || []);
    if (notes.length) h += '<ul class="subtab-cardnotes">' + notes.map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('') + '</ul>';
    h += '</div></section>';

    // 결제 예상 내역
    h += '<section class="subtab-field"><div class="subtab-legend">결제 예상 내역</div><dl class="subtab-sum">';
    h += row('총 구독금액 (' + r.years + '년)', fmt(r.total) + '원');
    if (r.prepay) h += row('선납 할인 (선납 ' + Math.round(r.prepay * 100) + '% · ' + Math.round(r.prepayRate * 100) + '%)', '-' + fmt(r.prepayDisc) + '원', 'is-blue');
    h += row(esc(autopayLabel()), '-' + fmt(r.autoDisc) + '원', 'is-blue');
    if (r.cardTotal) h += row('제휴카드 혜택 (' + esc(state.card) + ')', '-' + fmt(r.cardTotal) + '원', 'is-blue');
    var cash = r.ptMode === 'cash', sg = cash ? '+' : '-';
    h += row('결제 예상액' + (r.pointsAll && cash ? ' <small>실제 결제</small>' : ''), fmt(r.expected) + '원', r.pointsAll && !cash ? '' : 'is-total');
    if (r.pointsAll && cash) h += row('월 납부액 <small>실제 결제</small>', '월 ' + fmt(r.finalMonthly) + '원', 'is-strong');
    if (r.points) h += row((r.pointsInfo.months ? r.pointsInfo.months + '개월 구독료 상당 ' : '') + '포인트 지원', sg + fmt(r.points) + (cash ? 'P' : '원'), 'is-blue is-point');
    if (r.mpoints) h += row('적립 예정 멤버십 포인트 <small>' + r.mpointsInfo.pct + '%' + (r.mpointsInfo.add ? ' + ' + fmt(r.mpointsInfo.add) + 'P' : '') + '</small>', sg + fmt(r.mpoints) + 'P', 'is-blue is-point is-mpoint');
    if (r.pointsAll && !cash) {
      h += row('포인트 반영 실제 구독료', fmt(r.expectedNet) + '원', 'is-total');
      h += row('포인트 반영 월 실부담 <small>포인트 ÷ ' + r.months + '개월</small>', '월 ' + fmt(r.netMonthly) + '원', 'is-strong');
    }
    if (r.points && r.mpoints && cash) h += row('따로 받는 포인트 합계 <small>결제 뒤 적립 · 현금처럼 사용</small>', '+' + fmt(r.pointsAll) + 'P', 'is-blue is-strong');
    if (r.prepay) h += row('└ 선납금 (신청 시 1회)', fmt(r.prepayAmt) + '원', 'is-muted');
    var cmp = CFG.lumpCompare || 'auto';
    if (lump > 0 && (cmp === 'always' || (cmp === 'auto' && r.saving))) h += row('일시불 구매가', fmt(lump) + '원', 'is-muted');
    h += '</dl>';
    if (r.pointsAll) h += '<div class="subtab-ptmode" role="radiogroup" aria-label="포인트 받는 방법"><p>포인트 받는 방법을 골라 보세요</p>' +
      optBtn('data-ptmode="melt" role="radio" aria-checked="' + !cash + '"', !cash, '<b>구독료에 매월 녹이기</b><span>포인트만큼 월 ' + fmt(Math.max(0, r.finalMonthly - r.pointsAll / r.months)) + '원 부담으로 계산</span>') +
      optBtn('data-ptmode="cash" role="radio" aria-checked="' + cash + '"', cash, '<b>포인트로 따로 받기</b><span>월 ' + fmt(r.finalMonthly) + '원 결제 · ' + fmt(r.pointsAll) + 'P 현금처럼 사용</span>') + '</div>';
    h += '</section>';

    var cond = r.years + '년 약정 · ' + careLabel(r.care) + (r.prepay ? ' · 선납 ' + Math.round(r.prepay * 100) + '%' : '') +
      (r.cardTotal ? ' · ' + state.card + ' 적용' : '');
    var sum = r.saving ?
      // 일시불보다 저렴하면 얼마나 저렴한지
      // 일시불가와 구독 총액을 크게 나란히 — 얼마나 저렴한지가 한눈에
      '<div class="subtab-savebox" role="note"><span class="subtab-savebox-label">선택한 혜택 적용 시 일시불 구매보다</span>' +
        '<strong>' + fmt(r.saving) + '원 저렴해요</strong>' +
        '<div class="subtab-cmp"><div><em>일시불 구매가</em><b>' + fmt(lump) + '원</b></div><i aria-hidden="true"></i>' +
        '<div class="is-sub"><em>' + r.years + (r.pointsAll && !cash ? '년 실제 구독료<small>포인트 반영</small>' : r.pointsAll ? '년 결제 총액<small>포인트 ' + fmt(r.pointsAll) + 'P 별도</small>' : '년 구독 총액') + '</em><b>' + fmt(r.netTotal) + '원</b></div></div>' +
        '<span class="subtab-savebox-sub">' + esc(cond) + '</span></div>' :
      // 아니면 월 구독료 + 총액
      '<div class="subtab-monthbox" role="note"><span class="subtab-monthbox-label">선택한 혜택 적용 시 월 구독료</span>' +
        '<strong>월 ' + fmt(r.netMonthly) + '원</strong>' + (r.pointsAll ? '<span class="subtab-savebox-sub">' + (cash ? '포인트 ' + fmt(r.pointsAll) + 'P 따로 적립' : '포인트 매월 반영 · 실제 결제 월 ' + fmt(r.finalMonthly) + '원') + '</span>' : '') +
        '<span class="subtab-savebox-sub">' + r.years + (r.pointsAll && !cash ? '년 실제 구독료 ' : r.pointsAll ? '년 결제 총액 ' : '년 구독 총액 ') + fmt(r.netTotal) + '원 · ' + esc(cond) + '</span></div>';
    if (POL.texts.notice) h += '<p class="subtab-note">' + esc(POL.texts.notice) + '</p>';   // 안내 작은 글씨는 [조건별 구독가 확인하기] 안에만 (2026-11-03)
    h = top + sum +
      '<button type="button" class="subtab-acc" data-acc aria-expanded="' + state.open + '">조건별 구독가 확인하기<i aria-hidden="true"></i></button>' +
      '<div class="subtab-acc-body"' + (state.open ? '' : ' hidden') + '>' + h + '</div>';

    // 혜택 문구: 정책 기본 문구 + 기간 중인 행사 + 스킨 설정 extraPoints
    var points = (POL.texts.points || []).concat(promoTexts(info), CFG.extraPoints || []);
    if (points.length) h += '<ul class="subtab-points">' + points.map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('') + '</ul>';

    // 하단 고정 바 — 상담 신청만
    // CFG.source('goods'|'view'|…)·CFG.sourceName·CFG.utmSource 로 상담서에 남는 출처를 바꿀 수 있다 (구독 상품 페이지 sub_view 가 같은 파일을 쓴다)
    var srcName = CFG.sourceName || '상품상세 구독탭';
    var memo = '[' + srcName + '] ' + r.years + '년 · ' + careLabel(r.care) + ' · 월 ' + fmt(r.monthly) + '원' +
      (r.prepay ? ' · 선납 ' + Math.round(r.prepay * 100) + '%' : '') +
      (r.cardTotal ? ' · ' + state.card + ' ' + tierLabel(state.tier) : '') +
      ' → 월 납부 예상 ' + fmt(r.finalMonthly) + '원' + (r.pointsAll ? ' · 포인트 ' + fmt(r.pointsAll) + '원' + (r.mpoints ? ' (멤버십 ' + fmt(r.mpoints) + 'P 포함)' : '') + ' (실제 구독료 ' + fmt(r.expectedNet) + '원)' : '');
    var q = 'from=' + encodeURIComponent(CFG.source || 'goods') +
      '&product=' + encodeURIComponent((IDX.m[state.model] && IDX.cats[IDX.m[state.model][0]]) || CFG.productCat || '') +
      '&purpose=' + encodeURIComponent('신규구독') +
      '&model=' + encodeURIComponent(state.model) +
      '&memo=' + encodeURIComponent(memo) +
      '&src=' + encodeURIComponent(srcName + (CFG.goodsNo ? ' #' + CFG.goodsNo : '')) +
      '&utm_source=' + encodeURIComponent(CFG.utmSource || 'goods_view') + '&utm_medium=subtab&utm_campaign=' + encodeURIComponent(state.model);
    var discounted = r.finalMonthly < r.monthly - 0.5;
    h += '<div class="subtab-bar">' +
      '<div class="subtab-bar-row"><span>월 납부 예상금액</span><s' + (discounted ? '' : ' hidden') + '>월 ' + fmt(r.monthly) + '원</s></div>' +
      '<div class="subtab-bar-row is-main"><span>' + (r.cardTotal ? '제휴카드 적용가' : '혜택 적용가') + '</span><strong>월 ' + fmt(r.finalMonthly) + '원</strong></div>' +
      ctaHtml(consultBase() + q) + '</div>';

    els.panel.innerHTML = h;
    setHeadPrice(r);   // 조건을 바꾸면 탭 머리 가격도 같이
  }

  function render() { renderHead(); if (state.tab === 'sub') renderPanel(); }

  function openSub() {
    state.tab = 'sub';
    renderHead();
    renderPanel();
  }

  /* ---------- 하단 버튼 ----------
     CFG.cta: 'consult'(기본) = [상담하고 구독하기] + 전화 버튼(CFG.tel)
              'lump+consult'  = [시흥몰 가격 확인하기] + [구독 문의하기] 두 개 (전화 버튼 없음)
     시흥몰 가격 확인하기: CFG.lumpUrl 이 있으면 그 주소로(구독 상품 페이지 → 일반 상품), 없으면 일시불 탭으로 전환해 가격 영역으로 스크롤.
                           lumpUrl 도 없고 일시불 탭도 없으면(일시불가 0) 버튼을 숨긴다.
     라벨: CFG.lumpLabel · CFG.consultLabel */
  var PHONE_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/></svg>';
  // 상품상세(고도몰) 구독탭의 [시흥몰 가격 확인하기] 가 갈 곳 (2026-11-02): 시흥몰 [구독] 상품 페이지(카탈로그 7번째 항목 · 예: KU75MH80AFXKR → 1000000857),
  //   없으면 구독센터 상품 페이지(/data/gudok/view.html?model=…). 구독센터 자신(CFG.lumpUrl 지정)·구독 전용 페이지에서는 쓰지 않는다
  function subGoodsLink(m) {
    if (CFG.lumpUrl || state.subPage || !m) return '';
    var C = window.SUB_CATALOG && window.SUB_CATALOG.m, c = C && C[m], no = c && c[6] > 0 ? c[6] : 0;
    var cur = String(CFG.goodsNo || (document.querySelector('#frmView input[name="goodsNo"]') || {}).value || '');
    if (no && String(no) !== cur) return (CFG.goodsUrl || '/goods/goods_view.php?goodsNo=') + no + '&utm_source=' + encodeURIComponent(CFG.utmSource || 'goods_view') + '&utm_medium=subtab_sub&utm_campaign=' + encodeURIComponent(m);
    if (no) return '';   // 지금 보는 페이지가 그 구독 상품이면 버튼을 내지 않는다
    return (CFG.centerUrl || '/data/gudok/view.html?model=') + encodeURIComponent(m) + '&utm_source=' + encodeURIComponent(CFG.utmSource || 'goods_view') + '&utm_medium=subtab_center';
  }
  function ctaHtml(consultHref) {
    var tel = CFG.tel || (POL.defaults && POL.defaults.tel) || '';   // 스킨에 없으면 데이터센터 정책의 전화
    if (CFG.cta === 'lump+consult') {
      var subHref = subGoodsLink(state.model);
      var lumpOk = subHref ? true : ((!!CFG.lumpUrl || (CFG.lumpPrice > 0)) && !(pageModel && state.model !== pageModel));
      return '<div class="subtab-cta subtab-cta--two">' +
        (lumpOk ? '<a class="subtab-cta-lump" data-cta="lump" href="' + esc(CFG.lumpUrl || subHref || '#') + '">' + esc(CFG.lumpLabel || '시흥몰 가격 확인하기') + '</a>' : '') +
        '<a class="subtab-cta-main" data-cta="consult" href="' + esc(consultHref) + '">' + PHONE_SVG + esc(CFG.consultLabel || '구독 문의하기') + '</a>' +
        '</div>';
    }
    return '<div class="subtab-cta">' +
      '<a class="subtab-cta-main" data-cta="consult" href="' + esc(consultHref) + '">' + PHONE_SVG + esc(CFG.consultLabel || '상담하고 구독하기') + '</a>' +
      (tel ? '<a class="subtab-cta-sub" data-cta="tel" href="tel:' + esc(tel.replace(/[^0-9]/g, '')) + '">' + esc(tel) + '</a>' : '') +
      '</div>';
  }
  // 일시불 탭으로 전환하고 가격 영역을 보여준다
  function openLump() {
    state.tab = 'lump'; render();
    var target = null, sels = CFG.lumpOnly || ['.price-box'];
    for (var i = 0; i < sels.length && !target; i++) { try { target = document.querySelector(sels[i]); } catch (e) {} }
    if (target && target.scrollIntoView) target.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  // 구독요금을 전부 0 으로 막은 경우 등 → 일시불로 되돌리고 탭 숨김
  function hideTab() {
    if (state.tab === 'sub') { state.tab = 'lump'; renderHead(); }
    root.hidden = true;
  }

  function onClick(ev) {
    var t = ev.target.closest ? ev.target.closest('button, a') : null;
    if (!t || !root.contains(t) || t.disabled) return;
    if (t.hasAttribute('data-acc')) {
      state.open = !state.open; renderPanel(); track('sub_tab_conditions', { sub_open: state.open });
    } else if (t.hasAttribute('data-tab')) {
      if (t.getAttribute('data-tab') === 'sub') { openSub(); track('sub_tab_open'); }
      else if (!state.subPage) { state.tab = 'lump'; render(); }
    } else if (t.hasAttribute('data-model')) {
      var nm = t.getAttribute('data-model');
      if (nm && nm !== state.model) { setModel(nm, function () { if (!state.info) return; root.hidden = false; render(); }); track('sub_tab_model', { sub_model: nm }); }
    } else if (t.hasAttribute('data-year')) {
      state.year = +t.getAttribute('data-year'); renderPanel(); track('sub_tab_year', { sub_year: state.year });
    } else if (t.hasAttribute('data-type')) {
      state.type = t.getAttribute('data-type'); state.cycle = 0; renderPanel(); track('sub_tab_care', { sub_care: state.type });
    } else if (t.hasAttribute('data-cycle')) {
      state.cycle = +t.getAttribute('data-cycle'); renderPanel(); track('sub_tab_cycle', { sub_cycle: state.cycle });
    } else if (t.hasAttribute('data-prepay')) {
      state.prepay = +t.getAttribute('data-prepay'); state.prepaySet = true; renderPanel(); track('sub_tab_prepay', { sub_prepay: state.prepay });
    } else if (t.hasAttribute('data-ptmode')) {
      state.ptMode = t.getAttribute('data-ptmode') === 'cash' ? 'cash' : 'melt'; renderPanel(); track('sub_tab_ptmode', { sub_ptmode: state.ptMode });
    } else if (t.hasAttribute('data-help')) {
      var hk = t.getAttribute('data-help'); state.help[hk] = !state.help[hk]; renderPanel(); track('sub_tab_help', { sub_help: hk, sub_open: !!state.help[hk] });
    } else if (t.hasAttribute('data-cta')) {
      track('sub_tab_cta', { sub_cta: t.getAttribute('data-cta'), sub_year: state.year, sub_care: joinCare(state.type, state.cycle) });
      if (t.getAttribute('data-cta') === 'lump' && t.getAttribute('href') === '#') { ev.preventDefault(); openLump(); }
    }
  }
  function onChange(ev) {
    var t = ev.target;
    if (t.hasAttribute('data-card')) { state.card = t.value; state.tier = defaultTier(t.value); state.tierSet = false; state.cardOn = !!t.value; }
    else if (t.hasAttribute('data-tier')) { state.tier = t.value; state.tierSet = true; }
    else if (t.hasAttribute('data-cardon')) state.cardOn = t.checked;
    else return;
    renderPanel();
    track('sub_tab_card', { sub_card: state.cardOn ? state.card + ' ' + state.tier : '' });
  }

  /* ---------- 같은 모델 다른 색상 · 구독 전용 모델 (2026-11-02) ----------
     같은 품목·세부유형에서 모델명이 색상 글자만 다른 모델(규칙은 구독센터 sub_shop.js 의 SUB_FAMILY 와 같다)을 탭 안에서 바로 바꿔 볼 수 있게 한다.
     예: WD90H25AHS(다크스틸 · 일반 판매) ↔ WD90H25AHW(화이트 · 구독 전용 — 시흥몰에 일시불 상품이 없음). 구독 전용 모델은 월 구독료가 크게 다를 수 있어 둘 다 보여준다.
     이름·일시불 유무는 카탈로그(sub_catalog.js · 구독센터와 같은 파일)에서 읽는다 — 형제 모델이 있을 때만 받는다. CFG.siblings === false 면 끈다 (구독센터 상품 페이지는 자체 색상 목록이 있다) */
  var pageModel = '';
  function familyOf(model) {
    if (window.SUB_FAMILY) return window.SUB_FAMILY(model);
    var s = String(model || '').toUpperCase();
    // 세탁건조기 AI 콤보(WD90H25AHW · BHW · AHWN1 · BHWN1 …)는 A/B 가 출시 차수 차이라 한 묶음 — 구독 전용 AHW·AHWN1 이 BHW·BHWN1 상품 페이지에도 "최저가 · 구독 전용" 칩으로 보인다 (2026-11-02)
    var c = /^(WD\d+H\d+)[A-Z](H)([A-Z])(N\d)?$/.exec(s);
    if (c) return c[1] + c[2] + (c[4] || '');
    var m = /^(.*\d)([A-Z]+?)(N\d)?$/.exec(s);
    if (!m) return model;
    var letters = m[2], keep = letters.length >= 3 ? letters.slice(0, -1) : '';
    return m[1] + keep + (m[3] || '');
  }
  function siblings(model, info) {
    if (CFG.siblings === false) return [];
    var e = IDX.m[model]; if (!e) return [];
    var fam = familyOf(model), P = (window.SUB_PLANS || {})[e[0]] || {}, seg = info && info.s, out = [];
    for (var m in IDX.m) {
      if (m === model || IDX.m[m][0] !== e[0] || familyOf(m) !== fam) continue;
      if (seg && P[m] && P[m].s && P[m].s !== seg) continue;
      out.push(m);
    }
    out.sort(function (a, b) { return IDX.m[a][1] - IDX.m[b][1]; });
    return out;
  }
  // 시흥몰 상품(일시불 또는 구독 페이지)이 있는 모델인가 — 카탈로그가 아직 없으면 모른다(null)
  function hasGoods(m) { var C = window.SUB_CATALOG && window.SUB_CATALOG.m; return C ? !!(C[m] && C[m][0] > 0 && !C[m][5]) : null; }
  // 관리자·매장이 '구독 전용' 으로 표시한 모델 (카탈로그 6번째 항목 · mvp_259) — 시흥몰에 일시불 상품이 올라 있어도 구독 전용으로 다룬다
  function subOnlyFlag(m) { var C = window.SUB_CATALOG && window.SUB_CATALOG.m; return !!(C && C[m] && C[m][5]); }
  // 구독 전용 모델 = 시흥몰에 상품이 없고 월 구독료가 시흥몰 판매 모델과 다른 모델 (예: AI 콤보 WD90H25AHW)
  //   상품도 없고 요금도 같은 색상(예: WD90H25AHT)은 구독 전용이 아니라 시흥몰이 안 다루는 색상이라 칩에서 뺀다 (2026-11-02)
  function subOnlyOf(m, all) {
    if (subOnlyFlag(m)) return true;
    if (hasGoods(m) !== false) return false;
    var mine = IDX.m[m] ? IDX.m[m][1] : 0;
    return all.every(function (o) { return o === m || hasGoods(o) === false || !IDX.m[o] || IDX.m[o][1] !== mine; });
  }
  function siblingList(model, info) {   // 상품 페이지 모델 + 형제 모델 (중복 없이 · 시흥몰이 안 다루는 같은 요금 색상은 뺀다)
    var sibs = siblings(model, info);
    var all = [pageModel && pageModel !== model && sibs.indexOf(pageModel) < 0 ? pageModel : null].filter(Boolean).concat(sibs.indexOf(model) < 0 ? [model] : [], sibs);
    all = all.filter(function (m, i) { return all.indexOf(m) === i; });
    return all.filter(function (m) { return m === pageModel || m === model || hasGoods(m) !== false || subOnlyOf(m, all); });
  }
  // 가장 저렴한 모델(월 구독료 최저) — 상품 페이지 모델보다 싼 형제(구독 전용 등)가 있으면 그 모델을 먼저·기본으로 보여 준다
  function cheapestOf(model, info) {
    if (!IDX.m[model]) return model;
    var all = siblingList(model, info), best = model;
    all.forEach(function (m) { if (IDX.m[m] && IDX.m[m][1] < IDX.m[best][1]) best = m; });
    return best;
  }
  var catalogTried = false, catalogWait = [];
  function loadCatalog(cb) {   // 이름·시흥몰 상품 유무를 위해 카탈로그(sub_catalog.js)를 한 번 받아 온다 — 있으면 바로, 못 받으면 없이 진행
    if (window.SUB_CATALOG || (catalogTried && !catalogWait.length)) return cb();
    catalogWait.push(cb);
    if (catalogTried) return;
    catalogTried = true;
    var done = function () { var w = catalogWait; catalogWait = []; w.forEach(function (f) { f(); }); };
    loadScript('sub_catalog.js', function () { return !!window.SUB_CATALOG; }, done, done);
  }
  function colorOf(m) {
    var c = window.SUB_CATALOG && window.SUB_CATALOG.m && window.SUB_CATALOG.m[m];
    var name = c && c[1] ? String(c[1]).replace(/\s*\*+\s*$/, '') : '';
    var last = name ? name.split(/\s+/).pop() : '';
    return /^[가-힣]+$/.test(last) && last.length <= 6 ? last : '';   // 상품명 끝의 색상 낱말(다크스틸·그레이지·화이트 …)
  }
  // 칩 하나의 계산 — 지금 고른 약정·케어·선납·카드를 그 모델에 그대로 (그 조합이 없으면 그 모델의 최장 약정 기본 케어)
  function chipCalc(m) {
    var inf = null; getInfo(m, function (x) { inf = x; });   // 같은 품목 요금표는 이미 받아 둬서 바로 돌아온다
    if (!inf || !inf.p || !inf.p.length) return null;
    var plan = findPlan(inf, state.year, joinCare(state.type, state.cycle));
    if (!plan) {
      var ys = inf.p.map(function (x) { return x[0]; }), maxY = Math.max.apply(null, ys);
      var inY = inf.p.filter(function (x) { return x[0] === maxY; });
      var free = inY.filter(function (x) { return splitCare(x[1])[0] === '무상수리'; });
      plan = (free.length ? free : inY).slice().sort(function (a, b) { return a[3] - b[3]; })[0];
    }
    return calc(inf, plan, opts());
  }
  // 같은 모델 다른 색상 · 구독 전용 칩 (2026-11-03): 가장 저렴한 모델과 이 상품 두 개만. 이 상품 일시불가가 있으면 칩마다 "일시불 대비 ○○원 저렴"
  function siblingsHtml(info) {
    var sibs = siblings(state.model, info);
    if (!sibs.length) return '';
    if (!window.SUB_CATALOG) loadCatalog(function () { if (state.tab === 'sub') renderPanel(); });   // 이름·시흥몰 상품 유무 (못 받으면 모델명만)
    var all = siblingList(state.model, info), cheap = cheapestOf(state.model, info);
    var page = pageModel || state.model;
    if (!IDX.m[cheap] || !IDX.m[page] || cheap === page || IDX.m[cheap][1] >= IDX.m[page][1]) return '';   // 이 상품이 가장 저렴하면 칩을 내지 않는다
    var show = [cheap, page];
    if (show.indexOf(state.model) < 0 && IDX.m[state.model]) show.push(state.model);
    var lump = (CFG.lumpCompare !== 'never' && CFG.lumpPrice > 0) ? CFG.lumpPrice : 0;
    var h = '';
    show.forEach(function (m) {
      var color = colorOf(m), subOnly = subOnlyOf(m, all), cur = m === state.model, low = m === cheap;
      var tag = low ? (subOnly ? '최저가 · 구독 전용' : '최저가') : (m === page ? '이 상품' : (subOnly ? '구독 전용' : ''));
      var sv = '';
      if (lump) { var cr = chipCalc(m); if (cr && cr.expectedNet < lump) sv = '<strong>일시불 대비 ' + shortWon(lump - cr.expectedNet) + ' 저렴</strong>'; }
      h += '<button type="button" class="subtab-sib' + (cur ? ' is-active' : '') + (subOnly ? ' is-subonly' : '') + (low ? ' is-cheap' : '') + '" data-model="' + esc(m) + '" aria-pressed="' + cur + '">' +
        (tag ? '<em>' + tag + '</em>' : '') + '<b>' + esc(color || m) + '</b>' +
        '<span>월 ' + fmt(IDX.m[m][1]) + '원~</span>' + sv + '</button>';
    });
    var title = lump ? '이 상품 일시불 ' + fmt(lump) + '원 대비' : '더 저렴한 ' + (subOnlyOf(cheap, all) ? '구독 전용 모델' : '색상');
    return '<div class="subtab-sibs"><p class="subtab-sibs-t">' + title + '</p><div class="subtab-sibs-row">' + h + '</div></div>';
  }

  /* ---------- 옵션 변경 시 모델 다시 결정 ---------- */
  function refreshModel() {
    var m = resolveModel();
    if (!m) return hideTab();   // 선택된 옵션에 구독 모델이 없으면 일시불로 되돌리고 탭 숨김
    // 페이지의 모델이 그대로면 아무것도 하지 않는다 — 탭 안에서 형제 모델로 바꾼 상태를 지킨다
    // (고도몰 페이지는 네이버페이 배너 문구가 주기적으로 바뀌어 MutationObserver 가 계속 호출된다)
    if (m === pageModel) { if (state.info) root.hidden = false; return; }
    pageModel = m;   // 상품 페이지(선택한 옵션)의 모델 — 일시불 비교·[이 상품] 표시 기준 (탭 안 형제 모델 칩은 이 값을 바꾸지 않는다)
    m = cheapestOf(m, null);   // 옵션이 바뀌어 모델이 바뀌면 그 모델의 가장 저렴한 형제로
    if (m === state.model) { if (state.info) root.hidden = false; render(); return; }
    setModel(m, function () {
      if (!state.info) return hideTab();
      root.hidden = false;
      render();
    });
  }

  // 추가항목 "구독모델/구독요금" 은 내부 관리용 → 상품정보 목록(item_detail_list)에 나와도 숨긴다
  function hideAdminInfoRows() {
    var titles = [CFG.addInfoTitle || '구독모델', CFG.feeInfoTitle || '구독요금'];
    var dts = document.querySelectorAll('.item_detail_list dt');
    for (var i = 0; i < dts.length; i++) {
      var t = dts[i].textContent.replace(/^\s+/, '');
      if (t.indexOf(titles[0]) === 0 || t.indexOf(titles[1]) === 0) dts[i].parentNode.style.display = 'none';
    }
  }

  // 상담 신청 페이지 주소 — 이미 ?htmid=… 가 붙어 있으면 & 로 잇는다. 관심 모델·품목·메모는 그 뒤의 from/product/model/memo 로 넘어가 자동 채움된다
  function consultBase() {
    var u = CFG.consultUrl || (POL.defaults && POL.defaults.consultUrl) || '/main/html.php?htmid=service/SamSungSubscription.html';
    return u + (u.indexOf('?') >= 0 ? '&' : '?');
  }

  // 단계적 오픈 스위치
  //   CFG.enabled  : true(전체 오픈) | false(끔) | 'test'(주소에 ?subtab=on 을 붙인 사람만 보임, 이 탭/창에서 유지)
  //   CFG.onlyGoods: ['1000000123', …] 이 상품번호들에서만 동작 (비우면 전체)
  function isEnabled() {
    var en = CFG.enabled === undefined ? true : CFG.enabled;
    if (en === false || en === 'false') return false;
    if (CFG.onlyGoods && CFG.onlyGoods.length && CFG.onlyGoods.indexOf(String(CFG.goodsNo)) < 0) return false;
    // 대표 카테고리가 구독상품(012)·그 하위인 상품은 구독 전용 상품 페이지 → 일시불 탭 없이 계산기만 띄운다 (구독 전용 페이지 모드 · 2026-11-02)
    //   CFG.subPage === false 면 예전처럼 아예 띄우지 않는다. 카테고리 목록은 CFG.skipCate 로 바꿀 수 있다
    var cate = document.querySelector('#frmView input[name="cateCd"]'), cc = cate ? String(cate.value || '') : '';
    if (cc && (CFG.skipCate || ['012']).some(function (c) { return cc.indexOf(c) === 0; })) {
      if (CFG.subPage === false) return false;
      state.subPage = true;
    }
    if (en !== 'test') return true;
    var qs = location.search, on = /[?&]subtab=on(&|$)/.test(qs);
    try {
      if (on) sessionStorage.setItem('subtab', 'on');
      if (/[?&]subtab=off(&|$)/.test(qs)) sessionStorage.removeItem('subtab');
      return sessionStorage.getItem('subtab') === 'on';
    } catch (e) { return on; }
  }

  function init() {
    hideAdminInfoRows();                    // 내부 관리용 추가항목은 스위치와 상관없이 항상 숨김
    if (!isEnabled()) return;
    readSource();
    CFG.lumpPrice = parseFloat(CFG.lumpPrice) || 0;
    if (state.subPage) { CFG.lumpPrice = 0; CFG.lumpUrl = ''; CFG.lumpCompare = 'never'; }   // 구독 전용 페이지의 판매가는 월 구독료 자리표시라 일시불 비교에 쓰지 않는다
    var m = resolveModel();
    if (!m) return;                         // 구독 모델이 아닌 상품 → 아무 변화 없음
    pageModel = m;                          // 상품 페이지의 모델 (일시불 비교·[이 상품] 표시 기준)
    if (!build()) return;
    root.hidden = true;
    loadCatalog(function () {               // 구독 전용 판정에 카탈로그가 필요하다 — 못 받으면 상품 페이지 모델로
    if (subOnlyFlag(m) && !state.subPage) {   // 이 상품 페이지의 모델이 구독 전용으로 표시돼 있으면 일시불 비교·일시불 탭 없이 계산기만 (구독 전용 페이지 모드와 같다)
      state.subPage = true; CFG.lumpPrice = 0; CFG.lumpUrl = ''; CFG.lumpCompare = 'never'; root.classList.add('is-subpage');
    }
    setModel(cheapestOf(m, null), function () {   // 기본 선택: 가장 저렴한 모델 (예: WD90H25AHS 페이지 → 구독 전용 WD90H25AHW 의 총 구독가를 탭 머리에)
      if (!state.info) return;              // 구독요금으로 전부 숨긴 경우
      root.hidden = false;
      document.documentElement.classList.add('has-subtab');
      renderHead();
      track('sub_tab_view');
      if (state.subPage || CFG.defaultTab === 'sub' || /[?&]buy=sub(&|$)/.test(location.search)) openSub();
    });
    });

    var frm = document.getElementById('frmView');
    if (frm) {
      frm.addEventListener('change', function (e) { if (!root.contains(e.target)) setTimeout(refreshModel, 300); });
      // 고도몰은 옵션 선택 결과를 표(optionSno[])로 그리므로 표 변화도 감시 (탭 내부 변화는 무시)
      if (window.MutationObserver) new MutationObserver(function (list) {
        for (var i = 0; i < list.length; i++) if (!root.contains(list[i].target)) return setTimeout(refreshModel, 50);
      }).observe(frm, { childList: true, subtree: true });
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
}

(function () {
  if (window.SUB_INDEX && window.SUB_INDEX.m) return main();          // 1) 데이터가 이미 있다
  var CFG = window.SUB_TAB_CONFIG = window.SUB_TAB_CONFIG || {};
  var dc = CFG.dcBase || '', local = CFG.dataBase || '/data/js/sub/', q = function (v) { return encodeURIComponent(v || ''); };
  function add(src, ok, fail) {
    var s = document.createElement('script'); s.charset = 'utf-8'; s.src = src;
    s.onload = ok; s.onerror = fail || ok; document.head.appendChild(s);
  }
  function run() { if (window.SUB_INDEX && window.SUB_INDEX.m) main(); }
  function fromLocal() {                                              // 데이터센터를 못 읽음 → 고도몰 예비 사본
    if (CFG.dcFailed) return;
    CFG.dcFailed = !!dc; CFG.dataBase = local; CFG.ver = CFG.localVer || CFG.ver || '';
    add(local + 'sub_index.js?v=' + q(CFG.ver), run);
  }
  if (!dc) return fromLocal();
  add(dc + 'version.js?t=' + Math.floor(Date.now() / 300000), function () {   // 판 번호는 5분 단위로 새로 읽는다
    if (!window.SUB_VER) return fromLocal();
    CFG.localBase = local; CFG.localVer = CFG.ver; CFG.dataBase = dc; CFG.ver = window.SUB_VER;
    add(dc + 'sub_index.js?v=' + q(window.SUB_VER), run, fromLocal);
  }, fromLocal);
})();
