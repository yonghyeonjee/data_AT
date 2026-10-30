/* ===== 구독 상품 페이지 | subscribe/sub_view.html 에서 SUB_VIEW_CONFIG 설정 후 로드 =====
   주소: /main/html.php?htmid=subscribe/sub_view.html&model=RM80F91H1X
   동작 순서
   1) 주소의 model 로 SUB_INDEX(모델→[품목, 최저 월구독료]) 에서 모델을 찾는다 (없으면 안내 + 구독상품 찾기로)
   2) 상품 머리(이미지·이름·세부유형·월 X원~)를 그리고, 그 아래 #subTabRoot 에 상품상세 구독탭과
      같은 계산 화면(sub_tab.js — 데이터센터 배포본)을 구독 모드로 띄운다 → 금액이 상품상세와 항상 같다
   3) 고도몰에 같은 모델 상품이 있으면(데이터센터 fn_sub_goods_map) 이미지·상품명을 쓰고 "쇼핑몰 상품 보기" 를 단다
   4) 같은 세부유형의 다른 모델을 아래에 보여 준다
   ※ 고도몰 상품 등록과 상관없이 구독 요금표에 있는 모든 모델에 페이지가 생긴다
   2026-10-30: 카탈로그 배포본(sub_catalog.js) 이 있으면 RPC·대기 없이 바로 그린다 · 다른 색상 · 함께 구독하면 좋은 상품 · 삼성닷컴 특장점 요약(desc/<모델>.json) · 묶음 계산기 담기
===== */
window.SUB_VIEW_READY = true;   // sub_view.html 이 데이터센터에서 이 파일을 받았는지 확인하는 표시 (못 받았으면 예비 사본으로)
(function () {
  'use strict';
  var CFG = window.SUB_VIEW_CONFIG || {};
  var IDX = window.SUB_INDEX;
  var root = document.getElementById('subViewRoot');
  if (!root) return;
  // 고도몰 목록용 작은 사진(240px 미만)은 늘리지 않는다 — 300px 로 확대돼 깨져 보이던 것
  document.addEventListener('load', function (e) {
    var t = e.target;
    if (t && t.tagName === 'IMG' && t.closest && t.closest('.sv-img') && t.naturalWidth && t.naturalWidth < 240) t.className = 'is-small';
  }, true);

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
      '<button type="button" class="sv-bundle' + (cartHas(model) ? ' is-on' : '') + '" data-bundle="' + esc(model) + '">' + (cartHas(model) ? '묶음 계산기에 담김 ✓ · 계산하기' : '+ 다른 제품과 묶어 계산하기') + '</button>' +
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

  /* ---------- 묶음 계산기 담기 (sub_shop.js 의 SUB_CART — 아직 안 왔으면 같은 저장소 키에 직접) ---------- */
  function cartGet() { try { var v = JSON.parse(localStorage.getItem('ss_bundle_v1') || '[]'); return v instanceof Array ? v : []; } catch (e) { return []; } }
  function cartHas(m) { return window.SUB_CART ? window.SUB_CART.has(m) : cartGet().some(function (it) { return it.m === m; }); }
  function cartToggle(m) {
    if (window.SUB_CART) { if (window.SUB_CART.has(m)) window.SUB_CART.remove(m); else if (!window.SUB_CART.add(m)) alert('묶음 계산기에는 최대 10개까지 담을 수 있습니다'); return; }
    var items = cartGet().filter(function (it) { return it.m !== m; });
    if (items.length === cartGet().length) { if (items.length >= 10) return alert('묶음 계산기에는 최대 10개까지 담을 수 있습니다'); items.push({ m: m }); }
    try { localStorage.setItem('ss_bundle_v1', JSON.stringify(items)); } catch (e) {}
    try { document.dispatchEvent(new CustomEvent('ss-cart')); } catch (e2) {}
  }
  function bundleUrl() { return CFG.bundleUrl || (CFG.homeUrl ? CFG.homeUrl.replace(/index\.html$/, 'bundle.html') : '/main/html.php?htmid=' + PAGE_DIR + 'sub_bundle.html'); }
  function syncBundleBtn() {
    var b = root.querySelector('[data-bundle]'); if (!b) return;
    var on = cartHas(model); b.classList.toggle('is-on', on);
    b.textContent = on ? '묶음 계산기에 담김 ✓ · 계산하기' : '+ 다른 제품과 묶어 계산하기';
  }
  document.addEventListener('ss-cart', syncBundleBtn);

  /* ---------- 색상만 다른 모델 (규칙은 sub_shop.js 의 SUB_FAMILY 와 같다) ---------- */
  function familyKey(m) {
    if (window.SUB_FAMILY) return window.SUB_FAMILY(m);
    var x = /^(.*\d)([A-Z]+?)(N\d)?$/.exec(String(m || '').toUpperCase());
    if (!x) return m;
    return x[1] + (x[2].length >= 3 ? x[2].slice(0, -1) : '') + (x[3] || '');
  }
  function catInfo(m) {   // 카탈로그 [상품번호, 상품명, 사진, 일시불가, 사진출처]
    var c = catMap[m]; if (c) return c;
    for (var k in catMap) if (catMap.hasOwnProperty(k) && norm(k) === m) return catMap[k];
    return null;
  }
  function imgOf(c) { return c && c[2] ? (/^https?:/.test(c[2]) ? c[2] : (CFG.imgBase || '') + c[2]) : ''; }
  function renderVariants() {
    var P = (window.SUB_PLANS || {})[cat];
    var box = root.querySelector('[data-slot="variants"]');
    if (!P || !box) return;
    var fk = familyKey(model);
    var list = Object.keys(IDX.m).filter(function (m) { return m !== model && IDX.m[m][0] === cat && familyKey(m) === fk && (!P[m] || !seg || P[m].s === seg); })
      .sort(function (a, b) { return IDX.m[a][1] - IDX.m[b][1]; });
    if (!list.length) { box.innerHTML = ''; return; }
    box.innerHTML = '<h2 class="sv-h2">같은 모델, 다른 색상</h2><ul class="sv-variants">' + list.map(function (m) {
      var c = catInfo(m), im = imgOf(c);
      return '<li><a href="' + esc(viewUrl(m)) + '" data-cta="variant">' + (im ? '<img src="' + esc(im) + '" alt="" loading="lazy">' : '') +
        '<b>' + esc(m) + '</b><span>월 ' + fmt(IDX.m[m][1]) + '원~</span></a></li>';
    }).join('') + '</ul><p class="sv-note">색상·마감에 따라 월 구독료가 다를 수 있습니다.</p>';
  }
  /* ---------- 함께 구독하면 좋은 상품 — 다른 품목의 대표 모델 (자기 사진·이름 있는 것 중 저렴한 순) ---------- */
  var RECO = { ref: ['kimchi', 'cooking', 'laundry', 'water'], kimchi: ['ref', 'cooking', 'water'], laundry: ['ref', 'cleaner', 'airpurifier', 'tv'],
    aircon: ['airpurifier', 'dehumid', 'tv', 'ref'], sysaircon: ['airpurifier', 'ref', 'tv'], tv: ['audio', 'aircon', 'ref'], water: ['ref', 'airpurifier', 'cooking'],
    cooking: ['ref', 'kimchi', 'water'], cleaner: ['laundry', 'airpurifier', 'ref'], airpurifier: ['aircon', 'dehumid', 'cleaner'], dehumid: ['airpurifier', 'aircon'],
    monitor: ['book', 'tab', 'audio'], tab: ['book', 'monitor'], book: ['tab', 'monitor'], audio: ['tv', 'monitor'] };
  function renderReco() {
    var box = root.querySelector('[data-slot="reco"]');
    if (!box) return;
    var cats = RECO[cat] || [], out = [];
    cats.forEach(function (c) {
      var pool = [], seen = {};
      for (var m in IDX.m) {
        if (!IDX.m.hasOwnProperty(m) || IDX.m[m][0] !== c) continue;
        var ci = catInfo(m); if (!ci || ci[4] !== 'm' || !ci[1]) continue;   // 자기 사진 + 상품명 있는 모델만
        var fk = familyKey(m); if (seen[fk]) continue; seen[fk] = 1;          // 색상만 다른 모델은 하나로
        pool.push({ m: m, c: ci, min: IDX.m[m][1] });
      }
      var g = pool.filter(function (x) { return x.c[0]; }); if (g.length >= 3) pool = g;   // 고도몰 상품 있는 것 우선
      if (!pool.length) return;
      pool.sort(function (a, b) { return a.min - b.min; });
      out.push(pool[Math.min(pool.length - 1, Math.floor(pool.length * 0.6))]);   // 제일 싼 것 말고 흔히 고르는 가격대
    });
    if (!out.length) { box.innerHTML = ''; return; }
    box.innerHTML = '<h2 class="sv-h2">함께 구독하면 좋은 상품</h2><p class="sv-sub">여러 대를 같이 구독하면 월 납부액을 한 번에 계산해 볼 수 있습니다.</p><ul class="sv-reco">' + out.slice(0, 4).map(function (r) {
      var im = imgOf(r.c), on = cartHas(r.m);
      return '<li class="' + (on ? 'in-cart' : '') + '"><a href="' + esc(viewUrl(r.m)) + '" data-cta="reco">' + (im ? '<span class="sv-reco-img"><img src="' + esc(im) + '" alt="" loading="lazy"></span>' : '') +
        '<span class="sv-reco-cat">' + esc(IDX.cats[r.m && IDX.m[r.m][0]] || '') + '</span><b>' + esc(cleanName(r.c[1])) + '</b><span class="sv-reco-model">' + esc(r.m) + '</span>' +
        '<span class="sv-reco-price">월 ' + fmt(IDX.m[r.m][1]) + '원~</span></a>' +
        '<button type="button" class="sv-reco-add" data-bundle-add="' + esc(r.m) + '">' + (on ? '담김 ✓' : '+ 담기') + '</button></li>';
    }).join('') + '</ul><p class="sv-more-all"><a href="' + esc(bundleUrl()) + '">다품목 계산기에서 묶음 월 구독료 보기 →</a></p>';
  }
  document.addEventListener('ss-cart', function () {
    root.querySelectorAll('[data-bundle-add]').forEach(function (b) { var on = cartHas(b.getAttribute('data-bundle-add')); b.textContent = on ? '담김 ✓' : '+ 담기'; b.parentNode.classList.toggle('in-cart', on); });
  });
  /* ---------- 삼성닷컴 특장점 요약 (sdp/sub/desc/<모델>.json · tools/pdp summarize.py) ---------- */
  function renderDesc() {
    var box = root.querySelector('[data-slot="desc"]');
    if (!box || !window.fetch || CFG.desc === false) return;
    var b = CFG.dataBase || '/data/js/sub/';
    fetch(b + 'desc/' + encodeURIComponent(model) + '.json', { cache: 'force-cache' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) {
        var blocks = (d && d.blocks || []).filter(function (x) { return x.title || x.desc || x.img || x.video; });
        if (!blocks.length) return;
        box.innerHTML = '<h2 class="sv-h2">제품 특장점 <small>삼성전자 제공</small></h2><div class="sv-feat">' + blocks.map(function (x, i) {
          var media = x.video ? '<video src="' + esc(x.video) + '"' + (x.poster ? ' poster="' + esc(x.poster) + '"' : '') + ' muted loop playsinline preload="none" controls></video>'
            : x.img ? '<picture>' + (x.imgm && x.imgm !== x.img ? '<source media="(max-width:760px)" srcset="' + esc(x.imgm) + '">' : '') + '<img src="' + esc(x.img) + '" alt="' + esc(x.alt || x.title || '') + '" loading="lazy"></picture>' : '';
          var text = (x.eyebrow ? '<p class="sv-feat-eyebrow">' + esc(x.eyebrow) + '</p>' : '') + (x.title ? '<h3>' + esc(x.title) + '</h3>' : '') + (x.desc ? '<p>' + esc(x.desc) + '</p>' : '') + (x.note ? '<small>' + esc(x.note) + '</small>' : '');
          return '<section class="sv-feat-block' + (i === 0 && !x.title ? ' is-hero' : '') + '">' + media + (text ? '<div class="sv-feat-text">' + text + '</div>' : '') + '</section>';
        }).join('') + '</div><p class="sv-note">본 특장점의 이미지·영상·문구는 삼성전자 제공 자료를 요약한 것입니다. 제품 사양은 제조사 사정에 따라 변경될 수 있으며, 자세한 내용은 <a href="' + esc(d.src || 'https://www.samsung.com/sec/') + '" target="_blank" rel="noopener">삼성닷컴 제품 페이지</a>에서 확인하세요.</p>';
        // 영상은 화면에 들어올 때만 재생
        if (window.IntersectionObserver) {
          var io = new IntersectionObserver(function (es) { es.forEach(function (e) { var v = e.target; if (e.isIntersecting) { v.play && v.play().catch(function () {}); } else v.pause && v.pause(); }); }, { threshold: 0.4 });
          box.querySelectorAll('video').forEach(function (v) { io.observe(v); });
        }
        track('sub_view_desc', { sv_blocks: blocks.length });
      })
      .catch(function () { box.innerHTML = ''; });
  }

  /* ---------- 같은 세부유형 다른 모델 ---------- */
  function renderSiblings() {
    var P = (window.SUB_PLANS || {})[cat];
    var box = root.querySelector('[data-slot="more"]');
    if (!P || !box) return;
    var fk = familyKey(model);
    var list = Object.keys(P).filter(function (m) { return m !== model && IDX.m[m] && (!seg || P[m].s === seg) && familyKey(m) !== fk; })
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
    '<section data-slot="variants"></section>' +
    '<section data-slot="desc"></section>' +
    '<section data-slot="reco"></section>' +
    '<section data-slot="more"></section>';
  renderHead();
  centerNav('view', centerPage() ? centerPage().key : cat);
  root.addEventListener('click', function (ev) {
    var b = ev.target.closest ? ev.target.closest('[data-bundle],[data-bundle-add]') : null;
    if (b) {
      var m = b.getAttribute('data-bundle') || b.getAttribute('data-bundle-add');
      if (b.hasAttribute('data-bundle') && cartHas(m)) { location.href = bundleUrl(); return; }   // 이미 담겼으면 계산기로
      cartToggle(m); syncBundleBtn(); track('sub_view_cart', { sv_model: m });
      if (b.hasAttribute('data-bundle') && cartHas(m)) b.textContent = '담았습니다 ✓ · 계산하기';
      return;
    }
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
    openConditions: true,   // 구독 전용 페이지는 [조건별 구독가] 를 처음부터 펼쳐 둔다 (상품상세 구독탭은 요약만)
    // 상담 주소·전화·기본 카드는 비워 두면 sub_tab.js 가 데이터센터 정책(SUB_POLICY.defaults · 관리자 › 구독 혜택 정책 › 기본 기준)을 쓴다 — 구독탭과 같은 기준
    consultUrl: CFG.consultUrl || '',
    tel: '', defaultCard: CFG.defaultCard || '', defaultTier: '', cardGuideUrl: CFG.cardGuideUrl || '',
    productCat: catName, extraPoints: CFG.extraPoints || [],
    // 상담 신청서에 "구독 상품 페이지"에서 온 것으로 남긴다 (sub_tab.js 의 CFG.source / sourceName / utmSource)
    source: 'view', sourceName: '구독 상품 페이지', utmSource: 'sub_view',
    // 하단 버튼 2개 (sub_tab.js 가 지원하는 판부터 적용, 그 전엔 fixCta 가 대신)
    cta: 'lump+consult', lumpUrl: lumpHref(), lumpLabel: '시흥몰 가격 확인하기', consultLabel: '구독 문의하기'
  };
  var tabRoot = root.querySelector('#subTabRoot');
  if (tabRoot && window.MutationObserver) new MutationObserver(function () {
    fixCta();
    var ld = root.querySelector('[data-slot="loading"]');
    if (ld && root.querySelector('#subTabRoot .subtab-bar')) ld.parentNode.removeChild(ld);
  }).observe(tabRoot, { childList: true, subtree: true });
  loadCss(base + 'sub_tab.css?v=' + encodeURIComponent(ver));
  loadScript(base + 'sub_plans_' + cat + '.js?v=' + encodeURIComponent(ver), function () {
    var P = (window.SUB_PLANS || {})[cat] || {};
    seg = P[model] ? P[model].s || '' : '';
    renderHead(); renderVariants(); renderSiblings(); renderReco(); renderDesc();
    function calcFailed() {
      var ld = root.querySelector('[data-slot="loading"]');
      if (!ld) { ld = document.createElement('p'); ld.className = 'sv-loading'; ld.setAttribute('data-slot', 'loading'); root.querySelector('.sv-calc').appendChild(ld); }
      var pd = window.SUB_POLICY && window.SUB_POLICY.defaults;
      var href = (CFG.consultUrl || (pd && pd.consultUrl) || '/main/html.php?htmid=service/SamSungSubscription.html') + '&from=view&purpose=' + encodeURIComponent('신규구독') +
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
      }, 4000);
    }, calcFailed);
  });
  }

  /* ---------- 고도몰 상품 연결 (이미지·상품명·일시불 판매가) → 받은 뒤 계산 화면 시작 ----------
     연결표: 모델 → [상품번호, 상품명, 목록이미지, 일시불 판매가] — "[구독]" 전용 상품보다 일반 상품을 먼저 고른 값.
     데이터센터가 늦거나 실패해도 2.5초 뒤엔 계산 화면을 띄운다 (그때는 일시불 비교·시흥몰 가격 버튼 없이) */
  var started = false, catMap = {};
  function go() { if (started) return; started = true; startCalc(); }
  function useCatalog(G) {
    CFG.imgBase = G.img || '';
    catMap = (G && G.m) || {};
    var c = catInfo(model);
    if (c) {
      goods = c[0] ? c : null;
      pname = cleanName(c[1]);
      img = imgOf(c);
      imgRep = /^[sgc]$/.test(c[4] || '');   // 같은 세부유형·품목의 다른 모델 사진
      renderHead();
    }
  }
  var api = CFG.goodsApi;
  if (window.SUB_CATALOG && window.SUB_CATALOG.m) { useCatalog(window.SUB_CATALOG); go(); }   // 배포본 — 기다릴 것 없이 바로
  else if (api && api.url && window.fetch) {
    setTimeout(go, 1500);
    // 구독센터 카탈로그(fn_sub_catalog)를 쓴다 — 연결표와 같은 모양 + 고도몰에 없는 모델의 상품명까지 (상품번호 0 = 고도몰 미등록)
    var url = CFG.catalogApi && CFG.catalogApi.url ? CFG.catalogApi.url : api.url.replace(/fn_sub_goods_map$/, 'fn_sub_catalog');
    fetch(url, { method: 'POST', headers: { apikey: api.key, 'Content-Type': 'application/json' }, body: '{}' })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (G) { useCatalog(G); go(); })
      .catch(function (e) { if (window.console) console.warn('[구독상품] 상품 연결표를 못 읽음', e); go(); });
  } else go();
})();
