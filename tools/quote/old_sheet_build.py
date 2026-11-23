# -*- coding: utf-8 -*-
"""기존 시흥몰 구독 견적서(service/quote_subscribe.html) 수정본 만들기 (2026-11-16)
   python build.py <원본 raw.html> <고도몰 업로드용 출력> <우리 시스템용 출력>
   두 출력은 계산·화면 코드가 같다. 다른 점: 우리 시스템용은 보안 코드 잠금 대신 담당자 로그인(dc_session)을 쓴다."""
import io, sys
src, out_godo, out_dc = sys.argv[1:4]
s = io.open(src, encoding='utf-8', newline='').read(); CR = '\r\n' in s; s = s.replace('\r\n', '\n')
n = 0
def rep(a, b):
    global s, n
    c = s.count(a)
    if c != 1: raise SystemExit('MISS %d: %r' % (c, a[:80]))
    s = s.replace(a, b); n += 1

# 1. 선납금 — /quote/ 가 넘긴 품목(preIncl)은 총 구독료에 선납금이 이미 들어 있다. 다시 더하지 않는다
rep("    var finalP = Math.max(0, total - benefit) + preAmt;",
    "    var preAdd = it.preIncl ? 0 : preAmt;   // /quote/ 는 총 구독료에 선납금이 이미 들어 있다 (DPS 총구독료)\n    var finalP = Math.max(0, total - benefit) + preAdd;")
rep("    var payM = m > 0 ? Math.round((total - sub - multi - pre) / m) : 0;",
    "    var payM = m > 0 ? Math.round((total - sub - multi - pre - (it.preIncl ? preAmt : 0)) / m) : 0;")
rep("card: card, cardMonthly: cardMonthly, cons: cons, gift: gift, preAmt: preAmt,\n",
    "card: card, cardMonthly: cardMonthly, cons: cons, gift: gift, preAmt: preAmt, preAdd: preAdd,\n")
rep("T.preAmt += c.preAmt; T.finalP += c.finalP;", "T.preAmt += c.preAmt; T.preAdd = (T.preAdd || 0) + c.preAdd; T.finalP += c.finalP;")
rep("""'<span style="color:#1A4FA0;font-weight:700">+' + won(c.preAmt) + '</span>') + '</td></tr>';""",
    """'<span style="color:#1A4FA0;font-weight:700">' + (c.preAdd > 0 ? '+' : '') + won(c.preAmt) + '</span>') + '</td></tr>';""")
rep("      if(T.preAmt > 0){\n        /* 소계:", "      if(T.preAdd > 0){\n        /* 소계:")
rep("      if(c.pre > 0 && c.preAmt > 0) w.push(", "      if(c.pre > 0 && c.preAmt > 0 && !it.preIncl) w.push(")

# 2. 일반 구매 상자 — /quote/ 가 넘긴 q.lump 를 구독 아래에 같은 표 양식으로
LUMP = r"""    /* 일반 구매 (상담 견적 화면 /quote/ 가 넣는 q.lump) — 구독 아래에 같은 표 양식으로 (2026-11-16) */
    if(q.lump && q.lump.items && q.lump.items.length){
      var L = q.lump, lb = '<div class="q-box"><h3>💳 일반 구매' + (L.kindLabel ? ' <span style="font-weight:600;color:#666">(' + esc(L.kindLabel) + (num(L.months) ? ' · ' + num(L.months) + '개월' : '') + ')</span>' : '') + '</h3><table class="q-tbl">';
      L.items.forEach(function(x, i){ lb += '<tr><th>' + (i + 1) + '. ' + esc(x.name || x.model || '') + (x.model && x.name ? ' <span style="font-weight:500;color:#666">' + esc(x.model) + '</span>' : '') + (x.note ? ' <span style="font-weight:500;color:#666">· ' + esc(x.note) + '</span>' : '') + '</th><td class="num">' + won(x.amount) + '</td></tr>'; });
      lb += '<tr class="tot"><th>결제가</th><td class="num">' + won(L.amount) + '</td></tr>';
      if(num(L.fee) > 0) lb += '<tr><th>이용료</th><td class="num">+' + won(L.fee) + '</td></tr>';
      if(num(L.bill) > 0) lb += '<tr><th>청구할인</th><td class="num">-' + won(L.bill) + '</td></tr>';
      if(L.ptD != null){   // 입력 화면 계산 풀이와 같은 이름·같은 값 (2026-11-23)
        if(num(L.ptRest) > 0) lb += '<tr><th>캐시백(송금)</th><td class="num">-' + won(L.ptRest) + '</td></tr>';
        if(num(L.ptD) > 0) lb += '<tr class="q-pt"><th>⭐ 삼성전자 포인트 합계</th><td class="num">-' + won(L.ptD) + '</td></tr>';
        if(num(L.ptS) > 0) lb += '<tr class="q-pt"><th>⭐ 추가 포인트 (구독료 지원)</th><td class="num">-' + won(L.ptS) + '</td></tr>';
      } else {
      if(num(L.sPoint) > 0) lb += '<tr><th>금액별 S포인트</th><td class="num">-' + won(L.sPoint) + '</td></tr>';
      if(num(L.jPoint) > 0) lb += '<tr><th>DPS 포인트 (패키지·제휴할부 제외)</th><td class="num">-' + won(L.jPoint) + '</td></tr>';
      if(num(L.typePoint) > 0) lb += '<tr><th>' + esc(L.typeLabel || '포인트') + '</th><td class="num">-' + won(L.typePoint) + '</td></tr>';
      if(num(L.member) > 0) lb += '<tr><th>기본멤버십P 0.1%</th><td class="num">-' + won(L.member) + '</td></tr>';
      }
      if(num(L.cashback) > 0) lb += '<tr><th>조건부 캐시백</th><td class="num">-' + won(L.cashback) + '</td></tr>';
      (L.extras || []).forEach(function(x){ if(num(x.amount) > 0) lb += '<tr><th>' + esc(x.label || '추가혜택') + '</th><td class="num">-' + won(x.amount) + '</td></tr>'; });
      lb += '<tr class="ben"><th>혜택 합계</th><td class="num">-' + won(L.benefit) + '</td></tr>';
      lb += '<tr class="tot"><th>일반 최종가 (최종체감가)' + (num(L.per) > 0 ? ' <span style="font-weight:600;font-size:.9em">(월 ' + won(L.per) + ' × ' + num(L.months) + ')</span>' : '') + '</th><td class="num">' + won(L.net) + '</td></tr>';
      var T0 = calcTotals(q);
      lb += '<tr class="fin"><th>전체 최종가 <span style="font-weight:600;font-size:.85em">(구독 최종가 ' + won(T0.finalP) + ' + 일반 최종가)</span></th><td class="num">' + won(T0.finalP + num(L.net)) + '</td></tr>';
      lb += '</table></div>';
      blocks.push('<div class="q-sum solo">' + lb + '</div>');
    }
"""
rep("""    blocks.push(h);
    blocks.push('<div class="q-memo"><div class="t">세부 상담 내용</div>'""",
    """    blocks.push(h);
""" + LUMP + """    blocks.push('<div class="q-memo"><div class="t">세부 상담 내용</div>'""")

