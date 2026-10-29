/* 스마트 패키지 판 → sdp/spkg/data.js (GitHub Actions spkg-publish.yml · mvp_255)
   데이터센터에서 반영(active)한 판 중 아직 안 끝난 것을 모아 window.SPKG_DATA 로 쓴다.
   고도몰 상품상세가 sdp/spkg/spkg.js 를 부르고, spkg.js 가 이 파일을 읽어 오늘(KST) 기간의 판을 고른다.
   바뀐 게 없으면 아무것도 안 쓴다. --deployed <ver,ver> [커밋] : 푸시 뒤 fn_spkg_deployed 로 알린다 */
import fs from 'node:fs';
import { createHash } from 'node:crypto';
const URL_ = process.env.SUPABASE_URL, KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !KEY) { console.log('SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY 가 없어 건너뜁니다'); process.exit(0); }
const rpc = async (fn, body) => {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: KEY, authorization: 'Bearer ' + KEY, 'content-type': 'application/json' }, body: JSON.stringify(body || {}) });
  const t = await r.text(); if (!r.ok) throw new Error(`${fn} ${r.status} ${t.slice(0, 300)}`); return JSON.parse(t);
};
const a = process.argv.slice(2);
if (a[0] === '--deployed') {
  console.log(await rpc('fn_spkg_deployed', { p_vers: (a[1] || '').split(',').filter(Boolean), p_note: a[2] || null }));
  process.exit(0);
}
const ex = await rpc('fn_spkg_export');
const rel = (ex && ex.releases) || [];
const body = JSON.stringify(rel);
const sig = createHash('md5').update(body).digest('hex').slice(0, 10);
const P = 'sdp/spkg/data.js';
const cur = fs.existsSync(P) ? (fs.readFileSync(P, 'utf8').match(/SPKG_SIG = "([0-9a-f]+)"/) || [])[1] : null;
const vers = rel.map(r => r.ver).join(',');
let changed = 0;
if (cur !== sig) {
  const out = `/* 삼성전자 스마트 패키지 데이터 — 데이터센터 관리자 [스마트 패키지] 에서 반영한 판 (자동 생성 · 손으로 고치지 말 것 · mvp_255) */
var SPKG_SIG = "${sig}";
window.SPKG_DATA = {"sig":"${sig}","built":"${new Date().toISOString()}","releases":${body}};
`;
  fs.mkdirSync('sdp/spkg', { recursive: true }); fs.writeFileSync(P, out); changed = 1;
}
console.log(`판 ${vers || '없음'} · sig ${sig} (지금 ${cur || '없음'}) · 바뀜 ${changed}`);
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `vers=${vers}\nchanged=${changed}\n`);
