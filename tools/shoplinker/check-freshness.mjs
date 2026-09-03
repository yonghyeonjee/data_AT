#!/usr/bin/env node
/**
 * 원천별 적재 신선도 점검. 지연·미적재가 있으면 종료코드 1 로 끝난다.
 * GitHub 은 워크플로가 실패하면 저장소 참여자에게 메일을 보내므로, 그것이 곧 알림이 된다.
 * (별도 알림 채널을 붙이려면 아래 NOTIFY_WEBHOOK 부분을 켜면 된다 — 잔디·슬랙 모두 같은 형식)
 */
const SB_URL = process.env.SUPABASE_URL;
const SB_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const WEBHOOK = process.env.NOTIFY_WEBHOOK || "";   // 선택: 잔디/슬랙 incoming webhook
if (!SB_URL || !SB_KEY) { console.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 가 없습니다."); process.exit(1); }

const res = await fetch(`${SB_URL}/rest/v1/rpc/fn_data_status`, {
  method: "POST",
  headers: { "Content-Type": "application/json", apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
  body: "{}",
});
if (!res.ok) { console.error("fn_data_status 실패:", res.status, (await res.text()).slice(0, 300)); process.exit(1); }
const d = await res.json();

const pad = (s, w) => String(s ?? "").padEnd(w, " ");
console.log(`기준 ${d.now} · 원장 ${d.db.orders.toLocaleString()}행 · ${d.db.span} · ${d.db.size}\n`);
console.log(pad("원천", 24) + pad("상태", 6) + pad("행", 10) + pad("최근 데이터", 13) + "담당");
for (const s of d.sources) {
  console.log(pad(s.label, 24) + pad(s.state, 6) + pad((s.rows || 0).toLocaleString(), 10)
            + pad(s.to ?? "-", 13) + (s.owner ?? ""));
}

const bad = d.sources.filter((s) => s.state !== "정상");
if (!bad.length) { console.log("\n모든 원천이 기대 주기 안에 있습니다."); process.exit(0); }

const lines = bad.map((s) => {
  const why = s.rows === 0 ? "아직 한 건도 없습니다"
            : `마지막 데이터가 ${s.to} 로 ${s.age_days}일 지났습니다 (기대 ${s.expect_days}일)`;
  return `· ${s.label} — ${why}\n    담당 ${s.owner ?? "-"} / ${s.how ?? ""}`;
});
const msg = `[삼성앤텍 데이터] 확인이 필요한 원천 ${bad.length}건\n\n${lines.join("\n")}\n\n기준 ${d.now}`;
console.log("\n" + msg);

if (WEBHOOK) {
  try {
    await fetch(WEBHOOK, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ body: msg, text: msg }),   // 잔디는 body, 슬랙은 text
    });
    console.log("\n알림 전송 완료");
  } catch (e) { console.log("\n알림 전송 실패:", e.message); }
}
process.exit(1);   // 실패로 끝내야 GitHub 이 메일을 보낸다
