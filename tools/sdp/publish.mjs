/* 데이터센터에서 반영된 SDP 판을 받아 sdp/*.js 로 쓴다 (GitHub Actions sdp-publish.yml · mvp_245)
   + DPS 올인원구독모델(fn_sub_dps_export)·같은 판의 카드표·구독 혜택 정책(fn_sub_policy_export)으로 상품상세 구독탭 파일 sdp/sub/*.js 를 만든다 (mvp_246 · mvp_249)
   안전장치: DPS 최신 수집이 24시간 넘게 없거나, 모델 수가 직전 배포판(version.js 의 SUB_MODELS)보다 10% 넘게 줄거나 500 미만이면
   구독탭 파일을 건드리지 않고(이전 판 유지) fn_sub_publish_log('sub_skipped') 로 남긴다. DPS 를 아예 못 받으면(mvp_249 전·장애) SDP 판 DATA 로 만든다
   SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY 가 있어야 한다. 바뀐 게 없으면 아무것도 안 쓰고 끝낸다.
   --deployed <ver> <sub_ver> [커밋] : 커밋·푸시가 끝난 뒤 fn_sdp_deployed · fn_sub_policy_deployed 로 알린다 */
import fs from 'node:fs';
import { buildFiles } from './release_to_js.mjs';
import { buildSubFiles } from '../sub/build_sub.mjs';
const URL_ = process.env.SUPABASE_URL, KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !KEY) { console.log('SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY 가 없어 건너뜁니다'); process.exit(0); }
const rpc = async (fn, body) => {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: KEY, authorization: 'Bearer ' + KEY, 'content-type': 'application/json' }, body: JSON.stringify(body || {}) });
  const t = await r.text(); if (!r.ok) throw new Error(`${fn} ${r.status} ${t.slice(0, 300)}`); return JSON.parse(t);
};
const a = process.argv.slice(2);
if (a[0] === '--deployed') {
  console.log(await rpc('fn_sdp_deployed', { p_ver: a[1], p_note: a[3] || null }));
  if (a[2]) { try { console.log(await rpc('fn_sub_policy_deployed', { p_ver: a[2], p_note: a[3] || null })); } catch (e) { console.log('구독탭 배포 기록 실패(mvp_246 미적용?):', e.message); } }
  process.exit(0);
}
const rel = await rpc('fn_sdp_export');
if (!rel || !rel.ver) { console.log('반영된 판이 없습니다'); process.exit(0); }
const curVer = dir => fs.existsSync(`${dir}/version.js`) ? (fs.readFileSync(`${dir}/version.js`, 'utf8').match(/(?:SDP|SUB)_VER = "([^"]+)"/) || [])[1] : null;
const writeAll = (dir, files) => {
  fs.mkdirSync(dir, { recursive: true }); let changed = 0;
  for (const [n, s] of Object.entries(files)) {
    if (n.startsWith('__')) continue;
    const p = `${dir}/${n}`; if (fs.existsSync(p) && fs.readFileSync(p, 'utf8') === s) continue;
    fs.writeFileSync(p, s); changed++; console.log('씀', p, s.length);
  }
  return changed;
};
const cur = curVer('sdp');
const changed = writeAll('sdp', buildFiles(rel));
console.log(`판 ${rel.ver} (지금 ${cur || '없음'}) · 바뀐 파일 ${changed}`);

/* 구독탭: 정책을 못 받으면(mvp_246 전) 정책 파일 없이 요금표만 만든다 — 화면은 기본 정책으로 계산한다 */
let policy = null;
try { policy = await rpc('fn_sub_policy_export'); } catch (e) { console.log('구독 정책을 못 받았습니다 → 요금표만:', e.message); }
/* 요금표 원본 DPS (mvp_249) — 못 받으면 SDP 판 DATA 로 */
let dps = null;
try { dps = await rpc('fn_sub_dps_export'); if (!dps || !dps.items || !dps.items.length) { console.log('DPS 수집분이 비어 있습니다 → SDP 판 DATA 로'); dps = null; } }
catch (e) { console.log('DPS 수집분을 못 받았습니다 → SDP 판 DATA 로:', e.message); }
const log = async (kind, ver, note) => { console.log(`[${kind}] ${note}`); try { await rpc('fn_sub_publish_log', { p_kind: kind, p_ver: ver, p_note: note }); } catch (e) { console.log('기록 실패:', e.message); } };
const subCur = curVer('sdp/sub');
const prevModels = fs.existsSync('sdp/sub/version.js') ? Number((fs.readFileSync('sdp/sub/version.js', 'utf8').match(/SUB_MODELS = (\d+)/) || [])[1]) || 0 : 0;
let skip = '';
if (dps) {
  const ageH = (Date.now() - new Date(dps.fetched_at).getTime()) / 3600e3;
  if (!(ageH < 24)) skip = `DPS 최신 수집이 ${isNaN(ageH) ? '없음' : Math.round(ageH) + '시간 전'} (${dps.fetched_at || '?'}) — 24시간 넘어 이전 판 유지`;
  else if (dps.models < 500) skip = `DPS 모델 ${dps.models}개 — 500 미만이라 이전 판 유지`;
  else if (prevModels && dps.models < prevModels * 0.9) skip = `DPS 모델 ${dps.models}개 — 직전 배포판 ${prevModels}개보다 10% 넘게 줄어 이전 판 유지`;
}
let subChanged = 0, subVer = subCur || '';
if (skip) await log('sub_skipped', subCur || '', skip + ' (수집기 점검 필요 · 정책 변경도 다음 정상 수집 뒤에 반영됨)');
else {
  const sub = buildSubFiles(rel, policy, dps);
  subChanged = writeAll('sdp/sub', sub);
  subVer = (sub['version.js'].match(/SUB_VER = "([^"]+)"/) || [])[1];
  console.log(`구독탭 판 ${subVer} (지금 ${subCur || '없음'}) · 원본 ${sub.__stats.src} · 모델 ${sub.__stats.models} · 선납불가 ${sub.__stats.prepayNo} · 바뀐 파일 ${subChanged}` + (sub.__stats.missing.length ? ` · CAT_KEYS 에 없는 품목: ${sub.__stats.missing.join(', ')}` : ''));
  if (sub.__stats.missing.length) await log('sub_warn', subVer, `CAT_KEYS 에 없는 품목이라 제외됨: ${sub.__stats.missing.join(', ')}`);
  const ov = sub.__stats.overrides;   // 구독 요금 직접 관리 (mvp_251)
  if (ov) console.log(`요금 직접 관리: 바꿈 ${ov.applied} · 새로 ${ov.added} · 숨김 ${ov.hidden} · 못 넣음 ${ov.skipped.length}`);
  if (ov && ov.skipped.length) await log('sub_warn', subVer, `요금 직접 관리 중 반영 못 한 것: ${ov.skipped.join(' / ')}`);
  if (prevModels && sub.__stats.models < prevModels) console.log(`모델 수 ${prevModels} → ${sub.__stats.models} (${prevModels - sub.__stats.models}개 감소)`);
}

if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `ver=${rel.ver}\nsubver=${subVer}\nchanged=${changed + subChanged}\n`);
