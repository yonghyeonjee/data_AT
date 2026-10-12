// 홈페이지 문의 웹훅 → 데이터센터 상담  (Supabase Edge Function `homepage-hook`, verify_jwt=false · mvp_203)
// POST /functions/v1/homepage-hook?k=<키>        → 상담으로 저장 + 순번 배정 + 잔디 카드 (데이터센터가 보냄)
// POST ...?k=<키>&dry=1                          → 읽은 결과만 돌려줌 (저장 안 함 · 연결 확인용)
// GET  ...?k=<키>                                → 키 확인만 (200 ok / 403)
// 본문은 아무 모양이나 받는다: 잔디 웹훅 JSON(body · connectInfo[{title,description}]) · 일반 JSON(성함·연락처… / name·phone…)
//   · application/x-www-form-urlencoded · multipart/form-data(첨부는 파일 이름만) · text. 해석은 DB(core.f_hook_normalize)가 한다.
// 키는 core.api_key 'homepage_hook' 의 sha256 과 대조 (public.fn_homepage_hook · service_role 만 호출 가능). 헤더 x-dc-key 로 줘도 된다.
// 받은 요청은 성공·실패·키 틀림 전부 raw.webhook_log 에 남는다.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const MAX = 256 * 1024;
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });

function put(obj: Record<string, unknown>, k: string, v: string) {
  if (k in obj) obj[k] = `${obj[k]}, ${v}`; else obj[k] = v;
}

async function readBody(req: Request, ctype: string): Promise<Record<string, unknown>> {
  if (ctype.includes("multipart/form-data")) {
    const fd = await req.formData();
    const o: Record<string, unknown> = {};
    for (const [k, v] of fd.entries()) {
      if (typeof v === "string") put(o, k, v);
      else put(o, k, (v as File).name || "(파일)");   // 첨부는 이름만
    }
    return o;
  }
  const text = await req.text();
  if (text.length > MAX) throw new Error("too large");
  if (!text.trim()) return {};
  if (ctype.includes("application/x-www-form-urlencoded")) {
    const o: Record<string, unknown> = {};
    for (const [k, v] of new URLSearchParams(text)) put(o, k, v);
    // 잔디처럼 payload=<json> 으로 오는 경우
    if (typeof o.payload === "string") { try { return { ...o, ...JSON.parse(o.payload as string) }; } catch { /* 그대로 */ } }
    return o;
  }
  try {
    const j = JSON.parse(text);
    if (j && typeof j === "object" && !Array.isArray(j)) return j;
    if (Array.isArray(j)) return { fields: j };
    return { body: String(j) };
  } catch {
    return { body: text };
  }
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const k = (url.searchParams.get("k") || req.headers.get("x-dc-key") || "").trim();
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(k)) return json({ ok: false, error: "key" }, 403);
  const dry = ["1", "true", "y"].includes((url.searchParams.get("dry") || "").toLowerCase()) || req.method === "GET" || req.method === "HEAD";
  if (!["POST", "PUT", "GET", "HEAD"].includes(req.method)) return json({ ok: false, error: "method" }, 405);

  const ctype = (req.headers.get("content-type") || "").toLowerCase();
  let body: Record<string, unknown> = {};
  if (req.method === "POST" || req.method === "PUT") {
    try { body = await readBody(req, ctype); }
    catch (e) { return json({ ok: false, error: String((e as Error).message || e) }, 413); }
  }
  // 쿼리로 온 값도 (k·dry 제외)
  for (const [qk, qv] of url.searchParams) if (qk !== "k" && qk !== "dry" && !(qk in body)) body[qk] = qv;

  const meta = {
    dry: dry ? "1" : "",
    ip: req.headers.get("cf-connecting-ip") || (req.headers.get("x-forwarded-for") || "").split(",")[0].trim(),
    ua: req.headers.get("user-agent") || "",
    ctype: ctype || req.method,
  };
  const base = Deno.env.get("SUPABASE_URL")!;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  let r: Response;
  try {
    r = await fetch(`${base}/rest/v1/rpc/fn_homepage_hook`, {
      method: "POST",
      headers: { apikey: svc, Authorization: `Bearer ${svc}`, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ p_key: k, p_body: body, p_meta: meta }),
      signal: AbortSignal.timeout(15000),
    });
  } catch (e) {
    return json({ ok: false, error: "datacenter unreachable" }, 502);
  }
  if (!r.ok) return json({ ok: false, error: "datacenter " + r.status }, 502);
  const res = await r.json() as Record<string, unknown>;
  if (res && res.reason === "key") return json({ ok: false, error: "key" }, 403);
  if (req.method === "HEAD") return new Response(null, { status: 200 });
  if (!res || res.ok !== true) return json({ ok: false, error: res?.reason || "store", log: res?.log }, 500);
  return json(res, 200);
});
