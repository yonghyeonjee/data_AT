/* ===== 구독 상품 페이지 | service/sub_view.html 에서 SUB_VIEW_CONFIG 설정 후 로드 =====
   주소: /main/html.php?htmid=service/sub_view.html&model=RM80F91H1X
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
  function findUrl(q) { return (CFG.findUrl || '/main/html.php?htmid=service/sub_find.html') + (q ? '&' + q : ''); }
  function viewUrl(model) { return (CFG.viewUrl || '/main/html.php?htmid=service/sub_view.html&model=') + encodeURIComponent(model); }
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
  var goods = null, seg = '';

  /* ---------- 머리 ---------- */
  function headHtml() {
    var title = goods && goods[1] ? goods[1] : '삼성 ' + catName + (seg ? ' ' + segLabel(seg) : '') + ' ' + model;
    var img = goods && goods[2] ? (/^https?:/.test(goods[2]) ? goods[2] : (CFG.imgBase || '') + goods[2]) : '';
    return '<nav class="sv-crumb"><a href="' + esc(findUrl('')) + '">구독상품 찾기</a> › <a href="' + esc(findUrl('cat=' + cat)) + '">' + esc(catName) + '</a>' +
      (seg ? ' › <a href="' + esc(findUrl('cat=' + cat + '&seg=' + encodeURIComponent(seg))) + '">' + esc(segLabel(seg)) + '</a>' : '') + '</nav>' +
      '<div class="sv-head">' +
      '<div class="sv-img">' + (img ? '<img src="' + esc(img) + '" alt="' + esc(title) + '">' : '<span class="sv-icon">' + (CAT_ICON[cat] || '📦') + '</span>') + '</div>' +
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
    var title = (goods && goods[1]) || ('삼성 ' + catName + ' ' + model);
    document.title = title + ' 구독 · 월 ' + fmt(entry[1]) + '원~ | 삼성스토어 시흥';
    var md = document.querySelector('meta[name="description"]');
    if (md) md.setAttribute('content', title + ' (' + model + ') 삼성 AI 구독 월 ' + fmt(entry[1]) + '원부터. 약정·케어·제휴카드별 월 구독료를 바로 확인하고 구독 상담을 신청하세요.');
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
  }

  /* ---------- 골격 ---------- */
  root.innerHTML =
    '<div data-slot="head"></div>' +
    '<section class="sv-calc"><h2 class="sv-h2">구독 요금 계산</h2><div id="subTabRoot" hidden></div>' +
    '<p class="sv-loading" data-slot="loading">요금 정보를 불러오는 중…</p></section>' +
    '<section data-slot="more"></section>';
  renderHead();
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
    fetch(api.url, { method: 'POST', headers: { apikey: api.key, 'Content-Type': 'application/json' }, body: '{}' })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (G) {
        CFG.imgBase = G.img || '';
        var m = (G && G.m) || {};
        for (var k in m) if (m.hasOwnProperty(k) && norm(k) === model) { goods = m[k]; break; }
        if (goods) renderHead();
        go();
      })
      .catch(function (e) { if (window.console) console.warn('[구독상품] 상품 연결표를 못 읽음', e); go(); });
  } else go();
})();
