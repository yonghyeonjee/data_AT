/* 데이터센터 판(fn_sdp_export 응답) → 계산기용 data_*.js + version.js (mvp_245)
   import { buildFiles } from './release_to_js.mjs' — publish.mjs 와 테스트가 같이 쓴다 */
export function buildFiles(rel) {
  const out = {};
  for (const f of rel.files || []) {
    let s = f.head || '';
    s += `/*   데이터센터 배포판 ${rel.ver} (db.samsungat.co.kr/sdp · 원본은 데이터센터 sdp.release — 이 파일을 직접 고치지 마세요) */\n`;
    for (const v of f.vars || []) s += (v.lead || '') + `var ${v.name} = ${v.body};\n`;
    s += f.tail || '';
    out[f.file + '.js'] = s;
  }
  out['version.js'] = `/* SDP 계산기 데이터 판 — 계산기가 5분마다 이 파일로 최신 판을 확인합니다 */\nvar SDP_VER = ${JSON.stringify(rel.ver)};\nvar SDP_PUBLISHED_AT = ${JSON.stringify(rel.published_at || '')};\nvar SDP_FILES = ${JSON.stringify((rel.files || []).map(f => f.file))};\n`;
  return out;
}
