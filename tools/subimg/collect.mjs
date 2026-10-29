/* 구독센터 제품 사진 — 삼성닷컴(samsung.com/sec) 대표 이미지 수집기 (mvp_252 · 2026-10-29)
   무엇: dps.sub_model(active) 모델마다 삼성닷컴 고객지원 모델 페이지 https://www.samsung.com/sec/support/model/<모델>/ 를 읽어
         <div class="support-box-prod"> 안의 대표 사진(images.samsung.com/kdp/goods/…)과 제품명(alt)을 core.sub_model_image 에 넣는다.
         구독 전용 모델(…T·…Z 꼬리)도 고객지원 페이지는 있어서 판매 페이지(사이트맵 30개)보다 훨씬 많이 찾는다. 없는 모델은 500 응답.
   왜:  fn_sub_catalog 가 주던 고도몰 목록용 썸네일이 88px 짜리라 구독센터 상세·목록에서 작게 보였다.
   어디서: GitHub Actions sub-image.yml (매일) · PC 에서는 --models-file 로 DB 없이 돌려 볼 수 있다.
   환경변수: SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY (Actions Secrets · 코드·표에 넣지 않는다)
   사용:
     node tools/subimg/collect.mjs                 # fn_sub_image_samsung_targets() 가 고른 모델(미확인·오래된 것)만
     node tools/subimg/collect.mjs --all           # 활성 모델 전부 다시
     node tools/subimg/collect.mjs --models A,B    # 지정 모델만
     node tools/subimg/collect.mjs --models-file 목록.txt --out 결과.json --dry   # DB 없이 (공백·줄바꿈 구분)
     --limit N (기본 1200) · --dry (DB 에 쓰지 않음) · --out 파일 (결과 JSON)
   저장: fn_sub_image_samsung_save(p_rows) — 찾은 것은 core.sub_model_image (note 'auto:samsung.com/support · 제품명'),
         확인 기록은 core.sub_model_image_check. 손으로 넣은 행(note 가 'auto:' 로 시작하지 않음)은 건드리지 않는다. */
import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? (args[i + 1] ?? d) : d; };
const has = k => args.includes(k);
const URL_ = process.env.SUPABASE_URL, KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const DRY = has('--dry'), ALL = has('--all'), LIMIT = Math.max(1, Number(opt('--limit', 1200)) || 1200);
const OUT = opt('--out', ''), MODELS = opt('--models', ''), MODELS_FILE = opt('--models-file', '');

const UA = 'Mozilla/5.0 (compatible; samsungsh-subcenter-image/1.1; +https://www.samsungsh.co.kr)';
const CONCURRENCY = 4, SLEEP_MS = 250, TIMEOUT_MS = 20000;
const IMG_WIDTH = '?imwidth=720';   // 원본 1920px → 카드용 720px (images.samsung.com 이 크기를 맞춰 준다 · CORS * · 캐시 1시간)
const SAMSUNG_IMG = /^https:\/\/images\.samsung\.com\/kdp\/goods\/[\w\/.-]+\.(png|jpe?g|webp)$/i;
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function rpc(fn, body) {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: KEY, authorization: 'Bearer ' + KEY, 'content-type': 'application/json' }, body: JSON.stringify(body || {}) });
  const t = await r.text(); if (!r.ok) throw new Error(`${fn} ${r.status} ${t.slice(0, 300)}`); return t ? JSON.parse(t) : null;
}
const fetchT = (url, init = {}) => fetch(url, { ...init, headers: { 'user-agent': UA, ...(init.headers || {}) }, signal: AbortSignal.timeout(TIMEOUT_MS), redirect: 'follow' });

