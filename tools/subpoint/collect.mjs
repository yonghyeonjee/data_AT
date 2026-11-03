/* 삼성닷컴 구독 멤버십 포인트 수집기 (mvp_258 · 2026-11-02)
   무엇: dps.sub_model(active) 모델마다 삼성닷컴 구독 상품 페이지에서 상품번호(goodsId)를 찾고, 멤버십 포인트 계산 API(membershipPolicy)로
         "적립 예정 멤버십 포인트" — 정률(aiscRate %) · 기본률(basicRate %) · 상품별 추가 포인트(mdlAddPoint) · 기준 총액일 때 총 포인트(totalPoint) — 를 받아
         sub.model_point 에 넣는다. 구독탭(sub_tab.js)·구독센터가 sub_policy.js 의 points[모델] 로 "적립 예정 멤버십 포인트" 줄을 보여 준다.
   왜:  DPS 올인원구독모델조회에는 포인트 항목이 없고, 삼성닷컴 페이지의 "N개월 구독료 상당" 배너는 이미지라 읽을 수 없다. 정률·추가 포인트는 이 API 가 숫자로 준다.
   어디서: GitHub Actions sub-point.yml (매일 06:00 KST 전부 다시(--all) · 수동 실행 가능) · PC 에서는 --models 로 DB 없이 돌려 볼 수 있다.
   어떻게 찾나:
     1) 모델 → goodsId : sub.model_point.goods_id 에 캐시된 값 → 없으면 구독 상품 페이지 https://www.samsung.com/sec/ai-subs-living/<모델>-subscribe2-d2c/<모델>/
        (주소의 품목 slug 는 무엇이든 마지막 모델번호로 상품을 찾아 준다). 서버가 그려 준 HTML 의 StPrdtOptItemVO(goodsId=G00…, mdlCode=모델) 쌍을 읽는다 —
        같은 상품의 다른 색상·옵션 모델도 함께 나오므로 한 페이지로 형제 모델의 goodsId 까지 얻는다. 없는 모델은 og:url 이 빈 공통 페이지(약 226KB)로 떨어진다.
     2) goodsId + 기준금액(dps.sub_model 최장 약정 최저 product_fee = 제품분 · mvp_264 · 없으면 total_fee) → POST /sec/xhr/goods/membershipPolicy
        form: goodsListStr=[{goodsId, mdlCode, price, cnt:1, mainGoodsYn:'Y'}] · bespokeMinimumPrice=0 · bundleYn=N · bundleOrgAplVal=0 · aiscAinYn=Y
        응답(JSON): totalPoint · basicRate(0.1) · basicRatePoint · aplPoint(정률 포인트) · mdlAddPoint(상품별 추가) · aiscRate("6.0")
   환경변수: SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY (Actions Secrets) — 또는 SUPABASE_ANON_KEY + SUB_POINT_KEY(core.api_key 'sub_point' · 값은 _secrets.local.md). 코드·표·git 에 넣지 않는다
   사용:
     node tools/subpoint/collect.mjs                 # fn_sub_point_targets() 가 고른 모델(처음 보는 것 · 6일 지난 것 · 못 찾은 것은 7~30일 뒤)
     node tools/subpoint/collect.mjs --all           # 활성 모델 전부 다시
     node tools/subpoint/collect.mjs --models WD90H25AHS,WD90H25AHW --dry   # 지정 모델만 · DB 에 쓰지 않음 (DB 키가 없으면 기준 총액 0 으로 정률·추가 포인트만)
     --limit N (기본 3000) · --dry (DB 에 쓰지 않음) · --out 파일 (결과 JSON) · --price N (DB 없이 돌릴 때 기준 총액)
   저장: fn_sub_point_upsert(p_rows, p_key, p_meta) — 찾은 것은 sub.model_point (src 'samsung.com'), 모델별 확인은 sub.model_point_check, 1회 기록은 sub.model_point_fetch.
         손 입력 행(src 'manual')은 덮지 않는다. 저장 트리거가 데이터센터 배포(sdp-publish.yml)를 바로 건다.
   예의: 동시 3 · 요청 간 0.4초 · 식별 가능한 UA (tools/subimg/collect.mjs 규칙) · 일시 오류(HTTP 5xx·시간 초과)는 기록하지 않고 다음 실행에 다시 본다 */
