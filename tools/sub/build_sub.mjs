/* 상품상세 구독탭 데이터 — DPS 올인원구독모델(fn_sub_dps_export · 매일 수집) + SDP 판(카드표·정수기 할인값) + 정책(fn_sub_policy_export) → sdp/sub/*.js (mvp_246 · mvp_249)
   요금표 원본은 2026-10-27 부터 DPS(dps.sub_model active) 다. DPS 를 못 받으면 SDP 판의 DATA·PREPAY_NO 로 만든다 (이전 방식).
   DPS → 요금표 변환 규칙(품목·요금제 이름)은 DPS 판매 수집기 tools/submodel/export_products_js.mjs 와 같다.
   고도몰 예비 사본은 tools/build_sub_index.py 가 같은 규칙으로 만든 data_products.js(수집기 산출물)에서 만든다.
     sub_index.js          모델번호 → [카테고리키, 최저 월구독료, 최저 총구독료(자동납부 할인 반영)]   (상세페이지마다 로드 · 38KB)
     sub_plans_<키>.js     카테고리별 요금표 + 선납 미운영 표시 + 정수기 본사 할인값           (구독 모델일 때 1개 로드)
     sub_cards.js          제휴카드 청구할인 표 (CARD 그대로)
     sub_policy.js         정책값 (자동납부·선납·카드 유의사항·행사 문구) — 데이터센터 sub.policy 가 원본
     version.js            SUB_VER = "<SDP 판>+<정책 판>" — goods_view 가 5분마다 읽어 바뀌면 파일을 새로 받는다
   ※ 공개 파일: 제품 일시불가(v)·SPECS·인센티브·포인트 표는 넣지 않는다 (상세페이지 일시불가는 고도몰 판매가)
   import { buildSubFiles } from './build_sub.mjs' — publish.mjs 와 테스트가 같이 쓴다 */

// 카테고리 → 파일명용 영문 키 (새 카테고리가 생기면 여기와 build_sub_index.py 둘 다에 추가)
export const CAT_KEYS = {
  '냉장고': 'ref', '김치냉장고': 'kimchi', '정수기': 'water', 'TV': 'tv',
  '모니터': 'monitor', '오디오': 'audio', '의류케어': 'laundry', '청소기': 'cleaner',
  '에어컨': 'aircon', '시스템에어컨': 'sysaircon', '조리기기': 'cooking',
  '공기청정기': 'airpurifier', '제습기': 'dehumid', '갤럭시 탭': 'tab', '갤럭시 북': 'book',
};

const norm = m => String(m).replace(/\s+/g, '').toUpperCase();

/* ── DPS 올인원구독모델 → 계산기 요금표(DATA·PREPAY_NO) ──
   dps: fn_sub_dps_export 응답 { fetch_id, fetched_at, rows, models, items: [[model, category, seg, term_months, service, visit_cycle, total_fee, monthly_fee, prepay_ok]] }
   품목: 에어컨 중 세부유형이 천장형/전열교환기면 시스템에어컨 · 세탁기/건조기/에어드레서 → 의류케어 · 전기레인지/식기세척기/후드 → 조리기기
   요금제 이름: SDP 엑셀판과 같은 표기 — 무상수리(재설치포함)→무상수리 · 방문케어 12개월 주기는 '방문케어', 그 밖은 '방문케어(36개월주기)' · 셀프케어는 항상 주기 표기
   같은 (모델·약정·이름) 이 두 번 나오면(무상수리 와 무상수리(재설치포함)) DPS 순서상 앞의 것만 */
