/* ===== 구독상품 찾기 | subscribe/sub_find.html 에서 SUB_FIND_CONFIG 설정 후 로드 =====
   동작 순서
   1) SUB_INDEX(모델→[카테고리, 최저 월구독료, 자동납부 최저 총액]) 로 목록을 만든다
   2) 카테고리를 고르거나 검색어를 넣으면 그때 sub_plans_<키>.js 를 받아 세부유형(양문형·로봇청소기 등)까지 찾는다
   3) 고도몰에 등록된 모델(데이터센터 fn_sub_goods_map, 없으면 sub_goods.js)은 상품상세 구독탭으로(?buy=sub),
      등록 안 된 모델은 구독 상담 신청서로(모델·요금 자동 채움) 보낸다
   4) 검색 조건은 주소에 남는다 → 랜딩 주소로 그대로 사용
        /service/sub_find.php?cat=ref          냉장고만
        /service/sub_find.php?q=양문형          검색어
        /service/sub_find.php?cat=aircon&max=50000&sort=low
   ※ 요금 데이터는 sub_tab.js 와 같은 파일을 쓴다 — sub_find.html 이 goods_view.html 과 같은 순서로
     데이터센터(dcBase, version.js) → 예비 사본(dataBase) 에서 sub_index.js 를 읽고, 고른 위치를 CFG.dataBase 에 남긴다
===== */
window.SUB_FIND_READY = true;   // sub_find.html 이 데이터센터에서 이 파일을 받았는지 확인하는 표시 (못 받았으면 예비 사본으로)
(function () {
  'use strict';
  var CFG = window.SUB_FIND_CONFIG || {};
  var IDX = window.SUB_INDEX;
  var root = document.getElementById('subFindRoot');
  if (!root) return;
  if (!IDX || !IDX.m) { root.innerHTML = '<p class="sf-empty">구독 요금 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.</p>'; return; }

  var CAT_ICON = { ref: '🧊', kimchi: '🥬', water: '💧', tv: '📺', monitor: '🖥️', audio: '🔊', laundry: '👕', cleaner: '🧹',
    aircon: '❄️', sysaircon: '🌬️', cooking: '🍳', airpurifier: '🍃', dehumid: '💨', tab: '📱', book: '💻' };
  // 고객이 칠 법한 말 → 카테고리 (검색어가 이 말이면 해당 카테고리 전체가 걸린다)
  var CAT_ALIAS = {
    ref: ['냉장고', '양문형', '4도어', '비스포크냉장고', '냉동고'],
    kimchi: ['김치냉장고', '김치', '김냉'],
    water: ['정수기', '냉온정수기', '얼음정수기'],
    tv: ['tv', '티비', '텔레비전', 'oled', 'qled', '네오qled', '더프레임', '무빙스타일'],
    monitor: ['모니터', '스마트모니터', '오디세이', '게이밍모니터'],
    audio: ['오디오', '사운드바', '스피커', '뮤직프레임'],
    laundry: ['의류케어', '세탁기', '건조기', '세탁건조기', '콤보', '워시콤보', '에어드레서', '의류관리기'],
    cleaner: ['청소기', '로봇청소기', '무선청소기', '제트', '스팀'],
    aircon: ['에어컨', '무풍', '스탠드에어컨', '벽걸이', '홈멀티', '2in1'],
    sysaircon: ['시스템에어컨', '천장형', '천장형에어컨'],
    cooking: ['조리기기', '인덕션', '전기레인지', '식기세척기', '식세기', '오븐', '후드'],
    airpurifier: ['공기청정기', '청정기', '블루스카이', '인피니티'],
    dehumid: ['제습기'],
    tab: ['갤럭시탭', '태블릿', '탭', '갤탭'],
    book: ['갤럭시북', '노트북', '갤북', '랩탑']
  };
  // 줄임말 → 데이터에 쓰인 말 (세부유형으로 바로 찾게)
  var TERM_SYNONYM = { '식세기': '식기세척기', '김냉': '김치냉장고', '티비': 'TV', '텔레비전': 'TV', '청정기': '공기청정기',
    '드레서': '에어드레서', '콤보': '세탁건조기', '로청': '로봇' };
  // 요금 데이터의 세부유형 이름에 그 말이 없는 경우 (예: 식기세척기 = "8-14인용…", "카운터탑" / 에어드레서 = "3벌식", "5벌식")
  // 검색어(줄임말 풀이 후) → 세부유형 패턴. 이 패턴이 있으면 품목 전체가 아니라 해당 세부유형만 찾는다
  var TERM_SEG = {
    '식기세척기': ['cooking', /인용|카운터탑/], '에어드레서': ['laundry', /벌식/], '의류관리기': ['laundry', /벌식/],
    '인덕션': ['cooking', /전기레인지|인덕션/], '전기레인지': ['cooking', /전기레인지|인덕션/], '후드': ['cooking', /후드/],
    '세탁기': ['laundry', /세탁|드럼|전자동/], '건조기': ['laundry', /건조/]
  };
  var BANDS = [
    { k: '', label: '전체 금액' },
    { k: '30000', label: '월 3만원 이하', max: 30000 },
    { k: '50000', label: '월 5만원 이하', max: 50000 },
    { k: '100000', label: '월 10만원 이하', max: 100000 },
    { k: 'over', label: '월 10만원 초과', min: 100001 }
  ];
  var SORTS = [['low', '월 구독료 낮은순'], ['high', '월 구독료 높은순'], ['model', '모델명순']];
  var PAGE = CFG.pageSize || 24;

  var state = { q: '', cat: '', seg: '', band: '', sort: 'low', shown: PAGE, group: true };   // group: 색상만 다른 모델은 하나로 (2026-10-30)
  var rows = [];       // { model, cat, min, minNet, seg, name, goodsNo, hay }
  var byModel = {};
  var GOODS = {};      // 모델 → [상품번호, 상품명]
  var els = {};

  function fmt(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function norm(s) { return String(s || '').replace(/\s+/g, '').toUpperCase(); }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function track(name, extra) {
    var ev = { event: name, sf_q: state.q, sf_cat: state.cat };
    for (var k in extra) ev[k] = extra[k];
    if (window.dataLayer) window.dataLayer.push(ev);
  }
  function loadScript(src, ok, fail) {
    var s = document.createElement('script');
    s.src = src;
    s.onload = ok;
    s.onerror = fail || ok;
    document.head.appendChild(s);
  }

  /* ---------- URL ↔ 상태 ---------- */
  function readUrl() {
    var qs = location.search.replace(/^\?/, '').split('&');
    for (var i = 0; i < qs.length; i++) {
      var kv = qs[i].split('='), k = kv[0], v = '';
      try { v = decodeURIComponent((kv[1] || '').replace(/\+/g, ' ')); } catch (e) { v = kv[1] || ''; }
      if (k === 'q') state.q = v;
      else if (k === 'cat' && IDX.cats[v]) state.cat = v;
      else if (k === 'seg') state.seg = v;
      else if (k === 'max' || k === 'band') state.band = v;
      else if (k === 'sort' && /^(low|high|model)$/.test(v)) state.sort = v;
      else if (k === 'all' && v === '1') state.group = false;
    }
    if (!BANDS.some(function (b) { return b.k === state.band; })) state.band = '';
  }
  function writeUrl() {
    if (!window.history || !history.replaceState) return;
    var p = [];
    if (state.q) p.push('q=' + encodeURIComponent(state.q));
    if (state.cat) p.push('cat=' + state.cat);
    if (state.seg) p.push('seg=' + encodeURIComponent(state.seg));
    if (state.band) p.push('max=' + state.band);
    if (state.sort !== 'low') p.push('sort=' + state.sort);
    if (!state.group) p.push('all=1');
    // 고도몰 추가 페이지는 /main/html.php?htmid=… 로 열린다 → htmid 는 남겨 둔다
    var htmid = location.search.match(/[?&](htmid=[^&]*)/);
    if (htmid) p.unshift(htmid[1]);
    history.replaceState(null, '', location.pathname + (p.length ? '?' + p.join('&') : ''));
  }

  /* ---------- 데이터 ---------- */
  function buildRows() {
    var cats = IDX.cats;
    for (var m in IDX.m) {
      if (!IDX.m.hasOwnProperty(m)) continue;
      var e = IDX.m[m];
      if (!e || !(e[1] > 0) || !cats[e[0]]) continue;
      var g = GOODS[norm(m)];
      var r = { model: m, cat: e[0], min: e[1], minNet: e[2] || 0, seg: '', name: g ? g[1] || '' : '', goodsNo: g && g[0] ? String(g[0]) : '',
        img: g && g[2] ? (/^https?:/.test(g[2]) ? g[2] : IMG_BASE + g[2]) : '', imgRep: !!(g && /^[sgc]$/.test(g[4] || '')) };
      rows.push(r); byModel[m] = r;
    }
    rows.forEach(setHay);
  }
  function setHay(r) {
    // core: 모델·세부유형(원래 이름 + 고객용 이름)·품목명 (요금 데이터 기준) / hay: + 고도몰 상품명
    r.segLabel = segLabel(r.seg);
    r.size = segSize(r.seg);
    r.core = norm(r.model + ' ' + r.seg + ' ' + r.segLabel + ' ' + IDX.cats[r.cat]);
    r.hay = norm(r.core + ' ' + r.name);
  }
  /* DPS 세부유형은 내부 구분 코드라 고객에게 그대로 보이면 어색하다 → 화면용 이름으로 바꾼다
     (필터 값은 원래 이름 그대로 — 바꾸는 건 보이는 글자뿐. 모르는 형식은 밑줄만 공백으로) */
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
    var s = String(seg || '');
    for (var i = 0; i < SEG_LABEL_RULES.length; i++) s = s.replace(SEG_LABEL_RULES[i][0], SEG_LABEL_RULES[i][1]);
    return s.replace(/\s+/g, ' ').replace(/^\s|\s$/g, '');
  }
  // 세부유형 안의 화면 크기 범위 (TV·모니터) → [최소, 최대] 인치. "65인치"·"75형" 검색에 쓴다
  function segSize(seg) {
    var s = String(seg || ''), m;
    if ((m = s.match(/(\d{2,3})-(\d{2,3})/))) return [+m[1], +m[2]];
    if ((m = s.match(/(?:^|_)-(\d{2,3})/))) return [0, +m[1]];
    if ((m = s.match(/(\d{2,3})이하/))) return [0, +m[1]];
    if ((m = s.match(/(\d{2,3})이상/))) return [+m[1], 999];
    return null;
  }
  var planState = {};  // 카테고리 → 'loading' | 'done'
  var planWait = {};
  function loadPlans(cat, cb) {
    if (planState[cat] === 'done') return cb();
    (planWait[cat] = planWait[cat] || []).push(cb);
    if (planState[cat] === 'loading') return;
    planState[cat] = 'loading';
    loadScript((CFG.dataBase || '/data/js/sub/') + 'sub_plans_' + cat + '.js?v=' + encodeURIComponent(CFG.ver || IDX.ver), function () {
      var P = (window.SUB_PLANS || {})[cat] || {};
      rows.forEach(function (r) { if (r.cat === cat && P[r.model]) { r.seg = P[r.model].s || ''; setHay(r); } });
      planState[cat] = 'done';
      var q = planWait[cat]; planWait[cat] = [];
      q.forEach(function (f) { f(); });
    });
  }
  function loadAllPlans(cb) {
    var keys = Object.keys(IDX.cats), left = keys.length;
    keys.forEach(function (k) { loadPlans(k, function () { if (--left === 0) cb(); }); });
  }
  // 지금 조건에 세부유형 정보가 필요하면 받아 온 뒤 다시 그린다
  function ensurePlans() {
    if (state.cat && planState[state.cat] !== 'done') { loadPlans(state.cat, render); return; }
    if (state.q && !state.cat && !isModelQuery(state.q)) {
      var need = Object.keys(IDX.cats).some(function (k) { return planState[k] !== 'done'; });
      if (need) loadAllPlans(render);
    }
  }
  function isModelQuery(q) { return /^[A-Za-z]{2,}[0-9]/.test(String(q).replace(/\s+/g, '')); }

  /* ---------- 필터 ---------- */
  function aliasCats(token) {
    var t = token.toLowerCase(), out = [];
    for (var k in CAT_ALIAS) if (CAT_ALIAS[k].indexOf(t) >= 0 || IDX.cats[k] === token) out.push(k);
    return out;
  }
  // 검색어 하나하나: 모델·세부유형·상품명에 그대로 있으면 그걸로만 찾고("양문형" → 양문형만),
  // 어디에도 없을 때만 카테고리 별칭으로 넓힌다("로봇청소기" → 청소기 전체)
  function tokenRules(tokens) {
    return tokens.map(function (t) {
      var term = TERM_SYNONYM[t] || t;
      var n = norm(term);
      if (TERM_SEG[term]) return { n: n, cats: [], segCat: TERM_SEG[term][0], seg: TERM_SEG[term][1] };
      // "65인치" · "75형" → 그 크기가 들어가는 TV·모니터 세부유형
      var sz = String(t).match(/^(\d{2,3})(인치|형|")$/);
      if (sz) return { n: n, cats: [], size: +sz[1] };
      // 별칭을 끌지 말지는 요금 데이터(모델·세부유형)로만 판단 — 상품명 몇 개에 "노트북"이 있다고 갤럭시 북 전체가 빠지면 안 됨
      var direct = rows.some(function (r) { return r.core.indexOf(n) >= 0; });
      return { n: n, cats: direct ? [] : aliasCats(t) };
    });
  }
  function matchQuery(r, rules) {
    for (var i = 0; i < rules.length; i++) {
      if (r.hay.indexOf(rules[i].n) >= 0) continue;
      if (rules[i].seg && r.cat === rules[i].segCat && rules[i].seg.test(r.seg)) continue;
      if (rules[i].size && r.size && rules[i].size >= r.size[0] && rules[i].size <= r.size[1]) continue;
      if (rules[i].cats.indexOf(r.cat) >= 0) continue;
      return false;
    }
    return true;
  }
  function inBand(r, bandKey) {
    var b = BANDS.filter(function (x) { return x.k === bandKey; })[0];
    if (!b || !bandKey) return true;
    if (b.max && r.min > b.max) return false;
    if (b.min && r.min < b.min) return false;
    return true;
  }
  function filtered(opts) {
    var rules = tokenRules(state.q.split(/\s+/).filter(Boolean));
    return rows.filter(function (r) {
      if (rules.length && !matchQuery(r, rules)) return false;
      if (!opts.ignoreCat && state.cat && r.cat !== state.cat) return false;
      if (!opts.ignoreSeg && state.seg && r.seg !== state.seg) return false;
      return inBand(r, state.band);
    });
  }
  function sorted(list) {
    var f = state.sort === 'high' ? function (a, b) { return b.min - a.min; }
      : state.sort === 'model' ? function (a, b) { return a.model < b.model ? -1 : a.model > b.model ? 1 : 0; }
      : function (a, b) { return a.min - b.min || (a.model < b.model ? -1 : 1); };
    return list.sort(f);
  }

  /* ---------- 렌더 ---------- */
  function build() {
    root.innerHTML =
      '<form class="sf-search" role="search" data-slot="form">' +
      '<input type="search" data-slot="q" placeholder="모델명·제품 검색 (예: 양문형, 식세기)" aria-label="구독 상품 검색" autocomplete="off">' +
      '<button type="submit">검색</button></form>' +
      '<div class="sf-chips sf-cats" data-slot="cats" role="group" aria-label="카테고리"></div>' +
      '<div class="sf-chips sf-segs" data-slot="segs" role="group" aria-label="세부 유형" hidden></div>' +
      '<div class="sf-bar"><div class="sf-chips sf-bands" data-slot="bands" role="group" aria-label="월 구독료"></div>' +
      '<select class="sf-sort" data-slot="sort" aria-label="정렬"></select></div>' +
      '<p class="sf-count" data-slot="count" aria-live="polite"></p>' +
      '<ul class="sf-grid" data-slot="grid"></ul>' +
      '<div class="sf-more-wrap"><button type="button" class="sf-more" data-slot="more" hidden>더 보기</button></div>' +
      '<p class="sf-note">* 월 구독료는 VAT 포함, 최저 요금제 기준입니다. 자동납부 5% 할인·제휴카드·선납 혜택은 상품 페이지 또는 상담에서 확인하세요. 실제 청구 금액과 다를 수 있습니다.</p>';
    ['form', 'q', 'cats', 'segs', 'bands', 'sort', 'count', 'grid', 'more'].forEach(function (k) { els[k] = root.querySelector('[data-slot="' + k + '"]'); });
    els.q.value = state.q;
    els.sort.innerHTML = SORTS.map(function (s) { return '<option value="' + s[0] + '">' + s[1] + '</option>'; }).join('');
    els.sort.value = state.sort;

    els.form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      state.q = els.q.value.replace(/^\s+|\s+$/g, '');
      state.cat = '';   // 검색은 항상 전체에서 — 앞서 고른 품목 안에 갇혀 0건이 되지 않게
      // 검색어가 카테고리 이름 그 자체면 카테고리 칩으로 바꿔 준다 ("냉장고" → 냉장고 탭)
      var ac = aliasCats(state.q);
      if (state.q && ac.length === 1 && state.q.split(/\s+/).length === 1 && (IDX.cats[ac[0]] === state.q || state.q === CAT_ALIAS[ac[0]][0])) {
        state.cat = ac[0]; state.q = ''; els.q.value = '';
      }
      state.seg = ''; state.shown = PAGE;
      track('sub_find_search');
      update();
    });
    els.sort.addEventListener('change', function () { state.sort = els.sort.value; state.shown = PAGE; update(); });
    els.more.addEventListener('click', function () { state.shown += PAGE; render(); });
    root.addEventListener('click', onClick);
    root.addEventListener('change', function (ev) { if (ev.target.hasAttribute && ev.target.hasAttribute('data-group')) { state.group = ev.target.checked; state.shown = PAGE; update(); } });
    document.addEventListener('ss-cart', function () { root.querySelectorAll('.sf-add').forEach(function (b) { var on = cartHas(b.getAttribute('data-add')); b.textContent = on ? '담김 ✓' : '+ 담기'; b.parentNode.classList.toggle('in-cart', on); }); });
  }

  function chip(attr, value, label, on, count) {
    return '<button type="button" class="sf-chip' + (on ? ' is-active' : '') + '" ' + attr + '="' + esc(value) + '" aria-pressed="' + (on ? 'true' : 'false') + '">' +
      label + (count !== undefined ? ' <em>' + count + '</em>' : '') + '</button>';
  }

  function render() {
    // 카테고리 칩: 검색어·금액 조건 안에서의 개수
    var base = filtered({ ignoreCat: true, ignoreSeg: true });
    var cnt = {};
    base.forEach(function (r) { cnt[r.cat] = (cnt[r.cat] || 0) + 1; });
    var h = chip('data-cat', '', '전체', !state.cat, base.length);
    Object.keys(IDX.cats).forEach(function (k) {
      if (!cnt[k] && state.cat !== k) return;
      h += chip('data-cat', k, (CAT_ICON[k] ? CAT_ICON[k] + ' ' : '') + esc(IDX.cats[k]), state.cat === k, cnt[k] || 0);
    });
    els.cats.innerHTML = h;

    // 세부유형 칩 (카테고리 선택 + 요금표 로드 후)
    var segOn = state.cat && planState[state.cat] === 'done';
    els.segs.hidden = !segOn;
    if (segOn) {
      var segCnt = {}, segList = [];
      filtered({ ignoreSeg: true }).forEach(function (r) {
        if (!r.seg) return;
        if (!segCnt[r.seg]) { segCnt[r.seg] = 0; segList.push(r.seg); }
        segCnt[r.seg]++;
      });
      if (state.seg && !segCnt[state.seg]) state.seg = '';
      els.segs.hidden = segList.length < 2;
      els.segs.innerHTML = chip('data-seg', '', '전체 유형', !state.seg) +
        segList.map(function (s) { return chip('data-seg', s, esc(segLabel(s)), state.seg === s, segCnt[s]); }).join('');
    }

    els.bands.innerHTML = BANDS.map(function (b) { return chip('data-band', b.k, b.label, state.band === b.k); }).join('') +
      '<label class="sf-group"><input type="checkbox" data-group' + (state.group ? ' checked' : '') + '> 색상만 다른 모델은 하나로</label>';

    var list = sorted(filtered({}));
    var total = list.length;
    if (state.group) list = sorted(groupColors(list));
    var waiting = (state.cat && planState[state.cat] === 'loading') || (state.q && Object.keys(planState).some(function (k) { return planState[k] === 'loading'; }));
    els.count.innerHTML = waiting && !list.length ? '세부 유형까지 찾는 중…'
      : '구독 가능 모델 <b>' + fmt(list.length) + '</b>개' + (state.group && total > list.length ? ' <small>(색상만 다른 모델 ' + fmt(total - list.length) + '개는 묶음)</small>' : '') + (state.q ? ' · "' + esc(state.q) + '" 검색 결과' : '');

    if (!list.length && !waiting) {
      els.grid.innerHTML = '<li class="sf-empty">조건에 맞는 구독 모델이 없습니다.<br>' +
        '<a href="' + esc(consultHref(null)) + '" data-cta="consult-empty">찾는 모델을 알려주시면 구독 요금을 안내해 드립니다 →</a></li>';
    } else {
      els.grid.innerHTML = list.slice(0, state.shown).map(card).join('');
    }
    els.more.hidden = list.length <= state.shown;
    els.more.textContent = '더 보기 (' + fmt(Math.min(PAGE, list.length - state.shown)) + '개 / 남은 ' + fmt(Math.max(0, list.length - state.shown)) + '개)';
  }

  /* ---------- 색상만 다른 모델 묶기 (규칙은 sub_shop.js 의 SUB_FAMILY 와 같다) ---------- */
  function familyKey(model) {
    if (window.SUB_FAMILY) return window.SUB_FAMILY(model);
    var m = /^(.*\d)([A-Z]+?)(N\d)?$/.exec(String(model || '').toUpperCase());
    if (!m) return model;
    return m[1] + (m[2].length >= 3 ? m[2].slice(0, -1) : '') + (m[3] || '');
  }
  function groupColors(list) {
    var fam = {}, order = [];
    list.forEach(function (r) {
      var k = r.cat + '|' + r.seg + '|' + familyKey(r.model);
      if (!fam[k]) { fam[k] = []; order.push(k); }
      fam[k].push(r);
    });
    return order.map(function (k) {
      var vs = fam[k].slice().sort(function (a, b) { return a.min - b.min; });
      var rep = vs.filter(function (v) { return v.img && !v.imgRep; })[0] || vs[0];
      var o = {}; for (var key in rep) o[key] = rep[key];
      o.variants = vs; o.min = vs[0].min;
      return o;
    });
  }
  function cartHas(m) { return !!(window.SUB_CART && window.SUB_CART.has(m)); }

  function goodsHref(r) {
    return (CFG.goodsUrl || '/goods/goods_view.php?goodsNo=') + encodeURIComponent(r.goodsNo) + '&buy=sub' +
      '&utm_source=sub_find&utm_medium=list&utm_campaign=' + encodeURIComponent(r.model);
  }
  // SamSungSubscription.html 의 자동채움 파라미터(product/purpose/model/memo/src/from) 사용
  function consultHref(r) {
    var memo = r ? '[구독상품 찾기] ' + r.model + (r.seg ? ' (' + r.seg + ')' : '') + ' · 월 ' + fmt(r.min) + '원~'
      : '[구독상품 찾기] 찾는 모델 없음' + (state.q ? ' · 검색어: ' + state.q : '');
    var cat = r ? r.cat : state.cat;
    var q = 'from=finder' +
      (cat ? '&product=' + encodeURIComponent(IDX.cats[cat]) : '') +
      '&purpose=' + encodeURIComponent('신규구독') +
      (r ? '&model=' + encodeURIComponent(r.model) : '') +
      '&memo=' + encodeURIComponent(memo) +
      '&src=' + encodeURIComponent('구독상품 찾기') +
      '&utm_source=sub_find&utm_medium=' + (r ? 'consult' : 'empty') + (r ? '&utm_campaign=' + encodeURIComponent(r.model) : '');
    // 상담 주소에 이미 ? 가 있을 수 있다 (예: /main/html.php?htmid=service/SamSungSubscription.html) → & 로 잇는다
    var pd = window.SUB_POLICY && window.SUB_POLICY.defaults;   // 데이터센터 정책의 상담 주소 (구독탭과 같은 기준)
    var u = CFG.consultUrl || (pd && pd.consultUrl) || '/main/html.php?htmid=service/SamSungSubscription.html';
    return u + (u.indexOf('?') >= 0 ? '&' : '?') + q;
  }
  // 모든 모델은 구독 상품 페이지(sub_view)로 — 설정이 없으면 예전처럼 상품상세 구독탭/상담 신청으로
  function viewHref(r) {
    return CFG.viewUrl + encodeURIComponent(r.model) + '&utm_source=sub_find&utm_medium=list&utm_campaign=' + encodeURIComponent(r.model);
  }
  function card(r) {
    var title = r.name || r.model;
    var kind = CFG.viewUrl ? 'view' : r.goodsNo ? 'goods' : 'consult';
    var href = kind === 'view' ? viewHref(r) : kind === 'goods' ? goodsHref(r) : consultHref(r);
    var fam = r.variants && r.variants.length > 1 ? r.variants : null;
    return '<li class="sf-card' + (cartHas(r.model) ? ' in-cart' : '') + '">' +
      '<a class="sf-card-link' + (r.img ? ' has-img' : '') + '" href="' + esc(href) + '" data-cta="' + kind + '" data-model="' + esc(r.model) + '">' +
      (fam ? '<span class="sf-fam">색상 ' + fam.length + '종</span>' : '') +
      (r.img ? '<span class="sf-img"><img src="' + esc(r.img) + '" alt="" loading="lazy">' + (r.imgRep ? '<span class="sf-imgnote">대표 이미지</span>' : '') + '</span>' : '') +
      '<span class="sf-cat">' + (CAT_ICON[r.cat] || '') + ' ' + esc(IDX.cats[r.cat]) + (r.seg ? ' · ' + esc(r.segLabel || r.seg) : '') + '</span>' +
      '<strong class="sf-title">' + esc(title) + '</strong>' +
      (r.name ? '<span class="sf-model">' + esc(r.model) + '</span>' : '') +
      '<span class="sf-price"><small>월</small> ' + fmt(r.min) + '<small>원~</small></span>' +
      (fam ? '<span class="sf-fam-list">' + fam.map(function (v) { return esc(v.model); }).join(' · ') + '</span>' : '') +
      '<span class="sf-go">' + (kind === 'consult' ? '구독 상담으로 요금 받기' : '구독 요금 자세히 보기') + '</span>' +
      '</a>' + (window.SUB_CART ? '<button type="button" class="sf-add" data-add="' + esc(r.model) + '" aria-label="묶음 계산기에 담기">' + (cartHas(r.model) ? '담김 ✓' : '+ 담기') + '</button>' : '') + '</li>';
  }

  function update() { writeUrl(); render(); ensurePlans(); }

  function onClick(ev) {
    var t = ev.target.closest ? ev.target.closest('button, a') : null;
    if (!t || !root.contains(t)) return;
    if (t.hasAttribute('data-add')) {
      ev.preventDefault(); var m = t.getAttribute('data-add');
      if (!window.SUB_CART) return;
      if (window.SUB_CART.has(m)) window.SUB_CART.remove(m);
      else if (!window.SUB_CART.add(m)) alert('묶음 계산기에는 최대 10개까지 담을 수 있습니다');
      track('sub_find_cart', { sf_model: m });
    } else if (t.hasAttribute('data-cat')) {
      state.cat = t.getAttribute('data-cat'); state.seg = ''; state.shown = PAGE; update();
      track('sub_find_cat');
    } else if (t.hasAttribute('data-seg')) {
      state.seg = t.getAttribute('data-seg'); state.shown = PAGE; update();
    } else if (t.hasAttribute('data-band')) {
      state.band = t.getAttribute('data-band'); state.shown = PAGE; update();
    } else if (t.hasAttribute('data-cta')) {
      track('sub_find_click', { sf_cta: t.getAttribute('data-cta'), sf_model: t.getAttribute('data-model') || '' });
    }
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

  function start() {
    centerNav('find', '');
    readUrl();
    buildRows();
    build();
    update();
    track('sub_find_view');
  }

  /* ---------- 모델 → 고도몰 상품번호 ----------
     1순위: 데이터센터(Supabase) fn_sub_goods_map — 고도몰 Open API 로 하루 4번 갱신되는 실시간 표
     2순위: sub_goods.js (build_sub_goods.py 로 만든 엑셀 표) — 데이터센터가 응답하지 않을 때
     둘 다 없으면 전 모델이 상담 신청으로 연결된다 */
  var IMG_BASE = '';
  function useGoods(G) {
    var m = (G && G.m) || {};
    IMG_BASE = (G && G.img) || '';
    for (var k in m) if (m.hasOwnProperty(k)) GOODS[norm(k)] = m[k];
  }
  function fromFile(done) {
    if (window.SUB_GOODS) { useGoods(window.SUB_GOODS); return done(); }
    if (CFG.goodsMap === false) return done();
    // 예비 파일은 고도몰 쪽(localBase)에만 있다 — 요금표를 데이터센터에서 읽은 경우에도 여기서 찾는다
    loadScript((CFG.localBase || CFG.dataBase || '/data/js/sub/') + 'sub_goods.js?v=' + (CFG.goodsVer || CFG.localVer || CFG.ver || IDX.ver), function () {
      useGoods(window.SUB_GOODS); done();
    });
  }
  function fromApi(ok, fail) {
    var api = CFG.goodsApi;
    if (window.SUB_CATALOG && window.SUB_CATALOG.m) { useGoods(window.SUB_CATALOG); return ok(); }   // 배포본(sub_catalog.js) 이 있으면 바로 (2026-10-30)
    if (!api || !api.url || !window.fetch) return fail();
    var settled = false;
    var timer = setTimeout(function () { if (!settled) { settled = true; fail(); } }, api.timeout || 4000);
    // 구독센터 카탈로그(fn_sub_catalog) — 연결표와 같은 모양 + 고도몰에 없는 모델의 상품명까지 (상품번호 0 = 고도몰 미등록)
    var url = CFG.catalogApi && CFG.catalogApi.url ? CFG.catalogApi.url : api.url.replace(/fn_sub_goods_map$/, 'fn_sub_catalog');
    fetch(url, { method: 'POST', headers: { apikey: api.key, 'Content-Type': 'application/json' }, body: '{}' })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (G) { if (settled) return; settled = true; clearTimeout(timer); useGoods(G); ok(); })
      .catch(function (e) { if (settled) return; settled = true; clearTimeout(timer); if (window.console) console.warn('[구독찾기] 상품 연결표 데이터센터 실패 → 파일 사용', e); fail(); });
  }
  fromApi(start, function () { fromFile(start); });
})();
