/***********************************************************************
 * 외부 공유용 payload 엔드포인트 — 매출 대시보드 v4 Code.gs 에 추가
 * ---------------------------------------------------------------------
 * 1) 아래 sharePw_ 함수와 doGet 을 기존 Code.gs 에 붙여 넣는다 (기존 doGet 은 이걸로 교체).
 * 2) [배포] → [새 배포] → 유형 '웹 앱' · 실행 '나' · 액세스 '**모든 사용자**(Anyone)'.
 *    ※ 기존 배포(구글 계정 사용자)는 그대로 둔다. 이 새 배포 URL 은 JSON 전용으로만 쓴다.
 * 3) 새 배포의 /exec URL 을 db.samsungat.co.kr/dash/index.html 의 SHARE_URL 에 넣는다.
 *
 * 동작
 *   /exec                → 기존과 동일 (ALLOW_EMAILS 검사 → 대시보드 HTML). 익명 배포에서는 이메일이 비어 차단됨.
 *   /exec?json=1&pw=3166 → 비밀번호가 맞으면 payload JSON, 틀리면 {"error":"unauthorized"}
 * 비밀번호 변경: 스크립트 속성(프로젝트 설정 → 스크립트 속성) sharePassword 값 수정. 없으면 3166.
 ***********************************************************************/
const SHARE_PW_KEY = 'sharePassword';
const SHARE_PW_DEFAULT = '3166';
function sharePw_() {
  return PropertiesService.getScriptProperties().getProperty(SHARE_PW_KEY) || SHARE_PW_DEFAULT;
}

function doGet(e) {
  e = e || { parameter: {} };
  const p = e.parameter || {};

  /* ── 외부 공유 JSON ───────────────────────────────────────────── */
  if (String(p.json || '') === '1') {
    const ok = String(p.pw || '') === sharePw_();
    const body = ok ? loadPayloadJson_() : JSON.stringify({ error: 'unauthorized' });
    return ContentService.createTextOutput(body).setMimeType(ContentService.MimeType.JSON);
  }

  /* ── 기존 대시보드 (구글 계정 검사) ───────────────────────────── */
  const who = String(Session.getActiveUser().getEmail() || '').toLowerCase();
  const ok = ALLOW_EMAILS.some(function (x) { return x.toLowerCase() === who; });
  if (!ok) {
    return HtmlService.createHtmlOutput(
      '<div style="font-family:sans-serif;padding:48px;text-align:center;color:#3C434D">' +
      '<div style="font-size:17px;font-weight:700;margin-bottom:10px">접근 권한이 없습니다</div>' +
      '현재 로그인 계정: <b>' + (who || '(확인 불가)') + '</b><br>' +
      '관리자에게 이 계정의 등록을 요청하세요.</div>')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1')
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
  }
  return HtmlService.createHtmlOutput(renderDashboard_())
    .setTitle('매출 대시보드')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}
