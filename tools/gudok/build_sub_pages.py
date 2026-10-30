# -*- coding: utf-8 -*-
"""구독센터 페이지(고도몰 웹FTP > 스킨 subscribe/ 폴더) 생성기

    python -I tools/build_sub_pages.py

만드는 것
  skin_release/subscribe/  운영 스킨용 (예비 사본 /data/js/sub/)
  skin/subscribe/          테스트 스킨용 (예비 사본 {=c.PATH_SKIN}js/sub/)
  reports/구독센터_SEO설정.csv   고도몰 관리자 [검색엔진 최적화 > 페이지별 설정] 에 넣을 제목·설명·키워드

페이지
  sub_home.html            구독센터 홈        "삼성 구독 가격"
  sub_c_<품목>.html         품목별 구독 가격   "삼성 냉장고 구독 가격" · "삼성 AI 콤보 구독" …
  sub_card.html            제휴카드 혜택
  sub_guide.html           구독 안내 · FAQ

html 에는 검색엔진이 읽을 고정 글(제목·소개·FAQ)만 두고, 목록·가격·메뉴는 데이터센터 sub_shop.js 가 그린다.
품목 정의(PAGES)는 sub_shop.js 의 PAGES 와 key·이름을 맞춘다.
※ 고도몰 템플릿 치환 방지: 인라인 JS 의 여는 중괄호 뒤에는 항상 공백 / 고정 글에 중괄호를 쓰지 않는다
"""
import csv, html, os, sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VER = '261027-1+261027-1538+d261027-0915'   # 예비 사본 버전 (데이터센터를 읽으면 그쪽 판으로 바뀐다)
DC = 'https://db.samsungat.co.kr/sdp/sub/'
SITE = 'https://www.samsungsh.co.kr'
API = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/fn_sub_catalog'
API_KEY = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW'   # 공개키 (견적서·구독찾기와 같은 키)
TEL = '031-8042-3166'
BRAND = '삼성스토어 시흥 구독센터'
PAGE_DIR = 'subscribe'   # 스킨 안 폴더 — 주소 /main/html.php?htmid=subscribe/<파일>

COMMON_FAQ = [
    ('표시된 가격보다 더 저렴하게 구독할 수 있나요?',
     '네, 꼭 문의해 주세요. 표시된 월 구독료는 기본 요금이며, 시기별 행사·제휴카드·선납 조건을 맞추면 더 낮아질 수 있습니다. 상담을 완료하시면 문의 감사 상품(현재 네이버페이 1만원)도 드립니다.'),
    ('구독료 말고 따로 내는 돈이 있나요?',
     '표시된 월 구독료에 제품 이용료와 선택한 케어 서비스가 포함되어 있습니다. 설치 환경에 따라 추가 설치비가 생기는 경우에는 상담 단계에서 미리 안내해 드립니다.'),
    ('제휴카드 할인은 어떻게 받나요?',
     '구독료를 제휴카드로 자동결제하면 전월 이용실적 구간에 따라 매월 청구할인이 들어갑니다. 카드별 할인 금액과 기간은 제휴카드 혜택 페이지에서 확인할 수 있습니다.'),
    ('선납 할인은 무엇인가요?',
     '구독 신청 때 제품 금액의 일부를 먼저 내면 남은 기간의 월 구독료가 낮아지고, 선납 비율에 따라 추가 할인도 받을 수 있습니다. 품목마다 선납 가능한 비율이 다릅니다.'),
    ('상담 신청하면 바로 계약되나요?',
     '아닙니다. 상담 신청은 요금 안내를 받기 위한 단계입니다. 약정 기간·케어 주기·카드 조건을 맞춘 실제 월 납부액을 안내받은 뒤 결정하시면 됩니다.'),
]