# 3. 서버 호출 — 담당자 로그인(dc_session)이 있으면 그것으로 통과 (우리 시스템에서 열었을 때)
rep("""    var body = Object.assign({ p_code: window.SH_CODE || '' }, args || {});
    return fetch(DC.url + fn, { method: 'POST', headers: { apikey: DC.anon, Authorization: 'Bearer ' + DC.anon, 'Content-Type': 'application/json' }, body: JSON.stringify(body) })""",
    """    var ses = ''; try { ses = localStorage.getItem('dc_session') || ''; } catch(e){}
    var body = Object.assign({ p_code: window.SH_CODE || (ses ? null : '') }, args || {});
    var hd = { apikey: DC.anon, Authorization: 'Bearer ' + DC.anon, 'Content-Type': 'application/json' }; if(ses) hd['x-dc-session'] = ses;
    return fetch(DC.url + fn, { method: 'POST', headers: hd, body: JSON.stringify(body) })""")

# 4. /quote/ 가 저장한 견적은 meta 에 번호가 없다 — 불러온 번호를 넣어 다음 판으로 저장되게
rep("""            if(!QUOTE.meta) QUOTE.meta = { no: no, version: r.version || ver || 1, issuedAt: r.issuedAt || '' };""",
    """            if(!QUOTE.meta) QUOTE.meta = { no: no, version: r.version || ver || 1, issuedAt: r.issuedAt || '' };
            if(!QUOTE.meta.no){ QUOTE.meta.no = no; QUOTE.meta.version = QUOTE.meta.version || r.version || ver || 1; QUOTE.meta.issuedAt = QUOTE.meta.issuedAt || r.issuedAt || ''; }""")

# 5. 담당자 로그인(dc_session)이 있으면 보안 코드 없이도 시작 (우리 시스템에서 열었을 때)
rep("""    try { var e = localStorage.getItem('secure_auth_expiry');""", """    try { if(localStorage.getItem('dc_session')) return true;
          var e = localStorage.getItem('secure_auth_expiry');""")

# 6. 발행 내역에서 찾은 경우에도 견적 번호를 넣는다 (/quote/ 가 저장한 견적은 meta 에 번호가 없다)
rep("""        if(!QUOTE.meta) QUOTE.meta = { no: no, version: hit.version || 1, issuedAt: hit.issuedAt || '' };""",
    """        if(!QUOTE.meta) QUOTE.meta = { no: no, version: hit.version || 1, issuedAt: hit.issuedAt || '' };
        if(!QUOTE.meta.no){ QUOTE.meta.no = no; QUOTE.meta.version = QUOTE.meta.version || hit.version || 1; QUOTE.meta.issuedAt = QUOTE.meta.issuedAt || hit.issuedAt || ''; }""")

