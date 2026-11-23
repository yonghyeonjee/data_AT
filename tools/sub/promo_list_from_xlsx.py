# -*- coding: utf-8 -*-
"""본사 「N월 구독료 지원 행사모델 리스트」 엑셀 → 상담 견적 화면 [구독료 지원 확인] 자료 quote/promo_list.js (2026-11-16)
  + 구독센터·구독탭 「구독료 최대 n원 지원」 자료 sdp/sub/sub_promo_amt.js (2026-11-17)
  python -I -X utf8 tools/sub/promo_list_from_xlsx.py <리스트.xlsx> 2026-11 [--base 2026-11-01~2026-11-30] [--win 2026-11-13~2026-11-24] [--winname '라이온즈 우승 기념']
시트: B열부터 구분 · 품목1 · 품목2 · 계약 기간(년) · 서비스 주기 · 모델코드 · 총 구독료 · 월구독료 · 케어구분 · 케어유형 · 지원유형 · 포인트지원 · (판촉기간 포인트지원 · 대상모델 O/X · N개월)
DRM(NASCA) 파일이면 먼저 Excel 로 열어 일반 xlsx 로 저장한다 (tools/sub/README.md). 화면에 보이는 값은 리스트 숫자 그대로다 — 요금표로 다시 계산하지 않는다."""
import sys, io, json, openpyxl
TYPE = {'Type1': 6, 'Type2': 3, 'Type3': 6, 'Type4': 6, 'Type5': 3}
args = sys.argv[1:]; opt = {}
while '--base' in args or '--win' in args or '--winname' in args:
    for k in ('--base', '--win', '--winname'):
        if k in args: i = args.index(k); opt[k] = args[i + 1]; del args[i:i + 2]
path, ym = args[0], args[1]
rows = [r for r in list(openpyxl.load_workbook(path, data_only=True, read_only=True).worksheets[0].iter_rows(values_only=True))[3:] if len(r) > 12 and r[6]]
M = {}
for r in rows:
    m = str(r[6]).strip().upper(); base = TYPE.get(r[11], 0); win = int(r[15] or 0) if len(r) > 15 and r[14] == 'O' else 0
    assert r[12] == r[8] * base, ('포인트지원 수식이 다릅니다', r[:13])
    M.setdefault(m, [str(r[2] or '').strip(), []])[1].append([int(r[4]), str(r[10]).strip(), int(r[8]), base, win])
def span(s): a, b = (s or '~').split('~'); return {'from': a, 'to': b}
out = {'ym': ym, 'rows': len(rows), 'base': span(opt.get('--base')), 'win': dict(span(opt.get('--win')), name=opt.get('--winname', '판촉 기간')), 'm': M}
io.open('quote/promo_list.js', 'w', encoding='utf-8', newline='\n').write('/* tools/sub/promo_list_from_xlsx.py 가 만든 파일 — 손으로 고치지 않는다 */\nwindow.PROMO_LIST=' + json.dumps(out, ensure_ascii=False, separators=(',', ':')) + ';\n')
# 구독센터 카드·상품상세 구독탭의 「구독료 최대 n원 지원」 (2026-11-17) — 모델별 리스트 월구독료 × 지원 개월 의 최댓값 [평소, 판촉 기간]
A = {m: [max(x[2] * x[3] for x in v[1]), max(x[2] * x[4] for x in v[1])] for m, v in M.items()}
io.open('sdp/sub/sub_promo_amt.js', 'w', encoding='utf-8', newline='\n').write('/* tools/sub/promo_list_from_xlsx.py 가 만든 파일 — 손으로 고치지 않는다 · m[모델] = [평소 최대 지원액, 판촉 기간 최대 지원액] */\nwindow.SUB_PROMO_AMT=' + json.dumps({'ym': ym, 'base': out['base'], 'win': out['win'], 'm': A}, ensure_ascii=False, separators=(',', ':')) + ';\n')
print('models', len(M), 'rows', len(rows), 'win models', sum(1 for v in M.values() if any(x[4] for x in v[1])))
