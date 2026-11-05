# -*- coding: utf-8 -*-
"""본사 "□ N월 구독료 지원 행사모델 리스트" 엑셀 → sub.promo 행사 줄 SQL (2026-11-04)
  python tools/sub/promo_from_xlsx.py <리스트.xlsx 또는 .tsv> 2026-11 [출력.sql] [--to 2026-11-30] [--note '배송 27.02.28까지']

시트 모양(10월·11월 판 동일): B열부터 구분 · 품목1 · 품목2 · 계약 기간(년) · 서비스 주기 · 모델코드 · 총 구독료 · 월구독료 · 케어구분 · 케어유형 · 지원유형(Type1~5) · 포인트지원
  Type 범례(시트 오른쪽 S~U 열): Type1 6년 계약시 6개월 · Type2 6년 3개월 · Type3 5년 6개월 · Type4 4년 6개월 · Type5 4년 3개월
  포인트지원 = 월구독료 × 지원개월 (케어별 줄마다) — 화면 sub_tab.js 가 months × 선택 요금제 월 구독료로 같은 값을 낸다 (maxTerm: 최장 약정에서만)
  둘째 시트 '모델'(품목 · 모델명 · 지원개월) 은 첫 시트에 없는 모델(PC·Tab 등)만 보탠다.

DRM(NASCA) 파일은 openpyxl 로 못 읽는다 → Excel 로 열어 TSV 로 뽑은 파일을 넣는다 (tools/sub/README.md "구독료 지원 행사모델" 참고).
  TSV 첫 줄 '#origin<TAB>행<TAB>열<TAB>시트' 는 건너뛴다. 시트 하나당 파일 하나 — 둘째 시트는 같은 이름에 _s2.tsv 를 붙여 두면 같이 읽는다.

만든 SQL: 같은 달(note 'promo_xlsx:YYYYMM:%')의 예전 줄은 active=false 로 두고, (약정 년 · 지원 개월) 묶음마다 sub.f_promo_save 한 줄씩 넣는다.
  → 저장 트리거(mvp_255)가 sub_policy.js promos[] 로 배포 → 구독센터·상품 구독탭·/quote/ 견적서가 같은 금액을 쓴다. 실행은 MCP execute_sql 로 (DB 변경은 승인 뒤)."""
import sys, io, os, re, json, collections

TYPE = {'Type1': (6, 6), 'Type2': (6, 3), 'Type3': (5, 6), 'Type4': (4, 6), 'Type5': (4, 3)}   # 지원유형 → (약정 년, 지원 개월)
MODEL = re.compile(r'^[A-Z0-9][A-Z0-9\-]{4,}$')


def rows_of_tsv(path):
    L = [l.rstrip('\n').split('\t') for l in io.open(path, encoding='utf-8-sig')]
    return [r for r in L if not (r and r[0].startswith('#origin'))]


def rows_of_xlsx(path):
    import openpyxl
    wb = openpyxl.load_workbook(path, data_only=True)
    out = []
    for ws in wb.worksheets:
        rows = []
        for r in ws.iter_rows(min_col=2 if ws.title != '모델' else 1, values_only=True):
            rows.append(['' if v is None else str(v).replace('\n', ' ') for v in r])
        out.append(rows)
    return out