# key, 이름(화면), 검색 키워드 이름, 소개 글, 특징 몇 개, 품목 FAQ
PAGES = [
    ('ref', '냉장고', '냉장고',
     '비스포크 AI 하이브리드 4도어, 키친핏, 양문형까지 삼성 냉장고 구독 모델의 월 구독료를 한 페이지에서 비교하세요.',
     ['4도어 · 키친핏 · 양문형 · 일반형', '약정 3~6년', '방문케어 포함 요금'],
     [('냉장고 구독은 어떤 케어가 포함되나요?', '선택한 케어 유형에 따라 정기 방문 점검과 위생 관리가 포함되며, 약정 기간 동안 무상수리를 받을 수 있습니다. 모델마다 선택 가능한 케어가 다르니 모델 페이지에서 확인하세요.')]),
    ('kimchi', '김치냉장고', '김치냉장고',
     '스탠드형, 뚜껑형, 김치플러스까지 삼성 김치냉장고 구독 모델의 월 구독료를 비교하세요.',
     ['스탠드형 · 뚜껑형 · 김치플러스', '약정 3~6년', '제휴카드 할인'],
     [('김치냉장고도 구독이 되나요?', '네. 비스포크 김치플러스를 포함한 스탠드형·뚜껑형 모델을 구독으로 이용할 수 있고, 약정 기간과 케어 유형에 따라 월 구독료가 달라집니다.')]),
    ('aicombo', 'AI 콤보', 'AI 콤보',
     '세탁과 건조를 한 대로 끝내는 비스포크 AI 콤보(세탁건조기)를 구독으로 만나보세요. 수납함 세트까지 모델별 월 구독료를 비교할 수 있습니다.',
     ['세탁 + 건조 일체형', '수납함 세트 모델 포함', '방문케어 · 제휴카드 할인'],
     [('AI 콤보는 어떤 제품인가요?', '세탁기와 건조기를 한 대에 담은 삼성 비스포크 AI 세탁건조기입니다. 세탁이 끝나면 옮기지 않고 바로 건조까지 이어집니다.'),
      ('AI 콤보 구독료는 얼마인가요?', '모델·약정 기간·케어 유형에 따라 다릅니다. 이 페이지의 모델 목록에서 최저 월 구독료를 비교하고, 모델을 누르면 약정·케어·선납·카드별 금액을 계산해 볼 수 있습니다.')]),
    ('washer', '세탁기', '세탁기',
     '드럼세탁기, 전자동(통돌이), 세탁기+건조기 원바디까지 삼성 세탁기 구독 모델의 월 구독료를 비교하세요.',
     ['드럼 · 전자동 · 원바디', '약정 3~6년', '방문케어 포함 요금'],
     [('세탁기 구독에 세탁조 관리가 포함되나요?', '방문케어를 선택하면 정기적으로 방문해 세탁기 내부 관리를 해 드립니다. 케어 주기는 모델 페이지에서 선택할 수 있습니다.')]),
    ('dryer', '건조기', '건조기',
     '비스포크 AI 건조기와 그랑데 건조기의 구독 모델과 월 구독료를 비교하세요.',
     ['그랑데 · 비스포크 AI', '약정 3~6년', '제휴카드 할인'],
     [('건조기만 따로 구독할 수 있나요?', '네. 건조기 단독 모델도 구독할 수 있고, 세탁기와 함께 쓰려면 세탁기 페이지나 AI 콤보 페이지에서 함께 비교해 보세요.')]),
    ('airdresser', '에어드레서', '에어드레서',
     '3벌식부터 대용량 5~9벌까지 삼성 에어드레서 구독 모델의 월 구독료를 비교하세요.',
     ['3벌식 · 5벌식 · 대용량', '약정 3~6년', '방문케어 포함 요금'],
     [('에어드레서 구독은 선납이 얼마까지 되나요?', '에어드레서는 제품 금액의 최대 50%까지 선납할 수 있습니다. 선납 비율에 따라 월 구독료가 낮아집니다.')]),
    ('aircon', '에어컨', '에어컨',
     '무풍 스탠드, 홈멀티(2in1), 벽걸이, 창문형까지 삼성 에어컨 구독 모델의 월 구독료를 비교하세요.',
     ['스탠드 · 홈멀티 · 벽걸이 · 창문형', '방문 세척 케어', '제휴카드 할인'],
     [('에어컨 구독에 세척 서비스가 포함되나요?', '케어 유형에 따라 정기 방문 세척·점검이 포함됩니다. 케어 주기를 고르면 월 구독료가 바로 바뀌니 모델 페이지에서 비교해 보세요.'),
      ('설치비는 별도인가요?', '기본 설치는 포함되며, 배관 연장이나 실외기 거치 등 설치 환경에 따른 추가 비용은 상담 때 미리 안내해 드립니다.')]),
    ('sysaircon', '시스템에어컨', '시스템에어컨',
     '천장형 시스템에어컨과 전열교환기를 구독으로. 가정용 1실부터 4실 이상까지 월 구독료를 비교하세요.',
     ['천장형 1~5실', '전열교환기', '설치 상담'],
     [('시스템에어컨도 구독할 수 있나요?', '네. 가정용 천장형 시스템에어컨을 실 수별로 구독할 수 있습니다. 설치 환경 확인이 필요해 상담을 통해 정확한 금액을 안내해 드립니다.')]),
    ('tv', 'TV', 'TV',
     'Neo QLED, OLED, Micro RGB, 크리스탈 UHD, 더 무빙스타일까지 삼성 TV 구독 모델을 크기별로 비교하세요.',
     ['40형부터 100형까지', '사운드바 · 보조 TV 세트', '약정 3~6년'],
     [('TV 구독은 크기별로 가격이 다른가요?', '네. 화면 크기와 라인업(프리미엄 4K·OLED·크리스탈 UHD 등)에 따라 월 구독료가 다릅니다. 이 페이지에서 크기별로 걸러 볼 수 있습니다.')]),
    ('water', '정수기', '정수기',
     '비스포크 AI 정수기, 얼음정수기까지 삼성 정수기 구독 모델의 월 구독료와 필터 관리 주기를 비교하세요.',
     ['냉·온·정수 · 얼음정수기', '정기 필터 교체', '방문케어'],
     [('정수기 필터 교체는 어떻게 하나요?', '구독 기간 동안 정해진 주기에 맞춰 필터를 교체해 드립니다. 케어 주기는 모델 페이지에서 확인할 수 있습니다.')]),
    ('airpurifier', '공기청정기', '공기청정기',
     '인피니트 AI 공기청정기, 비스포크 큐브 Air, 블루스카이까지 삼성 공기청정기 구독 모델을 비교하세요.',
     ['인피니트 AI · 큐브 Air · 블루스카이', '필터 정기 교체', '제휴카드 할인'],
     [('공기청정기 구독에 필터가 포함되나요?', '케어 유형에 따라 필터 교체가 포함됩니다. 리유저블 필터 모델은 세척 관리가 들어갑니다.')]),
    ('cleaner', '청소기', '청소기',
     '비스포크 AI 스팀 로봇청소기와 제트 무선청소기를 구독으로. 모델별 월 구독료를 비교하세요.',
     ['AI 로봇청소기 · 무선청소기', '직배수 모델', '약정 3~6년'],
     [('로봇청소기도 구독이 되나요?', '네. 비스포크 AI 스팀 로봇청소기를 포함한 모델을 구독할 수 있고, 직배수 설치형 모델도 있습니다.')]),
    ('dishwasher', '식기세척기', '식기세척기',
     '비스포크 AI 빌트인 식기세척기 14인용부터 카운터탑까지, 정수필터 유무별로 구독 모델의 월 구독료를 비교하세요.',
     ['8~14인용 빌트인', '카운터탑', '정수필터 모델'],
     [('식기세척기 구독은 설치가 어떻게 되나요?', '빌트인 모델은 싱크대 하부 공간 확인이 필요합니다. 상담 때 설치 가능 여부와 추가 비용을 미리 확인해 드립니다.')]),
    ('induction', '인덕션·후드', '인덕션',
     '비스포크 인덕션, 인피니트 AI 인덕션, 후드 일체형 인덕션과 후드까지 삼성 조리기기 구독 모델을 비교하세요.',
     ['인덕션 · 전기레인지', '후드 일체형', '후드 단독'],
     [('인덕션 구독에 방문케어가 있나요?', '전기레인지는 방문케어 유형을 고를 수 있는 모델이 있습니다. 모델 페이지에서 케어별 요금을 비교해 보세요.')]),
    ('monitor', '모니터', '모니터',
     '스마트모니터 M7·M8, 뷰피니티, 오디세이까지 삼성 모니터 구독 모델의 월 구독료를 비교하세요.',
     ['스마트모니터 · 뷰피니티', '32형 이하부터 대형까지', '제휴카드 할인'],
     [('모니터 구독은 사업자도 가능한가요?', '개인과 사업자 모두 상담 가능합니다. 여러 대를 함께 구독하는 경우 상담으로 문의해 주세요.')]),
    ('galaxy', '갤럭시 탭·북', '갤럭시 탭',
     '갤럭시 탭 S10, 갤럭시 북6 등 삼성 태블릿·노트북 구독 모델의 월 구독료를 비교하세요.',
     ['갤럭시 탭 · 갤럭시 북', '파손보험 포함 상품', '약정 기간 선택'],
     [('갤럭시 탭·북 구독에는 어떤 혜택이 있나요?', '상품에 따라 파손보험과 무상보증이 포함됩니다. 포함 내용은 모델 페이지의 케어 유형에서 확인할 수 있습니다.')]),
    ('audio', '사운드바·오디오', '사운드바',
     '삼성 사운드바와 뮤직 스튜디오 스피커 구독 모델의 월 구독료를 비교하세요.',
     ['사운드바 · 스피커', 'TV 세트 구성 가능', '약정 기간 선택'],
     [('TV와 사운드바를 함께 구독할 수 있나요?', '네. TV 페이지에는 사운드바를 함께 묶은 세트 모델도 있습니다. 따로 구독하는 경우와 비교해 보세요.')]),
    ('dehumid', '제습기', '제습기',
     '삼성 제습기 구독 모델의 월 구독료를 비교하세요.',
     ['제습기', '약정 기간 선택', '제휴카드 할인'],
     [('제습기도 방문케어가 되나요?', '모델에 따라 선택 가능한 케어가 다릅니다. 모델 페이지에서 확인해 주세요.')]),
]


