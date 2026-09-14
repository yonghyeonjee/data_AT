// 휴가 달력 → 구글 캘린더 구독용 ICS 피드  (Supabase Edge Function `leave-ics`, verify_jwt=false)
// GET /functions/v1/leave-ics?k=<토큰>  →  text/calendar
// 토큰은 core.api_key 'leave_ics' 의 SHA-256 과 대조 (DB 함수 public.fn_leave_ics 가 확인). 구글이 헤더를 못 붙이므로 JWT 는 안 쓴다.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") return new Response("method not allowed", { status: 405 });
  const url = new URL(req.url);
  const k = (url.searchParams.get("k") || "").trim();
  if (!/^[0-9a-f]{32,64}$/.test(k)) return new Response("forbidden", { status: 403 });
  const base = Deno.env.get("SUPABASE_URL")!;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  // PostgREST 는 스칼라 함수 결과를 JSON 문자열로 준다 (text/plain Accept 는 406)
  const r = await fetch(`${base}/rest/v1/rpc/fn_leave_ics`, {
    method: "POST",
    headers: { apikey: svc, Authorization: `Bearer ${svc}`, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ p_key: k }),
  });
  if (r.status === 401 || r.status === 403) return new Response("forbidden", { status: 403 });
  if (!r.ok) return new Response("error " + r.status, { status: 502 });
  const ics = (await r.json()) as string;
  if (typeof ics !== "string" || !ics.startsWith("BEGIN:VCALENDAR")) return new Response("error body", { status: 502 });
  return new Response(req.method === "HEAD" ? null : ics, {
    status: 200,
    headers: { "Content-Type": "text/calendar; charset=utf-8", "Content-Disposition": "inline; filename=\"leave.ics\"", "Cache-Control": "public, max-age=600" },
  });
});
