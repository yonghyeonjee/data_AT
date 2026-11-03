/* ===== 구독 전용몰(시흥몰 cateCd=012 '구독상품') 목록을 "월 구독료 가격대"별로 묶어 보여준다 · 2026-11-03 =====
   어디서: 고도몰 스킨 goods/goods_list.html 이 cateCd 012* 일 때만 이 파일을 <script defer> 로 받는다 (deploy/skin_1103/goods_list_1103.html)
   무엇을:
   1) 목록(.goods_list_cont .item_basket_type li)의 표시 가격(data-goods-price · 구독상품은 월 구독료)을 읽어 가격대(BANDS)로 나눈다
   2) 80개씩 끊긴 페이지면 같은 주소에 pageNum=120 을 붙여 전부 받아 온 뒤 묶는다 (실패하면 보이는 것만 묶고 페이지 이동은 그대로)
   3) 위에 가격대 칩(누르면 그 묶음으로 이동) · 묶음마다 제목(가격대 · 개수) 을 붙인다. 상품 칸(li)은 그대로 옮기고 묶음 상자는 .goods_list_cont 바로 아래 두어(스킨 선택자) 담기·장바구니·모바일 2열은 스킨 그대로
   4) 3,000원 미만은 옵션에서 가격이 정해지는 자리표시 가격이라 "가격 상담" 묶음으로 뒤에 둔다
   고치려면: BANDS(가격대) · 문구만. 금액 계산은 하지 않는다 (상세 페이지 구독탭 sub_tab.js 가 한다) */
