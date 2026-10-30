/* ===== 다품목 구독 계산기 | /data/gudok/bundle.html 에서 SUB_BUNDLE_CONFIG 설정 후 로드 (2026-10-30) =====
   여러 대를 한 번에: 상품을 담고 → 대마다 약정·케어·선납을 고르고 → 제휴카드 하나를 고르면 월 납부액 합계가 나온다.
   금액 식은 상품상세 구독탭(sub_tab.js) 의 SUB_CALC 를 그대로 쓴다 → 한 대씩 본 금액과 항상 같다.
   담은 목록은 localStorage(ss_bundle_v1 · sub_shop.js 의 SUB_CART 와 같은 키)에 남아 구독센터 어느 화면에서 담아도 여기로 모인다.
   주소
     bundle.html?preset=newlywed          생활 유형 프리셋 (sub_shop.js 의 SUB_PERSONAS 와 같은 키)
     bundle.html?items=RM80F91H1X,WD90H25AHY   모델을 바로 담기 (모델~약정~케어~선납 으로 조건까지)
   ※ 다품목 추가 혜택(정책 bundle.rate · bundle.min)은 데이터센터 구독 혜택 정책에 있을 때만 계산에 넣는다. 없으면 "상담 시 안내" 로만.
===== */
window.SUB_BUNDLE_READY = true;
(function () {
  'use strict';
  var CFG = window.SUB_BUNDLE_CONFIG || {};
  var IDX = window.SUB_INDEX;
  var root = document.getElementById('subBundleRoot');
  if (!root) return;
  if (!IDX || !IDX.m) { root.innerHTML = '<p class="sb-empty">구독 요금 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.</p>'; return; }

  var MAX = 10;
  var CAT_ICON = { ref: '🧊', kimchi: '🥬', water: '💧', tv: '📺', monitor: '🖥️', audio: '🔊', laundry: '👕', cleaner: '🧹',
    aircon: '❄️', sysaircon: '🌬️', cooking: '🍳', airpurifier: '🍃', dehumid: '💨', tab: '📱', book: '💻' };
  // 생활 유형 프리셋 → 품목(구독센터 품목 키: 요금 품목 + 세부유형 조건)  ※ sub_shop.js 의 SUB_PERSONAS 와 같은 키
  var PAGE_SEG = { aicombo: ['laundry', /콤보/], washer: ['laundry', /^(드럼|전자동|세탁기\+건조기)/], dryer: ['laundry', /^건조기/], airdresser: ['laundry', /벌식/],
    dishwasher: ['cooking', /인용|카운터탑/], induction: ['cooking', /전기레인지|인덕션|후드/] };
  var PRESETS = { newlywed: ['ref', 'aicombo', 'tv', 'cleaner'], movein: ['ref', 'kimchi', 'aircon', 'washer', 'dryer'], moving: ['ref', 'washer', 'tv'],
    dualincome: ['aicombo', 'dishwasher', 'cleaner', 'airdresser'], family: ['ref', 'kimchi', 'dishwasher', 'induction'], kitchen: ['ref', 'dishwasher', 'induction', 'water'] };
  // 프리셋이 품목 안에서 먼저 찾는 세부유형·이름 (없으면 전체에서)
  var PRESET_PREF = { ref: /4도어|키친핏/, kimchi: /스탠드|김치플러스/, tv: /65|75/, cleaner: /로봇|무선|제트/, aircon: /스탠드|2in1|멀티/, washer: /드럼/, dryer: /건조기/, water: /정수기/ };
  var PRESET_NAME = { newlywed: '신혼집', movein: '새 아파트 입주', moving: '이사 · 교체', dualincome: '맞벌이 · 1인 가구', family: '3~4인 가족', kitchen: '주방 리모델링' };

  function fmt(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function norm(s) { return String(s || '').replace(/\s+/g, '').toUpperCase(); }
  function param(name) { var m = location.search.match(new RegExp('[?&]' + name + '=([^&]*)')); if (!m) return ''; try { return decodeURIComponent(m[1].replace(/\+/g, ' ')); } catch (e) { return m[1]; } }
  function track(name, extra) { var ev = { event: name }; for (var k in extra) ev[k] = extra[k]; if (window.dataLayer) window.dataLayer.push(ev); }
  function cleanName(s) { return String(s || '').replace(/\s*\*+\s*$/, '').replace(/\s*(삼성본사직배송|본사직배송)\s*/g, ' ').replace(/\s{2,}/g, ' ').replace(/^\s|\s$/g, ''); }
  function loadScript(src, ok, fail) { var s = document.createElement('script'); s.src = src; s.charset = 'utf-8'; s.onload = ok; s.onerror = fail || ok; document.head.appendChild(s); }
  var BASE = CFG.dataBase || '/data/js/sub/', VER = encodeURIComponent(CFG.ver || IDX.ver || '');
  function viewUrl(m) { return (CFG.viewUrl || '/main/html.php?htmid=subscribe/sub_view.html&model=') + encodeURIComponent(m) + '&utm_source=sub_bundle&utm_medium=item'; }
  function familyKey(m) {
    if (window.SUB_FAMILY) return window.SUB_FAMILY(m);
    var x = /^(.*\d)([A-Z]+?)(N\d)?$/.exec(String(m || '').toUpperCase());
    if (!x) return m;
    return x[1] + (x[2].length >= 3 ? x[2].slice(0, -1) : '') + (x[3] || '');
  }
  var SEG_LABEL_RULES = [
    [/^Entry_-(\d+)_더무빙$/, '$1형 이하 · 더 무빙스타일'], [/ \+ 4K_-(\d+)$/, ' + 보조 TV $1형 이하'], [/\(2인\)/, '(2인 설치)'],
    [/^Premium_4K_/, '프리미엄 4K '], [/^Premium_/, '프리미엄 '], [/^Entry_/, ''], [/^일반모니터 /, '일반 '],
    [/(\d+)이하/, '$1형 이하'], [/(\d+)이상 \((\d+)-(\d+)\)/, '$2~$3형'],
    [/(^|[ (])(\d{2,3})-(\d{2,3})(?=$|[ )(])/, '$1$2~$3형'], [/(^|[ _])-(\d{2,3})$/, '$1$2형 이하'],
    [/_M1\/M7$/, ' · 스마트 M1/M7'], [/_OLED$/, ' · OLED'], [/^SD Sound Device /, '사운드바 '],
    [/^AI로봇청소기_26신제품/, 'AI 로봇청소기 2026'], [/_/g, ' ']
  ];
  function segLabel(seg) { var s = String(seg || ''); for (var i = 0; i < SEG_LABEL_RULES.length; i++) s = s.replace(SEG_LABEL_RULES[i][0], SEG_LABEL_RULES[i][1]); return s.replace(/\s+/g, ' ').replace(/^\s|\s$/g, '').replace(/\s*공통$/, ''); }

  /* ---------- 바구니 (sub_shop.js 의 SUB_CART 와 같은 저장소) ---------- */
  var CART_KEY = 'ss_bundle_v1';
  function cartGet() { if (window.SUB_CART) return window.SUB_CART.get(); try { var v = JSON.parse(localStorage.getItem(CART_KEY) || '[]'); return v instanceof Array ? v : []; } catch (e) { return []; } }
  function cartSet(items) {
    items = items.slice(0, MAX);
    if (window.SUB_CART) return window.SUB_CART.set(items);
    try { localStorage.setItem(CART_KEY, JSON.stringify(items)); } catch (e) {}
    try { document.dispatchEvent(new CustomEvent('ss-cart')); } catch (e2) {}
  }
  function cartAdd(m, opt, silent) {
    if (!IDX.m[m]) return false;
    var items = cartGet(), i = -1;
    items.forEach(function (it, k) { if (it.m === m) i = k; });
    var it = { m: m }; if (opt) for (var k in opt) if (opt[k] !== undefined && opt[k] !== '') it[k] = opt[k];
    if (i >= 0) { for (var k2 in items[i]) if (it[k2] === undefined) it[k2] = items[i][k2]; items[i] = it; }
    else { if (items.length >= MAX) { if (!silent) toast('최대 ' + MAX + '개까지 담을 수 있습니다'); return false; } items.push(it); }
    cartSet(items); return true;
  }
  function cartRemove(m) { cartSet(cartGet().filter(function (it) { return it.m !== m; })); }
  function cartHas(m) { return cartGet().some(function (it) { return it.m === m; }); }
  function toast(msg) {
    var t = document.getElementById('ssToast');
    if (!t) { t = document.createElement('div'); t.id = 'ssToast'; t.className = 'ss-toast'; document.body.appendChild(t); }
    t.innerHTML = '<span>' + esc(msg) + '</span>'; t.classList.add('is-on');
    clearTimeout(toast.t); toast.t = setTimeout(function () { t.classList.remove('is-on'); }, 2500);
  }

  /* ---------- 카탈로그 (이름·사진·일시불가) ---------- */
  var CAT = { m: {}, img: '' };
  function catInfo(m) { return CAT.m[m] || CAT.m[norm(m)] || null; }
  function imgOf(c) { return c && c[2] ? (/^https?:/.test(c[2]) ? c[2] : CAT.img + c[2]) : ''; }
  function nameOf(m) {
    var c = catInfo(m); if (c && c[1]) return cleanName(c[1]);
    var e = IDX.m[m], P = e && (window.SUB_PLANS || {})[e[0]], s = P && P[m] ? segLabel(P[m].s) : '';
    return ('삼성 ' + (IDX.cats[e ? e[0] : ''] || '') + (s ? ' ' + s : '')).replace(/\s+/g, ' ');
  }
  function lumpOf(m) { var c = catInfo(m); return c && c[3] > 0 ? c[3] : 0; }

  /* ---------- 상태 ---------- */
  var state = { q: '', cat: '', card: '', tier: '', cardOn: true, shown: 12, group: true };
  var C = null;   // SUB_CALC
  var els = {};
  var infos = {};   // 모델 → info (요금표)

  /* ---------- 골격 ---------- */
  root.innerHTML =
    '<div class="sb-wrap">' +
    '<section class="sb-pick">' +
    '<h2 class="sb-h2">1. 상품 담기 <small>최대 ' + MAX + '개</small></h2>' +
    '<form class="sb-search" data-slot="form"><input type="search" data-slot="q" placeholder="모델명·제품 검색 (예: 냉장고, WD90H25AHY)" aria-label="검색" autocomplete="off"><button type="submit">검색</button></form>' +
    '<div class="sb-chips" data-slot="cats" role="group" aria-label="품목"></div>' +
    '<div class="sb-presets" data-slot="presets"></div>' +
    '<p class="sb-count" data-slot="count"></p>' +
    '<ul class="ss-grid sb-grid" data-slot="grid"></ul>' +
    '<div class="sb-more-wrap"><button type="button" class="sb-more" data-slot="more" hidden>더 보기</button></div>' +
    '</section>' +
    '<aside class="sb-cart" data-slot="cart"><h2 class="sb-h2">2. 내 묶음 <small data-slot="n"></small></h2>' +
    '<div data-slot="cardsel" class="sb-cardsel"></div>' +
    '<ul class="sb-items" data-slot="items"></ul>' +
    '<div class="sb-sum" data-slot="sum"></div>' +
    '</aside></div>' +
    '<div class="sb-bar" data-slot="bar" hidden><div class="sb-bar-in"><span data-slot="bartext"></span><a href="#subBundleCart" class="sb-bar-btn">묶음 보기</a></div></div>';
  ['form', 'q', 'cats', 'presets', 'count', 'grid', 'more', 'cart', 'n', 'cardsel', 'items', 'sum', 'bar', 'bartext'].forEach(function (k) { els[k] = root.querySelector('[data-slot="' + k + '"]'); });
  els.cart.id = 'subBundleCart';

  /* ---------- 상품 고르기 ---------- */
  var rows = [];
  function buildRows() {
    for (var m in IDX.m) {
      if (!IDX.m.hasOwnProperty(m)) continue;
      var e = IDX.m[m]; if (!e || !(e[1] > 0) || !IDX.cats[e[0]]) continue;
      var c = catInfo(m);
      rows.push({ model: m, cat: e[0], min: e[1], name: c ? cleanName(c[1]) : '', img: imgOf(c), own: !!(c && c[4] === 'm'), goodsNo: c && c[0] ? String(c[0]) : '', lump: c && c[3] > 0 ? c[3] : 0 });
    }
  }
  function segOf(r) { var P = (window.SUB_PLANS || {})[r.cat]; return P && P[r.model] ? P[r.model].s || '' : ''; }
  function score(r) { return (r.own ? 3 : r.img ? 1 : 0) + (r.name ? 1 : 0) + (r.goodsNo ? 1 : 0); }
  function filtered() {
    var q = norm(state.q), toks = q ? state.q.split(/\s+/).map(norm).filter(Boolean) : [];
    return rows.filter(function (r) {
      if (state.cat && r.cat !== state.cat) return false;
      if (!toks.length) return true;
      var hay = norm(r.model + ' ' + r.name + ' ' + IDX.cats[r.cat] + ' ' + segOf(r));
      return toks.every(function (t) { return hay.indexOf(t) >= 0; });
    });
  }
  function groupColors(list) { return state.group ? groupColorsRaw(list) : list; }
  function groupColorsRaw(list) {
    var fam = {}, order = [];
    list.forEach(function (r) { var k = r.cat + '|' + segOf(r) + '|' + familyKey(r.model); if (!fam[k]) { fam[k] = []; order.push(k); } fam[k].push(r); });
    return order.map(function (k) {
      var vs = fam[k].slice().sort(function (a, b) { return a.min - b.min; });
      var rep = vs.filter(function (v) { return v.own; })[0] || vs[0], o = {};
      for (var key in rep) o[key] = rep[key];
      o.variants = vs; o.min = vs[0].min; return o;
    });
  }
  function card(r) {
    var on = cartHas(r.model), fam = r.variants && r.variants.length > 1 ? r.variants : null, s = segOf(r);
    return '<li class="ss-card sb-card' + (on ? ' in-cart' : '') + '">' +
      '<a class="ss-card-link" href="' + esc(viewUrl(r.model)) + '" target="_blank" rel="noopener">' +
      (fam ? '<span class="ss-fam">색상 ' + fam.length + '종</span>' : '') +
      '<span class="ss-img">' + (r.img ? '<img src="' + esc(r.img) + '" alt="" loading="lazy">' : '<span class="ss-icon">' + (CAT_ICON[r.cat] || '📦') + '</span>') + '</span>' +
      '<span class="ss-meta">' + esc(IDX.cats[r.cat]) + (s ? ' · ' + esc(segLabel(s)) : '') + '</span>' +
      '<strong class="ss-name">' + esc(r.name || nameOf(r.model)) + '</strong><span class="ss-model">' + esc(r.model) + '</span>' +
      '<span class="ss-price"><small>월</small> ' + fmt(r.min) + '<small>원~</small></span></a>' +
      '<button type="button" class="sb-add' + (on ? ' is-on' : '') + '" data-add="' + esc(r.model) + '">' + (on ? '담김 ✓ (빼기)' : '+ 담기') + '</button></li>';
  }
  function renderPick() {
    var base = rows.filter(function (r) { return !state.cat || true; });
    var cnt = {}; rows.forEach(function (r) { cnt[r.cat] = (cnt[r.cat] || 0) + 1; });
    els.cats.innerHTML = '<button type="button" class="sb-chip' + (!state.cat ? ' is-active' : '') + '" data-cat="">전체</button>' +
      Object.keys(IDX.cats).filter(function (k) { return cnt[k]; }).map(function (k) {
        return '<button type="button" class="sb-chip' + (state.cat === k ? ' is-active' : '') + '" data-cat="' + k + '">' + (CAT_ICON[k] || '') + ' ' + esc(IDX.cats[k]) + ' <em>' + cnt[k] + '</em></button>';
      }).join('');
    els.presets.innerHTML = '<span>빠른 담기</span>' + Object.keys(PRESETS).map(function (k) {
      return '<button type="button" class="sb-preset" data-preset="' + k + '">' + esc(PRESET_NAME[k]) + '</button>';
    }).join('');
    var list = groupColors(filtered()).sort(function (a, b) { return score(b) - score(a) || a.min - b.min; });
    els.count.innerHTML = '구독 가능 모델 <b>' + fmt(list.length) + '</b>개' + (state.q ? ' · "' + esc(state.q) + '"' : '') +
      ' <label class="sb-group"><input type="checkbox" data-group' + (state.group ? ' checked' : '') + '> 색상만 다른 모델은 하나로</label>';
    els.grid.innerHTML = list.length ? list.slice(0, state.shown).map(card).join('') : '<li class="sb-empty">조건에 맞는 모델이 없습니다.</li>';
    els.more.hidden = list.length <= state.shown;
    els.more.textContent = '더 보기 (남은 ' + fmt(Math.max(0, list.length - state.shown)) + '개)';
  }

  /* ---------- 요금 계산 ---------- */
  function ensureInfo(m, cb) {
    if (infos.hasOwnProperty(m)) return cb(infos[m]);
    C.getInfo(m, function (info) { infos[m] = info; cb(info); });
  }
  function yearsOf(info) { var ys = []; info.p.forEach(function (p) { if (ys.indexOf(p[0]) < 0) ys.push(p[0]); }); return ys.sort(function (a, b) { return a - b; }); }
  function caresOf(info, y) { return C.plansOf(info, y).map(function (p) { return p[1]; }); }
  // 담긴 조건을 요금표에 맞춘다 (없는 약정·케어면 최장 약정 · 가장 저렴한 케어)
  function resolve(it, info) {
    var ys = yearsOf(info), y = ys.indexOf(+it.y) >= 0 ? +it.y : ys[ys.length - 1];
    var plans = C.plansOf(info, y).sort(function (a, b) { return a[3] - b[3]; });
    var plan = plans.filter(function (p) { return p[1] === it.c; })[0] || plans[0];
    var pm = C.prepayMax(info), pp = +it.p || 0; if (!(pp > 0 && pp <= pm + 1e-9)) pp = 0;
    return { y: y, plan: plan, prepay: pp, prepayMax: pm };
  }
  function cardOpt(baseMonthly) { return { prepay: 0, card: state.cardOn ? state.card : '', tier: state.tier, cardOn: state.cardOn }; }
  function calcItem(it, info) {
    var r = resolve(it, info), o = { prepay: r.prepay, card: state.cardOn ? state.card : '', tier: state.tier, cardOn: state.cardOn };
    var res = C.calc(info, r.plan, o);
    res.y = r.y; res.plan = r.plan; res.prepayMax = r.prepayMax; res.info = info;
    return res;
  }
  var POLB = null;   // 다품목 정책 { rate, min } — 정책에 있을 때만
  function bundlePolicy() { var P = C.policy(); return P && P.bundle && P.bundle.rate > 0 ? P.bundle : null; }

  /* ---------- 내 묶음 ---------- */
  function renderCardSel() {
    var names = C.cardNames(), P = C.policy();
    if (!state.card || names.indexOf(state.card) < 0) { state.card = names.indexOf(C.defaultCard()) >= 0 ? C.defaultCard() : names[0] || ''; state.tier = ''; }
    var cd = window.SUB_CARDS && window.SUB_CARDS[state.card], tiers = cd ? Object.keys(cd.t) : [];
    if (!state.tier || tiers.indexOf(state.tier) < 0) state.tier = C.defaultTier(state.card) && tiers.indexOf(C.defaultTier(state.card)) >= 0 ? C.defaultTier(state.card) : tiers[0] || '';
    els.cardsel.innerHTML = '<label class="sb-cardon"><input type="checkbox" data-cardon' + (state.cardOn ? ' checked' : '') + '> 제휴카드 자동결제 할인 적용</label>' +
      (names.length ? '<div class="sb-cardrow' + (state.cardOn ? '' : ' is-off') + '"><select data-card aria-label="제휴카드">' + names.map(function (n) { return '<option value="' + esc(n) + '"' + (n === state.card ? ' selected' : '') + '>' + esc(n) + '</option>'; }).join('') + '</select>' +
        '<select data-tier aria-label="전월 실적">' + tiers.map(function (t) { return '<option value="' + esc(t) + '"' + (t === state.tier ? ' selected' : '') + '>전월 실적 ' + esc(String(t).replace('↑', '원 이상')) + ' · 월 ' + fmt(cd.t[t]) + '원 할인</option>'; }).join('') + '</select></div>' : '') +
      '<p class="sb-cardnote">카드 할인은 구독 건마다 적용되는 것으로 계산했습니다. 실제 적용 조건(실적·건수·기간)은 카드사 기준을 따르며 상담 때 확인해 드립니다.</p>';
  }
  function itemHtml(it, res) {
    var m = it.m, info = res.info, ys = yearsOf(info), cares = caresOf(info, res.y), c = catInfo(m), im = imgOf(c);
    var steps = (C.policy().prepay.steps || []).filter(function (s) { return s <= res.prepayMax + 1e-9; });
    return '<li class="sb-item" data-model="' + esc(m) + '">' +
      '<div class="sb-item-head">' + (im ? '<img src="' + esc(im) + '" alt="">' : '<span class="sb-item-icon">' + (CAT_ICON[info.cat && IDX.m[m][0]] || CAT_ICON[IDX.m[m][0]] || '📦') + '</span>') +
      '<div class="sb-item-t"><span class="sb-item-cat">' + esc(IDX.cats[IDX.m[m][0]]) + (info.s ? ' · ' + esc(segLabel(info.s)) : '') + '</span><a href="' + esc(viewUrl(m)) + '" target="_blank" rel="noopener"><b>' + esc(nameOf(m)) + '</b></a><span class="sb-item-model">' + esc(m) + '</span></div>' +
      '<button type="button" class="sb-del" data-del="' + esc(m) + '" aria-label="빼기">×</button></div>' +
      '<div class="sb-item-opts">' +
      '<select data-y aria-label="약정 기간">' + ys.map(function (y) { return '<option value="' + y + '"' + (y === res.y ? ' selected' : '') + '>' + y + '년 약정</option>'; }).join('') + '</select>' +
      '<select data-c aria-label="케어">' + cares.map(function (cc) { return '<option value="' + esc(cc) + '"' + (cc === res.plan[1] ? ' selected' : '') + '>' + esc(cc) + '</option>'; }).join('') + '</select>' +
      '<select data-p aria-label="선납"' + (steps.length ? '' : ' disabled') + '><option value="0">선납 없음</option>' + steps.map(function (s) { return '<option value="' + s + '"' + (Math.abs(s - res.prepay) < 1e-9 ? ' selected' : '') + '>선납 ' + Math.round(s * 100) + '% (' + Math.round(C.prepayRate(s) * 1000) / 10 + '% 할인)</option>'; }).join('') + '</select>' +
      '</div>' +
      '<div class="sb-item-price"><span>월 <s>' + fmt(res.monthly) + '원</s></span><b>월 ' + fmt(res.finalMonthly) + '원</b>' +
      (res.prepayAmt ? '<small>선납금 ' + fmt(res.prepayAmt) + '원 별도</small>' : '') + '</div></li>';
  }
  function renderCart() {
    var items = cartGet();
    els.n.textContent = items.length ? items.length + '개' : '';
    if (!items.length) {
      els.items.innerHTML = '<li class="sb-empty">아직 담은 상품이 없습니다.<br>왼쪽에서 <b>+ 담기</b>를 누르거나 <b>빠른 담기</b>로 시작해 보세요.</li>';
      els.sum.innerHTML = ''; els.bar.hidden = true;
      return;
    }
    var left = items.length, results = {};
    items.forEach(function (it) {
      ensureInfo(it.m, function (info) {
        if (info) results[it.m] = calcItem(it, info);
        if (--left === 0) drawCart(items, results);
      });
    });
  }
  function drawCart(items, results) {
    var html = '', sum = { monthly: 0, auto: 0, prepayDisc: 0, prepayAmt: 0, card: 0, pay: 0, expected: 0, lump: 0, lumpAll: true, n: 0 };
    items.forEach(function (it) {
      var r = results[it.m];
      if (!r) { html += '<li class="sb-item is-na" data-model="' + esc(it.m) + '"><div class="sb-item-head"><div class="sb-item-t"><b>' + esc(it.m) + '</b><span class="sb-item-model">지금 구독으로 운영되지 않는 모델</span></div><button type="button" class="sb-del" data-del="' + esc(it.m) + '">×</button></div></li>'; return; }
      html += itemHtml(it, r);
      sum.n++; sum.monthly += r.monthly; sum.auto += r.autoDisc / r.months; sum.prepayDisc += r.prepayDisc; sum.prepayAmt += r.prepayAmt;
      sum.card += r.cardMonthly; sum.pay += r.finalMonthly; sum.expected += r.expected;
      var lp = lumpOf(it.m); if (lp) sum.lump += lp; else sum.lumpAll = false;
    });
    els.items.innerHTML = html;
    var bp = bundlePolicy(), bundleOff = 0;
    if (bp && sum.n >= (bp.min || 2)) bundleOff = Math.round(sum.pay * bp.rate);
    var payFinal = Math.max(0, sum.pay - bundleOff);
    var cardName = state.cardOn && state.card ? state.card : '';
    els.sum.innerHTML =
      '<table class="sb-table"><tbody>' +
      '<tr><th>월 구독료 합계 <small>' + sum.n + '대 · 정가</small></th><td>' + fmt(sum.monthly) + '원</td></tr>' +
      '<tr class="is-off"><th>' + esc(C.autopayLabel()) + '</th><td>− ' + fmt(sum.auto) + '원</td></tr>' +
      (sum.prepayDisc ? '<tr class="is-off"><th>선납 할인 <small>월 환산</small></th><td>− ' + fmt(sum.prepayDisc / 12 / 1) + '원</td></tr>' : '') +
      (cardName ? '<tr class="is-off"><th>' + esc(cardName) + ' 청구할인 <small>' + sum.n + '건</small></th><td>− ' + fmt(sum.card) + '원</td></tr>' : '') +
      (bundleOff ? '<tr class="is-off"><th>다품목 동시구독 혜택 <small>' + Math.round(bp.rate * 100) + '%</small></th><td>− ' + fmt(bundleOff) + '원</td></tr>' : '') +
      '</tbody><tfoot><tr><th>' + sum.n + '대 월 납부 예상액</th><td><b>월 ' + fmt(payFinal) + '원</b></td></tr></tfoot></table>' +
      (sum.prepayAmt ? '<p class="sb-sumnote">+ 선납금 ' + fmt(sum.prepayAmt) + '원 (신청 때 한 번)</p>' : '') +
      '<div class="sb-cmp"><div><span>약정 기간 총 결제 예상</span><b>' + fmt(sum.expected - bundleOff * 12 * 0) + '원</b></div>' +
      (sum.lumpAll && sum.lump ? '<div><span>시흥몰 일시불 합계</span><b>' + fmt(sum.lump) + '원</b></div><div class="is-save"><span>' + (sum.lump > sum.expected ? '구독이 ' : '일시불이 ') + '</span><b>' + fmt(Math.abs(sum.lump - sum.expected)) + '원 저렴</b></div>' : '') + '</div>' +
      (!bp ? '<p class="sb-sumnote">여러 대를 동시에 구독할 때의 추가 혜택(행사·사은품 등)은 상담 때 안내해 드립니다.</p>' : '') +
      '<div class="sb-ctas"><a class="sb-btn" data-cta="consult" href="' + esc(consultHref(items, results, payFinal)) + '">이 조건으로 구독 문의하기</a>' +
      (CFG.tel ? '<a class="sb-btn-line" href="tel:' + esc(CFG.tel.replace(/[^0-9]/g, '')) + '">' + esc(CFG.tel) + '</a>' : '') +
      '<button type="button" class="sb-btn-line" data-share>묶음 링크 복사</button>' +
      '<button type="button" class="sb-btn-line" data-print>인쇄 · PDF</button>' +
      '<button type="button" class="sb-link" data-clear>모두 비우기</button></div>' +
      '<p class="sb-note">* 월 구독료는 VAT 포함. 제휴카드 할인은 카드사 조건(전월 실적·정기결제 등)에 따라 달라질 수 있으며, 표시 금액은 혜택을 모두 받았을 때의 예상 금액입니다. 정확한 금액은 상담 때 안내해 드립니다.</p>';
    els.bar.hidden = false;
    els.bartext.innerHTML = sum.n + '대 묶음 · <b>월 ' + fmt(payFinal) + '원</b>';
    track('sub_bundle_calc', { sb_n: sum.n, sb_pay: payFinal });
  }
  function consultHref(items, results, pay) {
    var pd = C.policy().defaults || {};
    var u = CFG.consultUrl || pd.consultUrl || '/main/html.php?htmid=service/SamSungSubscription.html';
    var lines = items.map(function (it) { var r = results[it.m]; return it.m + (r ? ' ' + r.y + '년 ' + r.plan[1] + (r.prepay ? ' 선납' + Math.round(r.prepay * 100) + '%' : '') + ' 월 ' + fmt(r.finalMonthly) + '원' : ''); });
    var memo = '[다품목 계산기] ' + items.length + '대 · 월 ' + fmt(pay) + '원' + (state.cardOn && state.card ? ' (' + state.card + ' ' + state.tier + ')' : '') + ' / ' + lines.join(' / ');
    var q = 'from=bundle&purpose=' + encodeURIComponent('신규구독') + '&product=' + encodeURIComponent('다품목') + '&model=' + encodeURIComponent(items.map(function (i) { return i.m; }).join(',')) +
      '&memo=' + encodeURIComponent(memo.slice(0, 900)) + '&src=' + encodeURIComponent('다품목 계산기') + '&utm_source=sub_bundle&utm_medium=consult';
    return u + (u.indexOf('?') >= 0 ? '&' : '?') + q;
  }
  function shareUrl() {
    var items = cartGet().map(function (it) { return it.m + (it.y ? '~' + it.y : '') + (it.c ? '~' + it.c : '') + (it.p ? '~' + it.p : ''); });
    var base = location.href.replace(/[?#].*$/, '');
    return base + '?items=' + encodeURIComponent(items.join(',')) + (state.card ? '&card=' + encodeURIComponent(state.card) + '&tier=' + encodeURIComponent(state.tier) : '') + (state.cardOn ? '' : '&cardoff=1');
  }

  /* ---------- 프리셋 · 주소로 담기 ---------- */
  function presetModels(key, cb) {
    var keys = PRESETS[key]; if (!keys) return cb([]);
    var needCats = []; keys.forEach(function (k) { var c = PAGE_SEG[k] ? PAGE_SEG[k][0] : k; if (needCats.indexOf(c) < 0) needCats.push(c); });
    var left = needCats.length;
    needCats.forEach(function (c) {
      if ((window.SUB_PLANS || {})[c]) { if (--left === 0) done(); return; }
      loadScript(BASE + 'sub_plans_' + c + '.js?v=' + VER, function () { if (--left === 0) done(); });
    });
    function done() {
      var out = [];
      keys.forEach(function (k) {
        var cat = PAGE_SEG[k] ? PAGE_SEG[k][0] : k, re = PAGE_SEG[k] ? PAGE_SEG[k][1] : null, pref = PRESET_PREF[k];
        var pool = rows.filter(function (r) { return r.cat === cat && r.own && r.name && (!re || re.test(segOf(r))); });
        var withGoods = pool.filter(function (r) { return r.goodsNo; }); if (withGoods.length >= 3) pool = withGoods;   // 고도몰에 있는 상품 우선
        var liked = pref ? pool.filter(function (r) { return pref.test(segOf(r) + ' ' + r.name); }) : []; if (liked.length >= 2) pool = liked;
        if (!pool.length) return;
        // 색상 묶음으로 한 번 줄인 뒤 월 구독료 60% 지점 — 제일 싼 소형도, 제일 비싼 최상위도 아닌 "흔히 고르는" 모델
        var fams = groupColorsRaw(pool).sort(function (a, b) { return a.min - b.min; });
        var pick = fams[Math.min(fams.length - 1, Math.floor(fams.length * 0.6))];
        out.push(pick.model);
      });
      cb(out);
    }
  }
  function applyUrl() {
    var items = param('items'), preset = param('preset');
    if (param('card')) { state.card = param('card'); state.tier = param('tier') || ''; }
    if (param('cardoff') === '1') state.cardOn = false;
    if (items) {
      items.split(',').forEach(function (tok) { var p = tok.split('~'), m = norm(p[0]); if (IDX.m[m]) cartAdd(m, { y: p[1] ? +p[1] : undefined, c: p[2] || undefined, p: p[3] ? +p[3] : undefined }, true); });
    }
    if (preset && PRESETS[preset]) {
      presetModels(preset, function (ms) {
        var added = 0; ms.forEach(function (m) { if (!cartHas(m) && cartAdd(m, null, true)) added++; });
        if (added) toast(PRESET_NAME[preset] + ' 추천 ' + added + '대를 담았습니다 · 모델은 바꿀 수 있어요');
        renderPick(); renderCart();
      });
    }
  }

  /* ---------- 이벤트 ---------- */
  root.addEventListener('click', function (ev) {
    var t = ev.target.closest ? ev.target.closest('button, a') : null;
    if (!t || !root.contains(t)) return;
    if (t.hasAttribute('data-add')) { var m = t.getAttribute('data-add'); if (cartHas(m)) cartRemove(m); else if (cartAdd(m)) toast('담았습니다 · ' + cartGet().length + '개'); renderPick(); renderCart(); }
    else if (t.hasAttribute('data-del')) { cartRemove(t.getAttribute('data-del')); renderPick(); renderCart(); }
    else if (t.hasAttribute('data-cat')) { state.cat = t.getAttribute('data-cat'); state.shown = 12; renderPick(); }
    else if (t.hasAttribute('data-preset')) { var k = t.getAttribute('data-preset'); presetModels(k, function (ms) { var n = 0; ms.forEach(function (m) { if (!cartHas(m) && cartAdd(m, null, true)) n++; }); toast(PRESET_NAME[k] + ' 추천 ' + n + '대를 담았습니다'); renderPick(); renderCart(); track('sub_bundle_preset', { sb_preset: k }); }); }
    else if (t.hasAttribute('data-clear')) { if (confirm('담은 상품을 모두 비울까요?')) { cartSet([]); renderPick(); renderCart(); } }
    else if (t.hasAttribute('data-share')) {
      var u = shareUrl();
      var ok = function () { toast('묶음 링크를 복사했습니다'); };
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(u).then(ok, function () { prompt('이 주소를 복사하세요', u); });
      else prompt('이 주소를 복사하세요', u);
      if (history.replaceState) history.replaceState(null, '', u);
    }
    else if (t.hasAttribute('data-print')) { window.print(); track('sub_bundle_print'); }
    else if (t === els.more) { state.shown += 12; renderPick(); }
    else if (t.hasAttribute('data-cta')) track('sub_bundle_click', { sb_cta: t.getAttribute('data-cta') });
  });
  root.addEventListener('change', function (ev) {
    var t = ev.target;
    if (t.hasAttribute('data-group')) { state.group = t.checked; renderPick(); return; }
    if (t.hasAttribute('data-cardon')) { state.cardOn = t.checked; renderCardSel(); renderCart(); return; }
    if (t.hasAttribute('data-card')) { state.card = t.value; state.tier = ''; renderCardSel(); renderCart(); return; }
    if (t.hasAttribute('data-tier')) { state.tier = t.value; renderCart(); return; }
    var li = t.closest ? t.closest('.sb-item') : null;
    if (!li) return;
    var m = li.getAttribute('data-model'), items = cartGet();
    items.forEach(function (it) {
      if (it.m !== m) return;
      if (t.hasAttribute('data-y')) { it.y = +t.value; delete it.c; }
      if (t.hasAttribute('data-c')) it.c = t.value;
      if (t.hasAttribute('data-p')) it.p = +t.value || 0;
    });
    cartSet(items); renderCart();
  });
  els.form.addEventListener('submit', function (ev) { ev.preventDefault(); state.q = els.q.value.replace(/^\s+|\s+$/g, ''); state.cat = ''; state.shown = 12; renderPick(); track('sub_bundle_search', { sb_q: state.q }); });
  document.addEventListener('ss-cart', function () { renderPick(); });

  /* ---------- 구독센터 메뉴 (sub_shop.js 메뉴 전용) ---------- */
  function centerNav() {
    if (CFG.centerNav === false || document.getElementById('subShopNav')) return;
    var nav = document.createElement('div'); nav.id = 'subShopNav';
    root.parentNode.insertBefore(nav, root.parentNode.firstChild);
    window.SUB_SHOP_CONFIG = window.SUB_SHOP_CONFIG || { page: 'bundle', key: '', tel: CFG.tel || '', consultUrl: CFG.consultUrl, findUrl: CFG.findUrl, viewUrl: CFG.viewUrl,
      homeUrl: CFG.homeUrl, catUrl: CFG.catUrl, cardUrl: CFG.cardUrl, guideUrl: CFG.guideUrl, bundleUrl: CFG.bundleUrl };
    if (!document.querySelector('link[href*="sub_shop.css"]')) { var l = document.createElement('link'); l.rel = 'stylesheet'; l.href = BASE + 'sub_shop.css?v=' + VER; document.head.appendChild(l); }
    if (!window.SUB_CART) loadScript(BASE + 'sub_shop.js?v=' + VER);
  }

  /* ---------- 시작: 카탈로그 → 계산기(sub_tab.js API) → 카드·정책 → 그리기 ---------- */
  function start() {
    buildRows();
    centerNav();
    window.SUB_TAB_CONFIG = { ver: CFG.ver, dataBase: BASE, apiOnly: true, defaultCard: CFG.defaultCard || '' };
    function withCalc() {
      C = window.SUB_CALC;
      if (!C) { root.innerHTML = '<p class="sb-empty">계산기를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.</p>'; return; }
      C.ready(function () {
        renderCardSel(); renderPick(); renderCart();
        applyUrl();
        track('sub_bundle_view', { sb_n: cartGet().length });
      });
    }
    if (window.SUB_CALC) withCalc();
    else loadScript(BASE + 'sub_tab.js?v=' + VER, withCalc, withCalc);
  }
  function useCatalog(G) { CAT = { m: (G && G.m) || {}, img: (G && G.img) || '' }; }
  if (window.SUB_CATALOG && window.SUB_CATALOG.m) { useCatalog(window.SUB_CATALOG); start(); }
  else {
    var api = CFG.catalogApi, settled = false;
    function go() { if (settled) return; settled = true; start(); }
    if (api && api.url && window.fetch) {
      setTimeout(go, api.timeout || 3000);
      fetch(api.url, { method: 'POST', headers: { apikey: api.key, 'Content-Type': 'application/json' }, body: '{}' })
        .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
        .then(function (G) { useCatalog(G); go(); }).catch(go);
    } else go();
  }
})();