def parse(sheets):
    """sheets = [첫 시트 줄들, (둘째 시트 줄들)] → {model: (years, months, cat)}, legend"""
    s1 = sheets[0]
    legend = {}
    for r in s1[:15]:
        for i, c in enumerate(r):
            if re.match(r'^Type\d$', c or '') and i + 2 < len(r) and re.search(r'(\d)년.*?(\d)개월', r[i + 1] or ''):
                m = re.search(r'(\d)년.*?(\d)개월', r[i + 1]); legend[c] = (int(m.group(1)), int(m.group(2)))
    legend = legend or TYPE
    models, bad = {}, []
    for r in s1:
        if len(r) < 12: continue
        code = (r[5] or '').strip().upper()
        if not MODEL.match(code) or code == '모델코드': continue
        t = (r[10] or '').strip()
        if t not in legend: bad.append((code, t)); continue
        y, n = legend[t]
        try:
            if r[7] and r[11] and abs(float(r[7]) * n - float(r[11])) > 1: bad.append((code, 'point≠monthly×N'))
        except ValueError: pass
        prev = models.get(code)
        if prev and prev[:2] != (y, n): bad.append((code, 'type differs across rows'))
        models[code] = (y, n, (r[1] or '').strip())
    extra = 0
    if len(sheets) > 1:
        for r in sheets[1]:
            if len(r) < 3: continue
            code = (r[1] or '').strip().upper()
            if not MODEL.match(code) or code in models: continue
            try: n = int(float(r[2]))
            except ValueError: continue
            models[code] = (0, n, (r[0] or '').strip()); extra += 1
    return models, legend, bad, extra


def sql_of(models, ym, frm, to, note, by):
    q = lambda s: "'" + str(s).replace("'", "''") + "'"
    groups = collections.defaultdict(list)
    for m, (y, n, cat) in models.items(): groups[(y, n)].append(m)
    mm = int(ym[-2:])
    out = ["-- 구독료 지원 행사모델 %s · 모델 %d · 묶음 %d (tools/sub/promo_from_xlsx.py)" % (ym, len(models), len(groups)),
           "update sub.promo set active = false, updated_by = %s, updated_at = now() where note like %s and active;" % (q(by), q('promo_xlsx:%s:%%' % ym))]
    sort = 20
    for (y, n), ms in sorted(groups.items(), key=lambda kv: (-kv[0][0], -kv[0][1])):
        ms.sort()
        text = '%d월 구독료 지원 · %s %d개월 구독료 상당 포인트%s' % (mm, ('%d년 약정 시' % y) if y else '최장 약정 시', n, (' (%s)' % note) if note else '')
        data = {'text': text, 'from': frm, 'to': to, 'months': n, 'maxTerm': True, 'models': ms, 'sort': sort,
                'note': 'promo_xlsx:%s:%dy%dm · 모델 %d' % (ym, y, n, len(ms))}
        out.append("select sub.f_promo_save(%s::jsonb, %s);" % (q(json.dumps(data, ensure_ascii=False)), q(by)))
        sort += 1
    out.append("-- 확인: select id, text, months, max_term_only, cardinality(models) models, from_d, to_d, active from sub.promo order by sort, id;")
    return '\n'.join(out) + '\n'


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opt = {a.split('=')[0]: a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--') and '=' in a}
    if len(args) < 2: sys.exit(__doc__)
    src, ym = args[0], args[1].replace('-', '')
    dst = args[2] if len(args) > 2 else None
    frm = ym[:4] + '-' + ym[4:] + '-01'
    import calendar
    to = opt.get('--to', '%s-%s-%02d' % (ym[:4], ym[4:], calendar.monthrange(int(ym[:4]), int(ym[4:]))[1]))
    if src.lower().endswith('.tsv'):
        sheets = [rows_of_tsv(src)]
        s2 = re.sub(r'(_s1)?\.tsv$', '_s2.tsv', src)
        if os.path.exists(s2): sheets.append(rows_of_tsv(s2))
    else:
        sheets = rows_of_xlsx(src)
    models, legend, bad, extra = parse(sheets)
    by = opt.get('--by', 'promo_xlsx')
    out = sql_of(models, ym, frm, to, opt.get('--note', ''), by)
    g = collections.Counter((y, n) for y, n, _ in models.values())
    sys.stdout.write('legend %s\nmodels %d (둘째 시트에서 보탠 모델 %d) · 묶음 %s\n' % (json.dumps(legend), len(models), extra, ', '.join('%d년 %d개월 %d' % (y, n, c) for (y, n), c in sorted(g.items(), reverse=True))))
    if bad: sys.stdout.write('주의 %d: %s\n' % (len(bad), bad[:8]))
    if dst: io.open(dst, 'w', encoding='utf-8').write(out); sys.stdout.write('-> %s\n' % dst)
    else: sys.stdout.write(out)