def e(s):
    return html.escape(s, quote=True)


def faq_html(items):
    return '<dl class="ss-faq">\n' + '\n'.join(
        '            <dt>%s</dt>\n            <dd>%s</dd>' % (e(q), e(a)) for q, a in items) + '\n        </dl>'


def loader(base_expr, page, key=''):
    return '''<script type="text/javascript">
    /* ※ 고도몰 템플릿 치환 방지: 여는 중괄호 뒤에는 항상 공백 */
    /* 요금표·화면 파일은 데이터센터(sdp/sub)에서 읽는다 — 상품상세 구독탭·구독상품 찾기와 같은 순서: version.js → dcBase, 실패 시 dataBase(예비 사본) */
    var SUB_SHOP_CONFIG = { page: '%(page)s', key: '%(key)s', ver: '%(ver)s',
        dcBase: '%(dc)s',
        dataBase: '%(base)s',
        catalogApi: { url: '%(api)s', key: '%(apikey)s', timeout: 3000 },
        site: '%(site)s',
        tel: '%(tel)s',
        defaultCard: '삼성카드'
    };
    if (SUB_SHOP_CONFIG.dcBase) document.write('<script src="' + SUB_SHOP_CONFIG.dcBase + 'version.js?t=' + Math.floor(Date.now() / 300000) + '"><\\/script>');
</script>
<script type="text/javascript">
    if (window.SUB_VER && SUB_SHOP_CONFIG.dcBase) { SUB_SHOP_CONFIG.localBase = SUB_SHOP_CONFIG.dataBase; SUB_SHOP_CONFIG.localVer = SUB_SHOP_CONFIG.ver; SUB_SHOP_CONFIG.dataBase = SUB_SHOP_CONFIG.dcBase; SUB_SHOP_CONFIG.ver = window.SUB_VER; }
    document.write('<script src="' + SUB_SHOP_CONFIG.dataBase + 'sub_index.js?v=' + encodeURIComponent(SUB_SHOP_CONFIG.ver) + '" charset="utf-8"><\\/script>');
</script>
<script type="text/javascript">
    if (!window.SUB_INDEX && SUB_SHOP_CONFIG.localBase) { SUB_SHOP_CONFIG.dataBase = SUB_SHOP_CONFIG.localBase; SUB_SHOP_CONFIG.ver = SUB_SHOP_CONFIG.localVer; SUB_SHOP_CONFIG.dcFailed = true;
        document.write('<script src="' + SUB_SHOP_CONFIG.dataBase + 'sub_index.js?v=' + encodeURIComponent(SUB_SHOP_CONFIG.ver) + '" charset="utf-8"><\\/script>'); }
</script>
<script type="text/javascript">
    document.write('<link rel="stylesheet" href="' + SUB_SHOP_CONFIG.dataBase + 'sub_shop.css?v=' + encodeURIComponent(SUB_SHOP_CONFIG.ver) + '">');
    document.write('<script src="' + SUB_SHOP_CONFIG.dataBase + 'sub_shop.js?v=' + encodeURIComponent(SUB_SHOP_CONFIG.ver) + '" charset="utf-8"><\\/script>');
</script>
<script type="text/javascript">
    /* 데이터센터에서 화면 파일을 못 받았으면 예비 사본(웹FTP)에서 */
    if (!window.SUB_SHOP_READY && SUB_SHOP_CONFIG.localBase) { document.write('<link rel="stylesheet" href="' + SUB_SHOP_CONFIG.localBase + 'sub_shop.css?v=' + encodeURIComponent(SUB_SHOP_CONFIG.localVer) + '">');
        document.write('<script src="' + SUB_SHOP_CONFIG.localBase + 'sub_shop.js?v=' + encodeURIComponent(SUB_SHOP_CONFIG.localVer) + '" charset="utf-8"><\\/script>'); }
</script>''' % dict(page=page, key=key, ver=VER, dc=DC, base=base_expr, api=API, apikey=API_KEY, site=SITE, tel=TEL)


