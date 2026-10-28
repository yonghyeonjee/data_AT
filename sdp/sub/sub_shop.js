/* ===== 구독센터 공용 화면 | subscribe/sub_home.html · sub_c_<품목>.html · sub_card.html · sub_guide.html =====
   고도몰에는 얇은 html(검색용 제목·소개·FAQ 글 + SUB_SHOP_CONFIG)만 두고, 목록·가격·메뉴는 이 파일이 그린다.
   html 안의 자리 표시를 채운다 (없는 자리는 건너뛴다)
     data-ss="nav"      구독센터 메뉴 (홈 · 품목 · 카드 혜택 · 구독 안내 · 상품 찾기 · 상담 신청)
     data-ss="search"   검색창 → 구독상품 찾기(sub_find)
     data-ss="cats"     품목 바둑판 (품목별 최저 월 구독료 · 모델 수)
     data-ss="pick"     품목 하나의 대표 모델 몇 개   data-key="aicombo" data-n="4"
     data-ss="popular"  품목마다 대표 모델 하나씩
     data-ss="cards"    제휴카드 혜택 요약           data-ss="cardtable"  제휴카드 실적 구간표
     data-ss="list"     품목 페이지 전체 목록 (세부유형·금액대·정렬)  — CFG.key 품목
     data-ss="related"  다른 품목 바로가기
     data-ss="cta"      상담 띠 (전화 · 구독 문의)
   검색엔진용: 품목 목록(ItemList) · 경로(BreadcrumbList) · FAQ(FAQPage, html 의 .ss-faq 글에서) 구조화 데이터를 넣는다.
   ※ 요금 = sub_index.js / sub_plans_<품목>.js (상품상세 구독탭·구독상품 찾기와 같은 파일)
   ※ 상품명·이미지 = 데이터센터 fn_sub_catalog (고도몰 상품명 → 상품 마스터 이름 → 없으면 "삼성 품목 세부유형")
===== */
window.SUB_SHOP_READY = true;
(function () {
  'use strict';
  var CFG = window.SUB_SHOP_CONFIG || {};
  var IDX = window.SUB_INDEX;
  var root = document.getElementById('subShopRoot');
  // 메뉴만: 구독 상품 페이지(sub_view)·구독상품 찾기(sub_find)가 #subShopNav 를 만들고 이 파일을 불러온다
  var navOnly = !root && document.getElementById('subShopNav');
  if (navOnly) root = navOnly;
  if (!root) return;

  /* ---------- 품목 페이지 정의 — 메뉴·목록·주소가 모두 이 표를 따른다 ----------
     cats: 요금 데이터의 품목 키 / seg: 그 안의 세부유형만 (없으면 전체) / file: subscribe/sub_c_<key>.html */
  var PAGES = [
    { key: 'ref', name: '냉장고', icon: '🧊', cats: ['ref'] },
    { key: 'kimchi', name: '김치냉장고', icon: '🥬', cats: ['kimchi'] },
    { key: 'aicombo', name: 'AI 콤보', icon: '🌀', cats: ['laundry'], seg: /콤보/, hot: true },
    { key: 'washer', name: '세탁기', icon: '👕', cats: ['laundry'], seg: /^(드럼|전자동|세탁기\+건조기)/ },
    { key: 'dryer', name: '건조기', icon: '♨️', cats: ['laundry'], seg: /^건조기/ },
    { key: 'airdresser', name: '에어드레서', icon: '🧥', cats: ['laundry'], seg: /벌식/ },
    { key: 'aircon', name: '에어컨', icon: '❄️', cats: ['aircon'] },
    { key: 'sysaircon', name: '시스템에어컨', icon: '🌬️', cats: ['sysaircon'] },
    { key: 'tv', name: 'TV', icon: '📺', cats: ['tv'] },
    { key: 'water', name: '정수기', icon: '💧', cats: ['water'] },
    { key: 'airpurifier', name: '공기청정기', icon: '🍃', cats: ['airpurifier'] },
    { key: 'cleaner', name: '청소기', icon: '🧹', cats: ['cleaner'] },
    { key: 'dishwasher', name: '식기세척기', icon: '🍽️', cats: ['cooking'], seg: /인용|카운터탑/ },
    { key: 'induction', name: '인덕션·후드', icon: '🍳', cats: ['cooking'], seg: /전기레인지|인덕션|후드/ },
    { key: 'monitor', name: '모니터', icon: '🖥️', cats: ['monitor'] },
    { key: 'galaxy', name: '갤럭시 탭·북', icon: '💻', cats: ['tab', 'book'] },
    { key: 'audio', name: '사운드바·오디오', icon: '🔊', cats: ['audio'] },
    { key: 'dehumid', name: '제습기', icon: '💨', cats: ['dehumid'] }
  ];
  var PAGE_BY = {};
  PAGES.forEach(function (p) { PAGE_BY[p.key] = p; });

  // 구독센터 페이지 폴더: 지금 페이지 주소(htmid=<폴더>/sub_…)를 따른다 — 웹FTP subscribe/ · 예전 service/ 모두 동작
  var PAGE_DIR = CFG.pageDir || (/[?&]htmid=([\w-]+\/)sub_/.exec(location.search) || [])[1] || 'subscribe/';
  var LINK = {
    home: CFG.homeUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_home.html',
    cat: CFG.catUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_c_',
    card: CFG.cardUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_card.html',
    guide: CFG.guideUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_guide.html',
    find: CFG.findUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_find.html',
    view: CFG.viewUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_view.html&model=',
    consult: CFG.consultUrl || '/main/html.php?htmid=service/SamSungSubscription.html'
  };
  var SITE = CFG.site || location.protocol + '//' + location.host;
  var UTM = 'sub_' + (CFG.page || 'home') + (CFG.key ? '_' + CFG.key : '');

  function fmt(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function $all(sel) { return Array.prototype.slice.call(root.querySelectorAll(sel)); }
  function track(name, extra) {
    var ev = { event: name, ss_page: CFG.page || '', ss_key: CFG.key || '' };
    for (var k in extra) ev[k] = extra[k];
    if (window.dataLayer) window.dataLayer.push(ev);
  }
  function loadScript(src, ok, fail) {
    var s = document.createElement('script');
    s.src = src; s.onload = ok; s.onerror = fail || ok;
    document.head.appendChild(s);
  }
  function catHref(key) { return LINK.cat + key + '.html'; }
  function viewHref(model, medium) {
    return LINK.view + encodeURIComponent(model) + '&utm_source=' + UTM + '&utm_medium=' + (medium || 'list');
  }
  // SamSungSubscription.html 자동채움 파라미터 (sub_find.js 와 같은 형식)
  function consultHref(r, where) {
    var page = PAGE_BY[CFG.key];
    var memo = '[구독센터' + (page ? ' ' + page.name : '') + '] ' + (r ? r.model + (r.seg ? ' (' + r.seg + ')' : '') + ' · 월 ' + fmt(r.min) + '원~' : '구독 문의');
    var product = r ? IDX.cats[r.cat] : page ? IDX.cats[page.cats[0]] : '';
    var q = 'from=subcenter' + (product ? '&product=' + encodeURIComponent(product) : '') +
      '&purpose=' + encodeURIComponent('신규구독') + (r ? '&model=' + encodeURIComponent(r.model) : '') +
      '&memo=' + encodeURIComponent(memo) + '&src=' + encodeURIComponent('구독센터') +
      '&utm_source=' + UTM + '&utm_medium=' + (where || 'consult');
    return LINK.consult + (LINK.consult.indexOf('?') >= 0 ? '&' : '?') + q;
  }

  /* ---------- 세부유형 화면 이름 — sub_find.js · sub_view.js · sub_tab.js 의 SEG_LABEL_RULES 와 같은 규칙 ---------- */
  var SEG_LABEL_RULES = [
    [/^Entry_-(\d+)_더무빙$/, '$1형 이하 · 더 무빙스타일'], [/ \+ 4K_-(\d+)$/, ' + 보조 TV $1형 이하'], [/\(2인\)/, '(2인 설치)'],
    [/^Premium_4K_/, '프리미엄 4K '], [/^Premium_/, '프리미엄 '], [/^Entry_/, ''], [/^일반모니터 /, '일반 '],
    [/(\d+)이하/, '$1형 이하'], [/(\d+)이상 \((\d+)-(\d+)\)/, '$2~$3형'],
    [/(^|[ (])(\d{2,3})-(\d{2,3})(?=$|[ )(])/, '$1$2~$3형'], [/(^|[ _])-(\d{2,3})$/, '$1$2형 이하'],
    [/_M1\/M7$/, ' · 스마트 M1/M7'], [/_OLED$/, ' · OLED'], [/^SD Sound Device /, '사운드바 '],
    [/^AI로봇청소기_26신제품/, 'AI 로봇청소기 2026'], [/_/g, ' ']
  ];
  function segLabel(seg) {
    var s = String(seg || '');
    for (var i = 0; i < SEG_LABEL_RULES.length; i++) s = s.replace(SEG_LABEL_RULES[i][0], SEG_LABEL_RULES[i][1]);
    return s.replace(/\s+/g, ' ').replace(/^\s|\s$/g, '');
  }
  // 세부유형 이름이 "~ 공통" 이면 화면에서 뺀다 (건조기 공통 → 건조기)
  function segShort(seg) { return segLabel(seg).replace(/\s*공통$/, ''); }

  /* ---------- 데이터 ---------- */
  var rows = [], byModel = {}, CAT = { m: {}, img: '' };
  var CARDS = window.SUB_CARDS || null, POL = window.SUB_POLICY || null;
  var planState = {}, planWait = {};

  function cleanName(s) {
    return String(s || '').replace(/\s*\*+\s*$/, '').replace(/\s*(삼성본사직배송|본사직배송)\s*/g, ' ').replace(/\s{2,}/g, ' ').replace(/^\s|\s$/g, '');
  }
  function pageOf(r) {
    for (var i = 0; i < PAGES.length; i++) {
      var p = PAGES[i];
      if (p.cats.indexOf(r.cat) < 0) continue;
      if (!p.seg) return p;
      if (r.seg && p.seg.test(r.seg)) return p;
    }
    return null;
  }
  // 이름 없는 TV·모니터는 모델명에서 크기·라인업을 읽는다 (KQ65QNH80… → Neo QLED 65형)
  function modelHint(r) {
    var m;
    if (r.cat === 'tv' && (m = r.model.match(/^(KMR|KQ|KU)(\d{2,3})([A-Z]+)/))) {
      var line = m[1] === 'KMR' ? 'Micro RGB' : m[1] === 'KU' ? (/^MH/.test(m[3]) ? 'Mini LED' : /^LS/.test(m[3]) ? '더 무빙스타일' : 'UHD') : /^QN/.test(m[3]) ? 'Neo QLED' : /^S/.test(m[3]) ? 'OLED' : 'QLED';
      return '삼성 ' + line + ' ' + m[2] + '형 TV' + (/보조|\+/.test(r.seg) ? ' 세트' : '');
    }
    if (r.cat === 'monitor' && (m = r.model.match(/^L[SC](\d{2})/))) return '삼성 ' + m[1] + '형 모니터';
    return '';
  }
  function displayName(r) {
    if (r.name) return r.name;
    var hint = modelHint(r);
    if (hint) return hint;
    var p = r.seg ? pageOf(r) : null;
    var kind = p && p.key !== 'galaxy' ? p.name : IDX.cats[r.cat];
    var s = r.seg ? segShort(r.seg) : '';
    if (s && s.indexOf(kind) >= 0) kind = '';
    return ('삼성 ' + kind + (s ? ' ' + s : '')).replace(/\s+/g, ' ');
  }
  function buildRows() {
    for (var m in IDX.m) {
      if (!IDX.m.hasOwnProperty(m)) continue;
      var e = IDX.m[m];
      if (!e || !(e[1] > 0) || !IDX.cats[e[0]]) continue;
      var c = CAT.m[m];
      var r = { model: m, cat: e[0], min: e[1], seg: '', name: c ? cleanName(c[1]) : '', goodsNo: c && c[0] ? String(c[0]) : '',
        img: c && c[2] ? (/^https?:/.test(c[2]) ? c[2] : CAT.img + c[2]) : '', lump: c ? c[3] || 0 : 0,
        imgRep: !!(c && /^[sgc]$/.test(c[4] || '')) };   // s·g·c = 같은 세부유형·품목의 다른 모델 사진
      rows.push(r); byModel[m] = r;
    }
  }
  function loadPlans(cat, cb) {
    if (planState[cat] === 'done') return cb();
    (planWait[cat] = planWait[cat] || []).push(cb);
    if (planState[cat] === 'loading') return;
    planState[cat] = 'loading';
    loadScript((CFG.dataBase || '/data/js/sub/') + 'sub_plans_' + cat + '.js?v=' + encodeURIComponent(CFG.ver || IDX.ver), function () {
      var P = (window.SUB_PLANS || {})[cat] || {};
      rows.forEach(function (r) { if (r.cat === cat && P[r.model]) { r.seg = P[r.model].s || ''; r.plans = P[r.model].p || []; } });
      planState[cat] = 'done';
      var q = planWait[cat]; planWait[cat] = [];
      q.forEach(function (f) { f(); });
    });
  }
  function loadCats(cats, cb) {
    var left = cats.length;
    if (!left) return cb();
    cats.forEach(function (c) { loadPlans(c, function () { if (--left === 0) cb(); }); });
  }
  function rowsOf(p) {
    return rows.filter(function (r) { return p.cats.indexOf(r.cat) >= 0 && (!p.seg || (r.seg && p.seg.test(r.seg))); });
  }

  // 제휴카드 할인 — 기본 카드의 가장 낮은 실적 구간 (sub_tab.js 의 cardMonthly 와 같은 규칙)
  function cardInfo() {
    if (!CARDS) return null;
    var name = CFG.defaultCard && CARDS[CFG.defaultCard] ? CFG.defaultCard : Object.keys(CARDS)[0];
    var cd = CARDS[name]; if (!cd || !cd.t) return null;
    var tier = Object.keys(cd.t)[0];
    return { name: name, tier: tier, off: cd.t[tier] || 0, base: cd.base ? cd.base[tier] || cd.t[tier] : cd.t[tier],
      minMonthly: cd.minMonthly ? cd.minMonthly[tier] || 0 : 0 };
  }
  var CARD1 = null;
  function cardNet(r) {
    if (!CARD1) return 0;
    var off = CARD1.minMonthly && r.min < CARD1.minMonthly ? CARD1.base : CARD1.off;
    return Math.max(0, r.min - off);
  }
  function maxCardOff() {
    if (!CARDS) return 0;
    var mx = 0;
    for (var k in CARDS) { var t = CARDS[k].t || {}; for (var j in t) if (t[j] > mx) mx = t[j]; }
    return mx;
  }

  /* ---------- 조각 ---------- */
  function priceHtml(r) {
    var net = cardNet(r);
    return '<span class="ss-price"><small>월</small> ' + fmt(r.min) + '<small>원~</small></span>' +
      (CARD1 && net < r.min ? '<span class="ss-net">' + esc(CARD1.name) + ' 할인 시 <b>월 ' + fmt(net) + '원~</b></span>' : '');
  }
  function card(r, medium) {
    var p = pageOf(r);
    return '<li class="ss-card"><a class="ss-card-link" href="' + esc(viewHref(r.model, medium)) + '" data-cta="view" data-model="' + esc(r.model) + '">' +
      '<span class="ss-img">' + (r.img ? '<img src="' + esc(r.img) + '" alt="' + esc(displayName(r)) + '" loading="lazy">' +
        (r.imgRep ? '<span class="ss-imgnote">대표 이미지</span>' : '') : '<span class="ss-icon" aria-hidden="true">' + (p ? p.icon : '📦') + '</span>') + '</span>' +
      '<span class="ss-meta">' + esc(p ? p.name : IDX.cats[r.cat]) + (r.seg ? ' · ' + esc(segShort(r.seg)) : '') + '</span>' +
      '<strong class="ss-name">' + esc(displayName(r)) + '</strong>' +
      '<span class="ss-model">' + esc(r.model) + '</span>' +
      priceHtml(r) +
      '</a></li>';
  }
  function minOf(list) { var m = 0; list.forEach(function (r) { if (!m || r.min < m) m = r.min; }); return m; }

  /* ---------- 자리별 그리기 ---------- */
  function drawNav(el) {
    var cur = CFG.page === 'cat' || CFG.page === 'view' ? CFG.key : CFG.page;
    var top = [['home', '구독 홈', LINK.home], ['card', '카드 혜택', LINK.card], ['guide', '구독 안내', LINK.guide], ['find', '상품 찾기', LINK.find]];
    var h = '<nav class="ss-nav" aria-label="구독센터 메뉴"><div class="ss-nav-top">' +
      '<a class="ss-brand" href="' + esc(LINK.home) + '">삼성스토어 시흥 <b>구독센터</b></a>' +
      '<div class="ss-nav-links">' + top.map(function (t) {
        return '<a href="' + esc(t[2]) + '"' + (cur === t[0] ? ' aria-current="page"' : '') + '>' + t[1] + '</a>';
      }).join('') + '</div>' +
      '<a class="ss-nav-cta" href="' + esc(consultHref(null, 'nav')) + '" data-cta="consult">구독 상담 신청</a></div>' +
      '<div class="ss-nav-cats">' + PAGES.map(function (p) {
        return '<a href="' + esc(catHref(p.key)) + '"' + (cur === p.key ? ' aria-current="page"' : '') + (p.hot ? ' class="is-hot"' : '') + '>' + esc(p.name) + '</a>';
      }).join('') + '</div></nav>';
    el.innerHTML = h;
    var on = el.querySelector('.ss-nav-cats [aria-current]');
    if (on && on.scrollIntoView && on.parentNode.scrollWidth > on.parentNode.clientWidth) on.parentNode.scrollLeft = on.offsetLeft - 16;
  }
  function drawSearch(el) {
    el.innerHTML = '<form class="ss-search" role="search" action="#">' +
      '<input type="search" name="q" placeholder="모델명이나 제품으로 검색 (예: AI 콤보, 65인치 TV, RM80F91H1X)" aria-label="구독 상품 검색">' +
      '<button type="submit">검색</button></form>';
    el.querySelector('form').addEventListener('submit', function (ev) {
      ev.preventDefault();
      var q = this.q.value.replace(/^\s+|\s+$/g, '');
      track('ss_search', { ss_q: q });
      location.href = LINK.find + (q ? '&q=' + encodeURIComponent(q) : '');
    });
  }
  function drawCats(el) {
    el.innerHTML = '<ul class="ss-cats">' + PAGES.map(function (p) {
      var list = rowsOf(p), mn = minOf(list);
      if (!list.length) return '';
      return '<li><a href="' + esc(catHref(p.key)) + '"' + (p.hot ? ' class="is-hot"' : '') + '>' +
        '<span class="ss-cat-icon" aria-hidden="true">' + p.icon + '</span><strong>' + esc(p.name) + ' 구독</strong>' +
        '<span class="ss-cat-price">월 ' + fmt(mn) + '원~</span><span class="ss-cat-n">' + fmt(list.length) + '개 모델</span></a></li>';
    }).join('') + '</ul>';
  }
  // 대표 모델: 이름 있는(고도몰·상품 마스터) 모델을 먼저, 그다음 낮은 월 구독료
  function score(r) { return (r.img ? (r.imgRep ? 1 : 3) : 0) + (r.name ? 1 : 0); }
  function picks(list, n) {
    return list.slice().sort(function (a, b) { return score(b) - score(a) || a.min - b.min; }).slice(0, n);
  }
  function drawPick(el) {
    var p = PAGE_BY[el.getAttribute('data-key')]; if (!p) return;
    var n = +el.getAttribute('data-n') || 4, list = picks(rowsOf(p), n);
    el.innerHTML = list.length ? '<ul class="ss-grid">' + list.map(function (r) { return card(r, 'pick'); }).join('') + '</ul>' +
      '<p class="ss-more"><a href="' + esc(catHref(p.key)) + '">' + esc(p.name) + ' 구독 ' + fmt(rowsOf(p).length) + '개 모델 전체 보기 →</a></p>' : '';
  }
  function drawPopular(el) {
    var out = [];
    PAGES.forEach(function (p) { var r = picks(rowsOf(p), 1)[0]; if (r && r.name) out.push(r); });
    el.innerHTML = '<ul class="ss-grid">' + out.slice(0, +el.getAttribute('data-n') || 12).map(function (r) { return card(r, 'popular'); }).join('') + '</ul>';
  }
  function drawCards(el) {
    if (!CARDS) { el.innerHTML = ''; return; }
    var names = Object.keys(CARDS);
    el.innerHTML = '<ul class="ss-cardsum">' + names.map(function (k) {
      var t = CARDS[k].t || {}, mx = 0; for (var j in t) if (t[j] > mx) mx = t[j];
      return '<li><strong>' + esc(k) + '</strong><span>최대 월 <b>' + fmt(mx) + '원</b> 할인</span><small>최장 ' + (CARDS[k].m || '') + '개월</small></li>';
    }).join('') + '</ul><p class="ss-more"><a href="' + esc(LINK.card) + '">제휴카드별 실적 구간 자세히 보기 →</a></p>';
  }
  function drawCardTable(el) {
    if (!CARDS) { el.innerHTML = '<p class="ss-empty">카드 혜택 정보를 불러오지 못했습니다. 상담으로 안내해 드립니다.</p>'; return; }
    var pc = (POL && POL.cards) || {};
    el.innerHTML = Object.keys(CARDS).map(function (k) {
      var cd = CARDS[k], t = cd.t || {}, notes = (pc[k] && pc[k].notes) || [];
      return '<section class="ss-cardbox"><h3>' + esc(k) + ' <small>할인 기간 최장 ' + (cd.m || '-') + '개월</small></h3>' +
        '<table class="ss-table"><thead><tr><th scope="col">전월 이용실적</th><th scope="col">월 할인</th></tr></thead><tbody>' +
        Object.keys(t).map(function (tier) {
          var base = cd.base && cd.base[tier] && cd.base[tier] !== t[tier] ? ' <small>(기본 ' + fmt(cd.base[tier]) + '원 + 추가 ' + fmt(t[tier] - cd.base[tier]) + '원)</small>' : '';
          return '<tr><td>' + esc(tier.replace('↑', ' 이상')) + '</td><td><b>월 ' + fmt(t[tier]) + '원</b>' + base + '</td></tr>';
        }).join('') + '</tbody></table>' +
        (notes.length ? '<ul class="ss-notes">' + notes.map(function (n) { return '<li>' + esc(n) + '</li>'; }).join('') + '</ul>' : '') +
        '</section>';
    }).join('') +
      (POL && POL.cardNotes ? '<ul class="ss-notes">' + POL.cardNotes.map(function (n) { return '<li>' + esc(n) + '</li>'; }).join('') + '</ul>' : '');
  }
  // 다른 품목 요금표는 받지 않으므로 모델 수로 거르지 않는다
  function drawRelated(el) {
    var cur = CFG.key;
    el.innerHTML = '<ul class="ss-chips">' + PAGES.filter(function (p) { return p.key !== cur; }).map(function (p) {
      return '<li><a href="' + esc(catHref(p.key)) + '">' + esc(p.name) + ' 구독 가격</a></li>';
    }).join('') + '</ul>';
  }
  function drawCta(el) {
    var tel = CFG.tel || '';
    el.innerHTML = '<div class="ss-cta"><div><strong>내 조건에 맞는 구독료가 궁금하신가요?</strong>' +
      '<p>약정 기간·케어 주기·선납·제휴카드까지 맞춰 실제 월 납부액을 계산해 드립니다.</p></div>' +
      '<div class="ss-cta-btns">' + (tel ? '<a class="ss-btn-line" href="tel:' + esc(tel.replace(/[^0-9]/g, '')) + '" data-cta="tel">' + esc(tel) + '</a>' : '') +
      '<a class="ss-btn" href="' + esc(consultHref(null, 'cta')) + '" data-cta="consult">구독 문의하기</a></div></div>';
  }

  /* 품목 페이지 목록 — 세부유형 · 금액대 · 정렬 */
  var BANDS = [['', '전체'], ['30000', '월 3만원 이하', 0, 30000], ['50000', '월 5만원 이하', 0, 50000], ['100000', '월 10만원 이하', 0, 100000], ['over', '월 10만원 초과', 100001, 1e12]];
  var LIST = { seg: '', band: '', sort: 'rec' };
  function drawList(el) {
    var p = PAGE_BY[CFG.key];
    if (!p) { el.innerHTML = '<p class="ss-empty">품목 설정(CFG.key)이 없습니다.</p>'; return; }
    var all = rowsOf(p);
    if (!all.length) { el.innerHTML = '<p class="ss-empty">지금 안내 가능한 ' + esc(p.name) + ' 구독 모델이 없습니다. <a href="' + esc(consultHref(null, 'empty')) + '">상담으로 문의</a>해 주세요.</p>'; return; }
    var segs = {};
    all.forEach(function (r) { var s = segShort(r.seg); if (s) segs[s] = (segs[s] || 0) + 1; });
    var segKeys = Object.keys(segs).sort();
    var list = all.filter(function (r) {
      if (LIST.seg && segShort(r.seg) !== LIST.seg) return false;
      var b = BANDS.filter(function (x) { return x[0] === LIST.band; })[0];
      return !b || !b[0] || (r.min >= b[2] && r.min <= b[3]);
    }).sort(function (a, b) {
      if (LIST.sort === 'rec') return score(b) - score(a) || a.min - b.min;
      return LIST.sort === 'high' ? b.min - a.min : LIST.sort === 'model' ? (a.model < b.model ? -1 : 1) : a.min - b.min;
    });
    el.innerHTML = '<p class="ss-summary"><b>' + esc(p.name) + '</b> 구독 모델 <b>' + fmt(all.length) + '</b>개 · 월 <b>' + fmt(minOf(all)) + '원</b>부터' +
      (CARD1 ? ' · ' + esc(CARD1.name) + ' 할인 시 월 <b>' + fmt(Math.min.apply(null, all.map(cardNet))) + '원</b>부터' : '') + '</p>' +
      (segKeys.length > 1 ? '<div class="ss-filter" role="group" aria-label="세부유형"><button type="button" data-seg=""' + (LIST.seg ? '' : ' aria-pressed="true"') + '>전체 <small>' + all.length + '</small></button>' +
        segKeys.map(function (s) { return '<button type="button" data-seg="' + esc(s) + '"' + (LIST.seg === s ? ' aria-pressed="true"' : '') + '>' + esc(s) + ' <small>' + segs[s] + '</small></button>'; }).join('') + '</div>' : '') +
      '<div class="ss-filter ss-filter-sub" role="group" aria-label="금액대">' + BANDS.map(function (b) {
        return '<button type="button" data-band="' + b[0] + '"' + (LIST.band === b[0] ? ' aria-pressed="true"' : '') + '>' + b[1] + '</button>';
      }).join('') +
      '<select data-sort aria-label="정렬"><option value="rec"' + (LIST.sort === 'rec' ? ' selected' : '') + '>추천순</option><option value="low"' + (LIST.sort === 'low' ? ' selected' : '') + '>월 구독료 낮은순</option><option value="high"' + (LIST.sort === 'high' ? ' selected' : '') + '>월 구독료 높은순</option><option value="model"' + (LIST.sort === 'model' ? ' selected' : '') + '>모델명순</option></select></div>' +
      (list.length ? '<ul class="ss-grid">' + list.map(function (r) { return card(r, 'list'); }).join('') + '</ul>'
        : '<p class="ss-empty">조건에 맞는 모델이 없습니다.</p>');
  }

  /* ---------- 검색엔진용 구조화 데이터 ---------- */
  function ld(obj) {
    var s = document.createElement('script');
    s.type = 'application/ld+json';
    s.text = JSON.stringify(obj);
    document.head.appendChild(s);
  }
  function abs(u) { return /^https?:/.test(u) ? u : SITE + u; }
  function addLd() {
    var crumbs = [{ name: '구독센터', url: LINK.home }];
    var p = PAGE_BY[CFG.key];
    if (CFG.page === 'cat' && p) crumbs.push({ name: p.name + ' 구독', url: catHref(p.key) });
    if (CFG.page === 'card') crumbs.push({ name: '제휴카드 혜택', url: LINK.card });
    if (CFG.page === 'guide') crumbs.push({ name: '구독 안내', url: LINK.guide });
    ld({ '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: crumbs.map(function (c, i) {
      return { '@type': 'ListItem', position: i + 1, name: c.name, item: abs(c.url) };
    }) });
    if (CFG.page === 'cat' && p) {
      var list = rowsOf(p).sort(function (a, b) { return a.min - b.min; }).slice(0, 100);
      ld({ '@context': 'https://schema.org', '@type': 'ItemList', name: '삼성 ' + p.name + ' 구독 가격', numberOfItems: list.length,
        itemListElement: list.map(function (r, i) {
          return { '@type': 'ListItem', position: i + 1, url: abs(LINK.view + encodeURIComponent(r.model)), name: displayName(r) + ' ' + r.model };
        }) });
    }
    if (CFG.page === 'home') {
      ld({ '@context': 'https://schema.org', '@type': 'ItemList', name: '삼성 가전 구독 품목',
        itemListElement: PAGES.map(function (q, i) { return { '@type': 'ListItem', position: i + 1, url: abs(catHref(q.key)), name: '삼성 ' + q.name + ' 구독' }; }) });
    }
    var faq = $all('.ss-faq dt').map(function (dt) {
      var dd = dt.nextElementSibling;
      return dd && dd.tagName === 'DD' ? { '@type': 'Question', name: dt.textContent.replace(/^\s*Q\.?\s*/, ''), acceptedAnswer: { '@type': 'Answer', text: dd.textContent.replace(/^\s+|\s+$/g, '') } } : null;
    }).filter(Boolean);
    if (faq.length) ld({ '@context': 'https://schema.org', '@type': 'FAQPage', mainEntity: faq });
  }
  // 고도몰 관리자 SEO 제목이 비어 있어도 품목 페이지 제목·설명은 가격이 들어간 문장으로 (구글은 바뀐 제목을 읽는다)
  function setMeta() {
    var p = PAGE_BY[CFG.key];
    if (CFG.page !== 'cat' || !p || CFG.keepTitle) return;
    var all = rowsOf(p); if (!all.length) return;
    document.title = '삼성 ' + p.name + ' 구독 가격 월 ' + fmt(minOf(all)) + '원~ | ' + fmt(all.length) + '개 모델 비교 · 삼성스토어 시흥 구독센터';
    var d = document.querySelector('meta[name="description"]');
    if (d) d.setAttribute('content', '삼성 ' + p.name + ' 구독 ' + fmt(all.length) + '개 모델의 월 구독료를 한 번에 비교하세요. 월 ' + fmt(minOf(all)) + '원부터, 제휴카드 할인·선납 할인·방문케어 주기별 요금까지. 삼성스토어 시흥 구독 상담.');
  }

  /* ---------- 시작 ---------- */
  var DRAW = { nav: drawNav, search: drawSearch, cats: drawCats, pick: drawPick, popular: drawPopular, cards: drawCards,
    cardtable: drawCardTable, list: drawList, related: drawRelated, cta: drawCta };
  function draw(kinds) {
    $all('[data-ss]').forEach(function (el) {
      var k = el.getAttribute('data-ss');
      if (DRAW[k] && (!kinds || kinds.indexOf(k) >= 0)) { DRAW[k](el); el.classList.add('is-ready'); }
    });
  }
  function onClick(ev) {
    var t = ev.target.closest ? ev.target.closest('button, a') : null;
    if (!t || !root.contains(t)) return;
    if (t.hasAttribute('data-seg')) { LIST.seg = t.getAttribute('data-seg'); draw(['list']); track('ss_seg', { ss_seg: LIST.seg }); }
    else if (t.hasAttribute('data-band')) { LIST.band = t.getAttribute('data-band'); draw(['list']); }
    else if (t.hasAttribute('data-cta')) track('ss_click', { ss_cta: t.getAttribute('data-cta'), ss_model: t.getAttribute('data-model') || '' });
  }
  function start() {
    if (navOnly) { drawNav(root); return; }
    if (!IDX || !IDX.m) {
      $all('[data-ss="list"],[data-ss="cats"]').forEach(function (el) { el.innerHTML = '<p class="ss-empty">구독 요금 정보를 불러오지 못했습니다. 잠시 후 다시 시도하시거나 상담으로 문의해 주세요.</p>'; });
      draw(['nav', 'cta']);
      return;
    }
    CARD1 = cardInfo();
    buildRows();
    draw(['nav', 'search', 'cta', 'cards', 'cardtable']);   // 요금표 없이 그릴 수 있는 것 먼저
    // 세부유형 이름은 요금표(sub_plans_<품목>.js)에 있다 — 품목 페이지는 그 품목만,
    // 홈은 세부유형으로 나뉘는 품목(의류케어·조리기기)만 받는다 (전부 받으면 400KB)
    var p = PAGE_BY[CFG.key], cats = [];
    if (CFG.page === 'cat' && p) cats = p.cats;
    else if (CFG.page === 'home') PAGES.forEach(function (q) { if (q.seg) q.cats.forEach(function (c) { if (cats.indexOf(c) < 0) cats.push(c); }); });
    loadCats(cats, function () {
      draw(['cats', 'pick', 'popular', 'list', 'related']);
      setMeta();
      addLd();
      track('ss_view');
    });
    root.addEventListener('click', onClick);
    root.addEventListener('change', function (ev) {
      if (ev.target.hasAttribute && ev.target.hasAttribute('data-sort')) { LIST.sort = ev.target.value; draw(['list']); }
    });
  }

  /* 상품명·이미지 — 데이터센터 fn_sub_catalog (느리면 이름 없이 먼저 그린다) */
  function fromApi(done) {
    var api = CFG.catalogApi;
    if (!api || !api.url || !window.fetch) return done();
    var settled = false;
    var timer = setTimeout(function () { if (!settled) { settled = true; done(); } }, api.timeout || 3000);
    fetch(api.url, { method: 'POST', headers: { apikey: api.key, 'Content-Type': 'application/json' }, body: '{}' })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (G) { if (settled) return; settled = true; clearTimeout(timer); CAT = { m: (G && G.m) || {}, img: (G && G.img) || '' }; done(); })
      .catch(function (e) { if (settled) return; settled = true; clearTimeout(timer); if (window.console) console.warn('[구독센터] 상품명 표 실패 → 이름 없이 표시', e); done(); });
  }
  // 카드표·정책이 없으면 받아 온다 (sub_tab.js 를 쓰지 않는 페이지)
  function ensureCards(done) {
    var need = [];
    if (!window.SUB_CARDS) need.push('sub_cards.js');
    if (!window.SUB_POLICY) need.push('sub_policy.js');
    var left = need.length;
    if (!left) return done();
    need.forEach(function (f) {
      loadScript((CFG.dataBase || '/data/js/sub/') + f + '?v=' + encodeURIComponent(CFG.ver || ''), function () {
        if (--left === 0) { CARDS = window.SUB_CARDS || null; POL = window.SUB_POLICY || null; done(); }
      });
    });
  }
  if (navOnly) { start(); return; }
  var waits = 2;
  function ready() { if (--waits === 0) start(); }
  fromApi(ready);
  ensureCards(ready);
})();
