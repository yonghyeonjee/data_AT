/* ===== 상품상세 일시불/구독 탭 | 모듈 goods/_sub_tab.html 에서 SUB_TAB_CONFIG 설정 후 로드 =====
   동작 순서
   1) 모델번호 결정: 옵션의 자체옵션코드 → 추가항목 "구독모델" → 상품 모델번호 → 자체상품코드
   2) SUB_INDEX(모델→카테고리) 에 있으면 탭 표시(자리 #subTabRoot 가 없으면 가격 박스 위에 만든다), 없으면 아무것도 하지 않음 (일반 상품 영향 없음)
   3) 구독 모델이면 해당 카테고리 요금표(sub_plans_<키>.js)와 카드표(sub_cards.js)를 추가 로드
   4) 추가항목 "구독요금" 이 있으면 파일 요금보다 우선 적용
        구독요금            = 6년 무상수리 13420 / 6년 방문케어 20,020 / 6년 방문케어36 15840 / 3년 무상수리 0
        구독요금 RP20C3111S9 = (옵션 모델별로 따로 지정할 때)
      같은 약정+케어는 덮어쓰고, 없던 조합은 추가, 0 은 그 요금제를 숨김
   5) 할인율·선납 한도·카드 유의사항·행사 문구는 sub_policy.js(SUB_POLICY) 에서 읽는다
      파일이 없거나 못 불러오면 아래 DEFAULT_POLICY(현재 정책값)로 계산한다
   ※ 금액 계산은 calc_subscribe.html 과 같은 식을 쓴다
      - 구독료 할인(자동납부)·선납 할인: calcDiscount  (정수기는 본사 사전계산값 WATER_POLICY)
      - 선납금: ROUND(총구독료 × 선납비율 / 1.1 / 개월, -2) × 개월 × 1.1
      - 제휴카드: 월 혜택 × 계약 개월 (삼성카드 70만↑ 구간은 월구독료 7만원 미만이면 기본할인만)
        단, 고객 화면에서는 월 납부액을 넘는 카드 할인은 월 납부액까지만 반영한다 (카드사 약관)
===== */
(function () {
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
      notes: ['선납금은 구독 신청 시에만 선택할 수 있으며, 구독 기간 중에는 변경이 어렵습니다.']
    },
    cards: {}, cardNotes: [], promos: [],
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
    year: 0, type: '', cycle: 0, prepay: 0,
    card: '', tier: '', cardOn: true
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
  function autopayLabel() { return String(POL.autopay.label || '구독료 {rate} 할인 (자동납부)').replace('{rate}', pct(POL.autopay.rate)); }
  // 노출할 카드: 카드표에 있고, 정책에서 숨김·기간 밖이 아닌 카드
  function cardNames() {
    var cards = window.SUB_CARDS || {}, pc = POL.cards || {};
    return Object.keys(cards).filter(function (n) { return !pc[n] || inPeriod(pc[n]); });
  }
  // 이 상품에 해당하는 행사 문구 (기간 + 대상 품목/모델/상품번호)
  function promoTexts(info) {
    return (POL.promos || []).filter(function (p) {
      if (!p || !p.text || !inPeriod(p)) return false;
      if (p.cats && p.cats.length && p.cats.indexOf(info.cat) < 0) return false;
      if (p.models && p.models.length && p.models.map(norm).indexOf(state.model) < 0) return false;
      if (p.goods && p.goods.length && p.goods.map(String).indexOf(String(CFG.goodsNo)) < 0) return false;
      return true;
    }).map(function (p) { return p.text; });
  }

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
    var lump = CFG.lumpPrice || 0;
    r.saving = (lump > 0 && r.expected < lump && CFG.lumpCompare !== 'never') ? lump - r.expected : 0;
    return r;
  }
  function opts() { return { prepay: state.prepay, card: state.card, tier: state.tier, cardOn: state.cardOn }; }

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
    return type + '(' + cycle + '개월주기)';
  }
  function careLabel(c) {
    var s = splitCare(c);
    return s[0] === '무상수리' ? TYPE_LABEL['무상수리'] : TYPE_LABEL[s[0]] + ' (' + s[1] + '개월)';
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
    s.src = (CFG.dataBase || '/data/js/sub/') + file + '?v=' + (CFG.ver || IDX.ver);
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
    function done(file) { merged[model] = mergeInfo(file, OVR[model], e && IDX.cats[e[0]]); cb(merged[model]); }
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
    var dc = cardNames().indexOf(CFG.defaultCard) >= 0 ? CFG.defaultCard : '';
    var o = { prepay: 0, card: dc, tier: defaultTier(dc), cardOn: !!dc }, best = 0;
    info.p.forEach(function (p) { best = Math.max(best, calc(info, p, o).saving); });
    return best;
  }
  function defaultTier(name) {
    var cd = window.SUB_CARDS && window.SUB_CARDS[name];
    if (!cd) return '';
    var tiers = Object.keys(cd.t);
    return tiers.indexOf(CFG.defaultTier) >= 0 ? CFG.defaultTier : tiers[0];
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
        if (!state.card && CFG.defaultCard && cardNames().indexOf(CFG.defaultCard) >= 0) {
          state.card = CFG.defaultCard; state.tier = defaultTier(CFG.defaultCard);
        }
        if (cb) cb();
      }); });
    });
  }

  /* ---------- 선택값 정리 ---------- */
  function plansOf(info, y) { return info.p.filter(function (p) { return p[0] === y; }); }
  function normalizeSelection(info) {
    var years = [];
    info.p.forEach(function (p) { if (years.indexOf(p[0]) < 0) years.push(p[0]); });
    years.sort(function (a, b) { return a - b; });
    if (years.indexOf(state.year) < 0) {
      // 최장 약정 중 가장 저렴한 케어 (탭 라벨의 "월 X원~" 과 맞춘다)
      state.year = years[years.length - 1];
      var cheap = plansOf(info, state.year).sort(function (a, b) { return a[3] - b[3]; })[0];
      var sc = splitCare(cheap[1]); state.type = sc[0]; state.cycle = sc[1];
    }
    var inYear = plansOf(info, state.year);
    var types = [];
    inYear.forEach(function (p) { var t = splitCare(p[1])[0]; if (types.indexOf(t) < 0) types.push(t); });
    types.sort(function (a, b) { return TYPE_ORDER.indexOf(a) - TYPE_ORDER.indexOf(b); });
    if (types.indexOf(state.type) < 0) state.type = types[0];
    var cycles = [];
    inYear.forEach(function (p) { var s = splitCare(p[1]); if (s[0] === state.type && s[1] && cycles.indexOf(s[1]) < 0) cycles.push(s[1]); });
    cycles.sort(function (a, b) { return a - b; });
    if (state.type === '무상수리') state.cycle = 0;
    else if (cycles.indexOf(state.cycle) < 0) state.cycle = cycles.indexOf(12) >= 0 ? 12 : cycles[0];
    var maxR = prepayMax(info);
    if (state.prepay > maxR + 1e-9) state.prepay = 0;
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
      '<button type="button" role="tab" class="subtab-btn" data-tab="sub"><span>구독<em class="subtab-badge">혜택</em></span><strong data-slot="sub-price"></strong>' +
      '<em class="subtab-save" data-slot="sub-save" hidden></em></button>' +
      '</div><div class="subtab-panel" data-slot="panel" hidden></div>';
    els.lumpPrice = root.querySelector('[data-slot="lump-price"]');
    els.subPrice = root.querySelector('[data-slot="sub-price"]');
    els.subSave = root.querySelector('[data-slot="sub-save"]');
    els.panel = root.querySelector('[data-slot="panel"]');
    els.lumpPrice.textContent = CFG.lumpPrice > 0 ? fmt(CFG.lumpPrice) + '원' : '';
    root.addEventListener('click', onClick);
    root.addEventListener('change', onChange);
    return true;
  }

  function renderHead() {
    els.subPrice.textContent = state.min ? '월 ' + fmt(state.min) + '원~' : '';
    els.subSave.hidden = !state.best;
    els.subSave.textContent = state.best ? '카드 적용 시 최대 ' + fmt(state.best) + '원 저렴' : '';
    root.classList.toggle('is-cheaper', !!state.best);
    var btns = root.querySelectorAll('.subtab-btn');
    for (var i = 0; i < btns.length; i++) {
      var on = btns[i].getAttribute('data-tab') === state.tab;
      btns[i].classList.toggle('is-active', on);
      btns[i].setAttribute('aria-selected', on ? 'true' : 'false');
    }
    // 구독 탭일 때는 일시불 전용 영역(가격·장바구니·간편결제)을 숨긴다
    (CFG.lumpOnly || []).forEach(function (sel) {
      var nodes = document.querySelectorAll(sel);
      for (var j = 0; j < nodes.length; j++) nodes[j].classList.toggle('subtab-hide', state.tab === 'sub');
    });
    els.panel.hidden = state.tab !== 'sub';
  }

  function optBtn(attrs, active, inner, extraCls) {
    return '<button type="button" class="subtab-opt' + (extraCls ? ' ' + extraCls : '') + (active ? ' is-active' : '') + '" ' + attrs + '>' + inner + '</button>';
  }
  function row(label, value, cls) {
    return '<div' + (cls ? ' class="' + cls + '"' : '') + '><dt>' + label + '</dt><dd>' + value + '</dd></div>';
  }

  function renderPanel() {
    var info = state.info;
    if (!info) { els.panel.innerHTML = '<p class="subtab-note">요금 정보를 불러오는 중…</p>'; return; }
    var sel = normalizeSelection(info);
    var plan = findPlan(info, state.year, joinCare(state.type, state.cycle));
    var r = calc(info, plan, opts());
    var lump = CFG.lumpPrice || 0, maxYear = sel.years[sel.years.length - 1];
    var h = '';

    h += '<p class="subtab-model">구독 모델 <b>' + esc(state.model) + '</b>' + (info.s ? ' · ' + esc(info.s) : '') + '</p>';

    // 약정 기간
    h += '<fieldset class="subtab-field"><legend>약정 기간</legend><div class="subtab-grid">';
    sel.years.forEach(function (y) {
      h += optBtn('data-year="' + y + '"', y === state.year,
        (y === maxYear ? '<i class="subtab-rec">추천</i>' : '') + '<b>' + y + '년 약정</b><span>' + (y * 12) + '개월 플랜</span>');
    });
    h += '</div></fieldset>';

    // 구독 케어 유형
    h += '<fieldset class="subtab-field"><legend>구독 케어 유형</legend><div class="subtab-grid subtab-grid--1">';
    sel.types.forEach(function (t) {
      var low = Math.min.apply(null, sel.inYear.filter(function (p) { return splitCare(p[1])[0] === t; }).map(function (p) { return p[3]; }));
      h += optBtn('data-type="' + t + '"', t === state.type, '<b>' + TYPE_LABEL[t] + '</b><span>월 ' + fmt(low) + '원~</span>', 'subtab-opt--row');
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
    h += '<fieldset class="subtab-field"><legend>선납금<small>선납 시 월 구독료가 즉시 낮아집니다</small></legend><div class="subtab-grid subtab-grid--2">';
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

    // 일시불보다 저렴하면 강조
    if (r.saving) {
      h += '<div class="subtab-savebox" role="note"><span class="subtab-savebox-label">선택한 혜택 적용 시 일시불 구매보다</span>' +
        '<strong>' + fmt(r.saving) + '원 저렴해요</strong>' +
        '<span class="subtab-savebox-sub">' + r.years + '년 결제 예상액 ' + fmt(r.expected) + '원 · 일시불 ' + fmt(lump) + '원 · ' +
        Math.floor(r.saving / lump * 100) + '% 절약</span></div>';
    }

    // 결제 예상 내역
    h += '<section class="subtab-field"><div class="subtab-legend">결제 예상 내역</div><dl class="subtab-sum">';
    h += row('총 구독금액 (' + r.years + '년)', fmt(r.total) + '원');
    if (r.prepay) h += row('선납 할인 (선납 ' + Math.round(r.prepay * 100) + '% · ' + Math.round(r.prepayRate * 100) + '%)', '-' + fmt(r.prepayDisc) + '원', 'is-blue');
    h += row(esc(autopayLabel()), '-' + fmt(r.autoDisc) + '원', 'is-blue');
    if (r.cardTotal) h += row('제휴카드 혜택 (' + esc(state.card) + ')', '-' + fmt(r.cardTotal) + '원', 'is-blue');
    h += row('결제 예상액', fmt(r.expected) + '원', 'is-total');
    if (r.prepay) h += row('└ 선납금 (신청 시 1회)', fmt(r.prepayAmt) + '원', 'is-muted');
    var cmp = CFG.lumpCompare || 'auto';
    if (lump > 0 && (cmp === 'always' || (cmp === 'auto' && r.saving))) h += row('일시불 구매가', fmt(lump) + '원', 'is-muted');
    h += '</dl></section>';

    // 혜택 문구: 정책 기본 문구 + 기간 중인 행사 + 스킨 설정 extraPoints
    var points = (POL.texts.points || []).concat(promoTexts(info), CFG.extraPoints || []);
    if (points.length) h += '<ul class="subtab-points">' + points.map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('') + '</ul>';
    if (POL.texts.notice) h += '<p class="subtab-note">' + esc(POL.texts.notice) + '</p>';

    // 하단 고정 바 — 상담 신청만
    // CFG.source('goods'|'view'|…)·CFG.sourceName·CFG.utmSource 로 상담서에 남는 출처를 바꿀 수 있다 (구독 상품 페이지 sub_view 가 같은 파일을 쓴다)
    var srcName = CFG.sourceName || '상품상세 구독탭';
    var memo = '[' + srcName + '] ' + r.years + '년 · ' + careLabel(r.care) + ' · 월 ' + fmt(r.monthly) + '원' +
      (r.prepay ? ' · 선납 ' + Math.round(r.prepay * 100) + '%' : '') +
      (r.cardTotal ? ' · ' + state.card + ' ' + tierLabel(state.tier) : '') +
      ' → 월 납부 예상 ' + fmt(r.finalMonthly) + '원';
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
      '<div class="subtab-bar-row is-main"><span>' + (r.cardTotal ? '제휴카드 적용가' : '혜택 적용가') + '</span><strong>월 ' + fmt(r.finalMonthly) + '원~</strong></div>' +
      '<div class="subtab-cta">' +
      '<a class="subtab-cta-main" data-cta="consult" href="' + esc(consultBase() + q) + '">' +
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/></svg>' +
      '상담하고 구독하기</a>' +
      (CFG.tel ? '<a class="subtab-cta-sub" data-cta="tel" href="tel:' + esc(CFG.tel.replace(/[^0-9]/g, '')) + '">' + esc(CFG.tel) + '</a>' : '') +
      '</div></div>';

    els.panel.innerHTML = h;
  }

  function render() { renderHead(); if (state.tab === 'sub') renderPanel(); }

  function openSub() {
    state.tab = 'sub';
    renderHead();
    renderPanel();
  }

  // 구독요금을 전부 0 으로 막은 경우 등 → 일시불로 되돌리고 탭 숨김
  function hideTab() {
    if (state.tab === 'sub') { state.tab = 'lump'; renderHead(); }
    root.hidden = true;
  }

  function onClick(ev) {
    var t = ev.target.closest ? ev.target.closest('button, a') : null;
    if (!t || !root.contains(t) || t.disabled) return;
    if (t.hasAttribute('data-tab')) {
      if (t.getAttribute('data-tab') === 'sub') { openSub(); track('sub_tab_open'); }
      else { state.tab = 'lump'; render(); }
    } else if (t.hasAttribute('data-year')) {
      state.year = +t.getAttribute('data-year'); renderPanel(); track('sub_tab_year', { sub_year: state.year });
    } else if (t.hasAttribute('data-type')) {
      state.type = t.getAttribute('data-type'); state.cycle = 0; renderPanel(); track('sub_tab_care', { sub_care: state.type });
    } else if (t.hasAttribute('data-cycle')) {
      state.cycle = +t.getAttribute('data-cycle'); renderPanel(); track('sub_tab_cycle', { sub_cycle: state.cycle });
    } else if (t.hasAttribute('data-prepay')) {
      state.prepay = +t.getAttribute('data-prepay'); renderPanel(); track('sub_tab_prepay', { sub_prepay: state.prepay });
    } else if (t.hasAttribute('data-cta')) {
      track('sub_tab_cta', { sub_cta: t.getAttribute('data-cta'), sub_year: state.year, sub_care: joinCare(state.type, state.cycle) });
    }
  }
  function onChange(ev) {
    var t = ev.target;
    if (t.hasAttribute('data-card')) { state.card = t.value; state.tier = defaultTier(t.value); state.cardOn = !!t.value; }
    else if (t.hasAttribute('data-tier')) state.tier = t.value;
    else if (t.hasAttribute('data-cardon')) state.cardOn = t.checked;
    else return;
    renderPanel();
    track('sub_tab_card', { sub_card: state.cardOn ? state.card + ' ' + state.tier : '' });
  }

  /* ---------- 옵션 변경 시 모델 다시 결정 ---------- */
  function refreshModel() {
    var m = resolveModel();
    if (!m) return hideTab();   // 선택된 옵션에 구독 모델이 없으면 일시불로 되돌리고 탭 숨김
    if (m === state.model) { if (state.info) root.hidden = false; return; }
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
    var u = CFG.consultUrl || '/main/html.php?htmid=service/SamSungSubscription.html';
    return u + (u.indexOf('?') >= 0 ? '&' : '?');
  }

  // 단계적 오픈 스위치
  //   CFG.enabled  : true(전체 오픈) | false(끔) | 'test'(주소에 ?subtab=on 을 붙인 사람만 보임, 이 탭/창에서 유지)
  //   CFG.onlyGoods: ['1000000123', …] 이 상품번호들에서만 동작 (비우면 전체)
  function isEnabled() {
    var en = CFG.enabled === undefined ? true : CFG.enabled;
    if (en === false || en === 'false') return false;
    if (CFG.onlyGoods && CFG.onlyGoods.length && CFG.onlyGoods.indexOf(String(CFG.goodsNo)) < 0) return false;
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
    var m = resolveModel();
    if (!m) return;                         // 구독 모델이 아닌 상품 → 아무 변화 없음
    if (!build()) return;
    root.hidden = true;
    setModel(m, function () {
      if (!state.info) return;              // 구독요금으로 전부 숨긴 경우
      root.hidden = false;
      document.documentElement.classList.add('has-subtab');
      renderHead();
      track('sub_tab_view');
      if (CFG.defaultTab === 'sub' || /[?&]buy=sub(&|$)/.test(location.search)) openSub();
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
})();