def page(fname, title, desc, keywords, body, page_kind, key, base_expr):
    url = SITE + '/main/html.php?htmid=' + PAGE_DIR + '/' + fname
    return '''{*** [구독센터] %(title)s | main/html.php?htmid=%(dir)s/%(fname)s — tools/build_sub_pages.py 로 만든 파일 ***}
{ # header }
<meta name="title" content="%(title)s">
<meta name="description" content="%(desc)s">
<meta name="keywords" content="%(kw)s">
<link rel="canonical" href="%(url)s">
<meta property="og:title" content="%(title)s">
<meta property="og:description" content="%(desc)s">
<meta property="og:type" content="website">
<meta property="og:url" content="%(url)s">

<div id="subShopRoot">
    <div data-ss="nav"></div>
%(body)s
    <section class="ss-sec"><div data-ss="cta"></div></section>
</div>

%(loader)s

{ # footer }
''' % dict(title=e(title), fname=fname, desc=e(desc), kw=e(keywords), url=e(url), body=body,
           loader=loader(base_expr, page_kind, key), dir=PAGE_DIR)


def home_body():
    return '''    <header class="ss-hero">
        <p class="ss-eyebrow">삼성 AI 구독클럽 · 삼성스토어 시흥</p>
        <h1>삼성 가전 구독 가격, 한 번에 비교하세요</h1>
        <p class="ss-lead">냉장고·AI 콤보·에어컨·TV·정수기까지 삼성 구독 모델의 월 구독료를 품목별로 모았습니다.
            약정 기간, 방문케어 주기, 선납 할인, 제휴카드 할인을 반영한 실제 납부액은 상담으로 바로 안내해 드립니다.</p>
        <div data-ss="search"></div>
        <ul class="ss-points"><li>구독 모델 1,000여 개</li><li>제휴카드 청구할인</li><li>선납 할인</li><li>방문케어 · 무상수리</li></ul>
    </header>

    <section class="ss-sec">
        <h2>품목별 삼성 구독 가격</h2>
        <p class="ss-sub">품목을 고르면 모델별 최저 월 구독료를 비교할 수 있습니다.</p>
        <div data-ss="cats"></div>
    </section>

    <section class="ss-sec ss-band">
        <div>
            <h2>삼성 AI 콤보 구독</h2>
            <p>세탁부터 건조까지 한 대로. 비스포크 AI 콤보 세탁건조기를 월 구독료로 만나보세요.</p>
        </div>
        <div data-ss="pick" data-key="aicombo" data-n="3"></div>
    </section>

    <section class="ss-sec">
        <h2>품목별 대표 구독 모델</h2>
        <p class="ss-sub">모델을 누르면 약정·케어·선납·제휴카드별 월 납부액을 계산해 볼 수 있습니다.</p>
        <div data-ss="popular" data-n="12"></div>
    </section>

    <section class="ss-sec">
        <h2>제휴카드로 구독료를 더 낮추세요</h2>
        <p class="ss-sub">구독료를 제휴카드로 자동결제하면 전월 실적에 따라 매월 청구할인을 받습니다.</p>
        <div data-ss="cards"></div>
    </section>

    <section class="ss-sec">
        <h2>구독은 이렇게 진행돼요</h2>
        <ol class="ss-steps">
            <li><strong>구독 문의</strong><p>원하는 모델이나 품목을 남겨 주세요. 전화 상담도 가능합니다.</p></li>
            <li><strong>요금 안내</strong><p>약정 기간·케어 주기·선납·카드 조건을 맞춘 월 납부액을 안내해 드립니다.</p></li>
            <li><strong>계약 · 설치</strong><p>조건을 확정하면 삼성전자 전문 기사가 방문해 설치합니다.</p></li>
            <li><strong>케어 · 무상수리</strong><p>약정 기간 동안 정기 방문케어와 무상수리를 받습니다.</p></li>
        </ol>
    </section>

    <section class="ss-sec">
        <h2>자주 묻는 질문</h2>
        %(faq)s
    </section>
''' % dict(faq=faq_html(COMMON_FAQ))


