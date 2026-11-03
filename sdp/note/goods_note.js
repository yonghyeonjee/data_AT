/* ===== 상품 안내 문구 (mvp_266 · 2026-11-03) — 특정 상품에만 자유 문구 + 작은 버튼 =====
   고도몰 goods_view.html 에 아래 두 줄을 넣으면 데이터센터(fn_goods_note)에서 이 상품 문구를 받아 정한 위치에 끼워 넣는다.
     <script>var GOODS_NOTE_CONFIG = { mall: 'pm', goodsNo: '{=goodsView['goodsNo']}' };</script>
     <script src="https://db.samsungat.co.kr/sdp/note/goods_note.js" charset="utf-8"></script>
   - 대상: 상품번호(그 몰 번호) 또는 모델번호(상품명·CFG.models 에서 찾음). 문구가 없는 상품은 아무것도 안 한다.
   - 상태 test 인 문구는 주소에 gnote=on 이 붙은 사람만 본다 (예: …goods_view.php?goodsNo=123&gnote=on)
   - 위치 pos → 스킨 요소 (디자인북 스킨 기준 · CFG.anchors 로 바꿀 수 있다 · 요소가 없으면 가격 아래 → 상품명 영역 끝)
   - 매장 화면 미리보기도 이 파일의 GoodsNote.html / GoodsNote.place 를 그대로 쓴다 (CFG.auto === false 면 데이터를 부르지 않음)
   ※ 문구는 글자로만 넣는다(HTML 무시). 줄바꿈 그대로 · **굵게** 는 강조색 굵은 글씨 */
