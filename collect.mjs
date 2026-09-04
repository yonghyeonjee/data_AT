#!/usr/bin/env node
/**
 * 샵링커 주문 상세조회 API → Supabase core.orders
 * ───────────────────────────────────────────────────────────────
 * GAS 프로젝트 shoplinker_api_input 의 수집 로직을 GitHub Actions 로 옮긴 것.
 * 구글시트에 쓰지 않고 Supabase RPC(fn_sl_upsert)로 바로 넣는다.
 *
 * 왜 Actions 인가 (조사 결과, 2026-09-03)
 *   · apiweb.shoplinker.co.kr 의 HTTPS 는 DH 파라미터가 취약(1024bit 이하)해서
 *     Deno(rustls) 와 OpenSSL 3.x 는 핸드셰이크 자체를 거부한다.
 *     → Supabase Edge Function / Postgres http 에서는 HTTPS 로 못 붙는다.
 *     Node 는 SECLEVEL 을 낮출 수 있어 HTTPS 를 유지한 채 붙을 수 있다. (아래 TLS_CIPHERS)
 *   · 샵링커 서버는 iteminfo_url 로 *.supabase.co 를 읽지 못한다("could not open XML input").
 *     script.google.com / raw.githubusercontent.com 은 읽는다.
 *     → 조건 XML 은 계속 GAS 웹앱(/exec)이 응답한다. 그 GAS 에는 로직이 없다(에코 전용).
 *
 * 실행
 *   node collect.mjs                       최근분 (기본)
 *   node collect.mjs --from 20260902 --to 20260930
 *   node collect.mjs --back 202512         2025-12 부터 과거로 빈 달이 이어질 때까지
 *   node collect.mjs --dry                 적재하지 않고 건수만
 */
import https from "node:https";
import http from "node:http";
import zlib from "node:zlib";

// ── 환경 ────────────────────────────────────────────────────────
const env = (k, d) => {
  const v = process.env[k];
  if (v === undefined || v === "") {
    if (d !== undefined) return d;
    throw new Error(`환경변수 ${k} 가 없습니다. 저장소 Secrets 를 확인하세요.`);
  }
  return v;
};
const CUSTOMER_ID = env("SL_CUSTOMER_ID");
const REQ_URL     = env("SL_REQ_URL");            // 조건 XML 을 응답하는 주소 (GAS /exec)
const SB_URL      = env("SUPABASE_URL");
const SB_KEY      = env("SUPABASE_SERVICE_ROLE_KEY");

const BASE = "https://apiweb.shoplinker.co.kr/ShoplinkerApi/v7/order/detailOrderlist.php";
// OpenSSL 3 의 기본 보안수준은 상대의 약한 DH 를 거부한다. 낮은 쪽으로 한 단계씩 물러난다.
// 낮추는 대상은 이 서버 한 곳뿐이고, 통신 자체는 그대로 TLS 로 암호화된다.
// 성공한 단계는 로그에 찍히므로, 샵링커가 TLS 를 고치면 자연히 위쪽으로 돌아간다.
const TLS_LADDER = [null, "DEFAULT@SECLEVEL=1", "DEFAULT@SECLEVEL=0"];
let TLS_PICKED = null;   // 한 번 성공하면 그 단계로 고정

const PAGE_SIZE = 500;
const MAX_PAGE  = 200;
const SLEEP_MS  = Number(process.env.SL_SLEEP_MS ?? 500);
const CHUNK     = 300;
const RETRY     = 3;

// ── 조회 작업 정의 (GAS SL_JOBS 와 동일) ──────────────────────────
// 상태별 "이벤트 날짜"로 조회해야 최근 N일 사이에 변한 건이 잡힌다.
const DAILY_JOBS = [
  { name: "발주확인",      flag: "002", dateType: "002", days: 3 },
  { name: "송장등록",      flag: "015", dateType: "003", days: 3 },
  { name: "송장전송완료",   flag: "003", dateType: "004", days: 3 },
  { name: "신규수집분",     flag: "002", dateType: "001", days: 3 },
  { name: "취소/교환/반품", flag: "999", dateType: "001", days: 30 },
];
const ALL_FLAGS = ["002", "015", "003", "999"];

const FLAG_LABEL = {
  "002": "발주확인", "015": "송장등록", "003": "송장전송완료",
  "013": "취소완료", "005": "교환완료", "008": "반품완료",
};
const REFUND_FLAGS = { "013": 1, "008": 1 };   // 교환완료는 환불이 아니다
const DELIVERY = { delv0094: "CJ대한통운", delv0049: "삼성물류배송" };