export function dpsCat(category, seg) {
  if (category === '에어컨' && /^(천장형|전열교환기)/.test(seg || '')) return '시스템에어컨';
  if (['세탁기', '건조기', '에어드레서'].includes(category)) return '의류케어';
  if (['전기레인지', '식기세척기', '후드'].includes(category)) return '조리기기';
  return category;
}
export function dpsCare(service, cycle, months, cat) {
  const s = String(service).replace(/\(재설치포함\)/, '');
  const cyc = (name, c, dflt = 12) => (c && c !== dflt ? `${name}(${c}개월주기)` : name);
  if (s === '무상수리') return '무상수리';
  if (s === '무상수리+방문케어') return cyc('방문케어', cycle);
  if (s === '무상수리+방문케어 라이트') return cyc('방문케어 라이트', cycle);
  if (s === '무상수리+셀프케어') return `셀프케어(${cycle}개월주기)`;
  if (s === '무상수리+파손보험') return `파손보험+무상보증(${cat === '갤럭시 탭' && months === 48 ? '36/48' : months}개월)`;
  if (/배터리\/키보드/.test(s)) return `보험+보증+배터리+키보드(${months}개월)`;
  if (/배터리교체/.test(s)) return `보험+보증+배터리교체(${months}개월)`;
  return s.replace(/^무상수리\+/, '');
}
const careRank = l => (/^방문케어 라이트/.test(l) ? 5 : /^방문케어/.test(l) ? 1 : /^셀프케어/.test(l) ? 2 : l === '무상수리' ? 3 : 6);
// 수집 시각 → 판 번호 'd261027-0915' (한국시간)
export function dpsVer(dps) {
  const t = dps && dps.fetched_at ? new Date(dps.fetched_at) : null;
  if (!t || isNaN(t)) return 'd?';
  const k = new Date(t.getTime() + 9 * 3600e3), p = n => String(n).padStart(2, '0');
  return `d${String(k.getUTCFullYear()).slice(2)}${p(k.getUTCMonth() + 1)}${p(k.getUTCDate())}-${p(k.getUTCHours())}${p(k.getUTCMinutes())}`;
}
export function dpsToData(dps) {
  const DATA = {}, seen = new Set(), prepayOk = new Map(); let dup = 0;
  for (const it of dps.items || []) {
    const [model, category, seg, months, service, cycle, total, monthly, ok] = it;
    if (!model || !months || !(total > 0) || !(monthly > 0)) continue;
    const cat = dpsCat(category, seg);
    (DATA[cat] ||= {})[model] ||= { s: seg || '', p: [] };
    prepayOk.set(model, (prepayOk.get(model) || false) || !!ok);
    const care = dpsCare(service, cycle, months, cat), y = months / 12, key = model + '|' + y + '|' + care;
    if (seen.has(key)) { dup++; continue; }
    seen.add(key);
    DATA[cat][model].p.push([y, care, Number(total), Number(monthly)]);
  }
  for (const models of Object.values(DATA)) for (const o of Object.values(models)) o.p.sort((a, b) => b[0] - a[0] || careRank(a[1]) - careRank(b[1]) || a[1].localeCompare(b[1]));
  const PREPAY_NO = [...prepayOk].filter(([, ok]) => !ok).map(([m]) => m);
  return { DATA, PREPAY_NO, dup, models: prepayOk.size };
}
// 로컬 확인용: 수집기 sub_model.json(행 배열) + meta → fn_sub_dps_export 와 같은 모양
export function dpsFromRows(rows, meta) {
  const items = rows.map(r => [r.model, r.category, r.seg, r.term_months, r.service, r.visit_cycle || 0, r.total_fee, r.monthly_fee, (r.prepay || []).some(p => p.ratio > 0)]);
  return { fetch_id: meta?.fetched_at || '', fetched_at: meta?.fetched_at || '', fetch_rows: rows.length, rows: rows.length, models: new Set(rows.map(r => r.model)).size, items };
}

// 자동납부 할인 반영 총구독료 — calc_subscribe / sub_tab.js 의 calcDiscount 와 같은 식 (ROUNDUP(total×rate/1.1/months,-2)×months×1.1)
export function netTotal(plan, autopay) {
  const [years, , total] = plan, months = years * 12;
  const inner = total * autopay / 1.1 / months;
  const rounded = Math.ceil(Math.round(inner * 1e6) / 1e6 / 100) * 100;
  return total - Math.round(rounded * months * 1.1);
}

// 판에서 변수 하나 꺼내기 (body 는 JSON 글자 그대로)
function varOf(rel, name) {
  for (const f of rel.files || []) for (const v of f.vars || []) if (v.name === name) return JSON.parse(v.body);
  return null;
}

