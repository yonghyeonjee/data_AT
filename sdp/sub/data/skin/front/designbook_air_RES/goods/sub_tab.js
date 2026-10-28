/* 고도몰이 goods/_sub_tab.html 안의 주소 앞에 스킨 경로(/data/skin/front/designbook_air_RES/goods/)를 붙여 부를 때 받는 연결 파일 — 진짜 파일(sdp/sub/)을 부른다. 손으로 관리 · 배포가 덮지 않음 */
(function () { var s = document.currentScript, q = s && s.src.indexOf('?') > 0 ? s.src.slice(s.src.indexOf('?')) : '';
  document.write('<script src="https://db.samsungat.co.kr/sdp/sub/sub_tab.js' + q + '" charset="utf-8"><\/script>'); })();