import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? (args[i + 1] ?? d) : d; };
const has = k => args.includes(k);
const URL_ = process.env.SUPABASE_URL;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY, ANON = process.env.SUPABASE_ANON_KEY, API_KEY = process.env.SUB_POINT_KEY;
const DB_KEY = SVC || ANON;                        // PostgREST apikey 헤더 · 서비스 롤이면 그 자체로 인증, 아니면 p_key(SUB_POINT_KEY)로 인증
const P_KEY = SVC ? null : (API_KEY || null);
const DRY = has('--dry'), ALL = has('--all'), LIMIT = Math.max(1, Number(opt('--limit', 3000)) || 3000);
const OUT = opt('--out', ''), MODELS = opt('--models', ''), PRICE0 = Number(opt('--price', 0)) || 0;

const UA = 'Mozilla/5.0 (compatible; samsungsh-subcenter-point/1.0; +https://www.samsungsh.co.kr)';
const CONCURRENCY = 3, SLEEP_MS = 400, TIMEOUT_MS = 25000;
const BASE = 'https://www.samsung.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const norm = m => String(m || '').replace(/\s+/g, '').toUpperCase();

async function rpc(fn, body) {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: DB_KEY, authorization: 'Bearer ' + DB_KEY, 'content-type': 'application/json' }, body: JSON.stringify(body || {}) });
  const t = await r.text(); if (!r.ok) throw new Error(`${fn} ${r.status} ${t.slice(0, 300)}`); return t ? JSON.parse(t) : null;
}
// 표를 돌려주는 RPC 는 PostgREST 가 한 번에 최대 1000행만 주고 Range 헤더도 무시하므로 p_offset 으로 1000행씩 이어 받는다 (활성 구독 모델 1131개 · 2026-11-02)
async function rpcAll(fn, body, want) {
  const out = [], page = 1000, max = want || 100000;
  for (let from = 0; from < max; from += page) {
    const rows = await rpc(fn, { ...body, p_offset: from, p_limit: Math.min(page, max - from) }) || [];
    out.push(...rows);
    if (rows.length < page) break;
  }
  return out;
}
const fetchT = (url, init = {}) => fetch(url, { ...init, headers: { 'user-agent': UA, 'accept-language': 'ko-KR,ko;q=0.9', ...(init.headers || {}) }, signal: AbortSignal.timeout(TIMEOUT_MS), redirect: 'follow' });

/* 구독 상품 페이지 주소 — 품목 slug 는 무엇이든 마지막 모델번호로 상품을 찾아 준다 ('/' 가 든 모델은 그대로 둔다 · subimg 와 같은 규칙) */
export const pageUrl = model => `${BASE}/sec/ai-subs-living/${encodeURIComponent(model)}-subscribe2-d2c/${model.split('/').map(encodeURIComponent).join('/')}/`;

/* ---------- 삼성닷컴 상품 찾기(PF) 목록 — 품목별 구독 상품 전부 (2026-11-02) ----------
   GET /sec/cxhr/pf/goodsList?dispClsfNo=<품목 번호>&onlyAiscGoods=Y&rows=100&page=N → { count, products: [{ goodsId, mdlCode, goodsOptStr }] }
   goodsOptStr 에 같은 상품의 옵션 모델(색상·크기)과 goodsId 가 '…|KU65MH75-W6|G002965561,G002965562|…' 꼴로 들어 있어 형제 모델까지 한 번에 얻는다.
   품목 번호는 각 '모두 보기' 페이지(/sec/tvs/all-tvs/ 등) HTML 의 dispClsfNo — 새 품목이 생기면 여기 더한다. 목록에 없는 모델은 예전처럼 상품 페이지로 한 번 더 본다 */