// ── 유틸 ────────────────────────────────────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pad = (n) => String(n).padStart(2, "0");
const S = (v) => (v === undefined || v === null ? "" : String(v).trim());
function ymd(d) { return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`; }
function kstNow() { return new Date(Date.now() + 9 * 3600_000); }
function kstShift(days) { const d = kstNow(); d.setUTCDate(d.getUTCDate() + days); return d; }
function monthRange(ym) {                       // '202512' → ['20251201','20251231']
  const y = +ym.slice(0, 4), m = +ym.slice(4, 6);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return [`${y}${pad(m)}01`, `${y}${pad(m)}${pad(last)}`];
}
function prevMonth(ym) {
  let y = +ym.slice(0, 4), m = +ym.slice(4, 6) - 1;
  if (m === 0) { m = 12; y -= 1; }
  return `${y}${pad(m)}`;
}
function num(v) {
  const s = S(v).replace(/[^\d.\-]/g, "");
  if (s === "" || s === "-") return null;
  const n = Number(s);
  return Number.isNaN(n) ? null : n;
}
function toISO(v) {
  const s = S(v).replace(/\D/g, "");
  if (s.length < 8) return null;
  const y = +s.slice(0, 4), mo = +s.slice(4, 6), d = +s.slice(6, 8);
  if (y < 2000 || y > 2100 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  const hh = s.length >= 10 ? +s.slice(8, 10) : 0;
  const mi = s.length >= 12 ? +s.slice(10, 12) : 0;
  const ss = s.length >= 14 ? +s.slice(12, 14) : 0;
  return `${y}-${pad(mo)}-${pad(d)}T${pad(hh)}:${pad(mi)}:${pad(ss)}+09:00`;
}

// ── HTTP ────────────────────────────────────────────────────────
/** EUC-KR 응답을 그대로 받아 문자열로 돌려준다 */
function getRaw(urlStr, { ciphers } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(urlStr);
    const mod = u.protocol === "http:" ? http : https;
    const req = mod.request(u, {
      method: "GET",
      timeout: 60_000,
      headers: { "User-Agent": "samsungat-collector/1.0", "Accept-Encoding": "gzip, deflate" },
      ...(u.protocol === "https:" && ciphers ? { ciphers, minVersion: "TLSv1" } : {}),
    }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
        res.resume();
        return resolve(getRaw(new URL(res.headers.location, u).toString(), { ciphers }));
      }
      const chunks = [];
      let stream = res;
      const enc = S(res.headers["content-encoding"]).toLowerCase();
      if (enc === "gzip") stream = res.pipe(zlib.createGunzip());
      else if (enc === "deflate") stream = res.pipe(zlib.createInflate());
      stream.on("data", (c) => chunks.push(c));
      stream.on("end", () => {
        const buf = Buffer.concat(chunks);
        resolve({ status: res.statusCode, buf, text: new TextDecoder("euc-kr").decode(buf) });
      });
      stream.on("error", reject);
    });
    req.on("timeout", () => req.destroy(new Error("timeout")));
    req.on("error", reject);
    req.end();
  });
}

async function postJSON(urlStr, body, headers) {
  const res = await fetch(urlStr, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
  const txt = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status} ${txt.slice(0, 400)}`);
  return txt ? JSON.parse(txt) : null;
}
const rpc = (fn, args) =>
  postJSON(`${SB_URL}/rest/v1/rpc/${fn}`, args ?? {}, { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` });

// ── XML (평평한 구조라 태그 추출로 충분하다) ──────────────────────
const ENT = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'" };
function unesc(s) {
  return s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
          .replace(/&(amp|lt|gt|quot|apos);/g, (m) => ENT[m])
          .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d));
}
function fields(block) {
  const o = {};
  const re = /<([A-Za-z0-9_]+)>([\s\S]*?)<\/\1>/g;
  let m;
  while ((m = re.exec(block))) o[m[1]] = unesc(m[2]).trim();
  return o;
}
function parseResponse(text) {
  const err = text.match(/<ResultMessage>([\s\S]*?)<\/ResultMessage>/);
  if (err && !/<order>/i.test(text)) {
    const f = fields(err[1]);
    return { error: f.message || "알 수 없는 오류", orders: [], totalPage: 0, totalCount: 0 };
  }
  const head = text.match(/<header>([\s\S]*?)<\/header>/);
  const h = head ? fields(head[1]) : {};
  const orders = [];
  const re = /<order>([\s\S]*?)<\/order>/g;
  let m;
  while ((m = re.exec(text))) orders.push(fields(m[1]));
  return {
    error: null, orders,
    totalPage: Number(h.total_page) || (orders.length ? 1 : 0),
    totalCount: Number(h.total_count) || orders.length,
  };
}

// ── 한 페이지 조회 ───────────────────────────────────────────────
function reqUrl(params) {
  const q = new URLSearchParams({ customer_id: CUSTOMER_ID, ...params });
  return `${REQ_URL}${REQ_URL.includes("?") ? "&" : "?"}${q.toString()}`;
}
/** 약한 DH 때문에 핸드셰이크가 깨지면 보안수준을 한 단계 낮춰 다시 시도한다 */
async function getWithTls(target) {
  const start = TLS_PICKED === null ? 0 : TLS_LADDER.indexOf(TLS_PICKED);
  let lastErr;
  for (let i = Math.max(0, start); i < TLS_LADDER.length; i++) {
    try {
      const r = await getRaw(target, { ciphers: TLS_LADDER[i] });
      if (TLS_PICKED !== TLS_LADDER[i]) {
        TLS_PICKED = TLS_LADDER[i];
        console.log(`  TLS: ${TLS_LADDER[i] ?? "기본값"} 으로 연결`);
      }
      return r;
    } catch (e) {
      lastErr = e;
      const m = String(e.message || e);
      if (!/handshake|dh key|SSL|EPROTO|ssl3|alert/i.test(m)) throw e;
    }
  }
  throw new Error(`TLS 연결 실패 — ${lastErr?.message ?? "원인 불명"}`);
}

async function fetchPage(params) {
  const target = `${BASE}?iteminfo_url=${encodeURIComponent(reqUrl(params))}`;
  let lastErr;
  for (let i = 0; i < RETRY; i++) {
    try {
      const r = await getWithTls(target);
      if (r.status !== 200) throw new Error(`HTTP ${r.status}`);
      if (!r.text.includes("<Shoplinker") && !r.text.includes("<ResultMessage"))
        throw new Error(`XML 아님: ${r.text.slice(0, 160)}`);
      return parseResponse(r.text);
    } catch (e) {
      lastErr = e;
      if (i < RETRY - 1) await sleep(1500 * (i + 1));
    }
  }
  throw lastErr;
}

// ── 매핑 ────────────────────────────────────────────────────────
let CH_MAP = [];
function channelOf(mall, acct) {
  return CH_MAP.find((c) => c.mall === mall && c.acct === acct)
      ?? CH_MAP.find((c) => c.mall === mall && c.acct === "*")
      ?? null;
}
function mapRow(o, job) {
  const mall = S(o.mall_name), acct = S(o.seller_admin_id);
  const ch = channelOf(mall, acct);
  const flag = S(o.order_flag);
  const gross = num(o.order_price) ?? 0;
  const isRefund = !!REFUND_FLAGS[flag];
  const deliv = S(o.delivery);
  return {
    source_ref: S(o.pk_order_id),
    order_no: S(o.mall_order_id),
    order_at: toISO(o.custom_order_date) ?? toISO(o.order_reg_date),
    confirmed_at: toISO(o.order_confirm_date),
    shipped_at: toISO(o.delivery_trans_date),
    cancelled_at: isRefund ? toISO(o.order_reg_date) : null,
    channel_name: ch?.name ?? (mall || "기타"),
    channel_type: ch?.type ?? "오픈마켓",
    channel_account: acct,
    status: FLAG_LABEL[flag] ?? flag,
    product_code: S(o.shoplinker_product_id),
    model_code: (S(o.partner_product_id) || S(o.sku_code)).toUpperCase() || null,
    product_name: S(o.product_name),
    option_text: S(o.sku),
    qty: num(o.quantity) ?? 1,
    unit_price: num(o.sale_price),
    gross_amount: gross,
    refund_amount: isRefund ? gross : 0,
    payment_method: S(o.channel_type),
    customer_name: S(o.order_name),
    customer_phone: S(o.order_cel) || S(o.order_tel),
    email: S(o.order_email),
    address: S(o.receive_addr),
    notes: S(o.exchange_order_yn) === "Y" ? "교환주문" : null,
    raw: {
      job, mall_id: S(o.mall_id), ship_no: S(o.ship_no),
      delivery: DELIVERY[deliv] ?? deliv, invoice: S(o.invoice),
      item_gubun: S(o.item_gubun), order_input_type: S(o.order_input_type),
      exchange_org_id: S(o.exchange_org_id), receive: S(o.receive),
    },
  };
}

// ── 작업 실행 ───────────────────────────────────────────────────
const DRY = process.argv.includes("--dry");

async function runJob(job, st, ed) {
  let page = 1, totalPage = 1, fetched = 0, ins = 0, upd = 0, nokey = 0;
  let batch = [];
  const flush = async () => {
    if (!batch.length) return;
    if (DRY) { batch = []; return; }
    const r = await rpc("fn_sl_upsert", { p_job: job.name, p_rows: batch });
    ins += r.inserted; upd += r.updated; nokey += r.nokey;
    batch = [];
  };

  while (page <= totalPage && page <= MAX_PAGE) {
    const res = await fetchPage({
      st_date: st, ed_date: ed, date_type: job.dateType, order_flag: job.flag,
      page_no: String(page), total_standard_count: String(PAGE_SIZE),
    });
    if (res.error) {
      // "발주확인 주문이 없습니다" 류는 정상적인 0건 응답이다
      if (/없습니다|없음/.test(res.error)) break;
      throw new Error(res.error);
    }
    if (res.totalPage > 0) totalPage = res.totalPage;
    for (const o of res.orders) {
      fetched++;
      const row = mapRow(o, job.name);
      if (row.source_ref) batch.push(row);
      if (batch.length >= CHUNK) await flush();
    }
    if (!res.orders.length) break;
    page++;
    if (page <= totalPage) await sleep(SLEEP_MS);
  }
  await flush();
  return { pages: page - 1, fetched, ins, upd, nokey };
}

async function runRange(label, st, ed, jobs) {
  let tot = { fetched: 0, ins: 0, upd: 0, nokey: 0 };
  for (const job of jobs) {
    const jst = job.days ? ymd(kstShift(-job.days)) : st;
    const jed = ed;
    let r;
    try {
      r = await runJob(job, jst, jed);
    } catch (e) {
      console.log(`  ✕ ${job.name} ${jst}~${jed} — ${e.message}`);
      if (!DRY) await rpc("fn_sl_log", {
        p_status: "ERROR", p_job: job.name, p_period: `${jst}~${jed}`,
        p_pages: 0, p_fetched: 0, p_ins: 0, p_upd: 0, p_note: String(e.message).slice(0, 400), p_mark_ymd: null,
      });
      continue;
    }
    tot.fetched += r.fetched; tot.ins += r.ins; tot.upd += r.upd; tot.nokey += r.nokey;
    console.log(`  · ${job.name.padEnd(12)} ${jst}~${jed}  ${String(r.pages).padStart(2)}p  수신 ${String(r.fetched).padStart(5)}  신규 ${String(r.ins).padStart(5)}  갱신 ${String(r.upd).padStart(5)}`);
    if (!DRY) await rpc("fn_sl_log", {
      p_status: "OK", p_job: job.name, p_period: `${jst}~${jed}`,
      p_pages: r.pages, p_fetched: r.fetched, p_ins: r.ins, p_upd: r.upd,
      p_note: r.nokey ? `고객키없음 ${r.nokey}` : "", p_mark_ymd: null,
    });
  }
  console.log(`${label} → 수신 ${tot.fetched} · 신규 ${tot.ins} · 갱신 ${tot.upd}`);
  return tot;
}

// ── 진입점 ──────────────────────────────────────────────────────
function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : null;
}

/** 스케줄 걸기 전에 한 번 돌려보는 점검. 개인정보가 안 나오도록 결과 0건 기간만 쓴다. */
async function selftest() {
  console.log("① 조건 XML 주소 확인:", REQ_URL.replace(/\/[^/]{20,}\//, "/…/"));
  const own = await getRaw(reqUrl({ st_date: "19000101", ed_date: "19000102", date_type: "001", order_flag: "002" }));
  console.log(own.text.includes("<customer_id>")
    ? "   ✓ 조건 XML 이 정상 응답합니다"
    : `   ✕ 조건 XML 이 이상합니다:\n${own.text.slice(0, 300)}`);

  console.log("② 샵링커가 그 주소를 읽을 수 있는지 (결과 0건 기간)");
  const res = await fetchPage({ st_date: "19000101", ed_date: "19000102", date_type: "001", order_flag: "002", page_no: "1", total_standard_count: "1" });
  if (res.error && /could not open/i.test(res.error)) {
    console.log(`   ✕ 샵링커가 조건 XML 주소를 못 읽습니다 — ${res.error}`);
    console.log("     SL_REQ_URL 을 샵링커가 접근 가능한 곳으로 바꿔야 합니다.");
    process.exit(1);
  }
  console.log(`   ✓ 읽었습니다 (응답: ${res.error ?? `주문 ${res.totalCount}건`})`);

  console.log("③ Supabase 연결");
  const ctx = await rpc("fn_sl_context", {});
  console.log(`   ✓ 채널 매핑 ${ctx.channel_map?.length ?? 0}건 · 원장 마지막 주문일 ${ctx.last_order_at ?? "(없음)"}`);

  console.log("\n점검 통과. 이제 정기 수집을 켜도 됩니다.");
}

async function main() {
  const started = Date.now();
  if (process.argv.includes("--selftest")) return selftest();
  const ctx = await rpc("fn_sl_context", {});
  CH_MAP = ctx.channel_map ?? [];
  console.log(`채널 매핑 ${CH_MAP.length}건 · 원장 마지막 주문일 ${ctx.last_order_at ?? "(없음)"}`);
  if (DRY) console.log("*** DRY RUN — 적재하지 않습니다 ***");

  const back = arg("back");
  const from = arg("from"), to = arg("to");
  const today = ymd(kstNow());
  let grand = { fetched: 0, ins: 0, upd: 0 };

  if (back) {
    // 과거로 한 달씩 내려가며, 빈 달이 연속 EMPTY_STOP 번 나오면 멈춘다
    const EMPTY_STOP = Number(process.env.SL_EMPTY_STOP ?? 2);
    const FLOOR = arg("floor") ?? "201801";
    const jobs = ALL_FLAGS.map((f) => ({ name: `백필 ${FLAG_LABEL[f] ?? f}`, flag: f, dateType: "001", days: 0 }));
    let ym = back, empty = 0;
    while (ym >= FLOOR) {
      const [st, ed] = monthRange(ym);
      console.log(`\n── ${ym} (${st}~${ed}) ──`);
      const t = await runRange(ym, st, ed, jobs);
      grand.fetched += t.fetched; grand.ins += t.ins; grand.upd += t.upd;
      empty = t.fetched === 0 ? empty + 1 : 0;
      if (empty >= EMPTY_STOP) { console.log(`\n빈 달 ${empty}회 연속 → 여기서 멈춥니다 (${ym})`); break; }
      ym = prevMonth(ym);
    }
    if (!DRY) await rpc("fn_sl_log", {
      p_status: "BACKFILL", p_job: "전체", p_period: `${ym}~${back}`,
      p_pages: 0, p_fetched: grand.fetched, p_ins: grand.ins, p_upd: grand.upd,
      p_note: `${((Date.now() - started) / 1000).toFixed(0)}초`, p_mark_ymd: null,
    });
  } else if (from) {
    const jobs = ALL_FLAGS.map((f) => ({ name: `수집 ${FLAG_LABEL[f] ?? f}`, flag: f, dateType: "001", days: 0 }));
    console.log(`\n── ${from} ~ ${to ?? today} ──`);
    grand = await runRange("기간지정", from, to ?? today, jobs);
    if (!DRY) await rpc("fn_sl_log", {
      p_status: "DONE", p_job: "전체", p_period: `${from}~${to ?? today}`,
      p_pages: 0, p_fetched: grand.fetched, p_ins: grand.ins, p_upd: grand.upd,
      p_note: `${((Date.now() - started) / 1000).toFixed(0)}초`, p_mark_ymd: today,
    });
  } else {
    console.log(`\n── 정기 수집 (~${today}) ──`);
    grand = await runRange("정기", today, today, DAILY_JOBS);
    if (!DRY) await rpc("fn_sl_log", {
      p_status: "DONE", p_job: "전체", p_period: `~${today}`,
      p_pages: 0, p_fetched: grand.fetched, p_ins: grand.ins, p_upd: grand.upd,
      p_note: `${((Date.now() - started) / 1000).toFixed(0)}초`, p_mark_ymd: today,
    });
  }

  console.log(`\n합계 — 수신 ${grand.fetched} · 신규 ${grand.ins} · 갱신 ${grand.upd} · ${((Date.now() - started) / 1000).toFixed(0)}초`);
}

main().catch((e) => { console.error("실패:", e.message); process.exit(1); });
