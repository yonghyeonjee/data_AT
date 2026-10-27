/* 데이터센터에서 반영된 SDP 판을 받아 sdp/*.js 로 쓴다 (GitHub Actions sdp-publish.yml · mvp_245)
   SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY 가 있어야 한다. 바뀐 게 없으면 아무것도 안 쓰고 끝낸다.
   --deployed <ver> : 커밋·푸시가 끝난 뒤 fn_sdp_deployed 로 알린다 */
import fs from 'node:fs';
import { buildFiles } from './release_to_js.mjs';
const URL_ = process.env.SUPABASE_URL, KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !KEY) { console.log('SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY 가 없어 건너뜁니다'); process.exit(0); }
const rpc = async (fn, body) => {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: KEY, authorization: 'Bearer ' + KEY, 'content-type': 'application/json' }, body: JSON.stringify(body || {}) });
  const t = await r.text(); if (!r.ok) throw new Error(`${fn} ${r.status} ${t.slice(0, 300)}`); return JSON.parse(t);
};
const a = process.argv.slice(2);
if (a[0] === '--deployed') { console.log(await rpc('fn_sdp_deployed', { p_ver: a[1], p_note: a[2] || null })); process.exit(0); }
const rel = await rpc('fn_sdp_export');
if (!rel || !rel.ver) { console.log('반영된 판이 없습니다'); process.exit(0); }
const dir = 'sdp'; fs.mkdirSync(dir, { recursive: true });
const cur = fs.existsSync(`${dir}/version.js`) ? (fs.readFileSync(`${dir}/version.js`, 'utf8').match(/SDP_VER = "([^"]+)"/) || [])[1] : null;
const files = buildFiles(rel); let changed = 0;
for (const [n, s] of Object.entries(files)) {
  const p = `${dir}/${n}`; if (fs.existsSync(p) && fs.readFileSync(p, 'utf8') === s) continue;
  fs.writeFileSync(p, s); changed++; console.log('씀', p, s.length);
}
console.log(`판 ${rel.ver} (지금 ${cur || '없음'}) · 바뀐 파일 ${changed}`);
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `ver=${rel.ver}\nchanged=${changed}\n`);
