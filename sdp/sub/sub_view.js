/* ===== 구독 상품 페이지 | subscribe/sub_view.html 에서 SUB_VIEW_CONFIG 설정 후 로드 =====
   주소: /main/html.php?htmid=subscribe/sub_view.html&model=RM80F91H1X
   동작 순서
   1) 주소의 model 로 SUB_INDEX(모델→[품목, 최저 월구독료]) 에서 모델을 찾는다 (없으면 안내 + 구독상품 찾기로)
   2) 상품 머리(이미지·이름·세부유형·월 X원~)를 그리고, 그 아래 #subTabRoot 에 상품상세 구독탭과
      같은 계산 화면(sub_tab.js — 데이터센터 배포본)을 구독 모드로 띄운다 → 금액이 상품상세와 항상 같다
   3) 고도몰에 같은 모델 상품이 있으면(데이터센터 fn_sub_goods_map) 이미지·상품명을 쓰고 "쇼핑몰 상품 보기" 를 단다
   4) 같은 세부유형의 다른 모델을 아래에 보여 준다
   ※ 고도몰 상품 등록과 상관없이 구독 요금표에 있는 모든 모델에 페이지가 생긴다
===== */
window.SUB_VIEW_READY = true;   // sub_view.html 이 데이터센터에서 이 파일을 받았는지 확인하는 표시 (못 받았으면 예비 사본으로)
(function () {
  'use strict';
  var CFG = window.SUB_VIEW_CONFIG || {};
  var IDX = window.SUB_INDEX;
  var root = document.getElementById('subViewRoot');
  if (!root) return;

  var CAT_ICON = { ref: '🧊', kimchi: '🥬', water: '💧', tv: '📺', monitor: '🖥️', audio: '🔊', laundry: '👕', cleaner: '🧹',
    aircon: '❄️', sysaircon: '🌬️', cooking: '🍳', airpurifier: '🍃', dehumid: '💨', tab: '📱', book: '💻' };

  function norm(s) { return String(s || '').replace(/\s+/g, '').toUpperCase(); }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function fmt(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function param(name) {
    var m = location.search.match(new RegExp('[?&]' + name + '=([^&]*)'));
    if (!m) return '';
    try { return decodeURIComponent(m[1].replace(/\+/g, ' ')); } catch (e) { return m[1]; }
  }
  function loadScript(src, ok, fail) {
    var s = document.createElement('script');
    s.src = src; s.onload = ok; s.onerror = fail || ok;
    document.head.appendChild(s);
  }
  function loadCss(href) {
    var l = document.createElement('link');
    l.rel = 'stylesheet'; l.href = href;
    document.head.appendChild(l);
  }
  // 구독센터 페이지 폴더: 지금 페이지 주소(htmid=<폴더>/sub_…)를 따른다 — 웹FTP subscribe/ · 예전 service/ 모두 동작
  var PAGE_DIR = CFG.pageDir || (/[?&]htmid=([\w-]+\/)sub_/.exec(location.search) || [])[1] || 'subscribe/';
  function findUrl(q) { var u = CFG.findUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_find.html'; return q ? u + (u.indexOf('?') < 0 ? '?' : '&') + q : u; }
  function viewUrl(model) { return (CFG.viewUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_view.html&model=') + encodeURIComponent(model); }
  function track(name, extra) {
    var ev = { event: name, sub_model: model };
    for (var k in extra) ev[k] = extra[k];
    if (window.dataLayer) window.dataLayer.push(ev);
  }

  // 세부유형 화면 이름 — sub_find.js 의 SEG_LABEL_RULES 와 같은 규칙
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

  var model = norm(param('model'));
  if (!IDX || !IDX.m) { root.innerHTML = '<p class="sv-empty">구독 요금 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.</p>'; return; }
  var entry = IDX.m[model];
  if (!entry) {
    root.innerHTML = '<div class="sv-empty"><p>' + (model ? '<b>' + esc(model) + '</b> 은(는) 지금 구독으로 운영되지 않는 모델입니다.' : '모델이 지정되지 않았습니다.') + '</p>' +
      '<a class="sv-btn" href="' + esc(findUrl(model ? 'q=' + encodeURIComponent(model.slice(0, 6)) : '')) + '">비슷한 구독 모델 찾기</a></div>';
    return;
  }
  var cat = entry[0], catName = IDX.cats[cat] || '';
  var goods = null, seg = '', pname = '', img = '', imgRep = false;   // goods: 고도몰 연결 [상품번호, 상품명, 이미지, 일시불가] · pname/img: 구독센터 카탈로그

  /* 구독센터(sub_shop.js) 품목 페이지 — 경로·검색엔진 이동 경로에 쓴다 (sub_shop.js 의 PAGES 와 같은 규칙) */
  var CENTER = [['aicombo', 'AI 콤보', 'laundry', /콤보/], ['washer', '세탁기', 'laundry', /^(드럼|전자동|세탁기\+건조기)/],
    ['dryer', '건조기', 'laundry', /^건조기/], ['airdresser', '에어드레서', 'laundry', /벌식/],
    ['dishwasher', '식기세척기', 'cooking', /인용|카운터탑/], ['induction', '인덕션·후드', 'cooking', /전기레인지|인덕션|후드/],
    ['galaxy', '갤럭시 탭·북', 'tab'], ['galaxy', '갤럭시 탭·북', 'book']];
  function centerPage() {
    for (var i = 0; i < CENTER.length; i++) {
      var c = CENTER[i];
      if (c[2] === cat && (!c[3] || (seg && c[3].test(seg)))) return { key: c[0], name: c[1] };
    }
    if (cat === 'laundry' || cat === 'cooking') return null;
    return { key: cat, name: catName };
  }
  function homeUrl() { return CFG.homeUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_home.html'; }
  function catUrl(key) { return (CFG.catUrl || '/main/html.php?htmid=' + PAGE_DIR + 'sub_c_') + key + '.html'; }
  function cleanName(s) { return String(s || '').replace(/\s*\*+\s*$/, '').replace(/\s*(삼성본사직배송|본사직배송)\s*/g, ' ').replace(/\s{2,}/g, ' ').replace(/^\s|\s$/g, ''); }
  // 이름 없는 TV·모니터는 모델명에서 크기·라인업을 읽는다 (sub_shop.js 의 modelHint 와 같은 규칙)
  function modelHint() {
    var m;
    if (cat === 'tv' && (m = model.match(/^(KMR|KQ|KU)(\d{2,3})([A-Z]+)/))) {
      var line = m[1] === 'KMR' ? 'Micro RGB' : m[1] === 'KU' ? (/^MH/.test(m[3]) ? 'Mini LED' : /^LS/.test(m[3]) ? '더 무빙스타일' : 'UHD') :
        /^QN/.test(m[3]) ? 'Neo QLED' : /^S/.test(m[3]) ? 'OLED' : 'QLED';
      return '삼성 ' + line + ' ' + m[2] + '형 TV' + (/보조|\+/.test(seg) ? ' 세트' : '');
    }
    if (cat === 'monitor' && (m = model.match(/^L[SC](\d{2})/))) return '삼성 ' + m[1] + '형 모니터';
    return '';
  }
  function productName() {
    if (pname) return pname;
    var h = modelHint(); if (h) return h;
    var cp = centerPage(), kind = cp && cp.key !== 'galaxy' ? cp.name : catName, s = segLabel(seg).replace(/\s*공통$/, '');
    if (s && s.indexOf(kind) >= 0) kind = '';
    return ('삼성 ' + kind + (s ? ' ' + s : '')).replace(/\s+/g, ' ');
  }

  /* ---------- 머리 ---------- */
  function headHtml() {
    var title = productName(), cp = centerPage();
    return '<nav class="sv-crumb"><a href="' + esc(homeUrl()) + '">구독센터</a> › ' +
      (cp ? '<a href="' + esc(catUrl(cp.key)) + '">' + esc(cp.name) + ' 구독</a>' : '<a href="' + esc(findUrl('cat=' + cat)) + '">' + esc(catName) + '</a>') +
      (seg ? ' › <a href="' + esc(findUrl('cat=' + cat + '&seg=' + encodeURIComponent(seg))) + '">' + esc(segLabel(seg)) + '</a>' : '') + '</nav>' +
      '<div class="sv-head">' +
      '<div class="sv-img">' + (img ? '<img src="' + esc(img) + '" alt="' + esc(title) + '">' + (imgRep ? '<span class="sv-imgnote">대표 이미지 · 색상·구성은 모델마다 다를 수 있습니다</span>' : '') : '<span class="sv-icon">' + (CAT_ICON[cat] || '📦') + '</span>') + '</div>' +
      '<div class="sv-info">' +
      '<p class="sv-cat">' + esc(catName) + (seg ? ' · ' + esc(segLabel(seg)) : '') + '</p>' +
      '<h1 class="sv-title">' + esc(title) + '</h1>' +
      '<p class="sv-model">모델명 <b>' + esc(model) + '</b></p>' +
      '<p class="sv-price"><small>구독 월</small> ' + fmt(entry[1]) + '<small>원~</small></p>' +
      '<p class="sv-badge">삼성전자 AI 구독클럽 공식 파트너 · 무상수리 포함</p>' +
      (goods ? '<a class="sv-goods" data-cta="goods" href="' + esc(lumpHref()) + '">시흥몰 가격 확인하기' + (goods[3] > 0 ? ' · 일시불 ' + fmt(goods[3]) + '원' : '') + '</a>' : '') +
      '</div></div>';
  }
  function renderHead() {
    var h = root.querySelector('[data-slot="head"]');
    if (h) h.innerHTML = headHtml();
    var title = productName();
    document.title = title + ' 구독 가격 월 ' + fmt(entry[1]) + '원~ (' + model + ') | 삼성스토어 시흥 구독센터';
    var desc = title + ' (' + model + ') 삼성 AI 구독 월 ' + fmt(entry[1]) + '원부터. 약정 기간·방문케어 주기·선납 할인·제휴카드 할인별 월 구독료를 바로 계산하고 구독 상담을 신청하세요.';
    setMeta('name', 'description', desc);
    setMeta('property', 'og:title', document.title);
    setMeta('property', 'og:description', desc);
    if (img) setMeta('property', 'og:image', img);
    // 같은 모델 페이지가 utm 같은 꼬리표로 여러 주소가 되지 않게 대표 주소를 박는다
    var canon = (CFG.site || location.protocol + '//' + location.host) + viewUrl(model);
    var link = document.querySelector('link[rel="canonical"]');
    if (!link) { link = document.createElement('link'); link.rel = 'canonical'; document.head.appendChild(link); }
    link.href = canon;
    setMeta('property', 'og:url', canon);
    addLd(title, canon);
  }
  function setMeta(attr, key, val) {
    var m = document.querySelector('meta[' + attr + '="' + key + '"]');
    if (!m) { m = document.createElement('meta'); m.setAttribute(attr, key); document.head.appendChild(m); }
    m.setAttribute('content', val);
  }
  // 검색엔진용 상품(월 구독료) · 이동 경로 구조화 데이터
  var ldEl = null;
  function addLd(title, canon) {
    var site = CFG.site || location.protocol + '//' + location.host, cp = centerPage();
    var data = [{
      '@context': 'https://schema.org', '@type': 'Product', name: title, sku: model, mpn: model, url: canon,
      brand: { '@type': 'Brand', name: 'Samsung' }, category: catName + (seg ? ' > ' + segLabel(seg) : ''),
      description: title + ' 삼성 AI 구독 · 월 ' + fmt(entry[1]) + '원부터 (약정·케어·제휴카드 조건에 따라 달라집니다)',
      offers: { '@type': 'Offer', url: canon, priceCurrency: 'KRW', price: entry[1], availability: 'https://schema.org/InStock',
        seller: { '@type': 'Organization', name: '삼성스토어 시흥' },
        priceSpecification: { '@type': 'UnitPriceSpecification', price: entry[1], priceCurrency: 'KRW',
          referenceQuantity: { '@type': 'QuantitativeValue', value: 1, unitCode: 'MON' } } }
    }, {
      '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: [{ '@type': 'ListItem', position: 1, name: '구독센터', item: site + homeUrl() }]
        .concat(cp ? [{ '@type': 'ListItem', position: 2, name: cp.name + ' 구독', item: site + catUrl(cp.key) }] : [])
        .concat([{ '@type': 'ListItem', position: cp ? 3 : 2, name: title, item: canon }])
    }];
    if (img) data[0].image = img;
    if (!ldEl) { ldEl = document.createElement('script'); ldEl.type = 'application/ld+json'; document.head.appendChild(ldEl); }
    ldEl.text = JSON.stringify(data);
  }

  /* ---------- 같은 세부유형 다른 모델 ---------- */
  function renderSiblings() {
    var P = (window.SUB_PLANS || {})[cat];
    var box = root.querySelector('[data-slot="more"]');
    if (!P || !box) return;
    var list = Object.keys(P).filter(function (m) { return m !== model && IDX.m[m] && (!seg || P[m].s === seg); })
      .sort(function (a, b) { return IDX.m[a][1] - IDX.m[b][1]; }).slice(0, 8);
    if (!list.length) { box.innerHTML = ''; return; }
    box.innerHTML = '<h2 class="sv-h2">같은 유형의 다른 구독 모델</h2><ul class="sv-more">' + list.map(function (m) {
      return '<li><a href="' + esc(viewUrl(m)) + '" data-cta="sibling"><b>' + esc(m) + '</b><span>월 ' + fmt(IDX.m[m][1]) + '원~</span></a></li>';
    }).join('') + '</ul><p class="sv-more-all"><a href="' + esc(findUrl('cat=' + cat + (seg ? '&seg=' + encodeURIComponent(seg) : ''))) + '">' + esc(catName) + ' 구독 모델 전체 보기 →</a></p>';
    var cp = centerPage(), all = box.querySelector('.sv-more-all a');
    if (cp && all) { all.setAttribute('href', catUrl(cp.key)); all.textContent = cp.name + ' 구독 모델 전체 보기 →'; }
  }


  /* 구독센터 메뉴 — 데이터센터 sub_shop.js 를 메뉴 전용으로 불러와 페이지 위에 붙인다 (CFG.centerNav === false 면 끔) */
  function centerNav(page, key) {
    if (CFG.centerNav === false || document.getElementById('subShopNav')) return;
    var nav = document.createElement('div');
    nav.id = 'subShopNav';
    root.parentNode.insertBefore(nav, root.parentNode.firstChild);   // 페이지 맨 위 (머리글보다 먼저)
    window.SUB_SHOP_CONFIG = window.SUB_SHOP_CONFIG || { page: page, key: key || '', tel: CFG.tel || '', consultUrl: CFG.consultUrl, findUrl: CFG.findUrl, viewUrl: CFG.viewUrl,
      homeUrl: CFG.homeUrl, catUrl: CFG.catUrl, cardUrl: CFG.cardUrl, guideUrl: CFG.guideUrl };
    var b = CFG.dataBase || '/data/js/sub/', v = encodeURIComponent(CFG.ver || (IDX && IDX.ver) || '');
    var l = document.createElement('link'); l.rel = 'stylesheet'; l.href = b + 'sub_shop.css?v=' + v; document.head.appendChild(l);
    var s = document.createElement('script'); s.src = b + 'sub_shop.js?v=' + v; document.head.appendChild(s);
  }

  /* ---------- 골격 ---------- */
  root.innerHTML =
    '<div data-slot="head"></div>' +
    '<section class="sv-calc"><h2 class="sv-h2">구독 요금 계산</h2><div id="subTabRoot" hidden></div>' +
    '<p class="sv-loading" data-slot="loading">요금 정보를 불러오는 중…</p></section>' +
    '<section data-slot="more"></section>';
  renderHead();
  centerNav('view', centerPage() ? centerPage().key : cat);
  root.addEventListener('click', function (ev) {
    var a = ev.target.closest ? ev.target.closest('a[data-cta]') : null;
    if (a) track('sub_view_click', { sv_cta: a.getAttribute('data-cta') });
  });

  /* ---------- 하단 버튼 2개: "시흥몰 가격 확인하기" + "구독 문의하기" ----------
     sub_tab.js 가 CFG.cta='lump+consult' 를 지원하면 그쪽이 그린다(data-cta="lump" 가 있으면 손대지 않음).
     지원 전 판이면 여기서 버튼 칸만 바꿔 끼운다 — 상담 링크(선택한 약정·케어·카드가 담긴 메모)는 원래 버튼 주소를 그대로 쓴다 */
  function lumpHref() {
    return goods ? (CFG.goodsUrl || '/goods/goods_view.php?goodsNo=') + encodeURIComponent(goods[0]) +
      '&utm_source=sub_view&utm_medium=lump&utm_campaign=' + encodeURIComponent(model) : '';
  }
  function fixCta() {
    var cta = root.querySelector('#subTabRoot .subtab-cta');
    if (!cta || cta.getAttribute('data-sv') || cta.querySelector('[data-cta="lump"]')) return;
    var main = cta.querySelector('.subtab-cta-main');
    var consult = main ? main.getAttribute('href') : '';
    var lu = lumpHref();
    cta.setAttribute('data-sv', '1');
    cta.innerHTML = (lu ? '<a class="subtab-cta-sub sv-cta-lump" data-cta="lump" href="' + esc(lu) + '">시흥몰 가격 확인하기</a>' : '') +
      '<a class="subtab-cta-main" data-cta="consult" href="' + esc(consult) + '">구독 문의하기</a>';
  }

  /* ---------- 계산 화면: 상품상세 구독탭(sub_tab.js) 을 구독 모드로 ---------- */
  var base = CFG.dataBase || '/data/js/sub/', ver = CFG.ver || IDX.ver;
  function startCalc() {
  window.SUB_TAB_CONFIG = {
    ver: ver, dataBase: base,
    models: [model], goodsNo: goods ? String(goods[0]) : '',
    lumpPrice: goods && goods[3] > 0 ? goods[3] : 0,   // 시흥몰 일시불 판매가 → "일시불보다 ○원 저렴"·"일시불 구매가" 비교가 함께 나온다
    defaultTab: 'sub', enabled: true, lumpOnly: [],
    consultUrl: CFG.consultUrl || '/main/html.php?htmid=service/SamSungSubscription.html',
    tel: '', defaultCard: CFG.defaultCard || '', defaultTier: '', cardGuideUrl: CFG.cardGuideUrl || '',
    productCat: catName, extraPoints: CFG.extraPoints || [],
    // 상담 신청서에 "구독 상품 페이지"에서 온 것으로 남긴다 (sub_tab.js 의 CFG.source / sourceName / utmSource)
    source: 'view', sourceName: '구독 상품 페이지', utmSource: 'sub_view',
    // 하단 버튼 2개 (sub_tab.js 가 지원하는 판부터 적용, 그 전엔 fixCta 가 대신)
    cta: 'lump+consult', lumpUrl: lumpHref(), lumpLabel: '시흥몰 가격 확인하기', consultLabel: '구독 문의하기'
  };
  var tabRoot = root.querySelector('#subTabRoot');
  if (tabRoot && window.MutationObserver) new MutationObserver(fixCta).observe(tabRoot, { childList: true, subtree: true });
  loadCss(base + 'sub_tab.css?v=' + encodeURIComponent(ver));
  loadScript(base + 'sub_plans_' + cat + '.js?v=' + encodeURIComponent(ver), function () {
    var P = (window.SUB_PLANS || {})[cat] || {};
    seg = P[model] ? P[model].s || '' : '';
    renderHead(); renderSiblings();
    function calcFailed() {
      var ld = root.querySelector('[data-slot="loading"]');
      if (!ld) { ld = document.createElement('p'); ld.className = 'sv-loading'; ld.setAttribute('data-slot', 'loading'); root.querySelector('.sv-calc').appendChild(ld); }
      var href = (CFG.consultUrl || '/main/html.php?htmid=service/SamSungSubscription.html') + '&from=view&purpose=' + encodeURIComponent('신규구독') +
        '&product=' + encodeURIComponent(catName) + '&model=' + encodeURIComponent(model) + '&src=' + encodeURIComponent('구독 상품 페이지') + '&utm_source=sub_view&utm_medium=fallback';
      ld.innerHTML = '이 모델은 요금 계산 화면을 준비 중입니다. 약정·케어별 요금은 <a href="' + esc(href) + '">구독 상담 신청</a>으로 바로 안내해 드립니다.';
      track('sub_view_calc_fail', { sv_cat: cat });
    }
    loadScript(base + 'sub_tab.js?v=' + encodeURIComponent(ver), function () {
      // 계산 화면이 실제로 그려졌는지 확인 — 요금제 이름을 못 읽는 품목 등으로 비어 있으면 상담 안내로 대신한다
      setTimeout(function () {
        if (root.querySelector('#subTabRoot .subtab-bar')) {
          var ld = root.querySelector('[data-slot="loading"]');
          if (ld) ld.parentNode.removeChild(ld);
          track('sub_view_view', { sv_cat: cat });
        } else calcFailed();
      }, 2500);
    }, calcFailed);
  });
  }

  /* ---------- 고도몰 상품 연결 (이미지·상품명·일시불 판매가) → 받은 뒤 계산 화면 시작 ----------
     연결표: 모델 → [상품번호, 상품명, 목록이미지, 일시불 판매가] — "[구독]" 전용 상품보다 일반 상품을 먼저 고른 값.
     데이터센터가 늦거나 실패해도 2.5초 뒤엔 계산 화면을 띄운다 (그때는 일시불 비교·시흥몰 가격 버튼 없이) */
  var started = false;
  function go() { if (started) return; started = true; startCalc(); }
  var api = CFG.goodsApi;
  if (api && api.url && window.fetch) {
    setTimeout(go, 2500);
    // 구독센터 카탈로그(fn_sub_catalog)를 쓴다 — 연결표와 같은 모양 + 고도몰에 없는 모델의 상품명까지 (상품번호 0 = 고도몰 미등록)
    var url = CFG.catalogApi && CFG.catalogApi.url ? CFG.catalogApi.url : api.url.replace(/fn_sub_goods_map$/, 'fn_sub_catalog');
    fetch(url, { method: 'POST', headers: { apikey: api.key, 'Content-Type': 'application/json' }, body: '{}' })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (G) {
        CFG.imgBase = G.img || '';
        var m = (G && G.m) || {};
        var c = null;
        for (var k in m) if (m.hasOwnProperty(k) && norm(k) === model) { c = m[k]; break; }
        if (c) {
          goods = c[0] ? c : null;
          pname = cleanName(c[1]);
          img = c[2] ? (/^https?:/.test(c[2]) ? c[2] : (CFG.imgBase || '') + c[2]) : '';
          imgRep = /^[sgc]$/.test(c[4] || '');   // 같은 세부유형·품목의 다른 모델 사진
          renderHead();
        }
        go();
      })
      .catch(function (e) { if (window.console) console.warn('[구독상품] 상품 연결표를 못 읽음', e); go(); });
  } else go();
})();
