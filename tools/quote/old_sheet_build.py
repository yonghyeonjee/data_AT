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
      lb += '<tr class="tot"><th>① 결제가</th><td class="num">' + won(L.amount) + '</td></tr>';
      if(num(L.fee) > 0) lb += '<tr><th>이용료</th><td class="num">+' + won(L.fee) + '</td></tr>';
      if(num(L.bill) > 0) lb += '<tr><th>청구할인</th><td class="num">-' + won(L.bill) + '</td></tr>';
      if(num(L.sPoint) > 0) lb += '<tr><th>금액별 S포인트</th><td class="num">-' + won(L.sPoint) + '</td></tr>';
      if(num(L.jPoint) > 0) lb += '<tr><th>DPS 포인트 (패키지·제휴할부 제외)</th><td class="num">-' + won(L.jPoint) + '</td></tr>';
      if(num(L.typePoint) > 0) lb += '<tr><th>' + esc(L.typeLabel || '포인트') + '</th><td class="num">-' + won(L.typePoint) + '</td></tr>';
      if(num(L.cashback) > 0) lb += '<tr><th>조건부 캐시백</th><td class="num">-' + won(L.cashback) + '</td></tr>';
      if(num(L.member) > 0) lb += '<tr><th>기본멤버십P 0.1%</th><td class="num">-' + won(L.member) + '</td></tr>';
      (L.extras || []).forEach(function(x){ if(num(x.amount) > 0) lb += '<tr><th>' + esc(x.label || '추가혜택') + '</th><td class="num">-' + won(x.amount) + '</td></tr>'; });
      lb += '<tr class="ben"><th>혜택 합계</th><td class="num">-' + won(L.benefit) + '</td></tr>';
      lb += '<tr class="tot"><th>최종체감가' + (num(L.per) > 0 ? ' <span style="font-weight:600;font-size:.9em">(월 ' + won(L.per) + ' × ' + num(L.months) + ')</span>' : '') + '</th><td class="num">' + won(L.net) + '</td></tr>';
      var T0 = calcTotals(q);
      lb += '<tr class="fin"><th>전체 최종가 <span style="font-weight:600;font-size:.85em">(구독 최종 혜택가 ' + won(T0.finalP) + ' + 일반 최종체감가)</span></th><td class="num">' + won(T0.finalP + num(L.net)) + '</td></tr>';
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