def cat_body(key, name, kw, lead, points, faq):
    return '''    <header class="ss-head">
        <p class="ss-crumb"><a href="/main/html.php?htmid=%(dir)s/sub_home.html">구독센터</a> › %(name)s 구독</p>
        <h1>삼성 %(name)s 구독 가격</h1>
        <p class="ss-lead">%(lead)s</p>
        <ul class="ss-points">%(points)s</ul>
    </header>

    <section class="ss-sec">
        <h2 class="ss-hidden-h">삼성 %(name)s 구독 모델 목록</h2>
        <div data-ss="list"></div>
    </section>

    <section class="ss-sec">
        <h2>%(name)s 구독, 자주 묻는 질문</h2>
        %(faq)s
    </section>

    <section class="ss-sec">
        <h2>다른 품목 구독 가격</h2>
        <div data-ss="related"></div>
    </section>
''' % dict(dir=PAGE_DIR, name=e(name), lead=e(lead), points=''.join('<li>%s</li>' % e(p) for p in points), faq=faq_html(faq + COMMON_FAQ[:2]))


def card_body():
    return '''    <header class="ss-head">
        <p class="ss-crumb"><a href="/main/html.php?htmid=%(dir)s/sub_home.html">구독센터</a> › 제휴카드 혜택</p>
        <h1>삼성 구독 제휴카드 할인 혜택</h1>
        <p class="ss-lead">구독료를 제휴카드로 자동결제하면 전월 이용실적 구간에 따라 매월 청구할인을 받습니다.
            카드별 할인 금액과 할인 기간을 비교해 보세요.</p>
    </header>

    <section class="ss-sec">
        <h2>제휴카드 한눈에 보기</h2>
        <div data-ss="cards"></div>
    </section>

    <section class="ss-sec">
        <h2>카드별 실적 구간</h2>
        <p class="ss-sub">할인 금액은 전월 이용실적에 따라 달라집니다. 실적 산정 기준은 카드사 기준을 따릅니다.</p>
        <div data-ss="cardtable"></div>
    </section>

    <section class="ss-sec">
        <h2>제휴카드 혜택, 자주 묻는 질문</h2>
        %(faq)s
    </section>
''' % dict(dir=PAGE_DIR, faq=faq_html([
        ('구독 중에 카드를 바꿀 수 있나요?', '결제 카드는 변경할 수 있지만, 제휴카드 할인은 해당 카드로 자동결제가 등록된 달부터 적용됩니다. 카드사별 신청 조건은 상담 때 안내해 드립니다.'),
        ('카드 할인이 구독료보다 크면 어떻게 되나요?', '청구할인은 카드사 기준에 따라 적용되며, 할인 금액이 구독료보다 큰 경우의 처리는 카드사마다 다릅니다. 상담 때 예상 납부액을 정확히 계산해 드립니다.'),
        COMMON_FAQ[2]]))