/* 삼성닷컴 고객지원 모델 페이지 → { image, name } · null = 그 모델 페이지 없음 · 일시 오류는 throw */
export function parseSupportPage(html, model) {
  const box = html.match(/<div class="support-box-prod">([\s\S]{0,3000}?)<\/div>\s*<div class="prod-txt">/);
  if (!box) return null;
  const img = box[1].match(/<img[^>]*\bsrc="((?:https?:)?\/\/images\.samsung\.com\/[^"?]+)[^"]*"[^>]*>/i);
  if (!img) return null;
  const image = img[1].replace(/^\/\//, 'https://');
  if (!SAMSUNG_IMG.test(image)) return null;
  const alt = (img[0].match(/\balt="([^"]*)"/) || [])[1] || '';
  const name = alt.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();
  // 다른 모델로 넘어간 페이지가 아닌지 — 모델번호(또는 꼬리 뗀 기본형)가 본문에 있어야 한다
  const base = model.replace(/[A-Z]?\/KR$/, '');
  if (!html.includes(model) && !html.includes(base)) return null;
  return { image, name };
}
export async function findSamsung(model) {
  // 'HW-Q800H/KR' 처럼 / 가 든 모델은 / 를 그대로 둬야 열린다 (%2F 는 404)
  const r = await fetchT(`https://www.samsung.com/sec/support/model/${model.split('/').map(encodeURIComponent).join('/')}/`);
  if (r.status === 500 || r.status === 404) return null;   // 없는 모델은 500 "사이트 이용에 불편을 드려 죄송합니다"
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return parseSupportPage(await r.text(), model);
}
// 사진 주소가 실제로 열리는지
async function alive(url) {
  try { const r = await fetchT(url + IMG_WIDTH, { method: 'HEAD' }); return r.ok && /^image\//.test(r.headers.get('content-type') || ''); }
  catch { return false; }
}

if (process.argv[1] && /collect\.mjs$/.test(process.argv[1].replace(/\\/g, '/'))) {
  // 대상 모델
  let targets;
  if (MODELS) targets = MODELS.split(',');
  else if (MODELS_FILE) targets = fs.readFileSync(MODELS_FILE, 'utf8').split(/\s+/);
  else {
    if (!URL_ || !KEY) { console.log('SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY 가 없습니다 (PC 에서는 --models 또는 --models-file)'); process.exit(1); }
    targets = (await rpc('fn_sub_image_samsung_targets', { p_all: ALL, p_limit: LIMIT })).map(r => r.model);
  }
  targets = [...new Set(targets.map(m => String(m).trim().toUpperCase()).filter(Boolean))].slice(0, LIMIT);
  console.log(`대상 ${targets.length}개 (${MODELS || MODELS_FILE ? '지정' : ALL ? '전부' : '미확인·오래된 것'})`);

  const rows = []; let found = 0, missed = 0, errors = 0, i = 0;
  const started = Date.now();
  async function worker() {
    while (i < targets.length) {
      const model = targets[i++];
      try {
        const f = await findSamsung(model);
        if (f && await alive(f.image)) { rows.push({ model, image_url: f.image + IMG_WIDTH, name: f.name }); found++; }
        else { rows.push({ model, image_url: null, name: f ? f.name : null }); missed++; }
      } catch (e) { errors++; console.log(`  ! ${model} ${e.message}`); }   // 일시 오류: 기록하지 않고 다음에 다시
      await sleep(SLEEP_MS);
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  console.log(`찾음 ${found} · 없음 ${missed} · 오류 ${errors} · ${((Date.now() - started) / 1000).toFixed(0)}초`);
  if (OUT) { fs.writeFileSync(OUT, JSON.stringify(rows, null, 1)); console.log('씀', OUT); }
  let saved = null;
  if (!DRY && rows.length) {
    if (!URL_ || !KEY) console.log('DB 키가 없어 저장하지 않습니다');
    else { saved = await rpc('fn_sub_image_samsung_save', { p_rows: rows }); console.log('저장', JSON.stringify(saved)); }
  }
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `targets=${targets.length}\nfound=${found}\nmissed=${missed}\nerrors=${errors}\n`);
  if (errors && !found && !missed) process.exit(1);
}
