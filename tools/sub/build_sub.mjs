/* 상품상세 구독탭 데이터 — SDP 판(data_products·data_cards·data_discounts) + 정책(fn_sub_policy_export) → sdp/sub/*.js (mvp_246)
   고도몰 패키지의 tools/build_sub_index.py 를 그대로 옮긴 것 — 두 쪽 출력이 같아야 한다 (python 과 json 직렬화만 다르다).
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

/* rel: fn_sdp_export 응답 (DATA·PREPAY_NO·CARD·WATER_POLICY 가 들어 있어야 한다)
   policy: fn_sub_policy_export 응답 (없으면 sub_policy.js 를 만들지 않는다 — 화면은 기본값으로 계산)
   → { 'sub_index.js': '…', 'sub_plans_tv.js': '…', …, 'sub_cards.js', 'sub_policy.js', 'version.js' } */
export function buildSubFiles(rel, policy) {
  const DATA = varOf(rel, 'DATA'), PREPAY_NO = varOf(rel, 'PREPAY_NO') || [], CARD = varOf(rel, 'CARD') || {}, WATER = varOf(rel, 'WATER_POLICY') || {};
  if (!DATA) throw new Error('판에 DATA 가 없습니다');
  if (policy) checkPolicy(policy);
  const autopay = policy?.autopay?.rate ?? 0.05;
  const ver = rel.ver + (policy?.ver ? '+' + policy.ver : '');
  const head = `/* 상품상세 구독탭 데이터 | 데이터센터 배포판 ${ver} (db.samsungat.co.kr/sdp/sub · 원본은 SDP 판 ${rel.ver} + sub.policy — 직접 고치지 마세요) */\n`;
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
  out['sub_index.js'] = head + `window.SUB_INDEX=${JSON.stringify({ ver, cats, m: index })};\n`;
  out['sub_cards.js'] = head + `window.SUB_CARDS=${JSON.stringify(CARD)};\n`;
  if (policy) out['sub_policy.js'] = head + `window.SUB_POLICY=${JSON.stringify(policy)};\n`;
  out['version.js'] = `/* 상품상세 구독탭 데이터 판 — goods_view 가 5분마다 이 파일로 최신 판을 확인합니다 */\nvar SUB_VER = ${JSON.stringify(ver)};\nvar SUB_SDP_VER = ${JSON.stringify(rel.ver)};\nvar SUB_POLICY_VER = ${JSON.stringify(policy?.ver || '')};\nvar SUB_PUBLISHED_AT = ${JSON.stringify(rel.published_at || '')};\n`;
  out.__stats = { models: Object.keys(index).length, cats: Object.keys(cats).length, cards: Object.keys(CARD).length, missing };
  return out;
}

// 직접 실행: node tools/sub/build_sub.mjs <data_*.js 가 있는 폴더> <출력 폴더> [sub_policy.json]   (PC 에서 확인용 · 배포는 publish.mjs)
if (process.argv[1] && /build_sub\.mjs$/.test(process.argv[1])) {
  const fs = await import('node:fs'), path = await import('node:path');
  const { splitJs } = await import('../sdp/js_to_release.mjs');
  const [src, dst, polPath] = process.argv.slice(2);
  if (!src || !dst) { console.error('node build_sub.mjs <data_*.js 폴더> <출력 폴더> [sub_policy.json]'); process.exit(1); }
  const rel = { ver: 'local', files: [] };
  for (const f of ['data_products', 'data_cards', 'data_discounts']) {
    const p = path.join(src, f + '.js'); if (!fs.existsSync(p)) continue;
    const s = splitJs(fs.readFileSync(p, 'utf8')); rel.files.push({ file: f, head: s.head, tail: s.tail, vars: s.vars });
  }
  const policy = polPath ? JSON.parse(fs.readFileSync(polPath, 'utf8')) : null;
  if (policy) { for (const k of Object.keys(policy)) if (k.startsWith('_')) delete policy[k]; policy.ver = policy.ver || 'local'; }
  const files = buildSubFiles(rel, policy);
  fs.mkdirSync(dst, { recursive: true });
  for (const [n, s] of Object.entries(files)) if (n !== '__stats') fs.writeFileSync(path.join(dst, n), s);
  console.log(files.__stats, '→', dst);
}