// 정책 검사 — build_sub_index.py check_policy 와 같은 규칙 (DB sub.f_policy_check 가 저장할 때 막지만 배포 전에 한 번 더)
export function checkPolicy(pol) {
  const err = [], DATE = /^\d{4}-\d{2}-\d{2}$/;
  const rate = (v, where) => { if (typeof v !== 'number' || !(v >= 0 && v < 1)) err.push(`${where}: 0 이상 1 미만 소수여야 합니다 (현재 ${JSON.stringify(v)})`); };
  const period = (o, where) => { for (const k of ['from', 'to']) if (o[k] != null && !DATE.test(String(o[k]))) err.push(`${where}.${k}: YYYY-MM-DD 형식이어야 합니다 (현재 ${JSON.stringify(o[k])})`); };
  rate(pol.autopay?.rate, 'autopay.rate');
  const pp = pol.prepay || {};
  for (const st of pp.steps || []) { rate(st, 'prepay.steps'); if (!(pp.rates || {})[String(st)]) err.push(`prepay.rates: 선납 ${st} 의 할인율이 없습니다`); }
  for (const [k, v] of Object.entries(pp.rates || {})) rate(v, 'prepay.rates.' + k);
  rate(pp.defaultMax ?? 0.5, 'prepay.defaultMax');
  for (const [k, v] of Object.entries(pp.maxByCat || {})) rate(v, 'prepay.maxByCat.' + k);
  (pp.maxByName || []).forEach((m, i) => { if (!m.cat || !m.contains) err.push(`prepay.maxByName[${i}]: cat, contains 가 필요합니다`); rate(m.max, `prepay.maxByName[${i}].max`); });
  for (const [name, c] of Object.entries(pol.cards || {})) period(c, 'cards.' + name);
  (pol.promos || []).forEach((p, i) => { if (!p.text) err.push(`promos[${i}]: text 가 필요합니다`); period(p, `promos[${i}]`); });
  if (err.length) throw new Error('정책 오류\n  - ' + err.join('\n  - '));
  return pol;
}

/* 구독 요금 직접 관리(sub.price_override · mvp_251) 를 요금표 DATA 에 덧씌운다
   ov: [{ model, action 'set'|'hide', term(년 · 없으면 모든 약정), care(요금제 이름 · 없으면 모든 케어), cat, seg, monthly, total }]
   set  : 맞는 요금제의 월·총구독료를 바꾼다 (총구독료가 없으면 월 × 약정개월). 약정·케어를 둘 다 정했는데 그런 요금제가 없으면 새로 넣는다
          — DPS 에 없는 모델은 cat(품목)이 있어야 새로 만든다
   hide : 약정·케어를 안 정하면 모델 전체를, 정하면 맞는 요금제만 뺀다
   → { applied, added, hidden, skipped: [이유] } */
export function applyOverrides(DATA, ov) {
  const st = { applied: 0, added: 0, hidden: 0, skipped: [] };
  const where = m => { for (const [cat, models] of Object.entries(DATA)) for (const k of Object.keys(models || {})) if (norm(k) === m) return [cat, k]; return null; };
  const hit = (o, p) => (o.term == null || p[0] === Number(o.term)) && (o.care == null || p[1] === o.care);
  for (const o of ov || []) {
    const m = norm(o.model || ''); if (!m) continue;
    let at = where(m);
    if (o.action === 'hide') {
      if (!at) { st.skipped.push(`${m} 숨김: 요금표에 없는 모델`); continue; }
      const rec = DATA[at[0]][at[1]];
      if (o.term == null && o.care == null) { delete DATA[at[0]][at[1]]; st.hidden++; continue; }
      const n = rec.p.length; rec.p = rec.p.filter(p => !hit(o, p)); st.hidden += n - rec.p.length;
      if (!rec.p.length) delete DATA[at[0]][at[1]];
      continue;
    }
    const mon = Number(o.monthly); if (!(mon > 0)) { st.skipped.push(`${m}: 월 구독료 없음`); continue; }
    if (!at) {
      if (!o.cat || o.term == null || !o.care) { st.skipped.push(`${m}: 요금표에 없는 모델은 품목·약정·케어가 있어야 새로 넣습니다`); continue; }
      (DATA[o.cat] ||= {})[m] = { s: o.seg || '', p: [] }; at = [o.cat, m];
    }
    const rec = DATA[at[0]][at[1]], hits = rec.p.filter(p => hit(o, p));
    if (hits.length) { for (const p of hits) { p[3] = mon; p[2] = Number(o.total) > 0 && o.term != null ? Number(o.total) : mon * p[0] * 12; } st.applied += hits.length; }
    else if (o.term != null && o.care) { rec.p.push([Number(o.term), o.care, Number(o.total) > 0 ? Number(o.total) : mon * o.term * 12, mon]); st.added++; }
    else st.skipped.push(`${m}: 맞는 요금제가 없음 (약정 ${o.term ?? '전체'} · ${o.care ?? '모든 케어'})`);
    rec.p.sort((a, b) => b[0] - a[0] || careRank(a[1]) - careRank(b[1]) || a[1].localeCompare(b[1]));
  }
  return st;
}

