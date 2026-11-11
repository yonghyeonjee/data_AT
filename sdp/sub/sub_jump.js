/* 구독센터 홈 바로가기 (2026-11-11)
   홈은 구역이 13개라 길다 — 구역 사이를 바로 옮겨 다니게 한다. sub_shop.js 가 홈에서만 불러온다 (CFG.jump === false 면 안 씀).
   - 넓은 PC(본문 오른쪽에 자리가 있을 때): 오른쪽에 떠 있는 '바로가기' 목록 · 지금 보는 구역 표시 · 맨 위로
   - 좁은 PC·태블릿: 오른쪽 아래 '목차' 동그란 버튼 → 목록 창
   - 휴대폰(760px 이하): 화면 맨 아래 메뉴 바(혜택 · 가격대 · 품목 · 계산기 · 전체) · '전체'는 아래에서 올라오는 목록 창
     문의 바(#ssBubble)는 메뉴 바 위로 올린다
   구역은 section.ss-sec 의 h2 로 찾는다 — 고도몰에 올린 html 순서가 바뀌어도 그대로 따라간다 */
(function () {
  if (window.SUB_JUMP_READY) return;
  window.SUB_JUMP_READY = true;
  var CFG = window.SUB_SHOP_CONFIG || {};
  var MOBILE = 760;

  // h2 글자 → 짧은 이름 (위에서부터 처음 맞는 것)
  var NAMES = [
    [/이달의 혜택/, '이달의 혜택', 'gift'], [/인기 제품/, '인기 제품', 'fire'], [/가격대/, '가격대별 보기', 'won'],
    [/나에게 맞는/, '나에게 맞는 구독', 'quiz'], [/품목별 삼성 구독 가격/, '품목별 가격', 'grid'], [/AI 콤보/, 'AI 콤보', 'wash'],
    [/다품목/, '다품목 계산기', 'calc'], [/대표 구독 모델/, '대표 모델', 'star'], [/생활 유형/, '추천 묶음', 'home'],
    [/제휴카드/, '카드 혜택', 'card'], [/진행/, '구독 진행 절차', 'step'], [/센터 안내/, '매장 안내', 'pin'], [/자주 묻는/, '자주 묻는 질문', 'faq']
  ];
  var ICON = {
    gift: '<path d="M4 11h16v9H4zM3 7h18v4H3zM12 7v13M12 7c-1.5-3-5-3-5-.5S12 7 12 7zm0 0c1.5-3 5-3 5-.5S12 7 12 7z"/>',
    fire: '<path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-3 2-4 2-6 2 1 2 3 2 3s1-3 1-7z"/>',
    won: '<path d="M4 7l3 10 3-10 2 7 2-7 3 10 3-10M3 11h18"/>',
    quiz: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .8-1 1.5V14M12 17h.01"/>',
    grid: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
    wash: '<rect x="5" y="3" width="14" height="18" rx="2"/><circle cx="12" cy="13" r="4"/><path d="M8 6h.01M11 6h.01"/>',
    calc: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 7h8M8 11h2M14 11h2M8 15h2M14 15h2M8 18h2M14 18h2"/>',
    star: '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/>',
    home: '<path d="M4 11l8-7 8 7v9H4zM10 20v-5h4v5"/>',
    card: '<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M3 10h18M7 15h4"/>',
    step: '<path d="M5 6h14M5 12h14M5 18h9"/><circle cx="19" cy="18" r="1.5"/>',
    pin: '<path d="M12 21s-6-5.5-6-11a6 6 0 0 1 12 0c0 5.5-6 11-6 11z"/><circle cx="12" cy="10" r="2"/>',
    faq: '<path d="M4 5h16v11H9l-5 4z"/><path d="M9.5 9a2.5 2.5 0 1 1 3 2.4c-.6.2-.5.6-.5 1.1M12 14h.01"/>',
    list: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>',
    up: '<path d="M6 14l6-6 6 6"/>', x: '<path d="M6 6l12 12M18 6L6 18"/>'
  };
  function svg(k) { return '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">' + (ICON[k] || ICON.list) + '</svg>'; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function track(name, extra) { var ev = { event: name, ss_page: 'home' }; for (var k in extra) ev[k] = extra[k]; if (window.dataLayer) window.dataLayer.push(ev); }

  var CSS = '' +
    '.sj-rail,.sj-fab,.sj-pop,.sj-bar,.sj-sheet,.sj-dim{--sj-blue:#1d6fe8;--sj-ink:#111;--sj-sub:#6b7280;--sj-line:#e3e6eb;font-family:"Pretendard","Noto Sans KR",sans-serif;box-sizing:border-box;-webkit-font-smoothing:antialiased}' +
    '.sj-rail *,.sj-fab *,.sj-pop *,.sj-bar *,.sj-sheet *{box-sizing:border-box}' +
    '.sj-rail svg,.sj-fab svg,.sj-pop svg,.sj-bar svg,.sj-sheet svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round;flex:0 0 auto}' +
    /* PC 오른쪽 바로가기 */
    '.sj-rail{position:fixed;z-index:880;width:176px;padding:14px 10px 10px;border-radius:18px;background:rgba(255,255,255,.96);border:1px solid var(--sj-line);box-shadow:0 10px 30px rgba(17,24,39,.08);opacity:0;transform:translateX(8px);pointer-events:none;transition:opacity .25s,transform .25s;backdrop-filter:saturate(1.4) blur(6px)}' +
    '.sj-rail.is-on{opacity:1;transform:none;pointer-events:auto}' +
    '.sj-rail h4{margin:0 6px 8px;font-size:11.5px;font-weight:800;letter-spacing:.08em;color:var(--sj-sub)}' +
    '.sj-rail ol{list-style:none;margin:0;padding:0;position:relative;overflow:auto;max-height:inherit}' +
    '.sj-rail li{margin:0}' +
    '.sj-rail a{display:flex;align-items:center;gap:8px;padding:6px 8px;border-radius:10px;color:#4b5563;font-size:13px;font-weight:600;line-height:1.35;text-decoration:none;word-break:keep-all;transition:background .15s,color .15s}' +
    '.sj-rail a i{width:6px;height:6px;border-radius:50%;background:#cbd2db;flex:0 0 auto;transition:all .2s}' +
    '.sj-rail a:hover{background:#f3f6fb;color:var(--sj-ink)}' +
    '.sj-rail a.is-cur{background:#eef4ff;color:var(--sj-blue);font-weight:800}' +
    '.sj-rail a.is-cur i{background:var(--sj-blue);box-shadow:0 0 0 3px rgba(29,111,232,.18)}' +
    '.sj-rail .sj-top{display:flex;align-items:center;justify-content:center;gap:4px;width:100%;margin-top:8px;padding:8px 0 2px;border:0;border-top:1px solid var(--sj-line);background:none;color:var(--sj-sub);font:700 12px/1 inherit;cursor:pointer}' +
    '.sj-rail .sj-top:hover{color:var(--sj-blue)}' +
    '.sj-rail .sj-top svg{width:14px;height:14px}' +
    '.sj-prog{height:3px;margin:0 6px 10px;border-radius:3px;background:#edf0f4;overflow:hidden}.sj-prog b{display:block;height:100%;width:0;background:var(--sj-blue);border-radius:3px;transition:width .15s}' +
    /* 좁은 PC·태블릿: 동그란 목차 버튼 + 목록 창 */
    '.sj-fab{position:fixed;right:16px;z-index:890;display:flex;align-items:center;gap:6px;height:44px;padding:0 16px 0 14px;border:0;border-radius:22px;background:#111;color:#fff;font:800 13px/1 inherit;box-shadow:0 8px 24px rgba(17,24,39,.25);cursor:pointer;opacity:0;transform:translateY(8px);pointer-events:none;transition:opacity .25s,transform .25s,bottom .2s}' +
    '.sj-fab.is-on{opacity:1;transform:none;pointer-events:auto}' +
    '.sj-pop{position:fixed;right:16px;z-index:895;width:260px;max-height:70vh;overflow:auto;padding:10px;border-radius:16px;background:#fff;border:1px solid var(--sj-line);box-shadow:0 16px 40px rgba(17,24,39,.18);display:none}' +
    '.sj-pop.is-open{display:block}' +
    /* 휴대폰 아래 메뉴 바 */
    '.sj-bar{position:fixed;left:0;right:0;bottom:0;z-index:905;display:flex;height:calc(58px + env(safe-area-inset-bottom));padding:0 4px env(safe-area-inset-bottom);background:rgba(255,255,255,.97);border-top:1px solid var(--sj-line);box-shadow:0 -4px 16px rgba(17,24,39,.06);backdrop-filter:saturate(1.4) blur(8px);transition:transform .25s}' +
    '.sj-bar.is-hide{transform:translateY(100%)}' +
    '.sj-bar a,.sj-bar button{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;min-width:0;padding:0;border:0;background:none;color:#6b7280;font:700 11px/1.1 inherit;text-decoration:none;letter-spacing:-.02em;cursor:pointer;-webkit-tap-highlight-color:transparent}' +
    '.sj-bar svg{width:22px;height:22px}' +
    '.sj-bar .is-cur{color:var(--sj-blue)}' +
    '.sj-bar .is-cur svg{stroke-width:2.2}' +
    'body.sj-has-bar #ssBubble{bottom:calc(66px + env(safe-area-inset-bottom))!important;transition:bottom .2s,opacity .3s,transform .3s}' +
    'body.sj-has-bar #ssBubble.is-fold{opacity:0!important;visibility:hidden;pointer-events:none}' +
    'body.sj-has-bar #ssBubbleSpace{margin-bottom:calc(58px + env(safe-area-inset-bottom))}' +
    /* 목록 창 (휴대폰: 아래에서 올라옴) */
    '.sj-dim{position:fixed;inset:0;z-index:910;background:rgba(17,24,39,.42);opacity:0;pointer-events:none;transition:opacity .2s}' +
    '.sj-dim.is-open{opacity:1;pointer-events:auto}' +
    '.sj-sheet{position:fixed;left:0;right:0;bottom:0;z-index:915;max-height:82vh;overflow:auto;padding:8px 16px calc(16px + env(safe-area-inset-bottom));border-radius:20px 20px 0 0;background:#fff;transform:translateY(100%);transition:transform .28s cubic-bezier(.2,.8,.2,1)}' +
    '.sj-sheet.is-open{transform:none}' +
    '.sj-grab{width:40px;height:4px;margin:4px auto 12px;border-radius:4px;background:#d6dbe2}' +
    '.sj-head{display:flex;align-items:center;justify-content:space-between;margin:0 0 12px}' +
    '.sj-head b{font-size:17px;font-weight:800;color:var(--sj-ink)}' +
    '.sj-head button{width:36px;height:36px;border:0;border-radius:50%;background:#f3f4f6;color:#374151;display:flex;align-items:center;justify-content:center;cursor:pointer}' +
    '.sj-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin:0;padding:0;list-style:none}' +
    '.sj-grid a{display:flex;align-items:center;gap:10px;min-height:52px;padding:10px 12px;border:1px solid var(--sj-line);border-radius:14px;color:#1f2937;font-size:14px;font-weight:700;line-height:1.3;text-decoration:none;word-break:keep-all;background:#fff}' +
    '.sj-grid a span{display:flex;align-items:center;justify-content:center;width:30px;height:30px;border-radius:9px;background:#f1f5fb;color:var(--sj-blue);flex:0 0 auto}' +
    '.sj-grid a.is-cur{border-color:var(--sj-blue);background:#eef4ff;color:var(--sj-blue)}' +
    '.sj-pop .sj-grid{grid-template-columns:1fr;gap:4px}.sj-pop .sj-grid a{min-height:40px;padding:6px 8px;border:0;font-size:13.5px}.sj-pop .sj-grid a:hover{background:#f3f6fb}.sj-pop .sj-grid a span{width:26px;height:26px}' +
    '.sj-cta{display:flex;gap:8px;margin-top:14px}' +
    '.sj-cta a{flex:1;display:flex;align-items:center;justify-content:center;min-height:48px;border-radius:12px;font-size:15px;font-weight:800;text-decoration:none}' +
    '.sj-cta .is-main{background:var(--sj-blue);color:#fff}.sj-cta .is-line{border:1px solid #cfdcf5;color:var(--sj-blue)}' +
    '@media print{.sj-rail,.sj-fab,.sj-pop,.sj-bar,.sj-sheet,.sj-dim{display:none!important}}';

  function init() {
    var secs = [].slice.call(document.querySelectorAll('section.ss-sec')).filter(function (s) { return s.querySelector('h2') && s.offsetHeight > 0; });
    if (secs.length < 4) return;
    var items = secs.map(function (s, i) {
      var h = s.querySelector('h2'), t = (h.firstChild && h.firstChild.nodeType === 3 ? h.firstChild.nodeValue : h.textContent).replace(/\s+/g, ' ').trim();
      var name = t, ic = 'list';
      for (var k = 0; k < NAMES.length; k++) if (NAMES[k][0].test(t)) { name = NAMES[k][1]; ic = NAMES[k][2]; break; }
      if (!s.id) s.id = 'ss-sec-' + (i + 1);
      return { el: s, id: s.id, name: name, ic: ic };
    });
    var st = document.createElement('style'); st.id = 'sjCss'; st.textContent = CSS; document.head.appendChild(st);

    var nav = document.querySelector('[data-ss="nav"]'), first = items[0].el;
    function navH() { if (!nav) return 0; var r = nav.getBoundingClientRect(); return r.top <= 1 ? r.bottom : 0; }
    function go(id, how) {
      var it = null; items.forEach(function (x) { if (x.id === id) it = x; }); if (!it) return;
      var y = it.el.getBoundingClientRect().top + window.pageYOffset - (nav ? nav.offsetHeight : 0) - 12;
      window.scrollTo({ top: Math.max(0, y), behavior: 'smooth' });
      track('ss_jump_click', { ss_jump: it.name, ss_jump_ui: how });
    }
    function link(it, cls) { return '<a href="#' + esc(it.id) + '" data-sj="' + esc(it.id) + '"' + (cls ? ' class="' + cls + '"' : '') + '>'; }

    // 상담 신청 · 전화 (메뉴에 있는 주소를 그대로 쓴다)
    var consult = document.querySelector('[data-ss="nav"] a[href*="SamSungSubscription"], [data-ss="cta"] a[data-cta="consult"]');
    var tel = document.querySelector('[data-ss="cta"] a[href^="tel:"], #ssBubble a[href^="tel:"]');
    var bundle = document.querySelector('a[href*="bundle.html"]');

    /* --- PC 오른쪽 바로가기 --- */
    var rail = document.createElement('nav'); rail.className = 'sj-rail'; rail.setAttribute('aria-label', '구독센터 바로가기');
    rail.innerHTML = '<h4>바로가기</h4><div class="sj-prog"><b></b></div><ol>' + items.map(function (it) { return '<li>' + link(it) + '<i></i>' + esc(it.name) + '</a></li>'; }).join('') + '</ol>' +
      '<button type="button" class="sj-top">' + svg('up') + '맨 위로</button>';
    document.body.appendChild(rail);

    /* --- 좁은 PC·태블릿: 목차 버튼 --- */
    var fab = document.createElement('button'); fab.type = 'button'; fab.className = 'sj-fab'; fab.setAttribute('aria-expanded', 'false'); fab.innerHTML = svg('list') + '목차';
    var pop = document.createElement('div'); pop.className = 'sj-pop'; pop.setAttribute('role', 'dialog'); pop.setAttribute('aria-label', '구독센터 목차');
    pop.innerHTML = '<ul class="sj-grid">' + items.map(function (it) { return '<li>' + link(it) + '<span>' + svg(it.ic) + '</span>' + esc(it.name) + '</a></li>'; }).join('') + '</ul>';
    document.body.appendChild(fab); document.body.appendChild(pop);

    /* --- 휴대폰: 아래 메뉴 바 + 전체 목록 창 --- */
    function pick(re) { for (var i = 0; i < items.length; i++) if (re.test(items[i].name)) return items[i]; return null; }
    var tabs = [pick(/혜택/), pick(/가격대/), pick(/품목별/), pick(/다품목/)].filter(Boolean);
    var bar = document.createElement('nav'); bar.className = 'sj-bar'; bar.setAttribute('aria-label', '구독센터 메뉴');
    var SHORT = { '이달의 혜택': '혜택', '가격대별 보기': '가격대', '품목별 가격': '품목별', '다품목 계산기': '계산기' };
    bar.innerHTML = tabs.map(function (it) { return link(it) + svg(it.ic) + esc(SHORT[it.name] || it.name) + '</a>'; }).join('') +
      (consult ? '<a href="' + esc(consult.getAttribute('href')) + '" data-sj-cta="consult">' + svg('faq') + '상담</a>' : '') +
      '<button type="button" class="sj-all" aria-expanded="false">' + svg('list') + '전체</button>';
    var dim = document.createElement('div'); dim.className = 'sj-dim';
    var sheet = document.createElement('div'); sheet.className = 'sj-sheet'; sheet.setAttribute('role', 'dialog'); sheet.setAttribute('aria-label', '구독센터 전체 메뉴');
    sheet.innerHTML = '<div class="sj-grab"></div><div class="sj-head"><b>어디로 갈까요?</b><button type="button" class="sj-close" aria-label="닫기">' + svg('x') + '</button></div>' +
      '<ul class="sj-grid">' + items.map(function (it) { return '<li>' + link(it) + '<span>' + svg(it.ic) + '</span>' + esc(it.name) + '</a></li>'; }).join('') + '</ul>' +
      '<div class="sj-cta">' + (tel ? '<a class="is-line" href="' + esc(tel.getAttribute('href')) + '" data-sj-cta="tel">전화 상담</a>' : '') +
      (consult ? '<a class="is-main" href="' + esc(consult.getAttribute('href')) + '" data-sj-cta="consult">구독 상담 신청</a>' : '') + '</div>';
    document.body.appendChild(dim); document.body.appendChild(sheet); document.body.appendChild(bar);

    function openSheet(on) {
      sheet.classList.toggle('is-open', on); dim.classList.toggle('is-open', on);
      bar.querySelector('.sj-all').setAttribute('aria-expanded', on ? 'true' : 'false');
      if (on) track('ss_jump_open', { ss_jump_ui: 'sheet' });
    }
    function openPop(on) {
      pop.classList.toggle('is-open', on); fab.setAttribute('aria-expanded', on ? 'true' : 'false');
      if (on) track('ss_jump_open', { ss_jump_ui: 'pop' });
    }
    document.addEventListener('click', function (ev) {
      var a = ev.target.closest ? ev.target.closest('[data-sj], .sj-top, .sj-all, .sj-close, .sj-fab, .sj-dim, [data-sj-cta]') : null;
      if (!a) { if (pop.classList.contains('is-open')) openPop(false); return; }
      if (a.hasAttribute('data-sj')) {
        ev.preventDefault();
        var how = rail.contains(a) ? 'rail' : bar.contains(a) ? 'bar' : sheet.contains(a) ? 'sheet' : 'pop';
        openSheet(false); openPop(false); go(a.getAttribute('data-sj'), how);
      }
      else if (a.hasAttribute('data-sj-cta')) track('ss_jump_cta', { ss_cta: a.getAttribute('data-sj-cta') });
      else if (a.classList.contains('sj-top')) { window.scrollTo({ top: 0, behavior: 'smooth' }); track('ss_jump_top'); }
      else if (a.classList.contains('sj-all')) openSheet(!sheet.classList.contains('is-open'));
      else if (a.classList.contains('sj-close') || a === dim) openSheet(false);
      else if (a === fab) openPop(!pop.classList.contains('is-open'));
    });
    document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape') { openSheet(false); openPop(false); } });

    /* --- 자리 맞추기 · 지금 보는 구역 --- */
    var mode = '', cur = '';
    function bubbleTop() { var b = document.getElementById('ssBubble'); if (!b || !b.classList.contains('is-on')) return window.innerHeight; var r = b.getBoundingClientRect(); return r.height ? r.top : window.innerHeight; }
    function layout() {
      var w = window.innerWidth, box = first.getBoundingClientRect(), room = w - box.right;
      mode = w <= MOBILE ? 'bar' : room >= 176 + 40 ? 'rail' : 'fab';
      document.body.classList.toggle('sj-has-bar', mode === 'bar');
      bar.style.display = mode === 'bar' ? '' : 'none';
      if (mode !== 'bar') openSheet(false);
      if (mode !== 'fab') openPop(false);
      if (mode === 'rail') {
        var top = Math.max(navH(), nav ? Math.min(nav.offsetHeight, 140) : 0) + 20, bottom = bubbleTop() - 16;
        rail.style.left = Math.round(box.right + Math.min(40, (room - 176) / 2)) + 'px';
        rail.style.top = top + 'px';
        rail.querySelector('ol').style.maxHeight = Math.max(160, bottom - top - 90) + 'px';
      }
      if (mode === 'fab') { var fb = window.innerHeight - bubbleTop() + 16; fab.style.bottom = fb + 'px'; pop.style.bottom = (fb + 54) + 'px'; }
      onScroll();
    }
    function onScroll() {
      var y = window.pageYOffset, shown = first.getBoundingClientRect().top < window.innerHeight * 0.6;
      rail.classList.toggle('is-on', mode === 'rail' && shown);
      fab.classList.toggle('is-on', mode === 'fab' && shown);
      var line = (nav ? nav.offsetHeight : 0) + window.innerHeight * 0.3, now = '';
      items.forEach(function (it) { if (it.el.getBoundingClientRect().top <= line) now = it.id; });
      if (window.innerHeight + y >= document.documentElement.scrollHeight - 4) now = items[items.length - 1].id;
      if (now !== cur) {
        cur = now;
        [].forEach.call(document.querySelectorAll('[data-sj]'), function (a) { a.classList.toggle('is-cur', a.getAttribute('data-sj') === cur); });
      }
      var max = document.documentElement.scrollHeight - window.innerHeight;
      rail.querySelector('.sj-prog b').style.width = (max > 0 ? Math.min(100, y / max * 100) : 0) + '%';
    }
    var tick = false;
    window.addEventListener('scroll', function () { if (tick) return; tick = true; setTimeout(function () { tick = false; onScroll(); }, 60); }, { passive: true });
    window.addEventListener('resize', layout);
    // 문의 바는 1.5초 뒤에 뜨고 접었다 폈다 한다 — 높이가 바뀌면 다시 맞춘다
    var bb = document.getElementById('ssBubble');
    if (window.MutationObserver) new MutationObserver(layout).observe(document.body, { childList: true });
    if (bb && window.MutationObserver) new MutationObserver(layout).observe(bb, { attributes: true, attributeFilter: ['class'] });
    setTimeout(layout, 1700);
    layout();
    track('ss_jump_ready', { ss_jump_n: items.length });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
