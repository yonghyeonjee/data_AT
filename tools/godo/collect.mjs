#!/usr/bin/env node
/**
 * 고도몰 OpenAPI(주문 조회) → Datacenter raw.godo_order_hist   (mvp_170 · 2026-09-21)
 * ───────────────────────────────────────────────────────────────
 * 시흥몰(OpenAPI 키가 있는 몰)의 과거 주문을 4개월씩 끌어와 원본 행으로 쌓는다.
 * P몰·AT몰·S몰은 OpenAPI 키가 없어 GodomallCollector.exe(엑셀) 가 같은 자리에 넣는다.
 * 원장(core.orders)·고객(crm.customer)에는 쓰지 않는다 — 검수 뒤 별도 판단.
 *
 * 실행 (GitHub Actions · godo-orders.yml)
 *   node tools/godo/collect.mjs --from 2021-01-01 --to 2021-04-30 [--mall 시흥몰] [--dry]
 *   node tools/godo/collect.mjs --selftest        네트워크 없이 파싱·해시만 확인
 *
 * 환경변수(Secrets): GODO_PARTNER_KEY · GODO_KEY · GODO_INGEST_KEY(core.api_key 'godo_order_hist') · SUPABASE_URL
 *
 * 고도몰 API 메모 (2025-09 콜랩 스크립트에서 확인한 것)
 *   · POST form: partner_key, key, dateType=order, startDate, endDate, size(≤100), lastOrder(커서), sort=orderNo desc
 *   · 응답 XML: data.header.code('000' 성공) · data.return.order_data[] (orderInfoData[] · orderGoodsData[])
 *   · 헤더 ratelimit-available-level 이 EXHAUSTED 면 3초 쉼, 429 면 5초 쉬고 재시도
 *   · 조회 구간은 29일씩 — 한 번에 길게 잡으면 커서 페이징이 어긋난다
 */
import crypto from "node:crypto";
import { XMLParser } from "fast-xml-parser";

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const has = k => args.includes(k);
const SELFTEST = has("--selftest");
const DRY = has("--dry");
const MALL = opt("--mall", "시흥몰");
const FROM = opt("--from"), TO = opt("--to");

const env = (k, d) => { const v = process.env[k]; if (v === undefined || v === "") { if (d !== undefined) return d; throw new Error(`환경변수 ${k} 가 없습니다`); } return v; };
const API_URL = "https://openhub.godo.co.kr/godomall5/order/Order_Search.php";
const PAGE = 100, CHUNK_DAYS = 29, BATCH = 500;
const SB_ANON = "sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW";   // 공개 키 (anon) — 실제 권한은 GODO_INGEST_KEY 가 결정

const xml = new XMLParser({ ignoreAttributes: true, parseTagValue: false, trimValues: true });
const asList = x => x == null ? [] : Array.isArray(x) ? x : [x];
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ── 평탄화: 주문 1건 × 상품 줄 = 1행 (콜랩 스크립트와 같은 열 이름) ──
export function flatten(order, mall) {
  const info = asList(order.orderInfoData)[0] || {};
  return asList(order.orderGoodsData).map((g, i) => {
    const data = {
      "몰구분": mall, "주문번호": order.orderNo, "주문일자": order.orderDate, "결제일자": order.paymentDt,
      "주문상태": order.orderStatus, "첫구매": order.firstSaleFl, "결제금액": order.settlePrice, "총상품금액": order.totalGoodsPrice,
      "배송비": order.totalDeliveryCharge, "결제수단": order.settleKind, "주문경로": order.orderChannel,
      "회원번호": order.memNo, "회원ID": order.memId, "회원그룹": order.memGroupNm,
      "주문자명": info.orderName, "주문자휴대폰": info.orderCellPhone, "주문자전화": info.orderPhone, "이메일": info.orderEmail,
      "SMS동의": info.smsFl, "주소": info.orderAddress,
      "상품번호": g.goodsNo, "상품코드": g.goodsCd, "모델명": g.goodsModelNo, "상품명": g.goodsNm, "수량": g.goodsCnt,
      "상품가격": g.goodsPrice, "옵션": g.optionInfo, "품목상태": g.orderStatus, "취소일": g.cancelDt, "줄번호": g.sno ?? String(i + 1),
    };
    for (const k of Object.keys(data)) if (data[k] === undefined || data[k] === null) delete data[k];
    // 해시는 상태가 바뀌어도 같은 줄이 같은 키가 되도록 몰·주문번호·상품번호·줄번호로 만든다 (엑셀 수집기는 행 전체 해시 — 서로 다른 몰이라 겹치지 않는다)
    const h = crypto.createHash("sha1").update(`${mall}|${order.orderNo}|${g.goodsNo ?? ""}|${data["줄번호"]}`).digest("hex");
    const at = String(order.orderDate || "").match(/^\d{4}-\d{2}-\d{2}( \d{2}:\d{2}(:\d{2})?)?/);
    return { h, order_no: String(order.orderNo || ""), ordered_at: at ? at[0] : null, data };
  });
}