/* rel: fn_sdp_export 응답 (CARD·WATER_POLICY 를 쓴다 · dps 가 없으면 DATA·PREPAY_NO 도)
   policy: fn_sub_policy_export 응답 (없으면 sub_policy.js 를 만들지 않는다 — 화면은 기본값으로 계산)
   dps: fn_sub_dps_export 응답 (있으면 요금표 원본 · 없으면 SDP 판의 DATA 로)
   → { 'sub_index.js': '…', 'sub_plans_tv.js': '…', …, 'sub_cards.js', 'sub_policy.js', 'version.js' } */
export function buildSubFiles(rel, policy, dps) {
  const CARD = varOf(rel, 'CARD') || {}, WATER = varOf(rel, 'WATER_POLICY') || {};
  let DATA, PREPAY_NO, src, dup = 0;
  if (dps && dps.items) { ({ DATA, PREPAY_NO, dup } = dpsToData(dps)); src = `DPS 수집 ${dps.fetch_id || ''}`; }
  else { DATA = varOf(rel, 'DATA'); PREPAY_NO = varOf(rel, 'PREPAY_NO') || []; src = `SDP 판 ${rel.ver}`; }
  if (!DATA) throw new Error('요금표가 없습니다 (DPS 도 SDP 판 DATA 도 없음)');
  // 구독 요금 직접 관리(mvp_251) — 정책 응답의 overrides 를 요금표에 덧씌우고 sub_policy.js 에는 남기지 않는다
  let ovStats = null;
  if (policy && policy.overrides) { ovStats = applyOverrides(DATA, policy.overrides); policy = { ...policy }; delete policy.overrides; }
  if (policy) checkPolicy(policy);
  const autopay = policy?.autopay?.rate ?? 0.05;
  const ver = rel.ver + (policy?.ver ? '+' + policy.ver : '') + (dps ? '+' + dpsVer(dps) : '');
  const head = `/* 상품상세 구독탭 데이터 | 데이터센터 배포판 ${ver} (db.samsungat.co.kr/sdp/sub · 요금표 원본 ${src} · 카드표 SDP 판 ${rel.ver} · 정책 sub.policy — 직접 고치지 마세요) */\n`;
  const out = {}, index = {}, cats = {}, missing = [];
  const noPre = new Set(PREPAY_NO.map(norm));
  for (const [cat, models] of Object.entries(DATA)) {
    if (!models || !Object.keys(models).length) continue;
    const key = CAT_KEYS[cat];
    if (!key) { missing.push(cat); continue; }
    cats[key] = cat;
    const plans = {};
    for (const [model, info] of Object.entries(models)) {
      const p = info.p || [];
      if (!p.length) continue;
      const m = norm(model);
      // p 원소: [약정년수, 케어명, 총구독료, 월구독료]
      const rec = { s: info.s || '', p };
      if (noPre.has(m)) rec.np = 1;                       // 선납 미운영
      if (WATER[model]) {                                  // 정수기 본사 사전계산값: "년_케어" → [구독료 할인(5%), 선납 할인(5% 기준)]
        rec.w = {}; for (const [k, v] of Object.entries(WATER[model])) rec.w[k] = [v.disc, v.prepay];
      }
      plans[m] = rec;
      index[m] = [key, Math.min(...p.map(x => x[3])), Math.min(...p.map(x => netTotal(x, autopay)))];
    }
    out[`sub_plans_${key}.js`] = head + `(window.SUB_PLANS=window.SUB_PLANS||{})[${JSON.stringify(key)}]=${JSON.stringify(plans)};\n`;
  }
  out['sub_index.js'] = head + `window.SUB_INDEX=${JSON.stringify({ ver, src: dps ? 'dps' : 'sdp', cats, m: index })};\n`;
  out['sub_cards.js'] = head + `window.SUB_CARDS=${JSON.stringify(CARD)};\n`;
  if (policy) out['sub_policy.js'] = head + `window.SUB_POLICY=${JSON.stringify(policy)};\n`;
  out['version.js'] = `/* 상품상세 구독탭 데이터 판 — goods_view 가 5분마다 이 파일로 최신 판을 확인합니다 */\nvar SUB_VER = ${JSON.stringify(ver)};\nvar SUB_SDP_VER = ${JSON.stringify(rel.ver)};\nvar SUB_POLICY_VER = ${JSON.stringify(policy?.ver || '')};\nvar SUB_PUBLISHED_AT = ${JSON.stringify(rel.published_at || '')};\nvar SUB_DPS_VER = ${JSON.stringify(dps ? dpsVer(dps) : '')};\nvar SUB_MODELS = ${Object.keys(index).length};\n`;
  out.__stats = { models: Object.keys(index).length, cats: Object.keys(cats).length, cards: Object.keys(CARD).length, missing, src: dps ? 'dps' : 'sdp', dup, prepayNo: PREPAY_NO.length, overrides: ovStats };
  return out;
}

