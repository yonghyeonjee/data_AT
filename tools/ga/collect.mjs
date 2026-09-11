#!/usr/bin/env node
/**
 * GA4 방문량 → Datacenter core.web_traffic
 * ───────────────────────────────────────────────────────────────
 * 고도몰(시흥몰)에 붙은 GA4 속성에서 날짜별 세션·사용자·조회수를 가져와
 * 전체 / 구독문의 페이지 / 견적서 페이지 세 줄로 적재한다.
 * 관리자 [상담] → "방문 → 문의 → 성공" 표가 이걸 읽는다.
 *
 * 필요한 Secrets (GitHub 저장소)
 *   GA_PROPERTY_ID   GA4 속성 ID (숫자만, 예: 123456789)
 *   GA_SA_JSON       서비스 계정 키 JSON 전체 (GA 속성에 "뷰어"로 추가된 계정)
 *   SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY (이미 있음)
 * 선택
 *   GA_PATH_SUB      구독문의 페이지 경로 정규식 (기본: subscribe|구독)
 *   GA_PATH_QUOTE    견적서 페이지 경로 정규식 (기본: quote_subscribe|calc_subscribe|견적)
 *   GA_INGEST_KEY    Datacenter 적재 키 (기본값 내장)
 *
 * 실행   node collect.mjs                 최근 3일
 *        node collect.mjs --from 2026-09-01 --to 2026-09-10
 *        node collect.mjs --paths          경로별 세션 상위 40개만 출력 (정규식 정할 때)
 */
import crypto from "node:crypto";

const env = (k, d) => { const v = process.env[k]; if (v === undefined || v === "") { if (d !== undefined) return d; throw new Error(`환경변수 ${k} 가 없습니다`); } return v; };
const PROP   = env("GA_PROPERTY_ID");
const SA     = JSON.parse(env("GA_SA_JSON"));
const SB_URL = env("SUPABASE_URL");
const SB_KEY = env("SUPABASE_SERVICE_ROLE_KEY");
const INGEST = env("GA_INGEST_KEY");
const RE_SUB   = new RegExp(env("GA_PATH_SUB", "subscribe|구독|%EA%B5%AC%EB%8F%85"), "i");
const RE_QUOTE = new RegExp(env("GA_PATH_QUOTE", "quote_subscribe|calc_subscribe|견적|%EA%B2%AC%EC%A0%81"), "i");

const arg = n => { const i = process.argv.indexOf(`--${n}`); return i >= 0 ? process.argv[i + 1] : null; };
const pad = n => String(n).padStart(2, "0");
const ymd = d => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
const kst = (days = 0) => { const d = new Date(Date.now() + 9 * 3600_000); d.setUTCDate(d.getUTCDate() + days); return d; };

// ── 서비스 계정 → 액세스 토큰 (라이브러리 없이 JWT 서명) ──────────
const b64u = b => Buffer.from(b).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64u(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim  = b64u(JSON.stringify({ iss: SA.client_email, scope: "https://www.googleapis.com/auth/analytics.readonly",
                                        aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }));
  const sig = crypto.sign("RSA-SHA256", Buffer.from(`${header}.${claim}`), SA.private_key);
  const jwt = `${header}.${claim}.${b64u(sig)}`;
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer")}&assertion=${jwt}` });
  const j = await r.json();
  if (!j.access_token) throw new Error(`토큰 실패: ${JSON.stringify(j).slice(0, 300)}`);
  return j.access_token;
}

async function runReport(token, body) {
  const r = await fetch(`https://analyticsdata.googleapis.com/v1beta/properties/${PROP}:runReport`, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const j = await r.json();
  if (!r.ok) throw new Error(`GA ${r.status}: ${JSON.stringify(j).slice(0, 400)}`);
  return j.rows ?? [];
}
const rpc = async (fn, args) => {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, { method: "POST",
    headers: { "Content-Type": "application/json", apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` }, body: JSON.stringify(args) });
  const t = await r.text(); if (!r.ok) throw new Error(`HTTP ${r.status} ${t.slice(0, 300)}`); return t ? JSON.parse(t) : null;
};

async function main() {
  const from = arg("from") ?? ymd(kst(-3)), to = arg("to") ?? ymd(kst(0));
  const token = await accessToken();
  const metrics = [{ name: "sessions" }, { name: "totalUsers" }, { name: "screenPageViews" }];
  const range = [{ startDate: from, endDate: to }];

  if (process.argv.includes("--paths")) {
    const rows = await runReport(token, { dateRanges: range, dimensions: [{ name: "pagePath" }], metrics: [{ name: "sessions" }],
      orderBys: [{ metric: { metricName: "sessions" }, desc: true }], limit: 40 });
    console.log(`경로별 세션 (${from}~${to})`);
    rows.forEach(r => console.log(`  ${String(r.metricValues[0].value).padStart(6)}  ${r.dimensionValues[0].value}`
      + (RE_SUB.test(r.dimensionValues[0].value) ? "   ← 구독문의" : RE_QUOTE.test(r.dimensionValues[0].value) ? "   ← 견적서" : "")));
    return;
  }

  // 전체 (날짜별)
  const all = await runReport(token, { dateRanges: range, dimensions: [{ name: "date" }], metrics });
  // 경로별 (날짜 × 경로) → 정규식으로 묶기
  const byPath = await runReport(token, { dateRanges: range, dimensions: [{ name: "date" }, { name: "pagePath" }], metrics, limit: 100000 });
  const agg = {};
  const add = (day, page, path, m) => {
    const k = `${day}|${page}`; agg[k] ??= { day, page, path, sessions: 0, users: 0, views: 0 };
    agg[k].sessions += +m[0].value; agg[k].users += +m[1].value; agg[k].views += +m[2].value;
  };
  all.forEach(r => { const d = r.dimensionValues[0].value; add(`${d.slice(0,4)}-${d.slice(4,6)}-${d.slice(6,8)}`, "all", "/", r.metricValues); });
  byPath.forEach(r => {
    const d = r.dimensionValues[0].value, p = r.dimensionValues[1].value, day = `${d.slice(0,4)}-${d.slice(4,6)}-${d.slice(6,8)}`;
    if (RE_QUOTE.test(p)) add(day, "quote", p, r.metricValues);
    else if (RE_SUB.test(p)) add(day, "subscribe_inquiry", p, r.metricValues);
  });
  const rows = Object.values(agg);
  if (!rows.length) { console.log("가져온 행 없음"); return; }
  const res = await rpc("fn_traffic_ingest", { p_key: INGEST, p_rows: rows });
  console.log(`${from}~${to} · 적재 ${res.rows}행 (전체 ${rows.filter(r=>r.page==="all").length}일 · 구독문의 ${rows.filter(r=>r.page==="subscribe_inquiry").length} · 견적서 ${rows.filter(r=>r.page==="quote").length})`);
}
main().catch(e => { console.error("✕", e.message); process.exit(1); });
