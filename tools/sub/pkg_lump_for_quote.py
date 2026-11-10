# -*- coding: utf-8 -*-
"""본사 "N월 스마트 패키지" 엑셀(SDP 시트) → quote/index.html 의 PKG_ALL 줄 (일반 구매 품목도 품목 수에 넣기 위한 모델표 · 2026-11-09)
  python tools/sub/pkg_lump_for_quote.py "<11월 스마트 패키지.xlsx>" 2026-11 quote/index.html
  → 그 뒤 python tools/sub/make_quote_test.py 로 시험판도 다시 만든다.

배포 정책(sub.policy bundle)에는 구독 대상 모델만 있어, 일반 구매 대상은 이 표로 본다. 매달 표가 바뀌면 다시 돌린다.
PKG_ALL.ym 이 정책 bundle.from 의 달과 다르면 화면은 일반 구매를 품목 수에 넣지 않는다.
  cats     = 품목 수 혜택 일반 대상 (요약표 일반 칸이 비어 있는 품목 = 정수기·PC(구독)·태블릿(구독) 은 뺀다)
  bonus    = 『3만 혜택』 모델 (일반 구매일 때 3만P · 품목 수에는 안 들어감)
  subBonus = 『3만 혜택』 중 노란 음영 = 구독이면 품목 수에 들어가는 모델"""
import sys, io, re, json, collections
import openpyxl

src, ym, html = sys.argv[1], sys.argv[2], sys.argv[3]
ws = openpyxl.load_workbook(src, data_only=True)['SDP']
lump_ok = {}
for r in range(8, 40):
    c = ws.cell(r, 3).value
    if c and str(c).strip() != '합계': lump_ok[str(c).strip()] = ws.cell(r, 4).value
cats, bonus, yellow = collections.OrderedDict(), collections.OrderedDict(), []
for r in range(8, ws.max_row + 1):
    k, m = ws.cell(r, 11).value, ws.cell(r, 13).value
    if m and k and k != '필터' and lump_ok.get(str(k).strip()):
        cats.setdefault(str(k).strip(), []).append(str(m).strip().upper())
    p, q, rr = (ws.cell(r, c).value for c in (16, 17, 18))
    if rr and q and p and p != '필터':
        code = str(rr).strip().upper(); bonus.setdefault(str(p).strip(), []).append(code)
        if ws.cell(r, 18).fill.fill_type == 'solid': yellow.append(code)
n = sum(len(v) for v in cats.values())
want = sum(v for v in lump_ok.values() if v)
if n != want: sys.exit('일반 대상 수가 요약표와 다릅니다: %d != %d' % (n, want))
data = {'ym': ym, 'cats': {k: ','.join(v) for k, v in cats.items()}, 'bonus': {k: ','.join(v) for k, v in bonus.items()}, 'subBonus': ','.join(yellow)}
line = 'const PKG_ALL=' + json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';'
s = io.open(html, encoding='utf-8', newline='').read()
s2, k = re.subn(r'/\*PKG_ALL\*/.*?/\*/PKG_ALL\*/', lambda m: '/*PKG_ALL*/' + line + '/*/PKG_ALL*/', s, flags=re.S)
if k != 1: sys.exit('표식(/*PKG_ALL*/)을 찾지 못했습니다')
io.open(html, 'w', encoding='utf-8', newline='').write(s2)
print('일반 대상 %d · 품목 %d · 3만 혜택 %d · 구독 시 품목 수 포함 %d' % (n, len(cats), sum(len(v) for v in bonus.values()), len(yellow)))