def guide_body():
    return '''    <header class="ss-head">
        <p class="ss-crumb"><a href="/main/html.php?htmid=%(dir)s/sub_home.html">구독센터</a> › 구독 안내</p>
        <h1>삼성 가전 구독, 이렇게 이용해요</h1>
        <p class="ss-lead">삼성 AI 구독클럽은 제품을 일시불로 사지 않고 매월 구독료를 내며 이용하는 서비스입니다.
            약정 기간 동안 방문케어와 무상수리를 함께 받을 수 있습니다.</p>
    </header>

    <section class="ss-sec ss-text">
        <h2>구독료는 이렇게 정해져요</h2>
        <h3>약정 기간</h3>
        <p>품목에 따라 3년부터 6년까지 약정 기간을 고를 수 있습니다. 약정이 길수록 월 구독료가 낮아집니다.</p>
        <h3>케어 유형 · 방문 주기</h3>
        <p>방문케어, 셀프케어 등 케어 유형과 방문 주기에 따라 월 구독료가 달라집니다. 같은 모델이라도 케어를 바꾸면 금액이 바뀝니다.</p>
        <h3>선납 할인</h3>
        <p>신청할 때 제품 금액의 일부를 먼저 내면 남은 기간의 월 구독료가 낮아지고, 선납 비율에 따라 추가 할인도 받습니다. 선납은 신청할 때만 고를 수 있습니다.</p>
        <h3>제휴카드 · 자동납부 할인</h3>
        <p>제휴카드로 자동결제하면 전월 실적에 따라 매월 청구할인을 받고, 자동납부 할인이 추가로 적용될 수 있습니다.</p>
    </section>

    <section class="ss-sec">
        <h2>진행 순서</h2>
        <ol class="ss-steps">
            <li><strong>구독 문의</strong><p>원하는 모델이나 품목을 남겨 주세요.</p></li>
            <li><strong>요금 안내</strong><p>조건을 맞춘 실제 월 납부액을 안내해 드립니다.</p></li>
            <li><strong>계약 · 설치</strong><p>조건을 확정하면 전문 기사가 방문해 설치합니다.</p></li>
            <li><strong>케어 · 무상수리</strong><p>약정 기간 동안 정기 케어와 무상수리를 받습니다.</p></li>
        </ol>
    </section>

    <section class="ss-sec">
        <h2>자주 묻는 질문</h2>
        %(faq)s
    </section>

    <section class="ss-sec">
        <h2>품목별 구독 가격 보기</h2>
        <div data-ss="related"></div>
    </section>
''' % dict(dir=PAGE_DIR, faq=faq_html(COMMON_FAQ + [
        ('구독이 끝나면 제품은 어떻게 되나요?', '약정 기간이 끝난 뒤의 제품 소유와 이용 조건은 계약 유형에 따라 다릅니다. 계약 전에 상담에서 미리 안내해 드립니다.'),
        ('중간에 해지할 수 있나요?', '약정 기간 중 해지하면 남은 기간과 계약 조건에 따른 위약금이 생길 수 있습니다. 상담 때 조건을 미리 확인해 드립니다.')]))


