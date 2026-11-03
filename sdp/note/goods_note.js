/* ===== 상품 안내 문구 (mvp_266 · 2026-11-03) — 특정 상품에만 자유 문구 + 작은 버튼 =====
   고도몰 goods_view.html 에 아래 두 줄을 넣으면 데이터센터(fn_goods_note)에서 이 상품 문구를 받아 정한 위치에 끼워 넣는다.
     <script>var GOODS_NOTE_CONFIG = { mall: 'pm', goodsNo: '{=goodsView['goodsNo']}' };</script>
     <script src="https://db.samsungat.co.kr/sdp/note/goods_note.js" charset="utf-8"></script>
   - 대상: 상품번호(그 몰 번호) 또는 모델번호(상품명·CFG.models 에서 찾음). 문구가 없는 상품은 아무것도 안 한다.
   - 상태 test 인 문구는 주소에 gnote=on 이 붙은 사람만 본다 (예: …goods_view.php?goodsNo=123&gnote=on)
   - 위치 pos → 스킨 요소 (공통: 가격 아래 .price-box · 네이버페이 위 .pay_box — 두 몰 스킨에 다 있다 / 디자인북 스킨 기준 · CFG.anchors 로 바꿀 수 있다 · 요소가 없으면 가격 아래 → 상품명 영역 끝)
   - 매장 화면 미리보기도 이 파일의 GoodsNote.html / GoodsNote.place 를 그대로 쓴다 (CFG.auto === false 면 데이터를 부르지 않음)
   ※ 문구는 글자로만 넣는다(HTML 무시). 줄바꿈 그대로 · **굵게** 는 강조색 굵은 글씨 */