# 7. 품목마다 일시불가 한 줄 (일반 구매 시 가격)
rep("    if(it.careType || EDIT) h += '<tr><th>서비스 유형</th>", '    /* 일시불가 — 같은 제품을 일반 구매로 살 때 가격 (2026-11-16 · /quote/ 가 품목마다 넘긴다 · 고칠 수 있다) */\n    if(num(it.lumpPrice) > 0 || EDIT) h += \'<tr><th>일시불가 <span style="font-weight:500;color:#666">(일반 구매 시)</span></th><td class="num">\' + (EDIT ? cell(p + \'lumpPrice\', num(it.lumpPrice)) : won(num(it.lumpPrice))) + \'</td></tr>\';\n    if(it.careType || EDIT) h += \'<tr><th>서비스 유형</th>')

# 8. 0원 아래 = 고객이 받는 금액 → '+' 로 (2026-11-17) — /quote/ 가 카드 청구할인을 월 구독료보다 크게 넘기는 경우 (예: 소형 냉장고 + 삼성카드 70만↑ 17,000원)
ZERO = [("  function won(v){ return fmt(v) + '원'; }", "  function won(v){ return (v < 0 ? '+' + fmt(-v) : fmt(v)) + '원'; }   // 0원 아래 = 고객이 받는 금액 → + (카드 청구할인이 구독료보다 큰 경우 등, 2026-11-17)"), ('    var finalP = Math.max(0, total - benefit) + preAdd;', '    var finalP = total - benefit + preAdd;'), ('    var afterCardM = Math.max(0, payM - cardMonthly);', '    var afterCardM = payM - cardMonthly;'), ('    var remainM = m > 0 ? Math.max(0, Math.round((total - sub - multi - pre - card - preAmt) / m)) : 0;', '    var remainM = m > 0 ? Math.round((total - sub - multi - pre - card - preAmt) / m) : 0;'), ('    var realM = m > 0 ? Math.max(0, Math.round((finalP - preAmt) / m)) : 0;', '    var realM = m > 0 ? Math.round((finalP - preAmt) / m) : 0;'), ('    T.finalP = Math.max(0, T.finalP - T.extra);', '    T.finalP = T.finalP - T.extra;'), ('      T.finalP = Math.max(0, T.finalP - T.reward);', '      T.finalP = T.finalP - T.reward;'), ('T.finalP = Math.max(0, T.finalP - T.pointCommon); }', 'T.finalP = T.finalP - T.pointCommon; }'), ('    var realM   = Math.max(0, Math.round(T.realM - (num(q.opt.pointCommon) || 0) / m));', '    var realM   = Math.round(T.realM - (num(q.opt.pointCommon) || 0) / m);'), ('won(Math.max(0, T.finalP - T.preAmt))', 'won(T.finalP - T.preAmt)'), ('won(Math.max(0, Math.round(T.afterCardM)))', 'won(Math.round(T.afterCardM))')]
for a, b in ZERO:
    if s.count(a) < 1: raise SystemExit('MISS: %r' % a[:80])
    s = s.replace(a, b); n += 1