def page_list():
    """페이지 목록 (파일, 제목, 설명, 키워드, 본문, 종류, 품목키) — build_gudok.py 도 이 목록을 쓴다"""
    files = []
    t = '삼성 구독 가격 비교 | 삼성 AI 구독클럽 · ' + BRAND
    d = '삼성 가전 구독 가격을 품목별로 한 번에 비교하세요. 냉장고·AI 콤보·에어컨·TV·정수기 등 1,000여 개 모델의 월 구독료와 제휴카드·선납 할인까지. 삼성스토어 시흥 구독 상담.'
    k = '삼성 구독 가격, 삼성 가전 구독, 삼성 AI 구독클럽, 삼성 AI 콤보 구독, 가전 구독료 비교, 삼성스토어 시흥'
    files.append(('sub_home.html', t, d, k, home_body(), 'home', ''))
    for key, name, kw, lead, points, faq in PAGES:
        t = '삼성 %s 구독 가격 비교 | 월 구독료 · 카드 할인 · %s' % (name, BRAND)
        d = '삼성 %s 구독 모델의 월 구독료를 한 번에 비교하세요. %s 제휴카드 할인·선납 할인·방문케어 주기별 요금까지 삼성스토어 시흥에서 상담받으세요.' % (name, lead)
        k = '삼성 %s 구독, 삼성 %s 구독 가격, %s 구독료, %s 렌탈, 삼성 AI 구독클럽' % (kw, kw, kw, kw)
        if key == 'aicombo':
            k = '삼성 AI 콤보 구독, 삼성 ai 콤보 구독 가격, 비스포크 AI 콤보 구독, 세탁건조기 구독, AI 콤보 렌탈, 삼성 AI 구독클럽'
        files.append(('sub_c_%s.html' % key, t, d, k, cat_body(key, name, kw, lead, points, faq), 'cat', key))
    files.append(('sub_card.html', '삼성 구독 제휴카드 할인 혜택 | ' + BRAND,
                  '삼성 가전 구독료를 제휴카드로 자동결제하면 매월 청구할인. 삼성카드·우리카드·KB국민카드·롯데카드·하나카드 등 카드별 실적 구간과 할인 금액을 비교하세요.',
                  '삼성 구독 카드 할인, 구독 제휴카드, 삼성카드 구독 할인, 삼성 AI 구독클럽 카드', card_body(), 'card', ''))
    files.append(('sub_guide.html', '삼성 가전 구독 안내 · 자주 묻는 질문 | ' + BRAND,
                  '삼성 AI 구독클럽 이용 방법. 약정 기간, 케어 유형, 선납 할인, 제휴카드 할인으로 구독료가 정해지는 방식과 자주 묻는 질문을 정리했습니다.',
                  '삼성 구독 안내, 삼성 AI 구독클럽, 가전 구독 방법, 구독 선납 할인, 구독 해지', guide_body(), 'guide', ''))
    return files