function parseResp(text) {
  const root = xml.parse(text)?.data || {};
  const h = root.header || {};
  return { code: String(h.code ?? ""), msg: h.msg, orders: asList(root.return?.order_data) };
}

// Secrets 에 붙여넣을 때 따옴표·공백·줄바꿈이 섞이는 사고가 잦다 — 키 글자([A-Za-z0-9+/=]) 만 남긴다
const cleanKey = v => String(v || "").replace(/[^A-Za-z0-9+/=]/g, "");
const KEYS = { partner: cleanKey(process.env.GODO_PARTNER_KEY), key: cleanKey(process.env.GODO_KEY) };
function keyDiag() {   // 값은 안 찍고 길이·앞뒤 4자만 — 콜랩 원본과 대조용 (시흥몰 원본: partner 32자 TiU5…Qw== · key 144자 USVF…JUM0)
  const f = v => v ? `${v.length}자 ${v.slice(0, 4)}…${v.slice(-4)}` : "(없음)";
  console.log(`   키 확인 · partner_key ${f(KEYS.partner)} · key ${f(KEYS.key)}`);
}
async function callApi(extra) {
  if (!KEYS.partner || !KEYS.key) throw new Error("환경변수 GODO_PARTNER_KEY / GODO_KEY 가 없습니다");
  const body = new URLSearchParams({ partner_key: KEYS.partner, key: KEYS.key, sort: "orderNo desc", ...extra });
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const r = await fetch(API_URL, { method: "POST", body, headers: { "content-type": "application/x-www-form-urlencoded" } });
      if (r.status === 429) { console.log("   ! 429 → 5초 대기"); await sleep(5000); continue; }
      const text = await r.text();
      const lvl = String(r.headers.get("ratelimit-available-level") || "").toUpperCase();
      const p = parseResp(text);
      return { ...p, exhausted: lvl === "EXHAUSTED" };
    } catch (e) { console.log(`   ! 오류 ${e.message} → 재시도`); await sleep(2000); }
  }
  return { code: "ERR", msg: "재시도 초과", orders: [] };
}

function* chunks(from, to, days = CHUNK_DAYS) {
  let s = new Date(from + "T00:00:00Z"); const e = new Date(to + "T00:00:00Z");
  while (s <= e) {
    const t = new Date(Math.min(s.getTime() + days * 86400000, e.getTime()));
    yield [s.toISOString().slice(0, 10), t.toISOString().slice(0, 10)];
    s = new Date(t.getTime() + 86400000);
  }
}

