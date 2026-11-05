# -*- coding: utf-8 -*-
"""/quote/ 시험판 만들기 — 운영 DB 를 건드리지 않고 아직 안 넣은 정책을 화면에 심어 본다 (2026-11-04)
  python tools/sub/make_quote_test.py            → quote/test/index.html
심는 것: sql/mvp_276_consult_quote.sql 의 'lump' 정책(일시불 혜택 구간표) · sql/mvp_277_sub_promo_202611.sql 의 행사 줄(11월 구독료 지원 행사모델)
다른 점: 담당자 로그인 없이도 보인다(저장·내역·보내기는 안 됨) · 위에 '시험판' 띠. 두 SQL 을 운영에 넣은 뒤에는 이 파일이 필요 없다."""
import io, re, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
src = io.open(os.path.join(ROOT, 'quote', 'index.html'), encoding='utf-8').read()

lump = json.loads(re.search(r"\$j\$\s*(\{.*?\})\s*\$j\$", io.open(os.path.join(ROOT, 'sql', 'mvp_276_consult_quote.sql'), encoding='utf-8').read(), re.S).group(1))
promos = []
for m in re.finditer(r"select sub\.f_promo_save\('(.*?)'::jsonb", io.open(os.path.join(ROOT, 'sql', 'mvp_277_sub_promo_202611.sql'), encoding='utf-8').read(), re.S):
    d = json.loads(m.group(1).replace("''", "'"))
    p = {'text': d['text'], 'from': d['from'], 'to': d['to'], 'months': d['months'], 'models': d['models']}   # 배포 sub_policy.js 와 같은 꼴 (maxTerm true 는 생략)
    promos.append(p)

inject = ("\n/* ── 시험판: 운영 DB 에 아직 없는 정책을 심는다 (tools/sub/make_quote_test.py · mvp_276 lump · mvp_277 행사 %d줄) ── */\n"
          "window.QUOTE_TEST_POLICY=%s;\n"
          "function applyTestPolicy(){ const P=window.SUB_POLICY; if(!P) return; const T=window.QUOTE_TEST_POLICY; if(!P.lump) P.lump=T.lump;\n"
          "  const has=new Set((P.promos||[]).map(x=>x.text)), add=T.promos.filter(x=>!has.has(x.text)); P.promos=(P.promos||[]).concat(add); if(P.promosAll) P.promosAll=P.promosAll.concat(add); }   /* 운영에 이미 있는 줄은 다시 심지 않는다 (2026-11-05 mvp_276·277 운영 반영) */\n"
          % (len(promos), json.dumps({'lump': lump, 'promos': promos}, ensure_ascii=False, separators=(',', ':'))))

out = src
def rep(a, b):
    global out
    assert out.count(a) == 1, a[:60]
    out = out.replace(a, b)
rep("const ON_DC = /(^|\\.)samsungat\\.co\\.kr$/.test(location.hostname);", "const ON_DC = false;   /* 시험판: 요금표는 늘 데이터센터 주소에서 */")
rep("    window.SUB_TAB_CONFIG={ apiOnly:true, dataBase:SDP_BASE, noVer:true };", "    applyTestPolicy();\n    window.SUB_TAB_CONFIG={ apiOnly:true, dataBase:SDP_BASE, noVer:true };")
rep("/* ═══ 상태 ═══ */", inject + "\n/* ═══ 상태 ═══ */")
rep("  showLogin(''); return false;\n}", "  $('meLbl').textContent='시험판 · 로그인 없이 보기 (저장·보내기 안 됨)'; return false;\n}")
rep("<body>", "<body>\n<div style=\"background:#b45309;color:#fff;font-size:13px;font-weight:700;text-align:center;padding:6px 10px\">시험판 — 로그인 없이 보는 화면입니다 (11월 일시불 혜택표·구독료 지원 행사모델은 2026-11-05 운영 반영됨) · 저장·보내기는 안 됩니다</div>")
rep("<title>상담 견적 · 삼성스토어 시흥</title>", "<title>[시험판] 상담 견적 · 삼성스토어 시흥</title>")

dst = os.path.join(ROOT, 'quote', 'test', 'index.html')
os.makedirs(os.path.dirname(dst), exist_ok=True)
io.open(dst, 'w', encoding='utf-8').write(out)
print('-> quote/test/index.html · lump keys %d · promos %d · models %d' % (len(lump), len(promos), sum(len(p['models']) for p in promos)))