(function () {
  'use strict';
  var C = window.GOODS_NOTE_CONFIG || {};
  var API = C.api || 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/fn_goods_note';
  var KEY = C.key || 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';   // 공개(publishable) 키 — 공개 함수만 부른다
  // 위치 → [선택자, 넣는 법] 후보를 앞에서부터 찾는다 (몰·스킨마다 이름이 달라서)
  //   디자인북 PC/반응형(프라자몰 designbookR · 시흥몰/AT몰 designbook_air_RES): .price-box · .pay_box · .btn_choice_box · .detail_explain_box
  //   S몰 PC(no99): 가격이 .item_detail_list 의 dl.item_price · S몰 모바일(no99): .detail_info_top .price_box · 네이버페이·구매 버튼은 구매 창 안이라 상품정보 표(.detail_sub_info) 아래로 · .cont_detail
  var POS = {
    price_below:   [['.price-box', 'after'], ['.item_detail_list .item_price', 'after'], ['.detail_info_top .price_box', 'after']],
    pay_above:     [['.pay_box', 'before'], ['.btn_choice_box', 'after'], ['.detail_sub_info', 'after']],   // 네이버페이가 없는 몰(AT몰)은 구매 버튼 바로 아래
    title_below:   [['.item_detail_tit h3', 'after'], ['.detail_info_top h3', 'after'], ['.detail_info_top .goods_name', 'after']],
    benefit_above: [['.custom-benefit-notice', 'before']],
    benefit_below: [['.custom-benefit-notice', 'after']],
    buy_above:     [['.btn_choice_box', 'before'], ['.detail_sub_info', 'after']],
    pay_below:     [['.pay_box', 'after'], ['.btn_choice_box', 'after'], ['.detail_sub_info', 'after']],
    detail_top:    [['.detail_explain_box', 'prepend'], ['.cont_detail', 'prepend']]
  };
  var LAST = [['.item_detail_tit', 'append'], ['.item_info_box', 'append'], ['.detail_info_top', 'append']];
  var POS_LABEL = {
    price_below: '가격 아래', pay_above: '네이버페이 위',
    title_below: '상품명 아래',   // benefit_above/below 는 예전 고정 혜택 상자 기준 — 그 상자를 문구로 옮겨 목록에서 뺐다 (있던 문구는 가격 아래로 대신 들어감)
    buy_above: '구매 버튼 위', pay_below: '네이버페이 아래', detail_top: '상세정보 맨 위'
  };
  var TONES = {
    blue:   { bg: '#f7faff', line: '#d9e3f0', em: '#1757a6' },
    red:    { bg: '#fff6f6', line: '#f2d0d0', em: '#d43f3f' },
    gray:   { bg: '#f7f7f7', line: '#e3e3e3', em: '#333333' },
    yellow: { bg: '#fffbe8', line: '#f0e2a0', em: '#8a5a00' },
    plain:  { bg: 'transparent', line: 'transparent', em: '#1757a6' }   // 상자 없이 (이미지 배너 등)
  };
  var CSS = '.gnote{margin:14px 0;padding:16px 18px;border:1px solid;border-radius:6px;color:#333;font-size:14px;line-height:1.7;box-sizing:border-box;text-align:left;word-break:keep-all;position:relative}' +
    '.gnote-title{display:block;margin-bottom:4px;font-size:16px;font-weight:700;color:#222}' +
    '.gnote.plain{padding:0;border:0;text-align:center}' +
    '.gnote-img{display:inline-block;width:602px;max-width:100%;height:auto;vertical-align:top}' +
    '.gnote-small{color:#666;font-size:13px}' +
    '.gnote-line{min-height:1em}' +
    '.gnote-body strong{font-weight:700}' +
    '.gnote-btn{display:inline-block;margin-top:10px;padding:8px 16px;border-radius:4px;font-size:14px;font-weight:700;line-height:1.4;text-decoration:none!important;box-sizing:border-box}' +
    '.gnote-btn.kakao{background:#FEE500;color:#191919!important}' +
    '.gnote-btn.blue{background:#1757a6;color:#fff!important}' +
    '.gnote-btn.line{background:#fff;color:#1757a6!important;border:1px solid #1757a6}' +
    '.gnote-test{position:absolute;top:6px;right:8px;padding:1px 6px;border-radius:3px;background:#ff8a00;color:#fff;font-size:11px;font-weight:700}' +
    '@media (max-width:767px){.gnote{padding:13px 15px;font-size:13px}.gnote.plain{padding:0}.gnote-title{font-size:15px}.gnote-btn{font-size:13px}.gnote-small{font-size:12px}}';

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function safeUrl(u) { u = String(u || '').trim(); return /^(https?:\/\/|tel:|\/)/i.test(u) ? u : ''; }
  function addCss(doc) {
    doc = doc || document;
    if (doc.getElementById('gnoteCss')) return;
    var st = doc.createElement('style'); st.id = 'gnoteCss'; st.textContent = CSS; (doc.head || doc.documentElement).appendChild(st);
  }
  // 문구 하나 → HTML (글자만 · 한 줄씩 · **색 굵게** · !!빨간 굵게!! · ※ 로 시작하는 줄은 작은 회색 · 이미지는 https 주소만)
  function html(n) {
    var t = TONES[n.tone] || TONES.blue;
    var body = String(n.body || '').split(/\r?\n/).map(function (line) {
      var h = esc(line).replace(/\*\*(.+?)\*\*/g, '<strong style="color:' + t.em + '">$1</strong>')
                       .replace(/!!(.+?)!!/g, '<strong style="color:#d43f3f">$1</strong>');
      // ※ 로 시작하거나 ~ 로 시작하는 줄은 작은 회색 (~ 는 떼고 보인다)
      var small = /^\s*[※~]/.test(line);
      if (/^\s*~/.test(line)) h = h.replace(/^\s*~\s?/, '');
      return '<div class="' + (small ? 'gnote-small' : 'gnote-line') + '">' + (h || '&nbsp;') + '</div>';
    }).join('');
    var url = safeUrl(n.url), ext = /^https?:/i.test(url) && url.indexOf(location.host) < 0;
    var img = /^https:\/\//i.test(String(n.img || '')) ? String(n.img) : '';
    var imgHtml = img ? '<img class="gnote-img" src="' + esc(img) + '" alt="' + esc(n.title || '') + '">' : '';
    if (imgHtml && url && !n.btn) imgHtml = '<a href="' + esc(url) + '"' + (ext ? ' target="_blank" rel="noopener noreferrer"' : '') + '>' + imgHtml + '</a>';
    return '<div class="gnote' + (n.tone === 'plain' ? ' plain' : '') + '" data-gnote="' + esc(n.id || '') + '" style="background:' + t.bg + ';border-color:' + t.line + '">' +
      (n.test ? '<span class="gnote-test" title="상태가 test라 주소에 gnote=on 이 있을 때만 보입니다">test</span>' : '') +
      (n.title && n.tone !== 'plain' ? '<strong class="gnote-title">' + esc(n.title) + '</strong>' : '') +
      imgHtml +
      (String(n.body || '').trim() ? '<div class="gnote-body">' + body + '</div>' : '') +
      (n.btn && url ? '<div><a class="gnote-btn ' + esc(n.btnTone || 'kakao') + '" href="' + esc(url) + '"' + (ext ? ' target="_blank" rel="noopener noreferrer"' : '') + '>' + esc(n.btn) + '</a></div>' : '') +
      '</div>';
  }
  // 문구를 root(기본 document) 안의 정한 위치에 끼운다 — 요소가 없으면 가격 아래 → 상품명 영역 끝
  function place(n, root) {
    root = root || document;
    var t = target(n.pos, root); if (!t) return null;
    var el = t[0], how = t[1];
    var box = (root.ownerDocument || root).createElement('div'); box.innerHTML = html(n); box = box.firstChild;
    if (how === 'before') el.parentNode.insertBefore(box, el);
    else if (how === 'after') el.parentNode.insertBefore(box, el.nextSibling);
    else if (how === 'prepend') el.insertBefore(box, el.firstChild);
    else el.appendChild(box);
    return box;
  }
  // 위치의 후보 중 페이지에 있는 첫 요소 → [요소, 넣는 법] (없으면 가격 아래 → 상품명 영역 끝) · CFG.anchors[pos] = [선택자, 넣는 법] 이 먼저
  function target(pos, root) {
    var a = (C.anchors || {})[pos], list = (a ? [a] : []).concat(POS[pos] || [], POS.price_below, LAST);
    for (var i = 0; i < list.length; i++) { var el = root.querySelector(list[i][0]); if (el) return [el, list[i][1]]; }
    return null;
  }
  function modelsOnPage() {
    var out = (C.models || []).slice();
    var h = document.querySelector('.item_detail_tit h3') || document.querySelector('.detail_info_top h3');
    var og = document.querySelector('meta[property="og:title"]');
    var name = (C.name || (h && h.textContent) || (og && og.content) || document.title || '');
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
        // 같은 위치에 여러 개면 순서(sort)대로 — after/prepend 는 뒤에서부터, before/append 는 앞에서부터 넣어야 순서가 유지된다
        var how = function (n) { var t = target(n.pos, document); return t ? t[1] : ''; };
        list.slice().reverse().forEach(function (n) { if (/^(after|prepend)$/.test(how(n))) place(n); });
        list.forEach(function (n) { if (/^(before|append)$/.test(how(n))) place(n); });
      })
      .catch(function () { /* 데이터센터를 못 읽으면 아무것도 안 한다 */ });
  }
  window.GoodsNote = { html: html, place: place, addCss: addCss, POS: POS, POS_LABEL: POS_LABEL, TONES: TONES };
  if (C.auto === false) return;
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
})();