# 9. 가격 조건 확인 표 (2026-11-17) — /quote/ 에서 체크한 조합(q.cmp)을 짧게 · 10. /quote/ [견적서] 탭 안에서 열기(?embed=1)
CMP_FN = '  /* 가격 조건 확인 (2026-11-17) — /quote/ 에서 상담사가 체크한 조합만 q.cmp 로 넘어온다. 총 지불 금액 비교만 짧게 */\n  function cmpHtml(q){ var c = q && q.cmp; if(!c || !c.length) return \'\';\n    var h = \'<div class="q-box q-cmp" style="margin-top:10px"><h3>📊 가격 조건 확인 <span style="font-weight:600;color:#666">(같은 제품 · 구독/일반 구매 조합별)</span></h3><table class="q-tbl" style="table-layout:fixed;width:100%"><colgroup><col style="width:34%"><col style="width:20%"><col style="width:20%"><col style="width:26%"></colgroup>\'\n      + \'<tr><th style="text-align:left;width:auto">구성</th><th style="width:auto;text-align:right">총 구독료</th><th style="width:auto;text-align:right">총 지불 금액</th><th style="width:auto;text-align:left">월 납부 금액</th></tr>\';\n    c.forEach(function(r){\n      h += \'<tr\' + (r.cur ? \' style="background:#FFF8E1"\' : \'\') + \'><td style="text-align:left"><b>\' + esc(r.label) + \'</b>\' + (r.cur ? \' <span style="color:#B45309;font-weight:700">· 이 견적</span>\' : \'\')\n        + \'<br><span style="font-size:.85em;color:#666">\' + esc(r.sub || \'\') + \'</span></td>\'\n        + \'<td class="num">\' + (r.subTotal > 0 ? won(r.subTotal) : \'—\') + \'</td>\'\n        + \'<td class="num"><b>\' + (r.total == null ? \'일시불가 미입력\' : won(r.total)) + \'</b></td>\'\n        + \'<td style="text-align:left;white-space:nowrap">\' + esc(r.mon || \'—\').replace(/\\n/g, \'<br>\') + \'</td></tr>\';\n    });\n    return h + \'</table></div>\'; }\n'
rep('    }\n    blocks.push(\'<div class="q-memo"><div class="t">', '    }\n    blocks.push(cmpHtml(q));   // 가격 조건 확인 (2026-11-17) — 블록은 한 요소씩 (paginate 가 첫 요소만 씀)\n    blocks.push(\'<div class="q-memo"><div class="t">')
rep("  function renderSheet(){", CMP_FN + "  function renderSheet(){")
rep('  whenAuthed(function initQuoteEntry(){\n    if(openFromUrl()) return;', "  /* /quote/ [견적서] 탭 안에서 열 때 (?embed=1 · 2026-11-17) — 지금 견적(저장 전 포함)을 받아 이 화면 기능 그대로 쓴다 */\n  var SH_EMBED = /[?&]embed=1/.test(location.search);\n  if(SH_EMBED){\n    window.addEventListener('message', function(e){\n      if(e.origin !== location.origin) return; var m = e.data || {}; if(m.t !== 'quote' || !m.d || !m.d.quote) return;\n      QUOTE = JSON.parse(JSON.stringify(m.d.quote)); normalizeQuote(QUOTE);\n      if(m.d.no){ QUOTE.meta = QUOTE.meta || {}; QUOTE.meta.no = m.d.no; QUOTE.meta.version = m.d.ver || QUOTE.meta.version || 1; }\n      EDIT = false; syncEditBtn();\n      if(m.d.counselor && !applyCounselorName(m.d.counselor)) PENDING_COUNSELOR = m.d.counselor;\n      renderAll();\n    });\n    try { window.parent.postMessage({ t: 'qready' }, location.origin); } catch(e){}\n  }\n  whenAuthed(function initQuoteEntry(){\n    if(SH_EMBED) return;                            // ⓪ /quote/ 견적서 탭 — 견적은 postMessage 로 온다\n    if(openFromUrl()) return;")

# 11. 견적서 탭 설정을 /quote/ 로 돌려보내기 (2026-11-18)
rep("      renderAll();\n    });\n    try { window.parent.postMessage({ t: 'qready' }, location.origin); } catch(e){}", "      renderAll();\n    });\n    /* 견적서에서 바꾼 설정을 /quote/ 로 돌려보냄 — /quote/ 가 견적에 담아 저장한다 (2026-11-18) */\n    var SH_BACK = '', SH_RENDER = renderSheet;\n    renderSheet = function(){ SH_RENDER(); try{\n      var o = QUOTE.opt || {}, c = QUOTE.cust || {};\n      var d = { opt: { show: o.show, qrType: o.qrType, pointMode: o.pointMode, lumpSum: o.lumpSum, namecardId: o.namecardId, rewardOn: o.rewardOn },\n                cust: { date: c.date || '', until: c.until || '', untilMode: c.untilMode || '' } };\n      var sig = JSON.stringify(d); if(sig === SH_BACK) return; SH_BACK = sig;\n      window.parent.postMessage({ t: 'sheetopt', d: d }, location.origin); }catch(e){} };\n    try { window.parent.postMessage({ t: 'qready' }, location.origin); } catch(e){}")

# 12. ⭐ 삼성전자 멤버십 포인트 크게 · 다품목 해당 0원 = 월 구독료에 반영 (2026-11-19 — /quote/ 는 월 구독료에 할인 포함해서 넘김)
for a, b in [("    + '.q-sum{display:grid;grid-template-columns:1.2fr 1fr;gap:10px;margin-top:8px;break-inside:avoid;page-break-inside:avoid;}'", "    + '.q-sum{display:grid;grid-template-columns:1.2fr 1fr;gap:10px;margin-top:8px;break-inside:avoid;page-break-inside:avoid;}'\n    + 'tr.q-pt td{color:#B45309 !important;font-weight:800 !important;} .ln.q-pt > *:last-child{color:#B45309;font-weight:800;}'   /* ⭐ 포인트 = 금액 색만 (2026-11-23 · 11-19 크게 강조는 뺌) */"), ("    if(pm === 'replace') h += discRow('⭐ 삼성전자 멤버십 포인트' + pmChip(), p + 'disc.point', c.point, EDIT ? '' : null, 'freq');\n    else h += '<tr><th>⭐ 삼성전자 멤버십 포인트'", '    if(pm === \'replace\') h += discRow(\'⭐ 삼성전자 멤버십 포인트\' + pmChip(), p + \'disc.point\', c.point, EDIT ? \'\' : null, \'freq\').replace(\'<tr>\', \'<tr class="q-pt">\');\n    else h += \'<tr class="q-pt"><th>⭐ 삼성전자 멤버십 포인트\''), ('if(c.point > 0 && pm === \'cash\') h += \'<div class="ln"><span>· ⭐ 삼성전자 멤버십 포인트', 'if(c.point > 0 && pm === \'cash\') h += \'<div class="ln q-pt"><span>· ⭐ 삼성전자 멤버십 포인트'), ("if(T.pointItems > 0) sumBox += '<tr><th>⭐ 삼성전자 멤버십 포인트", 'if(T.pointItems > 0) sumBox += \'<tr class="q-pt"><th>⭐ 삼성전자 멤버십 포인트'), ("if(EDIT || T.pointCommon > 0) sumBox += '<tr><th>⭐ 멤버십 포인트 공통", 'if(EDIT || T.pointCommon > 0) sumBox += \'<tr class="q-pt"><th>⭐ 멤버십 포인트 공통'), ("(c.multi > 0 ? '-' + won(c.multi) : '해당 (할인액 0원)')", "(c.multi > 0 ? '-' + won(c.multi) : '해당 (월 구독료에 반영)')")]:
    rep(a, b)