export const PF_CATS = {
  34060000: 'TV', 36010000: '냉장고', 36020000: '김치냉장고', 37020000: '세탁기', 37080000: '건조기', 37090000: '에어드레서',
  37010000: '에어컨', 37040000: '공기청정기', 37030000: '청소기', 36080000: '식기세척기', 36070000: '인덕션', 36030000: '인덕션(플렉스존)',
  39030000: '모니터', 33020000: '갤럭시 탭', 39120000: '갤럭시 북', 33010000: '스마트폰', 41040000: '오디오',
};
export async function pfScan(log = console.log) {
  const pairs = {}; let goods = 0, cats = 0, fails = 0;
  for (const [no, name] of Object.entries(PF_CATS)) {
    try {
      for (let page = 1, seen = 0; page <= 20; page++) {
        const url = `${BASE}/sec/cxhr/pf/goodsList?searchFilter=&dispClsfNo=${no}&sortType=10&page=${page}&rows=100&ehcacheYn=Y&soldOutExceptYn=N&pfFasterUseYn=Y&secApp=false&secIos=false&aiscCtgYn=N&tcPlantCode=&onlyAiscGoods=Y`;
        const r = await fetchT(url, { headers: { accept: 'application/json, text/javascript, */*; q=0.01', 'x-requested-with': 'XMLHttpRequest', referer: `${BASE}/sec/` } });
        if (!r.ok) throw new Error(`PF ${name} HTTP ${r.status}`);
        const j = await r.json(); const list = Array.isArray(j.products) ? j.products : [];
        for (const p of list) {
          if (p.goodsId && p.mdlCode) { pairs[norm(p.mdlCode)] = pairs[norm(p.mdlCode)] || p.goodsId; goods++; }
          for (const m of String(p.goodsOptStr || '').matchAll(/\|([A-Za-z0-9][A-Za-z0-9\-\/]{4,})\|(G\d{6,12})(?:,(G\d{6,12}))*\|/g)) {
            const k = norm(m[1]); if (!pairs[k]) pairs[k] = m[3] || m[2];   // 두 개면 뒤쪽(보통 스탠드형·대표) — 포인트 정률은 같은 상품이면 같다
          }
        }
        seen += list.length;
        if (!list.length || seen >= (Number(j.count) || 0)) break;
        await sleep(SLEEP_MS);
      }
      cats++;
    } catch (e) { fails++; log(`  ! PF ${name}: ${e.message}`); }
    await sleep(SLEEP_MS);
  }
  return { pairs, goods, cats, fails, models: Object.keys(pairs).length };
}

