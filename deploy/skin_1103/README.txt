2026-11-03 · 고도몰 스킨(designbook_air_RES) 수정본
- header_before_1103.html / header_fixed_1103.html / header_fixed_1103b.html → outline/_header.html : 헤더 메뉴바 반응형 (다른 세션)
- goods_list_1103.html → goods/goods_list.html : 구독 전용몰(cateCd 012*) 에서만
    · 상단 배너를 메인 1번 슬라이드(AI 콤보·85인치 TV · 방문상담 와인 증정)와 같은 그림으로 (PC 511517418 / 모바일 1053291314 그림 · 링크 /board/view.php?&bdId=blog&sno=167)
      다른 카테고리(003·005·나머지 dataBanner)는 그대로
    · 목록을 월 구독료 가격대별로 묶는 스크립트 https://db.samsungat.co.kr/sdp/sub/sub_list.js (저장소 sdp/sub/sub_list.js · GitHub Pages 가 바로 서빙) 를 defer 로 받음
      80개 페이지면 pageNum=120 으로 전부 받아 묶고 페이지 번호는 숨김 · 3,000원 미만 자리표시 가격은 "가격 상담" 묶음
    · 메인 슬라이드 그림에는 글자가 없어(메인은 HTML 문구를 덧얹음) 같은 문구를 .sub-bn-txt 로 얹음 (PC 왼쪽 세로 가운데 · 모바일 아래 빈 영역)
  서버 파일: goods_list.html = 이 파일(3판 · v=1103b) · goods_list_bak_1103.html = 원본(7,152바이트) · goods_list_1103a/1103b.html = 중간판(지워도 됨)
올릴 때는 웹FTP(popup_webftp.php?dir=data/skin/front/designbook_air_RES/goods) 로 새 이름으로 올린 뒤 rename 으로 바꿔 넣는다. 토큰은 1회용.
