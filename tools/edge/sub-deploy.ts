// 구독 정책·요금 저장 → 데이터센터 배포(GitHub Actions sdp-publish.yml) 바로 실행 (mvp_255)  — 배포된 Edge Function 'sub-deploy' 의 원본 사본
//   호출: POST /functions/v1/sub-deploy?by=<표 이름>   — sub.policy · sub.card_policy · sub.promo · sub.price_override 의 저장 트리거(sub.f_deploy_kick)가 pg_net 으로 부른다
//   하는 일: GitHub 에 이미 돌고 있거나 방금(90초 안) 시작한 실행이 있으면 건너뛰고, 없으면 workflow_dispatch 를 건다.
//   비밀: GITHUB_DISPATCH_TOKEN (Edge Function Secrets · fine-grained PAT · 저장소 data_AT 의 Actions: Read and write 만) — 코드·표·git 에는 두지 않는다.
//   GitHub 의 10분 예약 실행(schedule)이 실제로는 돌지 않아(2026-10-29 확인) 저장 즉시 배포를 걸기 위해 만들었다. 워크플로 자체는 바뀐 것이 없으면 커밋하지 않으므로 여러 번 걸려도 안전하다.
const OWNER = "yonghyeonjee", REPO = "data_AT", WORKFLOW = "sdp-publish.yml", REF = "main";
const RECENT_SEC = 90;

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o, null, 2), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });

Deno.serve(async (req) => {
  const by = new URL(req.url).searchParams.get("by") ?? "";
  const token = Deno.env.get("GITHUB_DISPATCH_TOKEN");
  if (!token) return json({ ok: false, error: "GITHUB_DISPATCH_TOKEN 비밀이 없습니다 — Supabase › Edge Functions › Secrets 에 등록" }, 500);
  const gh = (path: string, init: RequestInit = {}) =>
    fetch(`https://api.github.com/repos/${OWNER}/${REPO}/actions/${path}`, {
      ...init,
      headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
                 "User-Agent": "samsungsh-datacenter-sub-deploy", ...(init.headers ?? {}) },
    });
  try {
    // 1) 이미 돌고 있거나 방금 시작한 실행이 있으면 건너뛴다 (저장을 연달아 해도 한 번만)
    const r = await gh(`workflows/${WORKFLOW}/runs?per_page=5`);
    if (r.ok) {
      const runs = (await r.json()).workflow_runs ?? [];
      const now = Date.now();
      const live = runs.find((x: any) => x.status === "queued" || x.status === "in_progress" || now - Date.parse(x.created_at) < RECENT_SEC * 1000);
      if (live) return json({ ok: true, skipped: true, reason: `이미 실행 중/직전 실행 (${live.status}, ${live.created_at})`, by });
    }
    // 2) 실행
    const d = await gh(`workflows/${WORKFLOW}/dispatches`, { method: "POST", body: JSON.stringify({ ref: REF }) });
    if (d.status !== 204) return json({ ok: false, error: `dispatch HTTP ${d.status} ${(await d.text()).slice(0, 200)}`, by }, 502);
    return json({ ok: true, dispatched: true, by, at: new Date().toISOString() });
  } catch (e) {
    return json({ ok: false, error: String(e), by }, 500);
  }
});
