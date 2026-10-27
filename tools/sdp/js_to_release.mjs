/* SDP 계산기 data_*.js → 데이터센터 판(release) JSON (mvp_245 · 2026-10-27)
   node tools/sdp/js_to_release.mjs data_products.js data_cards.js ... --out release.json [--ver 261027-1] [--note "…"] [--inc data_inc.js]
   · 파일을 실행하지 않고 글자로만 읽는다. 'var 이름 = <JSON>;' 마다 값(body)은 글자 그대로, 앞 주석(lead)·파일 머리(head)·꼬리(tail)도 그대로 둔다
   · INC(판매 인센티브)는 공개 배포에서 뺀다 — --inc 를 주면 그 변수만 따로 파일로 쓴다(고도몰 /data/js/data_inc.js 용) */
import fs from 'node:fs';
const args = process.argv.slice(2);
const opt = k => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const files = args.filter((a, i) => !a.startsWith('--') && !['--out','--ver','--note','--inc'].includes(args[i - 1]));
if (!files.length) { console.error('node js_to_release.mjs data_*.js --out release.json'); process.exit(1); }

export function splitJs(txt) {
  txt = txt.replace(/\r\n/g, '\n').replace(/^﻿/, '');
  const re = /^var\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*/gm; const st = []; let m;
  while ((m = re.exec(txt))) st.push({ name: m[1], at: m.index, vs: m.index + m[0].length });
  if (!st.length) throw new Error('var 가 없습니다');
  const head = txt.slice(0, st[0].at); const vars = []; let carry = '';
  st.forEach((s, i) => {
    const end = i + 1 < st.length ? st[i + 1].at : txt.length;
    let region = txt.slice(s.vs, end), tailTxt = '';
    // 끝의 주석·빈 줄은 다음 변수의 앞 주석(lead)으로 넘긴다
    for (;;) {
      const r = region.match(/(\n[ \t]*(\/\*[\s\S]*?\*\/|\/\/[^\n]*)[ \t]*|\n[ \t]*)$/);
      if (!r || !r[0]) break; tailTxt = r[0] + tailTxt; region = region.slice(0, -r[0].length);
    }
    let body = region.trim(); if (body.endsWith(';')) body = body.slice(0, -1).trim();
    JSON.parse(body); // JSON 이 아니면 여기서 멈춘다
    vars.push({ name: s.name, lead: carry, body }); carry = tailTxt.replace(/^\n/, '');
  });
  return { head, vars, tail: carry };
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('js_to_release.mjs')) {
  const out = { ver: opt('--ver') || undefined, note: opt('--note') || undefined, files: [] }; let inc = null;
  for (const f of files) {
    const name = f.split(/[\\/]/).pop().replace(/\.js$/, '').replace(/\s*\(\d+\)$/, '').replace(/__\d+_$/, '');
    const p = splitJs(fs.readFileSync(f, 'utf8'));
    const i = p.vars.findIndex(v => v.name === 'INC');
    if (i >= 0) { inc = p.vars[i]; if (i + 1 < p.vars.length) p.vars[i + 1].lead = p.vars[i + 1].lead; p.vars.splice(i, 1); }
    out.files.push({ file: name, head: p.head, tail: p.tail, vars: p.vars });
    console.log(name, p.vars.map(v => v.name).join(','), i >= 0 ? '(INC 뺌)' : '');
  }
  fs.writeFileSync(opt('--out') || 'release.json', JSON.stringify(out));
  if (opt('--inc')) {
    if (!inc) { console.error('INC 가 없습니다'); process.exit(1); }
    fs.writeFileSync(opt('--inc'), `/* ===== SDP 구독 계산기 — 모델별 판매 인센티브 (사내 전용 · 고도몰에만 둠, 데이터센터 공개 배포에서 제외) | 변수: INC ===== */\n${inc.lead}var INC = ${inc.body};\n`);
    console.log('INC →', opt('--inc'));
  }
  console.log('썼습니다:', opt('--out') || 'release.json');
}