async function ingest(rows, file) {
  const url = `${env("SUPABASE_URL")}/rest/v1/rpc/fn_godo_order_hist_ingest`;
  let tot = { rows: 0, new: 0, dup: 0 };
  for (let i = 0; i < rows.length; i += BATCH) {
    const r = await fetch(url, { method: "POST", headers: { "content-type": "application/json", apikey: SB_ANON, Authorization: `Bearer ${SB_ANON}` },
      body: JSON.stringify({ p_key: env("GODO_INGEST_KEY"), p_mall: MALL, p_file: file, p_rows: rows.slice(i, i + BATCH) }) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(`적재 실패 ${r.status}: ${JSON.stringify(j).slice(0, 200)}`);
    for (const k of Object.keys(tot)) tot[k] += Number(j[k] || 0);
  }
  return tot;
}

async function main() {
  if (SELFTEST) {
    const sample = `<?xml version="1.0" encoding="utf-8"?><data><header><code>000</code><msg>success</msg></header><return>
      <order_data><orderNo>2101010001</orderNo><orderDate>2021-01-01 10:20:30</orderDate><orderStatus>g1</orderStatus><settlePrice>123000</settlePrice>
        <orderInfoData><orderName>홍길동</orderName><orderCellPhone>010-1111-2222</orderCellPhone></orderInfoData>
        <orderGoodsData><goodsNo>1000001</goodsNo><goodsNm>테스트 상품 A</goodsNm><goodsCnt>1</goodsCnt><goodsPrice>100000</goodsPrice></orderGoodsData>
        <orderGoodsData><goodsNo>1000002</goodsNo><goodsNm>테스트 상품 B</goodsNm><goodsCnt>2</goodsCnt><goodsPrice>11500</goodsPrice></orderGoodsData>
      </order_data>
      <order_data><orderNo>2101010002</orderNo><orderDate>2021-01-02 09:00:00</orderDate><orderInfoData><orderName>김철수</orderName></orderInfoData>
        <orderGoodsData><goodsNo>1000003</goodsNo><goodsNm>테스트 상품 C</goodsNm></orderGoodsData></order_data>
    </return></data>`;
    const p = parseResp(sample);
    const rows = p.orders.flatMap(o => flatten(o, MALL));
    const again = p.orders.flatMap(o => flatten(o, MALL));
    const ok = p.code === "000" && rows.length === 3 && rows[0].ordered_at === "2021-01-01 10:20:30" && rows[0].data["주문자휴대폰"] === "010-1111-2222"
      && rows[1].data["상품명"] === "테스트 상품 B" && new Set(rows.map(r => r.h)).size === 3 && rows.every((r, i) => r.h === again[i].h);
    console.log(ok ? "selftest ✓ 3행 · 해시 안정 · 날짜 파싱" : "selftest ✗", JSON.stringify(rows.map(r => [r.h.slice(0, 8), r.order_no, r.ordered_at, r.data["상품명"]])));
    process.exit(ok ? 0 : 1);
  }
  if (!FROM || !TO) throw new Error("--from YYYY-MM-DD --to YYYY-MM-DD 가 필요합니다");
  console.log(`>> ${MALL} ${FROM}~${TO} 수집${DRY ? " (dry)" : ""}`);
  keyDiag();
  let grand = { orders: 0, rows: 0, new: 0, dup: 0 };
  for (const [s, e] of chunks(FROM, TO)) {
    const seen = new Set(); let cursor = null, page = 0, orders = [];
    while (true) {
      const q = { dateType: "order", startDate: s, endDate: e, size: String(PAGE) };
      if (cursor) q.lastOrder = cursor;
      const r = await callApi(q);
      if (!["000", "0"].includes(r.code)) { console.log(`   [${s}~${e}] 실패 ${r.code}: ${r.msg}`); break; }
      const batch = r.orders.filter(o => !seen.has(o.orderNo));
      if (!batch.length) break;
      batch.forEach(o => seen.add(o.orderNo)); orders.push(...batch); page++;
      console.log(`   [${s}~${e}] p${page} +${batch.length} 누적 ${orders.length}`);
      if (batch.length < PAGE) break;
      cursor = batch[batch.length - 1].orderNo;
      await sleep(r.exhausted ? 3000 : 300);
    }
    const rows = orders.flatMap(o => flatten(o, MALL));
    grand.orders += orders.length; grand.rows += rows.length;
    if (rows.length && !DRY) {
      const t = await ingest(rows, `api_${MALL}_${s}_${e}`);
      grand.new += t.new; grand.dup += t.dup;
      console.log(`   [${s}~${e}] 적재 ${t.rows}행 · 새 ${t.new} · 중복 ${t.dup}`);
    }
    await sleep(500);
  }
  console.log(`>> 끝 · 주문 ${grand.orders} · 행 ${grand.rows} · 새 ${grand.new} · 중복 ${grand.dup}`);
}
main().catch(e => { console.error("✗", e.message); process.exit(1); });