// 직접 실행: node tools/sub/build_sub.mjs <data_*.js 가 있는 폴더> <출력 폴더> [sub_policy.json] [--dps-rows sub_model.json [sub_model.meta.json]]
//   (PC 에서 확인용 · 배포는 publish.mjs) · --dps-rows: DPS 판매 수집기의 outputs/playwriter/구독모델/sub_model.json 으로 DPS 원본 시험
if (process.argv[1] && /build_sub\.mjs$/.test(process.argv[1])) {
  const fs = await import('node:fs'), path = await import('node:path');
  const { splitJs } = await import('../sdp/js_to_release.mjs');
  const argv = process.argv.slice(2), di = argv.indexOf('--dps-rows');
  let dps = null;
  if (di >= 0) {
    const rows = JSON.parse(fs.readFileSync(argv[di + 1], 'utf8'));
    const hasMeta = argv[di + 2] && !argv[di + 2].startsWith('--');
    const metaPath = hasMeta ? argv[di + 2] : argv[di + 1].replace(/\.json$/, '.meta.json');
    const meta = fs.existsSync(metaPath) ? JSON.parse(fs.readFileSync(metaPath, 'utf8')) : null;
    dps = dpsFromRows(rows, meta);
    argv.splice(di, hasMeta ? 3 : 2);
  }
  const [src, dst, polPath] = argv;
  if (!src || !dst) { console.error('node build_sub.mjs <data_*.js 폴더> <출력 폴더> [sub_policy.json] [--dps-rows sub_model.json]'); process.exit(1); }
  const rel = { ver: 'local', files: [] };
  for (const f of ['data_products', 'data_cards', 'data_discounts']) {
    const p = path.join(src, f + '.js'); if (!fs.existsSync(p)) continue;
    const s = splitJs(fs.readFileSync(p, 'utf8')); rel.files.push({ file: f, head: s.head, tail: s.tail, vars: s.vars });
  }
  const policy = polPath ? JSON.parse(fs.readFileSync(polPath, 'utf8')) : null;
  if (policy) { for (const k of Object.keys(policy)) if (k.startsWith('_')) delete policy[k]; policy.ver = policy.ver || 'local'; }
  const files = buildSubFiles(rel, policy, dps);
  fs.mkdirSync(dst, { recursive: true });
  for (const [n, s] of Object.entries(files)) if (n !== '__stats') fs.writeFileSync(path.join(dst, n), s);
  console.log(files.__stats, '→', dst);
}