(function () {
  'use strict';
  var C = window.GOODS_NOTE_CONFIG || {};
  var API = C.api || 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/fn_goods_note';
  var KEY = C.key || 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';   // 공개(publishable) 키 — 공개 함수만 부른다
  var POS = {
    title_below:   ['.item_detail_tit h3', 'after'],
    price_below:   ['.price-box', 'after'],
    benefit_above: ['.custom-benefit-notice', 'before'],
    benefit_below: ['.custom-benefit-notice', 'after'],
    buy_above:     ['.btn_choice_box', 'before'],
    pay_below:     ['.pay_box', 'after'],
    detail_top:    ['.detail_explain_box', 'prepend']
  };
  var POS_LABEL = {
    title_below: '상품명 아래', price_below: '가격 아래', benefit_above: '혜택 안내 상자 위', benefit_below: '혜택 안내 상자 아래',
    buy_above: '구매 버튼 위', pay_below: '네이버페이 아래', detail_top: '상세정보 맨 위'
  };
  var TONES = {
    blue:   { bg: '#f7faff', line: '#d9e3f0', em: '#1757a6' },
    red:    { bg: '#fff6f6', line: '#f2d0d0', em: '#d43f3f' },
    gray:   { bg: '#f7f7f7', line: '#e3e3e3', em: '#333333' },
    yellow: { bg: '#fffbe8', line: '#f0e2a0', em: '#8a5a00' }
  };
  var CSS = '.gnote{margin:14px 0;padding:16px 18px;border:1px solid;border-radius:6px;color:#333;font-size:14px;line-height:1.7;box-sizing:border-box;text-align:left;word-break:keep-all;position:relative}' +
    '.gnote-title{display:block;margin-bottom:4px;font-size:16px;font-weight:700;color:#222}' +
    '.gnote-body{white-space:pre-line}' +
    '.gnote-body strong{font-weight:700}' +
    '.gnote-btn{display:inline-block;margin-top:10px;padding:8px 16px;border-radius:4px;font-size:14px;font-weight:700;line-height:1.4;text-decoration:none!important;box-sizing:border-box}' +
    '.gnote-btn.kakao{background:#FEE500;color:#191919!important}' +
    '.gnote-btn.blue{background:#1757a6;color:#fff!important}' +
    '.gnote-btn.line{background:#fff;color:#1757a6!important;border:1px solid #1757a6}' +
    '.gnote-test{position:absolute;top:6px;right:8px;padding:1px 6px;border-radius:3px;background:#ff8a00;color:#fff;font-size:11px;font-weight:700}' +
    '@media (max-width:767px){.gnote{padding:13px 15px;font-size:13px}.gnote-title{font-size:15px}.gnote-btn{font-size:13px}}';

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function safeUrl(u) { u = String(u || '').trim(); return /^(https?:\/\/|tel:|\/)/i.test(u) ? u : ''; }
  function addCss(doc) {
    doc = doc || document;
    if (doc.getElementById('gnoteCss')) return;
    var st = doc.createElement('style'); st.id = 'gnoteCss'; st.textContent = CSS; (doc.head || doc.documentElement).appendChild(st);
  }
  // 문구 하나 → HTML (글자만 · 줄바꿈 유지 · **굵게**)
  function html(n) {
    var t = TONES[n.tone] || TONES.blue;
    var body = esc(n.body).replace(/\*\*(.+?)\*\*/g, '<strong style="color:' + t.em + '">$1</strong>');
    var url = safeUrl(n.url), ext = /^https?:/i.test(url) && url.indexOf(location.host) < 0;
    return '<div class="gnote" data-gnote="' + esc(n.id || '') + '" style="background:' + t.bg + ';border-color:' + t.line + '">' +
      (n.test ? '<span class="gnote-test" title="상태가 시험이라 주소에 gnote=on 이 있을 때만 보입니다">시험</span>' : '') +
      (n.title ? '<strong class="gnote-title">' + esc(n.title) + '</strong>' : '') +
      '<div class="gnote-body">' + body + '</div>' +
      (n.btn && url ? '<div><a class="gnote-btn ' + esc(n.btnTone || 'kakao') + '" href="' + esc(url) + '"' + (ext ? ' target="_blank" rel="noopener noreferrer"' : '') + '>' + esc(n.btn) + '</a></div>' : '') +
      '</div>';
  }
  // 문구를 root(기본 document) 안의 정한 위치에 끼운다 — 요소가 없으면 가격 아래 → 상품명 영역 끝
  function place(n, root) {
    root = root || document;
    var anchors = C.anchors || {}, p = anchors[n.pos] || POS[n.pos] || POS.benefit_below;
    var el = root.querySelector(p[0]), how = p[1];
    if (!el) { el = root.querySelector('.price-box'); how = 'after'; }
    if (!el) { el = root.querySelector('.item_detail_tit') || root.querySelector('.item_info_box'); how = 'append'; }
    if (!el) return null;
    var box = (root.ownerDocument || root).createElement('div'); box.innerHTML = html(n); box = box.firstChild;
    if (how === 'before') el.parentNode.insertBefore(box, el);
    else if (how === 'after') el.parentNode.insertBefore(box, el.nextSibling);
    else if (how === 'prepend') el.insertBefore(box, el.firstChild);
    else el.appendChild(box);
    return box;
  }
  function modelsOnPage() {
    var out = (C.models || []).slice();
    var h = document.querySelector('.item_detail_tit h3') || document.querySelector('h3');
    var name = (C.name || (h && h.textContent) || '');
    name.split(/[\s\/\[\]()+,]+/).forEach(function (w) { if (w.length >= 8 && /^[A-Z][A-Z][A-Z0-9-]+$/.test(w)) out.push(w); });
    return out;
  }
  function goodsOnPage() {
    if (C.goodsNo) return String(C.goodsNo);
    var m = /[?&]goodsNo=(\d+)/.exec(location.search); return m ? m[1] : null;
  }
  function run() {
    var goods = goodsOnPage(), models = modelsOnPage();
    if (!goods && !models.length) return;
    var test = /[?&]gnote=on(&|$)/.test(location.search);
    fetch(API, { method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_mall: C.mall || 'pm', p_goods: goods, p_models: models, p_test: test }) })
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (list) {
        if (!list || !list.length) return;
        addCss();
        // 같은 위치에 여러 개면 순서(sort)대로 — after/before 는 뒤에서부터 넣어야 순서가 유지된다
        list.slice().reverse().forEach(function (n) { if (/(after|before|prepend)/.test(((C.anchors || {})[n.pos] || POS[n.pos] || ['', 'after'])[1])) place(n); });
        list.forEach(function (n) { if (!/(after|before|prepend)/.test(((C.anchors || {})[n.pos] || POS[n.pos] || ['', 'after'])[1])) place(n); });
      })
      .catch(function () { /* 데이터센터를 못 읽으면 아무것도 안 한다 */ });
  }
  window.GoodsNote = { html: html, place: place, addCss: addCss, POS: POS, POS_LABEL: POS_LABEL, TONES: TONES };
  if (C.auto === false) return;
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
})();