(function () {
  'use strict';
  if (window.__subListDone) return; window.__subListDone = true;
  var BANDS = [
    { k: 'u10', label: '월 1만원 미만', min: 0, max: 10000 },
    { k: 'u20', label: '월 1만 ~ 2만원', min: 10000, max: 20000 },
    { k: 'u40', label: '월 2만 ~ 4만원', min: 20000, max: 40000 },
    { k: 'u60', label: '월 4만 ~ 6만원', min: 40000, max: 60000 },
    { k: 'u100', label: '월 6만 ~ 10만원', min: 60000, max: 100000 },
    { k: 'o100', label: '월 10만원 이상', min: 100000, max: 1e12 },
    { k: 'ask', label: '가격 상담', note: '옵션(약정·케어)에 따라 월 구독료가 정해지는 상품 — 상품을 누르면 구독탭에서 바로 계산됩니다' }
  ];
  var ASK_UNDER = 3000;   // 이 금액 미만의 표시 가격은 옵션에서 정해지는 자리표시(100원·693원·2,150원 …) → 가격 상담 묶음
  // 스킨 list.css/dbook.css 가 ".goods_list_cont > div > ul li" (모바일 768px↓ 폭 50% !important) 로 상품 칸을 잡으므로
  // 묶음 상자(div.item_basket_type > ul > li)는 .goods_list_cont 의 바로 아래에 두고, 칩·제목은 ul/li 를 쓰지 않는다
  var CSS = '.sl-head{display:flex;flex-wrap:wrap;align-items:center;gap:8px 10px;margin:8px 0 14px}' +
    '.sl-head h3{margin:0;font-size:17px;font-weight:800;letter-spacing:-.02em}.sl-head small{color:#888;font-size:12.5px;font-weight:400}' +
    '.sl-nav{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 22px}' +
    '.sl-nav a{display:inline-block;padding:7px 13px;border:1px solid #d9dee6;border-radius:18px;background:#fff;color:#222;font-size:13px;line-height:1.2;text-decoration:none;white-space:nowrap}' +
    '.sl-nav a b{color:#1d6fe8;margin-left:4px;font-weight:700}.sl-nav a:hover,.sl-nav a.on{border-color:#1d6fe8;background:#eef4ff;color:#1d6fe8}' +
    '.sl-band-tit{display:flex;align-items:baseline;gap:10px;margin:0 0 12px;padding:0 0 10px;border-bottom:2px solid #222;scroll-margin-top:90px}' +
    '.sl-band-tit h3{margin:0;font-size:18px;font-weight:800;letter-spacing:-.02em}.sl-band-tit .sl-n{color:#1d6fe8;font-size:14px;font-weight:700}.sl-band-tit .sl-rng{color:#888;font-size:12.5px;margin-left:auto}' +
    '.sl-band-note{margin:-4px 0 12px;color:#777;font-size:12.5px;line-height:1.5}.sl-loading{margin:0 0 12px;color:#888;font-size:13px}' +
    '.goods_list_cont > .item_basket_type.sl-box{margin:0 0 34px}' +
    '.sl-foot{margin:4px 0 24px;color:#888;font-size:12px;line-height:1.6}' +
    '@media (max-width:640px){.sl-head h3{font-size:15px}.sl-nav a{padding:6px 10px;font-size:12px}.sl-band-tit h3{font-size:15.5px}.sl-band-tit .sl-rng{display:none}.sl-band-tit{scroll-margin-top:70px}}';
  var fmt = function (n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); };
  function priceOf(li) {
    var b = li.querySelector('[data-goods-price]');
    var p = b ? parseFloat(b.getAttribute('data-goods-price')) : NaN;
    if (!(p > 0)) {   // 버튼이 없으면 표시 가격 글자에서
      var t = li.querySelector('.item_price'); p = t ? parseFloat((t.textContent || '').replace(/[^0-9.]/g, '')) : NaN;
    }
    return p > 0 ? p : NaN;
  }
  function bandOf(p) {
    if (!(p >= ASK_UNDER)) return BANDS[BANDS.length - 1];
    for (var i = 0; i < BANDS.length - 1; i++) if (p >= BANDS[i].min && p < BANDS[i].max) return BANDS[i];
    return BANDS[BANDS.length - 1];
  }
  function idxOf(k) { for (var i = 0; i < BANDS.length; i++) if (BANDS[i].k === k) return i; return 99; }
  function lisOf(doc) {
    return Array.prototype.slice.call(doc.querySelectorAll('.goods_list_cont .item_basket_type > ul > li')).filter(function (li) { return li.querySelector('.item_cont'); });
  }
  function totalOf(doc) {
    var el = doc.querySelector('.pick_list_num strong'); var n = el ? parseInt((el.textContent || '').replace(/\D/g, ''), 10) : NaN; return n > 0 ? n : 0;
  }
  function mk(tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html) e.innerHTML = html; return e; }
  function render(cont, lis) {
    var sample = cont.querySelector('.item_basket_type > ul');
    var ulClass = sample ? sample.className : '';
    var groups = {}, order = [];
    lis.forEach(function (li) {
      var p = priceOf(li), b = bandOf(p);
      if (!groups[b.k]) { groups[b.k] = { band: b, lis: [], min: Infinity, max: 0 }; order.push(b.k); }
      var g = groups[b.k]; g.lis.push(li); if (p > 0) { g.min = Math.min(g.min, p); g.max = Math.max(g.max, p); }
    });
    order.sort(function (a, b) { return idxOf(a) - idxOf(b); });
    var frag = document.createDocumentFragment();
    frag.appendChild(mk('div', 'sl-head', '<h3>구독 가격대별로 보기</h3><small>표시 금액은 월 구독료(VAT 포함) · 전체 ' + lis.length + '개</small>'));
    var nav = mk('nav', 'sl-nav', order.map(function (k) { var g = groups[k]; return '<a href="#sl-' + k + '" data-k="' + k + '">' + g.band.label + '<b>' + g.lis.length + '</b></a>'; }).join(''));
    frag.appendChild(nav);
    order.forEach(function (k) {
      var g = groups[k];
      var rng = g.band.k === 'ask' ? '' : (g.min < Infinity ? '<span class="sl-rng">' + fmt(g.min) + '원 ~ ' + fmt(g.max) + '원</span>' : '');
      var tit = mk('div', 'sl-band-tit', '<h3>' + g.band.label + '</h3><span class="sl-n">' + g.lis.length + '개</span>' + rng); tit.id = 'sl-' + k;
      frag.appendChild(tit);
      if (g.band.note) frag.appendChild(mk('p', 'sl-band-note', g.band.note));
      var box = mk('div', 'item_basket_type sl-box'), ul = document.createElement('ul'); if (ulClass) ul.className = ulClass;
      g.lis.forEach(function (li) { ul.appendChild(li); });
      box.appendChild(ul); frag.appendChild(box);
    });
    var foot = mk('p', 'sl-foot');
    foot.textContent = '* 가격대는 목록에 표시된 월 구독료 기준입니다. 약정 기간·케어 서비스·선납·제휴카드에 따라 실제 월 납부액은 달라지며, 상품을 누르면 구독탭에서 바로 계산해 볼 수 있습니다.';
    frag.appendChild(foot);
    cont.innerHTML = ''; cont.appendChild(frag);
    nav.addEventListener('click', function (e) {
      var a = e.target.closest ? e.target.closest('a') : null; if (!a) return;
      var tit = document.getElementById(a.getAttribute('href').slice(1)); if (!tit) return;
      e.preventDefault(); tit.scrollIntoView({ behavior: 'smooth', block: 'start' });
      Array.prototype.forEach.call(nav.children, function (x) { x.classList.toggle('on', x === a); });
    });
  }
  function run() {
    var cont = document.querySelector('.goods_list_cont'); if (!cont) return;
    var lis = lisOf(document); if (!lis.length) return;
    var st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
    var total = totalOf(document), pag = document.querySelector('.pagination');
    var needAll = total > lis.length && !/[?&]pageNum=/.test(location.search) && window.fetch && window.DOMParser;
    if (!needAll) { render(cont, lis); return; }
    var note = document.createElement('p'); note.className = 'sl-loading'; note.textContent = '전체 ' + total + '개 상품을 가격대별로 정리하는 중…';
    cont.parentNode.insertBefore(note, cont);
    var url = location.pathname + (location.search ? location.search + '&' : '?') + 'pageNum=120';
    fetch(url, { credentials: 'same-origin' }).then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); }).then(function (html) {
      var doc = new DOMParser().parseFromString(html, 'text/html');
      var all = lisOf(doc);
      note.parentNode && note.parentNode.removeChild(note);
      if (all.length >= lis.length) { render(cont, all); if (pag) pag.style.display = 'none'; }
      else render(cont, lis);
    }).catch(function () { note.parentNode && note.parentNode.removeChild(note); render(cont, lis); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
})();