# 13. (2026-11-23) 금액 모두 오른쪽 정렬 · 매달 내시는 금액: 구독료 할인 칸 → 월 구독료 (할인 후) · 일반 구매로 내시는 금액 · 전체 비용 한눈에
#     · 공통 포인트를 입력 화면 이름 그대로(q.opt.pointParts) · /quote/ 견적서 탭(?embed=1): 쪽을 위아래로 · 크게 보기 때 옵션 패널 접기
rep("    + '.q-pay-grid .c.big .sub{font-size:9px;color:#5A6B85;margin-top:1px;white-space:nowrap;}'",
    "    + '.q-pay-grid .c.big .sub{font-size:9px;color:#5A6B85;margin-top:1px;white-space:nowrap;}'\n"
    "    + '.q-pay-grid .c{text-align:right;} .q-tbl:not(.q-cust) td:not(:first-child){text-align:right !important;}'   /* 금액 모두 오른쪽 정렬 (2026-11-23) */\n"
    "    + '.q-pay.l{border-color:#7A4B1E;} .q-pay.l .q-pay-h{background:#7A4B1E;} .q-pay.l .q-pay-grid{background:#E5D5C3;} .q-pay.l .q-pay-grid .c.big{background:#F6EEE4;} .q-pay.l .q-pay-grid .c.big .k,.q-pay.l .q-pay-grid .c.big .v{color:#7A4B1E;}'\n"
    "    + '.q-pay.all{border-color:#0F1E3D;} .q-pay.all .q-pay-h{background:#0F1E3D;} .q-pay.all .q-pay-grid .c.big{background:#EEF1F7;} .q-pay.all .q-pay-grid .c.big .k,.q-pay.all .q-pay-grid .c.big .v{color:#0F1E3D;} .q-pay.all .v.plus{color:#1E7A4C;}'")
rep("    + '.q-pages .q-page{margin:0;flex:0 0 auto;}'",
    "    + '.q-pages .q-page{margin:0;flex:0 0 auto;}'\n    + 'html.sh-embed .q-pages{flex-direction:column;}'   /* 견적서 탭 안: 2쪽이 옆으로 숨지 않게 위아래로 (2026-11-23) */")
rep("    if(discM > 0){ cells += c('구독료 할인 (월 환산)', '-' + won(discM), 'minus'); n++; }",
    "    if(discM > 0){ cells += c('월 구독료 (할인 후)', won(monthly - discM)); n++; }   // 할인 금액 대신 할인 후 월 구독료 — 입력 화면 용어 (2026-11-23)")
