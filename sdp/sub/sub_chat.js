/* =====
   구독센터 상담 도우미 (2026-11-26 · 정해진 답변형)
   - 문의 바의 [바로 답변] 또는 오른쪽 아래 둥근 단추를 누르면 sub_shop.js 가 이 파일을 받아 연다 (window.SUB_CHAT.open)
   - 답은 아래 QA 표에 정해 둔 글만 쓴다 (AI 가 지어내지 않음) · 가격 질문은 요금표(SUB_INDEX)에서 그 모델·품목의 월 구독료를 바로 보여 준다
   - 찾는 질문이 없으면 [구독 문의 남기기] · [전화 상담] 으로 넘긴다
   - 질문 출처: 삼성닷컴 구독 FAQ · 우리 매장 구독·홈페이지 문의 글 · 구독센터 페이지 FAQ (2026-11-26 정리)
   ※ 화면 값(요금·카드·포인트·주소)은 sub_shop.js 가 넘기는 SUB_SHOP_API 를 쓴다
===== */
(function () {
  'use strict';
  if (window.SUB_CHAT) return;
  var A = window.SUB_SHOP_API || {};
  var CFG = window.SUB_SHOP_CONFIG || {};
  var d = document;
  var fmt = A.fmt || function (n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); };
  var esc = A.esc || function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var track = A.track || function () {};
  var TEL = A.tel || CFG.tel || '031-8042-3166';
  var STORE = CFG.store || {
    name: '삼성스토어 시흥', addr: '경기도 시흥시 서해안로1685번길 12 (대야동)', hours: '매일 10:30 ~ 20:00',
    map: 'https://map.naver.com/p/search/%EC%82%BC%EC%84%B1%EC%8A%A4%ED%86%A0%EC%96%B4%20%EC%8B%9C%ED%9D%A5'
  };
  var LINK = A.link || {};
  function consultUrl(r) { return A.consultHref ? A.consultHref(r) : (LINK.consult || '/main/html.php?htmid=service/SamSungSubscription.html'); }
  function telHref() { return 'tel:' + TEL.replace(/[^0-9]/g, ''); }
  function a(href, txt, cta, blank) { return '<a href="' + esc(href) + '" data-cta="' + cta + '"' + (blank ? ' target="_blank" rel="noopener"' : '') + '>' + txt + '</a>'; }

  /* ---------- 질문·답 표 ----------
     g: 묶음 · q: 버튼 글 · k: 직접 친 글에서 찾을 낱말 (하나라도 들어 있으면 점수) · a: 답 (글 또는 함수) · n: 이어서 보여 줄 질문 */
  var GROUPS = [
    { id: 'price', t: '💰 가격·실제 납부액' },
    { id: 'store', t: '🏬 매장 방문·체험' },
    { id: 'card', t: '💳 제휴카드 할인' },
    { id: 'term', t: '📅 기간·소유권·요금제' },
    { id: 'cancel', t: '↩️ 해지·위약금' },
    { id: 'care', t: '🛠️ 케어·포인트' },
    { id: 'install', t: '🚚 배송·설치' },
    { id: 'who', t: '✅ 가입 조건' }
  ];
  function cardTable() {
    var C = A.cards || window.SUB_CARDS; if (!C) return '';
    var html = '<table class="sc-tbl"><thead><tr><th>카드</th><th>전월 실적</th><th>월 할인</th></tr></thead><tbody>';
    Object.keys(C).forEach(function (name) {
      var cd = C[name], t = cd.t || {}, keys = Object.keys(t);
      keys.forEach(function (k, i) {
        var base = cd.base && cd.base[k] && cd.base[k] !== t[k] ? cd.base[k] : 0;
        html += '<tr>' + (i === 0 ? '<td rowspan="' + keys.length + '"><b>' + esc(name) + '</b></td>' : '') + '<td>' + esc(k.replace('↑', ' 이상')) + '</td><td>' + fmt(t[k]) + '원' +
          (base ? '<small>' + (cd.m || '') + '개월 뒤 ' + fmt(base) + '원</small>' : '') + '</td></tr>';
      });
    });
    return html + '</tbody></table>';
  }
  var QA = [
    // 가격
    { id: 'p_model', g: 'price', q: '이 모델 구독하면 한 달에 얼마예요?', k: ['얼마', '가격', '구독료', '월납', '월 납', '납부', '비용'],
      a: '모델명(예: <b>RM80F91H1X</b>)이나 제품 이름(예: <b>AI 콤보</b>, <b>65인치 TV</b>)을 아래 칸에 적어 주세요. 요금표에서 가장 낮은 월 구독료와 제휴카드 할인 후 금액을 바로 찾아 드립니다.', ask: 1 },
    { id: 'p_card30', g: 'price', q: '삼성카드 30만원 쓰면 실제로 얼마 내나요?', k: ['30만', '실적', '실제', '청구할인'],
      a: function () {
        var c1 = A.card1;
        return '제휴카드로 구독료를 자동결제하면 <b>전월 카드 이용 실적</b>에 따라 매달 청구할인이 들어가 실제 납부액이 줄어듭니다.' +
          (c1 ? '<br>예) ' + esc(c1.name) + ' ' + esc(String(c1.tier).replace('↑', ' 이상')) + ' 사용 시 월 <b>' + fmt(c1.off) + '원</b> 할인' : '') +
          '<br>모델명을 알려 주시면 할인 후 금액을 계산해 드립니다. 카드별 할인 표는 「제휴카드는 어떤 게 있나요?」에서 볼 수 있습니다.';
      }, n: ['c_which', 'p_model'] },
    { id: 'p_vs', g: 'price', q: '구독이 일시불 구매보다 싼가요?', k: ['일시불', '일반구매', '일반 구매', '비교', '싼', '저렴', '현금'],
      a: '제품과 조건에 따라 다릅니다. 구독은 <b>월 구독료 × 기간</b>에 케어 서비스가 포함되고, 제휴카드 할인·멤버십 포인트·구독료 지원 행사를 받으면 일시불보다 총액이 낮아지는 모델도 많습니다.<br>상담에서는 <b>구독 총액과 일시불 금액을 나란히</b> 계산해 가장 유리한 방법을 안내해 드립니다.', n: ['p_model', 'p_cheaper'] },
    { id: 'p_multi', g: 'price', q: '여러 대 같이 하면 할인되나요? (혼수·입주·이사)', k: ['여러', '다품목', '!혼수', '!신혼', '!입주', '이사', '같이', '세트', '한꺼번'],
      a: function () { return '네. 2대 이상 함께 구독하면 <b>다품목 구독 할인</b>을 받을 수 있고, 혼수·입주·이사처럼 한 번에 여러 대가 필요하면 품목을 묶어 견적을 드립니다.<br>' + a(LINK.bundle || '/data/gudok/bundle.html', '다품목 계산기로 직접 계산해 보기 →', 'chat_bundle'); }, n: ['p_vs', 'store_visit'] },
    { id: 'p_pre', g: 'price', q: '선납하면 얼마나 줄어드나요?', k: ['!선납', '미리'],
      a: '구독 신청 때 제품 금액의 일부를 먼저 내면 남은 기간의 월 구독료가 낮아지고, 선납 비율에 따라 추가 할인도 받을 수 있습니다. 품목마다 선납할 수 있는 비율이 다릅니다(예: 에어드레서 최대 50%).<br>모델 페이지의 계산기에서 선납 비율별 금액을 바로 볼 수 있습니다.', n: ['p_model'] },
    { id: 'p_cheaper', g: 'price', q: '표시된 가격보다 더 싸게 할 수 있나요?', k: ['더 싸', '할인', '혜택', '최대', '사은품', '네이버페이'],
      a: function () {
        var t = A.bubbleTexts ? A.bubbleTexts() : {};
        return '네, 꼭 문의해 주세요. 표시된 월 구독료는 기본 요금이며 시기별 행사·제휴카드·선납 조건을 맞추면 더 낮아질 수 있습니다.' + (t.gift ? '<br>🎁 ' + esc(t.gift) : '');
      }, n: ['p_multi', 'c_which'] },
    // 매장
    { id: 'store_visit', g: 'store', q: '실제로 제품을 보고 구매할 수 있나요?', k: ['!매장', '방문', '직접', '!실물', '보고', '!체험', '!주소', '!위치', '어디', '오시는', '찾아가', '구경'],
      a: function () {
        return '네. 삼성 구독센터는 <b>' + esc(STORE.name) + '</b>에서 운영하며, 주소는 <b>' + esc(STORE.addr) + '</b>입니다.<br>' +
          '매장에 진열된 제품이라면 언제든 편하게 직접 보고 비교해 보실 수 있습니다. 모델명을 적어 주시면 진열 여부도 확인해 드립니다.' +
          '<div class="sc-store"><span>🕙 ' + esc(STORE.hours) + '</span><span>📞 ' + a(telHref(), esc(TEL), 'chat_tel') + '</span>' + a(STORE.map, '🗺️ 지도 보기', 'chat_map', true) + '</div>';
      }, n: ['store_hours', 'p_model'] },
    { id: 'store_hours', g: 'store', q: '매장 영업시간과 주차가 궁금해요', k: ['영업시간', '몇시', '몇 시', '!주차', '!휴무', '쉬는 날'],
      a: function () { return '영업시간은 <b>' + esc(STORE.hours) + '</b>입니다. 방문 전에 전화(' + a(telHref(), esc(TEL), 'chat_tel') + ')를 주시면 원하시는 제품을 미리 준비해 두고, 주차 안내도 함께 드립니다.'; }, n: ['store_visit'] },
    { id: 'store_area', g: 'store', q: '시흥이 아닌 지역도 구독할 수 있나요?', k: ['지역', '타지역', '서울', '인천', '부천', '안산', '먼', '전국', '지방'],
      a: '네. 구독 제품은 삼성전자에서 배송·설치하므로 매장에 오시지 않아도 온라인·전화 상담만으로 진행할 수 있습니다. 설치 가능 지역과 일정은 상담 때 주소를 확인해 안내해 드립니다.', n: ['i_when', 'store_visit'] },
    // 카드
    { id: 'c_which', g: 'card', q: '제휴카드는 어떤 게 있고 얼마나 할인되나요?', k: ['제휴카드', '카드사', '어떤 카드', '무슨 카드', '!카드할인', '!카드 할인', '!국민', '!하나카드', '!우리카드', '!롯데', '!신한', '!현대카드', '!bc', '!광주'],
      a: function () { return '구독료를 제휴카드로 자동결제하면 전월 실적에 따라 매달 청구할인이 들어갑니다.' + cardTable() + (LINK.card ? a(LINK.card, '제휴카드 혜택 자세히 보기 →', 'chat_card') : ''); }, n: ['c_any', 'c_multi'] },
    { id: 'c_any', g: 'card', q: '그냥 갖고 있는 삼성카드로도 할인되나요?', k: ['아무', '갖고 있는', '기존 카드', '일반 삼성카드', '그냥'],
      a: '청구할인은 <b>구독 전용 제휴카드</b>(예: 삼성전자 AI 구독 삼성카드)로 결제할 때 들어갑니다. 갖고 계신 일반 카드로도 결제는 할 수 있지만 구독 청구할인은 없습니다. 제휴카드는 상담 때 함께 발급 안내를 받으실 수 있습니다.', n: ['c_which'] },
    { id: 'c_multi', g: 'card', q: '카드 한 장으로 여러 대 할인되나요?', k: ['한 장', '한장', '여러 대', '!중복', '!몇 개', '!몇개', '!몇 대', '!몇대'],
      a: '제휴카드 한 장은 구독 제품 <b>한 대</b>에만 할인이 들어갑니다. 여러 대를 구독하실 때는 제휴카드를 추가로 발급해 제품마다 다른 카드로 결제하시면 각각 할인받으실 수 있습니다.', n: ['p_multi'] },
    { id: 'c_other', g: 'card', q: '가족 카드로 구독료를 내도 되나요?', k: ['!가족', '남편', '아내', '부모', '자녀', '다른 사람', '!명의'],
      a: '구독료는 계약하신 분 명의 카드로 내는 것이 원칙이고, 예외로 <b>1촌 이내 가족</b>(부모·자녀·배우자) 카드는 서류(가족 명의 카드 변경 신청서, 개인정보 동의서, 가족관계증명서)를 내면 바꿀 수 있습니다.', n: ['c_check'] },
    { id: 'c_check', g: 'card', q: '체크카드로도 구독할 수 있나요?', k: ['!체크', '계좌', '자동이체'],
      a: '구독료는 신용카드 자동결제가 기본입니다. 체크카드나 다른 결제 방법이 가능한지는 계약 유형에 따라 달라 상담 때 확인해 드립니다.', n: ['c_which', 'w_credit'] },
    // 기간·소유권
    { id: 't_len', g: 'term', q: '구독 기간은 몇 년인가요?', k: ['!기간', '몇 년', '몇년', '!약정'],
      a: '제품마다 <b>2·3·4·5·6년</b> 가운데 고를 수 있습니다. 기간이 길수록 월 구독료가 낮아지고, 행사·포인트 조건도 기간에 따라 달라집니다.', n: ['t_own', 't_plans'] },
    { id: 't_own', g: 'term', q: '구독이 끝나면 제품은 제 것이 되나요?', k: ['!소유', '내 것', '내것', '끝나면', '!만료', '!반납'],
      a: '<b>AI 올인원 요금제</b>는 계약 기간 동안 소유권이 삼성전자에 있고, 기간이 끝나 남은 구독료를 모두 내면 고객님 소유가 됩니다.<br><b>AI 스마트 요금제</b>(제품 구매 + 구독케어)는 배송된 때부터 고객님 소유입니다.', n: ['t_plans', 'x_cancel'] },
    { id: 't_plans', g: 'term', q: '올인원 요금제와 스마트 요금제는 뭐가 달라요?', k: ['!올인원', '스마트', '!요금제', '차이'],
      a: '<b>AI 올인원</b>: 제품과 구독케어를 함께 월 구독료로 이용 · 모든 신용카드 결제 가능(제휴카드는 청구할인) · 중도 해지 시 제품 회수와 해약금.<br><b>AI 스마트</b>: 제품은 따로 구매하고 원하는 구독케어만 결제 · 제품 해지는 없고 케어만 해지 가능.', n: ['t_own', 'x_cancel'] },
    { id: 't_same', g: 'term', q: '구독 제품은 일반 판매 제품과 같은가요?', k: ['같은 제품', '리퍼', '중고', '새 제품', '새제품', '정품'],
      a: '네. 구독 제품은 일반 판매 제품과 <b>같은 새 제품</b>이고, 구매·이용 방법만 다릅니다. 삼성전자 정품을 삼성전자 기사가 설치합니다.', n: ['t_change'] },
    { id: 't_change', g: 'term', q: '구독 중에 새 모델로 바꿀 수 있나요?', k: ['신모델', '새 모델', '교체', '바꿀', '업그레이드'],
      a: '구독 기간 중에 제품을 바꿀 수는 없습니다. 기간이 끝난 뒤 새 제품을 다시 구독하시면 재구독 혜택을 받을 수 있습니다.', n: ['t_len'] },
    // 해지
    { id: 'x_cancel', g: 'cancel', q: '중간에 해지할 수 있나요? 위약금은요?', k: ['!해지', '위약금', '!해약', '취소', '!중도'],
      a: '해지할 수 있습니다. <b>AI 올인원 요금제</b>는 제품을 돌려주고 해약금을 냅니다.<ul class="sc-ul"><li>등록비: 제품당 10만원</li><li>회수비: 품목별 (예: 냉장고 105,000원 · 세탁기 108,000원 · AI 콤보 170,000원 · 스탠드 에어컨 219,000원)</li><li>위약금: 남은 기간 구독료의 1년 안 30% · 1~2년 20% · 2년 뒤 10%</li><li>받은 혜택(포인트·할인·사은품) 반환</li></ul><b>AI 스마트 요금제</b>는 별도 위약금 없이 구독케어만 해지되며 조건에 따라 환불됩니다.', n: ['t_own'] },
    // 케어·포인트
    { id: 'k_care', g: 'care', q: '방문케어는 뭘 해 주나요?', k: ['!케어', '방문', '!세척', '!필터', '!점검', '관리', '무상수리', 'a/s', '!수리', '고장'],
      a: '케어는 모델마다 고를 수 있습니다.<ul class="sc-ul"><li><b>무상수리</b>: 구독 기간 내내 고장 수리 무료</li><li><b>방문케어</b>: 전문 기사가 정기 방문해 내부 세척·위생 관리(세탁조·에어컨 열교환기·정수기 필터 등)</li><li><b>셀프·라이트</b>: 소모품을 받아 직접 관리하고 월 구독료는 더 낮게</li></ul>모델 페이지에서 케어 종류별 월 구독료를 비교할 수 있습니다.', n: ['k_point', 'k_benefit'] },
    { id: 'k_point', g: 'care', q: '포인트는 언제 들어오고 어디에 쓰나요?', k: ['!포인트', '!적립', '멤버십'],
      a: '구독 계약을 하면 삼성전자 <b>멤버십 포인트</b>가 적립됩니다. 적립된 포인트는 구독료 결제에 나눠 쓰거나 삼성전자 제품 구매에 쓸 수 있습니다. 모델을 알려 주시면 예상 포인트를 보여 드립니다.', n: ['p_model', 'k_support'] },
    { id: 'k_support', g: 'care', q: '구독료 지원(○개월 무료)은 어떻게 받나요?', k: ['지원', '무료', '개월 상당', '페스티벌', '행사', '이벤트'],
      a: function () { return '행사 모델을 행사에서 정한 약정 기간으로 계약하면, 지원 개월 수만큼의 월 구독료에 해당하는 금액을 삼성전자 멤버십 포인트로 적립해 드립니다. 행사 기간 안에 신청하고 배송 기한 등 조건을 지켜야 합니다.' + (LINK.event ? '<br>' + a(LINK.event, '지금 진행 중인 행사 보기 →', 'chat_event') : ''); }, n: ['k_point'] },
    { id: 'k_benefit', g: 'care', q: '구독하면 받는 혜택은 뭐가 있나요?', k: ['혜택', '쿠폰', '리포트', '제휴'],
      a: '제품별 전문 케어와 함께 삼성닷컴 소모품 할인 쿠폰, 월간 케어 리포트, 생활 제휴 혜택(커피·식품·여행 등)을 받으실 수 있습니다. 여기에 제휴카드 청구할인과 멤버십 포인트가 더해집니다.', n: ['k_care', 'k_point'] },
    // 배송·설치
    { id: 'i_when', g: 'install', q: '설치는 언제 되나요? 빨리 되나요?', k: ['언제', '설치일', '!배송', '빨리', '빠른', '급해', '날짜', '일정', '!재고', '설치'],
      a: '구독 제품은 삼성전자에서 직접 배송·설치합니다. 설치 날짜는 모델 재고와 지역 일정에 따라 정해지며, 원하시는 날짜(이사·입주일)를 알려 주시면 상담 때 맞춰서 잡아 드립니다.', n: ['i_fee', 'store_area'] },
    { id: 'i_fee', g: 'install', q: '설치비가 따로 드나요?', k: ['설치비', '추가 비용', '추가비용', '배관', '실외기', '거치', '벽걸이'],
      a: '기본 설치는 구독료에 포함됩니다. 배관 연장, 실외기 거치, TV 벽걸이 등 설치 환경에 따른 추가 비용은 상담 때 미리 안내해 드립니다.', n: ['i_when', 'i_move'] },
    { id: 'i_move', g: 'install', q: '이사 가면 옮겨 설치할 수 있나요?', k: ['!이전', '옮겨', '이사 가', '이사가'],
      a: '구독 중 이사하시면 이전 설치를 신청하실 수 있습니다. 이전 설치비와 일정은 품목과 거리에 따라 달라 상담 때 안내해 드립니다.', n: ['i_fee'] },
    // 가입 조건
    { id: 'w_biz', g: 'who', q: '사무실·가게에서도 구독할 수 있나요?', k: ['!사무실', '!사업자', '!가게', '매장용', '!법인', '회사', '!상가', 'b2b'],
      a: function () { return '가정용 구독 제품은 <b>가정에서만</b> 쓸 수 있습니다(상업 시설은 설치·케어 불가). 사무실·가게는 사업자 전용 <b>B2B 구독</b>으로 따로 견적을 드립니다.' + (LINK.b2b ? '<br>' + a(LINK.b2b, '사업자 구독 안내 보기 →', 'chat_b2b') : ''); }, n: ['w_credit'] },
    { id: 'w_credit', g: 'who', q: '신용이 걱정되는데 구독이 되나요?', k: ['!신용', '!심사', '등급', '!연체', '!파산', '!회생', '거절'],
      a: '구독은 계약 때 삼성전자 기준의 심사가 있어, 결과에 따라 진행이 어려울 수 있습니다. 개인 사정은 상담에서 먼저 말씀해 주시면 가능한 방법(일시불·할부 등)과 함께 안내해 드립니다.', n: ['c_check'] },
    { id: 'w_consult', g: 'who', q: '상담 신청하면 바로 계약되나요?', k: ['계약', '바로', '부담', '상담 신청'],
      a: '아닙니다. 상담 신청은 요금 안내를 받기 위한 단계입니다. 약정 기간·케어·카드 조건을 맞춘 실제 월 납부액을 안내받으신 뒤 결정하시면 됩니다.', n: ['p_cheaper', 'store_visit'] }
  ];
  var BY = {}; QA.forEach(function (x) { BY[x.id] = x; });
  var FIRST = ['p_model', 'store_visit', 'p_card30', 'p_vs', 'x_cancel', 'i_when'];   // 처음 보여 줄 자주 묻는 질문

  /* ---------- 모델·품목 찾기 (요금표) ---------- */
  var ALIAS = { tv: ['티비', 'tv', '텔레비전', 'oled', 'qled', '네오qled', '인치', '형tv'], aicombo: ['콤보', '세탁건조기', '올인원세탁'], washer: ['세탁기', '통돌이', '드럼', '워시타워', '원바디'],
    dryer: ['건조기'], kimchi: ['김치'], ref: ['냉장고', '냉동고', '양문형', '4도어', '키친핏', '비스포크냉장'], airdresser: ['에어드레서', '드레서', '의류관리'], sysaircon: ['시스템에어컨', '시스템 에어컨', '천장형'],
    aircon: ['에어컨', '무풍', '벽걸이에어컨', '스탠드에어컨', '창문형'], water: ['정수기'], airpurifier: ['공기청정기', '공청기'], cleaner: ['청소기', '로봇청소기', '제트'], dishwasher: ['식기세척기', '식세기'],
    induction: ['인덕션', '전기레인지', '후드'], monitor: ['모니터'], galaxy: ['갤럭시', '탭', '노트북', '북'], audio: ['사운드바', '오디오', '스피커'], dehumid: ['제습기'] };
  function norm(s) { return String(s || '').toLowerCase().replace(/\s+/g, ''); }
  function rowsAll() {
    if (A.rows && A.rows.length) return A.rows;
    var I = A.idx || window.SUB_INDEX, out = [];
    if (I && I.m) for (var m in I.m) { var e = I.m[m]; if (e && e[1] > 0) out.push({ model: m, cat: e[0], min: e[1], seg: '' }); }
    return out;
  }
  function findModels(text) {
    var codes = String(text || '').toUpperCase().match(/[A-Z]{2,}[0-9][A-Z0-9\-]{3,}/g);
    if (!codes) return [];
    var rs = rowsAll(), out = [];
    codes.forEach(function (c) {
      var hit = rs.filter(function (r) { return r.model === c; });
      if (!hit.length) hit = rs.filter(function (r) { return r.model.indexOf(c) === 0 || (c.indexOf(r.model) === 0 && r.model.length >= 8); });
      hit.sort(function (x, y) { return x.min - y.min; }).slice(0, 3).forEach(function (r) { if (out.indexOf(r) < 0) out.push(r); });
    });
    return out.slice(0, 3);
  }
  function findPage(text) {
    var t = norm(text), pages = A.pages || [];
    var order = ['kimchi', 'sysaircon', 'aicombo', 'dishwasher', 'airdresser', 'airpurifier', 'dryer', 'washer', 'aircon', 'ref', 'tv', 'water', 'cleaner', 'induction', 'monitor', 'galaxy', 'audio', 'dehumid'];
    for (var i = 0; i < order.length; i++) {
      var k = order[i], al = ALIAS[k] || [];
      for (var j = 0; j < al.length; j++) if (t.indexOf(norm(al[j])) >= 0) {
        for (var p = 0; p < pages.length; p++) if (pages[p].key === k) return pages[p];
      }
    }
    return null;
  }
  function name(r) { return A.displayName ? A.displayName(r) : r.model; }
  function modelAnswer(list) {
    var c1 = A.card1;
    return '요금표에서 찾은 결과입니다.' + list.map(function (r) {
      var net = A.cardNet ? A.cardNet(r) : 0, pt = A.pointOf ? A.pointOf(r.model) : 0, st = A.inStore ? A.inStore(r) : false;
      return '<div class="sc-model">' + (r.img ? '<img src="' + esc(r.img) + '" alt="" loading="lazy">' : '') + '<div><b>' + esc(name(r)) + '</b><small>' + esc(r.model) + '</small>' +
        '<p>월 구독료 <b>' + fmt(r.min) + '원~</b>' + (c1 && net < r.min ? '<br>' + esc(c1.name) + ' ' + esc(String(c1.tier).replace('↑', ' 이상')) + ' 사용 시 <b class="sc-net">월 ' + fmt(net) + '원~</b>' : '') +
        (pt ? '<br>멤버십 포인트 약 ' + fmt(pt) + 'P' : '') + '</p>' +
        (st ? '<p class="sc-st">● 매장 진열 중 — 직접 보실 수 있습니다</p>' : '') +
        '<span class="sc-links">' + (A.viewHref ? a(A.viewHref(r.model), '조건별 계산하기', 'chat_view') : '') + a(consultUrl(r), '이 모델 상담', 'chat_consult_model') + '</span></div></div>';
    }).join('') + '<p class="sc-note">가장 낮은 요금제(약정·케어) 기준이며, 선납·행사·카드 조건에 따라 달라집니다.</p>';
  }
  function pageAnswer(p) {
    var rs = rowsAll().filter(function (r) { return p.cats.indexOf(r.cat) >= 0; });
    var seg = p.seg ? rs.filter(function (r) { return r.seg && p.seg.test(r.seg); }) : rs;
    if (seg.length) rs = seg;
    if (!rs.length) return '';
    var mn = Math.min.apply(null, rs.map(function (r) { return r.min; }));
    var named = rs.filter(function (r) { return r.name; }).sort(function (x, y) { return x.min - y.min; }).slice(0, 3);
    return '<b>' + esc(p.name) + '</b> 구독은 ' + fmt(rs.length) + '개 모델, 월 <b>' + fmt(mn) + '원</b>부터입니다.' +
      (named.length ? '<ul class="sc-ul">' + named.map(function (r) { return '<li>' + (A.viewHref ? a(A.viewHref(r.model), esc(name(r)), 'chat_view') : esc(name(r))) + ' · 월 ' + fmt(r.min) + '원~</li>'; }).join('') + '</ul>' : '') +
      (A.catHref ? a(A.catHref(p.key), esc(p.name) + ' 모델 전체 비교하기 →', 'chat_cat') : '') + '<p class="sc-note">모델명을 적어 주시면 그 모델의 카드 할인 후 금액도 알려 드립니다.</p>';
  }

  /* ---------- 직접 친 글 → 답 ---------- */
  function matchQA(text) {
    var t = norm(text), best = null, bs = 0;
    QA.forEach(function (x) {
      // 3글자 이상 낱말·! 붙인 낱말 = 2점, 나머지 = 1점 · 2점 이상일 때만 답한다 (「빨리」 하나로 엉뚱한 답이 나오지 않게)
      var s = 0; x.k.forEach(function (w) { var strong = w.charAt(0) === '!'; w = strong ? w.slice(1) : w; if (t.indexOf(norm(w)) >= 0) s += strong || w.length >= 3 ? 2 : 1; });
      if (norm(x.q).indexOf(t) >= 0 && t.length >= 4) s += 3;
      if (s > bs) { bs = s; best = x; }
    });
    return bs >= 2 ? best : null;
  }

  /* ---------- 화면 ---------- */
  var SPARK = '<svg viewBox="0 0 32 32" aria-hidden="true"><defs><linearGradient id="scSpG" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1f6bff"/><stop offset="1" stop-color="#2fc4e8"/></linearGradient></defs>' +
    '<path fill="url(#scSpG)" d="M13 5c.6 4.6 2.9 6.9 7.5 7.5-4.6.6-6.9 2.9-7.5 7.5-.6-4.6-2.9-6.9-7.5-7.5C10.1 11.9 12.4 9.6 13 5z"/><path fill="url(#scSpG)" d="M22.5 17c.35 2.6 1.65 3.9 4.25 4.25-2.6.35-3.9 1.65-4.25 4.25-.35-2.6-1.65-3.9-4.25-4.25 2.6-.35 3.9-1.65 4.25-4.25z"/><circle cx="24" cy="8" r="1.6" fill="#2fc4e8"/></svg>';
  var CSS = '#ssChat{position:fixed;right:24px;bottom:24px;z-index:1000;display:flex;flex-direction:column;width:380px;height:min(720px,calc(100vh - 48px));border-radius:18px;background:linear-gradient(180deg,#c5d9ff 0%,#e4e6fb 38%,#f6f6fb 72%,#f8f8fb 100%);box-shadow:0 18px 48px -12px rgba(20,30,70,.35),0 0 0 1px rgba(20,30,70,.06);font-family:"Pretendard","Noto Sans KR",sans-serif;color:#111;overflow:hidden;opacity:0;transform:translateY(20px) scale(.98);transform-origin:right bottom;transition:opacity .22s,transform .25s cubic-bezier(.2,.7,.2,1)}' +
    '#ssChat.is-on{opacity:1;transform:none}' +
    '#ssChat .sc-hd{display:flex;align-items:center;gap:6px;padding:18px 14px 10px 20px}' +
    '#ssChat .sc-hd b{flex:1;font-size:15px;font-weight:800;letter-spacing:-.02em}' +
    '#ssChat .sc-hd button{border:0;background:none;color:#111;font:inherit;cursor:pointer}#ssChat .sc-home{height:30px;padding:0 10px;border-radius:15px;font-size:12.5px;color:#4a5370!important}#ssChat .sc-home:hover{background:rgba(255,255,255,.6)}' +
    '#ssChat .sc-x{width:34px;height:34px;padding:0;display:grid;place-items:center}#ssChat .sc-x svg{width:22px;height:22px}' +
    '#ssChat .sc-body{flex:1;overflow-y:auto;padding:8px 16px 8px 20px;scrollbar-width:thin}' +
    '#ssChat .sc-hello{margin:14px 0 22px}#ssChat .sc-hello i{display:grid;place-items:center;width:34px;height:34px;margin:0 0 14px;border-radius:50%;background:#fff;box-shadow:0 2px 8px -2px rgba(20,60,160,.25)}#ssChat .sc-hello i svg{width:24px;height:24px}' +
    '#ssChat .sc-hello p{margin:0;font-size:21px;line-height:1.4;letter-spacing:-.03em;font-weight:500}#ssChat .sc-hello p b{display:block;font-weight:800}#ssChat .sc-hello small{display:block;margin-top:10px;color:#5a6380;font-size:13.5px}' +
    '#ssChat .sc-msg{display:flex;margin:0 0 10px}#ssChat .sc-msg.is-me{justify-content:flex-end}' +
    '#ssChat .sc-b{max-width:90%;padding:12px 15px;border-radius:18px;background:#fff;box-shadow:0 1px 4px rgba(20,30,70,.06);font-size:14.5px;line-height:1.62;word-break:keep-all;overflow-wrap:anywhere}' +
    '#ssChat .is-me .sc-b{max-width:80%;background:#2189ff;color:#fff;box-shadow:none;font-weight:600}' +
    '#ssChat .sc-b a{color:#1a6dff;font-weight:700}#ssChat .sc-b small{display:block;color:#667;font-size:12px}' +
    '#ssChat .sc-dots{display:inline-flex;gap:4px;padding:5px 2px}#ssChat .sc-dots i{width:7px;height:7px;border-radius:50%;background:#9aa6c4;animation:scDot 1s infinite}#ssChat .sc-dots i:nth-child(2){animation-delay:.15s}#ssChat .sc-dots i:nth-child(3){animation-delay:.3s}' +
    '@keyframes scDot{0%,60%,100%{opacity:.3;transform:none}30%{opacity:1;transform:translateY(-3px)}}' +
    '#ssChat .sc-chips{display:flex;flex-direction:column;align-items:flex-start;gap:7px;margin:2px 0 14px}' +
    '#ssChat .sc-chips button{max-width:100%;border:1px solid #cfe0ff;background:#fff;color:#1a6dff;border-radius:18px;padding:9px 14px;font:inherit;font-size:14px;font-weight:600;text-align:left;cursor:pointer;transition:background .15s,border-color .15s}' +
    '#ssChat .sc-chips button:hover{background:#eef5ff;border-color:#9cc3ff}' +
    '#ssChat .sc-chips.is-grid{display:grid;grid-template-columns:1fr 1fr;align-items:stretch}#ssChat .sc-chips.is-grid button{color:#111;border-color:#e3e6ef;font-weight:700}' +
    '#ssChat .sc-tbl{width:100%;margin:8px 0;border-collapse:collapse;font-size:12.5px}#ssChat .sc-tbl th,#ssChat .sc-tbl td{padding:5px 6px;border:1px solid #e6e9f2;text-align:left;vertical-align:top}#ssChat .sc-tbl th{background:#f5f7fc}#ssChat .sc-tbl small{display:inline;margin-left:4px}' +
    '#ssChat .sc-ul{margin:6px 0;padding-left:18px}#ssChat .sc-ul li{margin:2px 0}' +
    '#ssChat .sc-store{display:flex;flex-wrap:wrap;gap:6px 12px;margin-top:8px;padding:9px 11px;border-radius:12px;background:#f3f6fd;font-size:13px}' +
    '#ssChat .sc-model{display:flex;gap:10px;margin:8px 0;padding:10px;border-radius:12px;background:#f5f7fc}#ssChat .sc-model img{width:64px;height:64px;object-fit:contain;border-radius:8px;background:#fff;flex:0 0 auto}' +
    '#ssChat .sc-model p{margin:4px 0 0;font-size:13.5px}#ssChat .sc-net{color:#0a7a46}#ssChat .sc-st{color:#0a7a46;font-weight:700}#ssChat .sc-links{display:flex;flex-wrap:wrap;gap:4px 12px;margin-top:6px;font-size:13px}' +
    '#ssChat .sc-note{margin:6px 0 0;color:#667;font-size:12px}' +
    '#ssChat .sc-help{margin:2px 0 14px;padding:13px 14px;border-radius:18px;background:rgba(255,255,255,.75);font-size:13.5px;line-height:1.55}' +
    '#ssChat .sc-help p{margin:0 0 10px;color:#333}#ssChat .sc-help div{display:flex;gap:6px}#ssChat .sc-help a{flex:1;display:flex;align-items:center;justify-content:center;min-height:38px;border-radius:19px;font-weight:700;text-decoration:none;font-size:13.5px}' +
    '#ssChat .sc-help .is-main{background:#2189ff;color:#fff}#ssChat .sc-help .is-tel{background:#fff;color:#1a6dff;border:1px solid #cfe0ff}' +
    '#ssChat .sc-ft{display:flex;align-items:center;gap:8px;padding:10px 14px 16px}' +
    '#ssChat .sc-menu{flex:0 0 auto;display:grid;place-items:center;width:34px;height:34px;border:0;border-radius:50%;background:#2189ff;color:#fff;cursor:pointer}#ssChat .sc-menu svg{width:18px;height:18px}' +
    '#ssChat .sc-ft form{flex:1;min-width:0;display:flex;align-items:center;padding:0 6px 0 14px;height:40px;border:1px solid #2189ff;border-radius:20px;background:#fff}#ssChat .sc-ft form:focus-within{box-shadow:0 0 0 3px rgba(33,137,255,.15)}' +
    '#ssChat .sc-ft input{flex:1;min-width:0;height:38px;border:0;outline:0;background:transparent;font:inherit;font-size:14px;color:#111}#ssChat .sc-ft input::placeholder{color:#8a8f9c}' +
    '#ssChat .sc-send{flex:0 0 auto;display:grid;place-items:center;width:30px;height:30px;border:0;background:none;color:#2189ff;cursor:pointer}#ssChat .sc-send svg{width:20px;height:20px}' +
    '@media (max-width:560px){#ssChat{right:0;bottom:0;left:0;width:auto;height:100%;height:100dvh;border-radius:0}}';

  var box, body, input, busy = false;
  function build() {
    var st = d.createElement('style'); st.textContent = CSS; d.head.appendChild(st);
    box = d.createElement('div'); box.id = 'ssChat'; box.setAttribute('role', 'dialog'); box.setAttribute('aria-label', '구독 상담 도우미');
    box.innerHTML = '<div class="sc-hd"><b>구독 상담 도우미</b><button type="button" class="sc-home">처음으로</button><button type="button" class="sc-x" aria-label="닫기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 5l14 14M19 5L5 19"/></svg></button></div>' +
      '<div class="sc-body" aria-live="polite"></div>' +
      '<div class="sc-ft"><button type="button" class="sc-menu" aria-label="질문 주제 보기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="4" y="4" width="6.5" height="6.5" rx="1.6"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.6"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.6"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.6"/></svg></button>' +
      '<form><input type="text" name="q" placeholder="궁금한 내용이나 모델명을 적어 주세요" aria-label="질문 입력" autocomplete="off"><button type="submit" class="sc-send" aria-label="보내기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M21 3L10.5 13.5M21 3l-6.5 18-4-7.5L3 9.5z"/></svg></button></form></div>';
    d.body.appendChild(box);
    body = box.querySelector('.sc-body'); input = box.querySelector('input');
    box.querySelector('.sc-x').addEventListener('click', close);
    box.querySelector('.sc-home').addEventListener('click', function () { track('ss_chat_home'); home(true); });
    box.querySelector('.sc-menu').addEventListener('click', function () { if (busy) return; track('ss_chat_menu'); push('어떤 주제가 궁금하세요?'); chips([], GROUPS, true); });
    box.querySelector('form').addEventListener('submit', function (ev) { ev.preventDefault(); var v = input.value.replace(/^\s+|\s+$/g, ''); if (!v || busy) return; input.value = ''; ask(v); });
    body.addEventListener('click', function (ev) {
      var b = ev.target.closest('button[data-q],button[data-g]');
      if (b && !busy) {
        if (b.hasAttribute('data-g')) { var g = b.getAttribute('data-g'); track('ss_chat_group', { ss_q: g }); showGroup(g, b.textContent); }
        else { var x = BY[b.getAttribute('data-q')]; if (x) { track('ss_chat_q', { ss_q: x.id }); reply(x, x.q); } }
        return;
      }
      var l = ev.target.closest('a[data-cta]'); if (l) track('ss_chat_click', { ss_cta: l.getAttribute('data-cta') });
    });
    d.addEventListener('keydown', function (ev) { if (ev.key === 'Escape' && box.classList.contains('is-on')) close(); });
    home(false);
  }
  function scroll() { body.scrollTop = body.scrollHeight; }
  function push(html, me) { var m = d.createElement('div'); m.className = 'sc-msg' + (me ? ' is-me' : ''); m.innerHTML = '<div class="sc-b">' + html + '</div>'; body.appendChild(m); scroll(); return m; }
  function chips(ids, groups, grid) {
    var c = d.createElement('div'); c.className = 'sc-chips' + (grid ? ' is-grid' : '');
    c.innerHTML = (groups || []).map(function (g) { return '<button type="button" class="is-grp" data-g="' + g.id + '">' + esc(g.t) + '</button>'; }).join('') +
      (ids || []).map(function (id) { return BY[id] ? '<button type="button" data-q="' + id + '">' + esc(BY[id].q) + '</button>' : ''; }).join('');
    body.appendChild(c); scroll();
  }
  function help(lead) {
    var c = d.createElement('div'); c.className = 'sc-help';
    c.innerHTML = '<p>' + (lead || '찾으시는 답이 없나요? 구독 문의를 남기시거나 전화 주시면 담당 프로가 바로 안내해 드립니다.') + '</p>' +
      '<div>' + '<a class="is-main" href="' + esc(consultUrl(null)) + '" data-cta="chat_consult">💬 구독 문의 남기기</a><a class="is-tel" href="' + esc(telHref()) + '" data-cta="chat_tel">📞 ' + esc(TEL) + '</a></div>';
    body.appendChild(c); scroll();
  }
  function typing(cb) {
    busy = true;
    var m = push('<span class="sc-dots" aria-label="답변 준비 중"><i></i><i></i><i></i></span>');
    setTimeout(function () { m.parentNode.removeChild(m); busy = false; cb(); }, 650 + Math.random() * 350);
  }
  function home(again) {
    if (again) body.innerHTML = '';
    var h = d.createElement('div'); h.className = 'sc-hello';
    h.innerHTML = '<i>' + SPARK + '</i><p>무엇이든 물어보세요<b>삼성 구독센터 상담 도우미</b></p><small>' + esc(STORE.name) + ' · 자주 묻는 질문 바로 답변 · 정확한 금액은 상담에서 확인</small>';
    body.appendChild(h);
    chips(FIRST);
    body.scrollTop = 0;
  }
  function showGroup(g, label) {
    push(esc(label), true);
    typing(function () {
      push('어떤 점이 궁금하세요?');
      chips(QA.filter(function (x) { return x.g === g; }).map(function (x) { return x.id; }));
      help();
    });
  }
  function reply(x, said) {
    push(esc(said), true);
    typing(function () {
      push(typeof x.a === 'function' ? x.a() : x.a);
      if (x.ask) { input.focus(); return; }
      if (x.n && x.n.length) chips(x.n);
      help();
    });
  }
  function ask(text) {
    track('ss_chat_text', { ss_q: text.slice(0, 60) });
    push(esc(text), true);
    typing(function () {
      var ms = findModels(text);
      if (ms.length) { push(modelAnswer(ms)); chips(['store_visit', 'p_vs', 'c_which']); help('조건을 맞춘 정확한 월 납부액은 상담에서 계산해 드립니다.'); return; }
      var x = matchQA(text), p = findPage(text);
      var priceQ = /얼마|가격|구독료|월\s?납|비용|최저|싸/.test(text);
      if (p && (priceQ || !x)) { var h = pageAnswer(p); if (h) { push(h); chips(['p_model', 'store_visit', 'p_multi']); help(); return; } }
      if (x) { push(typeof x.a === 'function' ? x.a() : x.a); if (x.n && !x.ask) chips(x.n); help(); return; }
      if (/^[A-Za-z]{2,}[0-9]/.test(text.replace(/\s/g, ''))) {
        push('적어 주신 <b>' + esc(text) + '</b> 모델을 구독 요금표에서 찾지 못했습니다. 모델명을 한 번 더 확인해 주시거나, 아래로 문의해 주시면 구독 가능 여부와 금액을 확인해 드립니다.');
        help();
        return;
      }
      push('죄송합니다. 그 질문에는 아직 정해진 답이 없습니다. 😥<br>아래 자주 묻는 질문을 보시거나, 구독 문의·전화로 물어봐 주세요.');
      chips(FIRST.slice(0, 4));
      help('구독 문의를 남기시면 담당 프로가 연락드리고, 전화하시면 바로 답변 드립니다.');
    });
  }
  function open() {
    if (!box) build();
    box.style.display = 'flex';
    requestAnimationFrame(function () { box.classList.add('is-on'); });
    var fab = d.getElementById('ssChatFab'); if (fab) fab.style.display = 'none';
    track('ss_chat_open');
    if (window.matchMedia && !window.matchMedia('(max-width:560px)').matches) setTimeout(function () { try { input.focus({ preventScroll: true }); } catch (e) {} }, 250);
  }
  function close() {
    box.classList.remove('is-on');
    setTimeout(function () { box.style.display = 'none'; }, 220);
    var fab = d.getElementById('ssChatFab'); if (fab) fab.style.display = '';
    track('ss_chat_close');
  }
  window.SUB_CHAT = { open: open, close: close, qa: QA, spark: SPARK };
})();
