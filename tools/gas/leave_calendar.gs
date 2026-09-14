/***********************************************************************
 * 휴가 달력 → 구글 캘린더 동기화  (Apps Script · 독립 프로젝트로 붙여 넣기)
 * ---------------------------------------------------------------------
 * 데이터센터(core.staff_leave)의 휴가를 지정한 구글 캘린더에 종일 일정으로 넣고,
 * 바뀌면 고치고, 데이터센터에서 지우면 구글에서도 지운다.  방향은 데이터센터 → 구글 한 방향.
 *
 * 붙이는 법
 *  ① script.google.com › 새 프로젝트 › 이 파일 전체 붙여넣기
 *  ② DC_KEY 에 전달받은 값(leave_ics 토큰)을 넣는다  — 저장소에는 절대 넣지 않는다
 *  ③ 편집기에서 syncLeaveToCalendar 를 1회 실행 (권한 허용: 캘린더 · 외부 연결)
 *  ④ installLeaveSyncTrigger 를 1회 실행 → 15분마다 자동 동기화
 *
 * 캘린더 일정은 태그 dc_leave_id 로 식별한다. 태그 없는 일정(손으로 넣은 것)은 건드리지 않는다.
 ***********************************************************************/
var CAL_ID = 'c3e549542f1c7e457d0caaebbfb5d68584c9ea538e3dac7e990f16197c8d44f3@group.calendar.google.com';
var DC_URL  = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/';
var DC_ANON = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';   // 공개키 (브라우저에도 있는 값)
var DC_KEY  = 'PASTE_DC_KEY_HERE';                                 // leave_ics 토큰 (core.api_key 해시와 대조)

var KIND_COLOR = { '반차': CalendarApp.EventColor.YELLOW, '휴무': CalendarApp.EventColor.PALE_BLUE, '교육': CalendarApp.EventColor.PALE_GREEN,
                   '휴가': CalendarApp.EventColor.BLUE, '연차': CalendarApp.EventColor.CYAN, '매장휴무': CalendarApp.EventColor.GRAY };

function dcLeaveRows_() {
  var res = UrlFetchApp.fetch(DC_URL + 'fn_leave_feed', {
    method: 'post', contentType: 'application/json',
    headers: { apikey: DC_ANON, Authorization: 'Bearer ' + DC_ANON },
    payload: JSON.stringify({ p_key: DC_KEY }), muteHttpExceptions: true });
  if (res.getResponseCode() !== 200) throw new Error('Datacenter ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 200));
  var rows = JSON.parse(res.getContentText());
  if (rows === null) throw new Error('DC_KEY 가 틀립니다 (fn_leave_feed → null)');
  return rows;
}
function ymd_(s) { var p = String(s).split('-'); return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])); }
function addDays_(d, n) { var x = new Date(d); x.setDate(x.getDate() + n); return x; }
function titleOf_(r) {
  if (r.kind === '매장휴무') return '매장휴무' + (r.note ? ' · ' + r.note : '');
  return r.name + ' · ' + r.kind + (r.kind === '반차' ? ' (오후 3시까지)' : '');
}
function descOf_(r) { return [r.note ? '메모: ' + r.note : '', r.by ? '입력: ' + r.by : '', '데이터센터 휴가 #' + r.id].filter(String).join('\n'); }

function syncLeaveToCalendar() {
  var cal = CalendarApp.getCalendarById(CAL_ID);
  if (!cal) throw new Error('캘린더를 못 찾습니다 — CAL_ID 와 공유 권한(수정 가능)을 확인하세요');
  var rows = dcLeaveRows_();
  var from = addDays_(new Date(), -60), to = addDays_(new Date(), 400);
  var existing = {};
  cal.getEvents(from, to).forEach(function (ev) { var id = ev.getTag('dc_leave_id'); if (id) existing[id] = ev; });
  var made = 0, changed = 0, removed = 0;
  rows.forEach(function (r) {
    var start = ymd_(r.from), end = addDays_(ymd_(r.to), 1);   // 종일 일정: 종료일은 exclusive
    var title = titleOf_(r), desc = descOf_(r), ev = existing[String(r.id)];
    if (ev) {
      var same = ev.getTitle() === title && ev.getDescription() === desc
              && ev.getAllDayStartDate().getTime() === start.getTime() && ev.getAllDayEndDate().getTime() === end.getTime();
      if (!same) { ev.setTitle(title); ev.setDescription(desc); ev.setAllDayDates(start, end); changed++; }
      if (KIND_COLOR[r.kind] && ev.getColor() !== KIND_COLOR[r.kind]) ev.setColor(KIND_COLOR[r.kind]);
      delete existing[String(r.id)];
    } else {
      var nv = cal.createAllDayEvent(title, start, end, { description: desc });
      nv.setTag('dc_leave_id', String(r.id));
      if (KIND_COLOR[r.kind]) nv.setColor(KIND_COLOR[r.kind]);
      made++;
    }
  });
  Object.keys(existing).forEach(function (id) { existing[id].deleteEvent(); removed++; });   // 데이터센터에서 지운 것
  Logger.log('휴가 동기화: 새로 ' + made + ' · 고침 ' + changed + ' · 지움 ' + removed + ' (전체 ' + rows.length + ')');
}

/** 15분마다 자동 — 1회만 실행 */
function installLeaveSyncTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (t.getHandlerFunction() === 'syncLeaveToCalendar') ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('syncLeaveToCalendar').timeBased().everyMinutes(15).create();
  Logger.log('트리거 설치 완료: syncLeaveToCalendar 15분마다');
}
