/* 데이터센터에서 반영된 SDP 판을 받아 sdp/*.js 로 쓴다 (GitHub Actions sdp-publish.yml · mvp_245)
   + 같은 판과 구독 혜택 정책(fn_sub_policy_export)으로 상품상세 구독탭 파일 sdp/sub/*.js 를 만든다 (mvp_246)
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
const sub = buildSubFiles(rel, policy);
const subCur = curVer('sdp/sub');
const subChanged = writeAll('sdp/sub', sub);
const subVer = (sub['version.js'].match(/SUB_VER = "([^"]+)"/) || [])[1];
console.log(`구독탭 판 ${subVer} (지금 ${subCur || '없음'}) · 모델 ${sub.__stats.models} · 바뀐 파일 ${subChanged}` + (sub.__stats.missing.length ? ` · CAT_KEYS 에 없는 품목: ${sub.__stats.missing.join(', ')}` : ''));

if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `ver=${rel.ver}\nsubver=${subVer}\nchanged=${changed + subChanged}\n`);