BANDS = r"""  /* 일반 구매로 내시는 금액 · 전체 비용 한눈에 (2026-11-23) — 매달 내시는 금액 밴드 아래 */
  function bandCell(k, v, cls, sub){
    return '<div class="c' + (cls === 'big' ? ' big' : '') + '"><div class="k">' + k + '</div>'
      + '<div class="v' + (cls === 'minus' ? ' minus' : '') + '">' + v + '</div>' + (sub ? '<div class="sub">' + sub + '</div>' : '') + '</div>';
  }
  function lumpBandHtml(q){
    var L = q.lump; if(!L || !L.items || !L.items.length) return '';
    var ins = num(L.months) > 0 && num(L.per) > 0, cells = '', n = 0;
    cells += bandCell('결제가', won(L.amount)); n++;
    if(num(L.fee) > 0){ cells += bandCell('이용료', '+' + won(L.fee)); n++; }
    if(num(L.benefit) > 0){ cells += bandCell('혜택 합계', '-' + won(L.benefit), 'minus'); n++; }
    if(ins){ cells += bandCell('할부 개월수별 납부금액', won(L.per) + ' × ' + num(L.months)); n++; }
    cells += bandCell('일반 최종가 (최종체감가)', won(L.net), 'big', ins ? num(L.months) + '개월 할부' : '일시불 · 할부 합계'); n++;
    return '<div class="q-pay l"><div class="q-pay-h">🛒 고객님이 일반 구매(일시불 · 할부)로 내시는 금액'
      + '<span class="r">' + esc(L.kindLabel || '') + ' · 상품 ' + L.items.length + '개</span></div>'
      + '<div class="q-pay-grid" style="grid-template-columns:repeat(' + (n - 1) + ',1fr) 1.3fr">' + cells + '</div>'
      + '<div class="q-pay-note">※ 일반 최종가는 청구할인 · 캐시백 · 포인트까지 반영한 금액입니다.</div></div>';
  }
  function allBandHtml(q, T){
    var L = q.lump; if(!L || !L.items || !L.items.length || !T.count) return '';
    var P = periodSegments(q), netM = P.segs.length ? Math.round(P.segs[0].net) : 0;
    var benS = num(T.benefit) + num(T.pointCommon), ben = benS + num(L.benefit), all = num(T.finalP) + num(L.net);
    var cells = bandCell('구독 월 비용', won(netM) + ' / 월', '', T.maxM + '개월 · 구독 최종가 ' + won(T.finalP))
      + bandCell('일반 구매', won(L.net), '', '일반 최종가')
      + bandCell('받은 혜택', '-' + won(ben), 'minus', '구독 ' + won(benS) + ' · 일반 ' + won(L.benefit))
      + bandCell('전체 비용', won(all), 'big', '구독 최종가 + 일반 최종가');
    return '<div class="q-pay all"><div class="q-pay-h">🧾 전체 비용 한눈에<span class="r">구독 ' + T.count + '개 · 일반 ' + L.items.length + '개</span></div>'
      + '<div class="q-pay-grid" style="grid-template-columns:repeat(3,1fr) 1.3fr">' + cells + '</div>'
      + '<div class="q-pay-note">※ 받은 혜택 = 구독 할인 · 제휴카드 청구할인 · 포인트 + 일반 구매 청구할인 · 캐시백 · 포인트</div></div>';
  }
"""
rep("  function payBandHtml(q, T){", BANDS + "  function payBandHtml(q, T){")
rep("    blocks.push(payBand);          // ★ 매달 내시는 금액 (한눈에 보기)",
    "    blocks.push(payBand);          // ★ 매달 내시는 금액 (한눈에 보기)\n    if(S.payband !== false){ blocks.push(lumpBandHtml(q)); blocks.push(allBandHtml(q, T)); }   // 일반 구매로 내시는 금액 · 전체 비용 (2026-11-23)")
rep("      if(EDIT || T.pointCommon > 0) sumBox += '<tr class=\"q-pt\"><th>⭐ 멤버십 포인트 공통",
    "      var PP = q.opt.pointParts || [], PPsum = PP.reduce(function(a, x){ return a + num(x.amount); }, 0);   // 입력 화면 [견적 공통 - 포인트] 이름 그대로 (2026-11-23)\n"
    "      if(!EDIT && T.pointCommon > 0 && PP.length && PPsum === T.pointCommon) PP.forEach(function(x){ if(num(x.amount) > 0) sumBox += '<tr class=\"q-pt\"><th>' + esc(x.label) + ' <span style=\"font-weight:500;color:#666\">(' + (pm === 'replace' ? '차감' : '별도 적립') + ')</span></th><td class=\"num\">-' + won(x.amount) + '</td></tr>'; });\n"
    "      else if(EDIT || T.pointCommon > 0) sumBox += '<tr class=\"q-pt\"><th>⭐ 멤버십 포인트 공통")
rep("  var SH_EMBED = /[?&]embed=1/.test(location.search);\n  if(SH_EMBED){\n",
    "  var SH_EMBED = /[?&]embed=1/.test(location.search);\n  if(SH_EMBED){\n"
    "    document.documentElement.classList.add('sh-embed');\n"
    "    window.addEventListener('message', function(e){ if(e.origin !== location.origin) return; var m = e.data || {}; if(m.t !== 'panel') return;   // /quote/ [크게 보기] — 옵션 패널 접기·펴기 (2026-11-23)\n"
    "      var md = document.getElementById('quoteModal'); if(md){ md.classList.toggle('panel-off', !!m.off); setTimeout(fitScale, 0); } });\n")