/* 상품 페이지 HTML → { goodsId, pairs: {모델: goodsId}, found } · 없는 모델은 og:url 이 비고 상품 쌍이 없다 */
export function parsePage(html, model) {
  const pairs = {};
  for (const m of html.matchAll(/goodsId=(G\d{6,12}),\s*mdlCode=([A-Za-z0-9\/\-]+)/g)) pairs[norm(m[2])] = m[1];
  const og = (html.match(/<meta property="og:url" content="([^"]*)"/) || [])[1] || '';
  const share = (html.match(/data-goods-id="(G\d{6,12})"/) || [])[1] || '';
  let goodsId = pairs[norm(model)] || '';
  // 쌍에 이 모델이 없어도 og:url 이 이 모델의 페이지면 공유 버튼의 상품번호가 이 모델이다
  if (!goodsId && share && og.toUpperCase().includes('/' + norm(model).replace(/\//g, '/') + '/')) goodsId = share;
  return { goodsId, pairs, found: !!goodsId, og };
}
export async function findGoodsId(model) {
  const r = await fetchT(pageUrl(model));
  if (r.status === 404) return { goodsId: '', pairs: {}, found: false, og: '' };
  if (!r.ok) throw new Error(`page HTTP ${r.status}`);
  return parsePage(await r.text(), model);
}
/* 멤버십 포인트 계산 API — 응답 모양이 조금 달라도 읽히게 키를 깊이 찾아 꺼낸다 */
export function pickPoints(json) {
  const out = {}; const KEYS = ['totalPoint', 'basicRate', 'basicRatePoint', 'aplPoint', 'mdlAddPoint', 'aiscRate'];
  (function walk(o, depth) {
    if (!o || typeof o !== 'object' || depth > 6) return;
    for (const [k, v] of Object.entries(o)) {
      if (KEYS.includes(k) && out[k] === undefined && (typeof v === 'number' || typeof v === 'string')) out[k] = v;
      else if (v && typeof v === 'object') walk(v, depth + 1);
    }
  })(json, 0);
  const num = v => (v === undefined || v === null || v === '' ? null : Number(String(v).replace(/[^0-9.\-]/g, '')));
  const r = { total_point: num(out.totalPoint), basic_point: num(out.basicRatePoint), apl_point: num(out.aplPoint), mdl_add_point: num(out.mdlAddPoint), aisc_rate: num(out.aiscRate), basic_rate: num(out.basicRate) };
  for (const k of Object.keys(r)) if (r[k] !== null && !isFinite(r[k])) r[k] = null;
  return r;
}
export async function membershipPolicy(goodsId, model, price) {
  const body = new URLSearchParams({
    goodsListStr: JSON.stringify([{ goodsId, mdlCode: model, price: Math.max(0, Math.round(price || 0)), cnt: 1, mainGoodsYn: 'Y' }]),
    bespokeMinimumPrice: '0', bundleYn: 'N', bundleOrgAplVal: '0', aiscAinYn: 'Y',
  });
  const r = await fetchT(`${BASE}/sec/xhr/goods/membershipPolicy`, {
    method: 'POST', body,
    headers: { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8', accept: 'application/json, text/javascript, */*; q=0.01',
               'x-requested-with': 'XMLHttpRequest', origin: BASE, referer: pageUrl(model) },
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`membershipPolicy HTTP ${r.status} ${t.slice(0, 120)}`);
  let j; try { j = JSON.parse(t); } catch { throw new Error('membershipPolicy 응답이 JSON 이 아님: ' + t.slice(0, 120)); }
  return { raw: j, ...pickPoints(j) };
}

if (process.argv[1] && /collect\.mjs$/.test(process.argv[1].replace(/\\/g, '/'))) {
  const started = new Date();
  const dbOk = !!(URL_ && DB_KEY && (SVC || P_KEY));
  // 대상: [{model, term_months, price, goods_id}]
  let targets;
  if (dbOk) {
    try { targets = await rpcAll('fn_sub_point_targets', { p_all: ALL || !!MODELS, p_key: P_KEY }, MODELS ? 100000 : LIMIT); }
    catch (e) { if (!MODELS) throw e; console.log('대상 조회 실패 → 지정 모델만 기준 총액 없이:', e.message); targets = []; }
  } else {
    if (!MODELS) { console.log('SUPABASE_URL 과 SUPABASE_SERVICE_ROLE_KEY(또는 SUPABASE_ANON_KEY + SUB_POINT_KEY) 가 없습니다 (PC 에서는 --models A,B --dry)'); process.exit(1); }
    targets = [];
  }
  if (MODELS) {
    const want = MODELS.split(',').map(norm).filter(Boolean), byM = new Map(targets.map(t => [norm(t.model), t]));
    targets = want.map(m => byM.get(m) || { model: m, term_months: null, price: PRICE0, goods_id: null });
  }
  targets = targets.slice(0, LIMIT);
  console.log(`대상 ${targets.length}개 (${MODELS ? '지정' : ALL ? '전부' : '처음·오래된 것'})${dbOk ? '' : ' · DB 없음(dry)'}`);

  const rows = [], gidCache = new Map();   // 모델 → goodsId (PF 목록 · 페이지 하나로 얻은 형제 모델 포함)
  for (const t of targets) if (t.goods_id) gidCache.set(norm(t.model), t.goods_id);
  // 삼성닷컴 상품 찾기 목록을 먼저 훑어 모델→goodsId 를 채운다 (품목당 1~2번 요청) — 목록 값이 DB 에 캐시된 옛 goodsId 보다 새롭다
  const pf = targets.length ? await pfScan() : { pairs: {}, goods: 0, cats: 0, fails: 0, models: 0 };
  for (const [m, g] of Object.entries(pf.pairs)) gidCache.set(m, g);
  const inPf = targets.filter(t => pf.pairs[norm(t.model)]).length;
  console.log(`PF 목록: 품목 ${pf.cats}개(실패 ${pf.fails}) · 상품 ${pf.goods}개 · 모델 ${pf.models}개 · 대상 중 ${inPf}개가 목록에 있음`);
  let found = 0, missed = 0, errors = 0, pages = 0, i = 0; const errSamples = [];   // 오류 표본: 전부 실패했을 때 원인을 fetch 기록(note)에 남긴다 — Actions 로그를 못 볼 때 관리자 화면에서 본다
  async function worker() {
    while (i < targets.length) {
      const t = targets[i++], model = norm(t.model);
      try {
        let gid = gidCache.get(model), fromPage = false;
        if (!gid) {
          const p = await findGoodsId(model); pages++;
          for (const [m, g] of Object.entries(p.pairs)) if (!gidCache.has(m)) gidCache.set(m, g);
          await sleep(SLEEP_MS);
          if (!p.found) { rows.push({ model, goods_id: null, term_months: t.term_months, price: t.price, err: '삼성닷컴 구독 상품 페이지 없음' }); missed++; continue; }
          gid = p.goodsId; fromPage = true;
        }
        let mp;
        try {
          mp = await membershipPolicy(gid, model, t.price);
          // 같은 요청에 정률(aiscRate)이 0 으로 오는 때가 간혹 있다(2026-11-02 확인) → 잠깐 뒤 한 번 더 보고 큰 쪽을 쓴다
          if (!mp.aisc_rate && !mp.apl_point && mp.total_point !== null) { await sleep(SLEEP_MS * 2); const again = await membershipPolicy(gid, model, t.price); if ((again.aisc_rate || 0) > 0 || (again.apl_point || 0) > 0) mp = again; }
        }
        catch (e) {
          // 캐시된 goodsId 가 낡았을 수 있다 → 페이지에서 다시 찾아 한 번 더
          if (fromPage || /HTTP 5|timeout|aborted|fetch failed/i.test(e.message)) throw e;
          await sleep(SLEEP_MS); const p = await findGoodsId(model); pages++;
          if (!p.found) { rows.push({ model, goods_id: null, term_months: t.term_months, price: t.price, err: '삼성닷컴 구독 상품 페이지 없음 (옛 goodsId ' + gid + ')' }); missed++; continue; }
          gid = p.goodsId; mp = await membershipPolicy(gid, model, t.price);
        }
        if (mp.aisc_rate === null && mp.total_point === null) { rows.push({ model, goods_id: gid, term_months: t.term_months, price: t.price, err: '포인트 응답에 aiscRate·totalPoint 없음: ' + JSON.stringify(mp.raw).slice(0, 160) }); missed++; }
        else { delete mp.raw; rows.push({ model, goods_id: gid, term_months: t.term_months, price: t.price, ...mp }); found++; }
      } catch (e) { errors++; console.log(`  ! ${model} ${e.message}`); if (errSamples.length < 3) errSamples.push(`${model}: ${e.message.slice(0, 120)}`); }   // 일시 오류: 기록하지 않고 다음에 다시
      await sleep(SLEEP_MS);
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  const secs = ((Date.now() - started.getTime()) / 1000).toFixed(0);
  console.log(`찾음 ${found} · 없음 ${missed} · 오류 ${errors} · 페이지 ${pages}번 · ${secs}초`);
  if (MODELS || rows.length <= 5) for (const r of rows) console.log('  ', JSON.stringify(r));
  if (OUT) { fs.writeFileSync(OUT, JSON.stringify(rows, null, 1)); console.log('씀', OUT); }
  let saved = null;
  if (!DRY && (rows.length || errors)) {   // 찾은 게 없어도 오류가 있었으면 기록은 남긴다 (오류 표본 포함)
    if (!dbOk) console.log('DB 키가 없어 저장하지 않습니다');
    else {
      const note = `${MODELS ? '지정' : ALL ? '전부' : '정기'} · PF 품목 ${pf.cats}/${Object.keys(PF_CATS).length} 모델 ${pf.models}개 · 페이지 ${pages}번 · ${secs}초` + (errSamples.length ? ` · 오류 예: ${errSamples.join(' | ')}` : '');
      saved = await rpc('fn_sub_point_upsert', { p_rows: rows, p_key: P_KEY, p_meta: { started_at: started.toISOString(), targets: targets.length, errors, note } });
      console.log('저장', JSON.stringify(saved));
    }
  }
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `targets=${targets.length}\nfound=${found}\nmissed=${missed}\nerrors=${errors}\n`);
  if (errors && !found && !missed) process.exit(1);
}
