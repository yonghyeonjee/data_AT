상품상세 구독탭 고도몰 반영본 (2026-11-02 · 판 261102a)
- sub_tab_261102a.js / .css : sdp/sub/sub_tab.js·css 의 복사본 → 고도몰 웹FTP /data/js/sub/ 에 올린다 (같은 이름 덮어쓰기 금지 · 판을 올릴 때마다 새 이름)
- _sub_tab_v11_1102.html : 스킨 goods/_sub_tab.html 새 판 (uiVer 261102a) → 웹FTP 에 올린 뒤 기존 _sub_tab.html 을 _sub_tab_v10_1102.html 로 rename 하고 이 파일을 _sub_tab.html 로 rename
- 올리는 방법: 관리자 페이지 안에서 fetch('https://db.samsungat.co.kr/deploy/sub_tab_godo/<파일>') → popup_webftp_ps.php (mode=upload, file=<폴더>, webFtpToken, file_data[])
이번 판 내용: N개월 구독료 상당 포인트 지원(결제 예상액 차감 → 실제 구독료), 같은 모델 다른 색상·구독 전용 모델 전환 칩