# 14. (2026-11-23) [편집하기] 때 일반 구매 금액도 고치기 — 품목 결제가 · 이용료 · 청구할인 · 캐시백(송금) · 포인트 · 조건부 캐시백 · 추가혜택
#     고친 만큼만 혜택 합계 · 일반 최종가 · 할부 월 금액에 더하고 뺀다 (처음 받은 값 L._b 기준 — /quote/ 계산과 어긋나지 않게)
rep("  function lumpBandHtml(q){\n    var L = q.lump; if(!L || !L.items || !L.items.length) return '';\n",
    "  /* 일반 구매 금액 다시 맞추기 (2026-11-23) — 견적서에서 고친 칸만큼 혜택 합계 · 일반 최종가 · 할부 월 금액을 바꾼다 */\n"
    "  var LUMP_BEN = ['bill', 'ptRest', 'ptD', 'ptS', 'sPoint', 'jPoint', 'typePoint', 'member', 'cashback'];\n"
    "  function lumpRecalc(L){\n"
    "    if(!L || !L.items) return;\n"
    "    if(!L._b){ L._b = { amount: num(L.amount), fee: num(L.fee), benefit: num(L.benefit), net: num(L.net), per: num(L.per), r: {}, x: (L.extras || []).map(function(e){ return num(e.amount); }) };\n"
    "      LUMP_BEN.forEach(function(k){ L._b.r[k] = num(L[k]); }); }\n"
    "    var b = L._b, amt = L.items.reduce(function(a, x){ return a + num(x.amount); }, 0), dB = 0;\n"
    "    LUMP_BEN.forEach(function(k){ dB += num(L[k]) - b.r[k]; });\n"
    "    (L.extras || []).forEach(function(e, i){ dB += num(e.amount) - (b.x[i] || 0); });\n"
    "    var dA = amt - b.amount, dF = num(L.fee) - b.fee;\n"
    "    L.amount = amt; L.benefit = Math.max(0, b.benefit + dB); L.net = L.amount + num(L.fee) - L.benefit;\n"
    "    if(num(L.months) > 0) L.per = Math.max(0, Math.round(b.per + (dA + dF - (num(L.bill) - b.r.bill)) / num(L.months)));\n"
    "  }\n"
    "  function lumpRow(l, path, v, cls){ if(!EDIT && !(num(v) > 0)) return '';\n"
    "    return '<tr' + (cls ? ' class=\"' + cls + '\"' : '') + '><th>' + l + '</th><td class=\"num\">' + (EDIT ? cell(path, v) : '-' + won(v)) + '</td></tr>'; }\n"
    "  function lumpBandHtml(q){\n    var L = q.lump; if(!L || !L.items || !L.items.length) return ''; lumpRecalc(L);\n")
rep("""      var L = q.lump, lb = '<div class="q-box"><h3>💳 일반 구매'""",
    """      var L = q.lump; lumpRecalc(L); var lb = '<div class="q-box"><h3>💳 일반 구매'""")
rep("""'</th><td class="num">' + won(x.amount) + '</td></tr>'; });
      lb += '<tr class="tot"><th>결제가</th>""",
    """'</th><td class="num">' + (EDIT ? cell('lump.items.' + i + '.amount', x.amount) : won(x.amount)) + '</td></tr>'; });
      if(EDIT) lb += '<tr class="no-print"><td colspan="2" class="q-fxnote" style="text-align:left">✏️ 일반 구매 금액을 고치면 혜택 합계 · 일반 최종가가 다시 계산됩니다 (입력 화면에는 돌아가지 않음)</td></tr>';
      lb += '<tr class="tot"><th>결제가</th>""")
rep("""      if(num(L.fee) > 0) lb += '<tr><th>이용료</th><td class="num">+' + won(L.fee) + '</td></tr>';
      if(num(L.bill) > 0) lb += '<tr><th>청구할인</th><td class="num">-' + won(L.bill) + '</td></tr>';
      if(L.ptD != null){""",
    """      if(EDIT || num(L.fee) > 0) lb += '<tr><th>이용료</th><td class="num">' + (EDIT ? cell('lump.fee', L.fee) : '+' + won(L.fee)) + '</td></tr>';
      lb += lumpRow('청구할인', 'lump.bill', L.bill);
      if(L.ptD != null && EDIT){
        lb += lumpRow('캐시백(송금)', 'lump.ptRest', L.ptRest) + lumpRow('⭐ 삼성전자 포인트 합계', 'lump.ptD', L.ptD, 'q-pt') + lumpRow('⭐ 추가 포인트 (구독료 지원)', 'lump.ptS', L.ptS, 'q-pt');
      } else if(L.ptD != null){""")
rep("""      if(num(L.cashback) > 0) lb += '<tr><th>조건부 캐시백</th><td class="num">-' + won(L.cashback) + '</td></tr>';
      (L.extras || []).forEach(function(x){ if(num(x.amount) > 0) lb += '<tr><th>' + esc(x.label || '추가혜택') + '</th><td class="num">-' + won(x.amount) + '</td></tr>'; });""",
    """      lb += lumpRow('조건부 캐시백', 'lump.cashback', L.cashback);
      (L.extras || []).forEach(function(x, i){ lb += lumpRow(esc(x.label || '추가혜택'), 'lump.extras.' + i + '.amount', x.amount); });""")

