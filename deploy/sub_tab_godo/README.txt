상품상세 구독탭 고도몰 반영본 (2026-11-02 · 판 261102e)
- sub_tab_261102e.js / .css : sdp/sub/sub_tab.js·css 의 복사본 → 고도몰 웹FTP /data/js/sub/ 에 올린다 (같은 이름 덮어쓰기 금지 · 판을 올릴 때마다 새 이름)
- sub_tab_v15_1102.html (올릴 때 이름 앞에 _ 를 붙인다 · GitHub Pages 는 _ 로 시작하는 파일을 내보내지 않음) : 스킨 goods/_sub_tab.html 새 판 (uiVer 261102e) → 웹FTP 에 올린 뒤 기존 _sub_tab.html 을 _sub_tab_v14_1102.html 로 rename 하고 이 파일을 _sub_tab.html 로 rename
- 올리는 방법: 관리자 페이지 안에서 fetch('https://db.samsungat.co.kr/deploy/sub_tab_godo/<파일>') → popup_webftp_ps.php (mode=upload, file=<폴더>, webFtpToken, file_data[]) — 업로드 토큰은 창을 연 폴더에만 통한다
이번 판 내용 (261102e · mvp_258): 적립 예정 멤버십 포인트 — 삼성닷컴 모델별 정률(6%)+기본 0.1% × 결제 예상액 + 상품별 추가 포인트를 결제 예상 내역에 한 줄 더 보여 주고 실제 구독료에서 뺀다 (행사 "N개월 구독료 상당" 포인트와 둘 다 표시). 포인트 원본 sub.model_point (수집기 tools/subpoint · 매주 월요일)
이전 판 (261102d): N개월 구독료 상당 포인트 지원(결제 예상액 차감 → 실제 구독료), 같은 모델 다른 색상·구독 전용 모델 전환 칩
