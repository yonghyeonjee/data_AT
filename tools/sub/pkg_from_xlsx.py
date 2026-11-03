# -*- coding: utf-8 -*-
"""본사 "스마트 패키지" 엑셀(SDP 시트) → sub.pkg_model 넣는 SQL (mvp_264 · 2026-11-03)
  python tools/sub/pkg_from_xlsx.py "C:/…/11월 스마트 패키지.xlsx" [출력.sql]
시트 모양: K~N 열 = 품목 · 모델군 · 모델명 · 구독 대상여부('구독') — 품목 수 혜택 대상 모델
          P~R 열 = 『3만 혜택』 모델 (품목 · 모델군 · 모델명) — 일반 구매 때만 3만P (구독 계산에는 안 쓴다)
          H~I 열 = 품목 수 → 혜택(만원) — 정책 bundle.tiers 로 (sub.policy · 관리자 화면에서도 고친다)
만든 SQL 은 select sub.f_pkg_import(…, true, '…') 한 줄 — 목록에 없는 기존 모델은 active=false 가 된다 (MCP execute_sql 로 실행)."""
import sys, io, json, openpyxl

def read(path):
    wb = openpyxl.load_workbook(path, data_only=True); ws = wb['SDP']
    tiers = {}
    for r in range(9, 60):
        h, i = ws.cell(r, 8).value, ws.cell(r, 9).value
        if isinstance(h, (int, float)) and i is not None: tiers[int(h)] = int(i) * 10000
    rows, bonus = [], []
    for r in range(8, ws.max_row + 1):
        k, l, m, n = (ws.cell(r, c).value for c in (11, 12, 13, 14))
        if m and k: rows.append({'model': str(m).strip().upper(), 'cat': str(k).strip(), 'grp': str(l or '').strip(), 'sub_ok': (str(n or '').strip() == '구독')})
        p, q, rr = (ws.cell(r, c).value for c in (16, 17, 18))
        if rr and q and p: bonus.append({'model': str(rr).strip().upper(), 'cat': str(p).strip(), 'grp': str(q).strip()})
    bset = {b['model'] for b in bonus}
    have = {r['model'] for r in rows}
    for b in bonus:
        if b['model'] not in have: rows.append({'model': b['model'], 'cat': b['cat'], 'grp': b['grp'], 'sub_ok': False})
    for r in rows: r['bonus'] = r['model'] in bset
    return tiers, rows

def sql_of(rows, by='pkg_from_xlsx'):
    q = lambda s: "'" + str(s).replace("'", "''") + "'"
    parts = ["jsonb_build_object('model',%s,'cat',%s,'grp',%s,'sub_ok',%s,'bonus',%s)" % (q(r['model']), q(r['cat']), q(r['grp']), 'true' if r['sub_ok'] else 'false', 'true' if r['bonus'] else 'false') for r in rows]
    return "select sub.f_pkg_import(jsonb_build_array(\n" + ",\n".join(parts) + "\n), true, " + q(by) + ");\n"

if __name__ == '__main__':
    src = sys.argv[1]; dst = sys.argv[2] if len(sys.argv) > 2 else None
    tiers, rows = read(src)
    out = sql_of(rows, 'mvp_264')
    sys.stdout.write("tiers: %s\nmodels %d · 구독 대상 %d · 3만 혜택 %d\n" % (json.dumps(tiers), len(rows), sum(1 for r in rows if r['sub_ok']), sum(1 for r in rows if r['bonus'])))
    if dst: io.open(dst, 'w', encoding='utf-8').write(out); sys.stdout.write('-> %s\n' % dst)