# 15. (2026-11-23) [편집하기] 때 일반 구매 혜택 합계 · 일반 최종가도 직접 수정 — 결제가(원래 가격) − 혜택 합계 = 일반 최종가
#     혜택 합계를 넣으면 최종가가, 최종가를 넣으면 혜택 합계가 맞춰진다 · 그 뒤 위 줄(품목 금액 · 혜택 줄)을 고치면 직접 넣은 값은 풀리고 다시 자동 합계
rep("    if(num(L.months) > 0) L.per = Math.max(0, Math.round(b.per + (dA + dF - (num(L.bill) - b.r.bill)) / num(L.months)));\n",
    "    if(num(L.months) > 0) L.per = Math.max(0, Math.round(b.per + (dA + dF - (num(L.bill) - b.r.bill)) / num(L.months)));\n"
    "    var sig = amt + '|' + num(L.fee) + '|' + dB;\n"
    "    if(b.sig != null && b.sig !== sig){ delete L.benM; delete L.netM; }   // 위 줄을 고쳤다 — 직접 넣은 합계는 풀고 다시 자동\n"
    "    else if(L.benM != null && L.benM !== b.pb) delete L.netM;             // 방금 혜택 합계를 넣었다\n"
    "    else if(L.netM != null && L.netM !== b.pn) delete L.benM;             // 방금 일반 최종가를 넣었다\n"
    "    b.sig = sig; b.pb = L.benM; b.pn = L.netM;\n"
    "    if(L.benM != null){ L.benefit = Math.max(0, num(L.benM)); L.net = L.amount + num(L.fee) - L.benefit; }\n"
    "    else if(L.netM != null){ L.net = Math.max(0, num(L.netM)); L.benefit = Math.max(0, L.amount + num(L.fee) - L.net); }\n"
    "    L.manual = (L.benM != null || L.netM != null);\n")
rep("""      lb += '<tr class="ben"><th>혜택 합계</th><td class="num">-' + won(L.benefit) + '</td></tr>';""",
    """      lb += '<tr class="ben"><th>혜택 합계' + (EDIT ? ' <span class="q-fxnote">' + (L.manual ? '직접 입력' : '자동 · 직접 수정 가능') + '</span>' : '') + '</th><td class="num">' + (EDIT ? cell('lump.benM', L.benefit) : '-' + won(L.benefit)) + '</td></tr>';""")
rep("""+ '</th><td class="num">' + won(L.net) + '</td></tr>';""",
    """+ (EDIT ? ' <span class="q-fxnote">결제가 − 혜택 합계 · 직접 수정 가능</span>' : '') + '</th><td class="num">' + (EDIT ? cell('lump.netM', L.net) : won(L.net)) + '</td></tr>';""")

# 16. (2026-11-23) 혜택 합계 · 일반 최종가를 직접 넣었으면(통합 혜택가) 견적서에는 혜택 줄(청구할인 · 캐시백 · 포인트 · 조건부 캐시백 · 추가혜택)을 내지 않는다 — 편집 화면에서는 그대로 보이고, 고치면 다시 자동 합계
rep("    L.manual = (L.benM != null || L.netM != null);\n", "    L.manual = (L.benM != null || L.netM != null); LUMP_MAN = L.manual;\n")
rep("  function lumpRow(l, path, v, cls){ if(!EDIT && !(num(v) > 0)) return '';\n", "  var LUMP_MAN = false;\n  function lumpRow(l, path, v, cls){ if(!EDIT && (LUMP_MAN || !(num(v) > 0))) return '';\n")
rep("      } else if(L.ptD != null){", "      } else if(L.manual && !EDIT){\n      } else if(L.ptD != null){")
rep("' + (L.manual ? '직접 입력' : '자동 · 직접 수정 가능') + '", "' + (L.manual ? '직접 입력 · 견적서에는 위 혜택 줄 없이 합계만' : '자동 · 직접 수정 가능') + '")

def save(p, t):
    if CR: t = t.replace('\n', '\r\n')
    io.open(p, 'w', encoding='utf-8', newline='').write(t)
save(out_godo, s)

# 우리 시스템용: 고도몰 주석 줄 제거 · 보안 코드 잠금 → 담당자 로그인 확인
d = s
assert d.startswith('{***'); d = d[d.index('\n') + 1:]
a = d.index('<!-- ═══ 보안 잠금 오버레이'); z = d.index('</script>', a) + len('</script>')
assert 'verifySecureCode' in d[a:z] and d.count('verifySecureCode') == d[a:z].count('verifySecureCode')
LOCK = """<!-- 담당자 로그인 확인 (우리 시스템 판) — 담당자 화면과 같은 로그인(dc_session)이 있어야 열린다. 서버가 호출마다 다시 확인한다 -->
<div id="secure-lock-overlay">
  <div class="secure-box">
    <i class="fa-solid fa-lock"></i>
    <h2>담당자 로그인 필요</h2>
    <p>내부 상담 전용 페이지입니다.<br>담당자 화면 로그인 후 이용</p>
    <a class="secure-btn" href="/store.html" style="display:inline-block;text-decoration:none;line-height:2.6">담당자 화면으로</a>
  </div>
</div>
<script type="text/javascript">
    window.SH_CODE = '';
    (function(){ var ses = ''; try { ses = localStorage.getItem('dc_session') || ''; } catch(e){}
      if(ses){ var o = document.getElementById('secure-lock-overlay'); if(o) o.remove(); } })();
</script>"""
d = d[:a] + LOCK + d[z:]
assert 'secureKey' not in d
save(out_dc, d)
print('edits', n, 'godo', len(s), 'dc', len(d))