def build():
    targets = [('skin_release', '/data/js/sub/'), ('skin', '{=c.PATH_SKIN}js/sub/')]
    files = page_list()
    for folder, base in targets:
        out = os.path.join(BASE, folder, PAGE_DIR)
        os.makedirs(out, exist_ok=True)
        for fname, t, d, k, body, kind, key in files:
            with open(os.path.join(out, fname), 'w', encoding='utf-8', newline='\n') as f:
                f.write(page(fname, t, d, k, body, kind, key, base))
    rep = os.path.join(BASE, 'reports', '구독센터_SEO설정.csv')
    os.makedirs(os.path.dirname(rep), exist_ok=True)
    with open(rep, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['파일(' + PAGE_DIR + '/)', '주소', '제목(title)', '설명(description)', '키워드'])
        for fname, t, d, k, *_ in files:
            w.writerow([fname, SITE + '/main/html.php?htmid=' + PAGE_DIR + '/' + fname, t, d, k])
    sys.stdout.buffer.write(('%d pages x %d skins · %s\n' % (len(files), len(targets), rep)).encode('utf-8'))




def build_sitemap(index_js):
    """구독센터 사이트맵 — 홈·품목·카드·안내·찾기 + 구독 모델 페이지 전부 (sub_index.js 의 모델 목록)
        python -I tools/build_sub_pages.py sitemap <sub_index.js 경로>"""
    import json, re, datetime
    src = open(index_js, encoding='utf-8').read()
    m = re.search(r'=\s*(\{.*\})\s*;?\s*$', src, re.S)
    idx = json.loads(m.group(1))
    today = datetime.date.today().isoformat()
    urls = [('sub_home.html', '1.0', 'daily')] + [('sub_c_%s.html' % p[0], '0.9', 'daily') for p in PAGES] + \
           [('sub_card.html', '0.7', 'weekly'), ('sub_guide.html', '0.6', 'monthly'), ('sub_find.html', '0.6', 'daily')]
    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for f, pri, freq in urls:
        out.append('<url><loc>%s</loc><lastmod>%s</lastmod><changefreq>%s</changefreq><priority>%s</priority></url>' % (
            e(SITE + '/main/html.php?htmid=' + PAGE_DIR + '/' + f), today, freq, pri))
    for model in sorted(idx['m']):
        out.append('<url><loc>%s</loc><lastmod>%s</lastmod><changefreq>weekly</changefreq><priority>0.5</priority></url>' % (
            e(SITE + '/main/html.php?htmid=' + PAGE_DIR + '/sub_view.html&model=' + model), today))
    out.append('</urlset>')
    path = os.path.join(BASE, 'reports', 'sitemap_sub.xml')
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('\n'.join(out) + '\n')
    sys.stdout.buffer.write(('sitemap %d urls · %s\n' % (len(out) - 3, path)).encode('utf-8'))


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == 'sitemap':
        build_sitemap(sys.argv[2])
    else:
        build()
