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
BRAND = '삼성스토어 구독센터'
PAGE_DIR = 'subscribe'   # 스킨 안 폴더 — 주소 /main/html.php?htmid=subscribe/<파일>

COMMON_FAQ = [
    ('표시된 가격보다 더 저렴하게 구독할 수 있나요?',
     '네, 꼭 문의해 주세요. 표시된 월 구독료는 기본 요금이며, 시기별 행사·제휴카드·선납 조건을 맞추면 더 낮아질 수 있습니다. 상담을 완료하시면 네이버 페이 1만원을, 매장 방문 구매를 완료하시면 와인을 드립니다.'),
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
        <p class="ss-eyebrow">삼성스토어 구독센터 · 삼성 AI 구독클럽 · 삼성스토어 시흥</p>
        <h1>삼성스토어 구독센터 <span>삼성 가전 구독 가격, 한 번에 비교하세요</span></h1>
        <p class="ss-lead">냉장고·AI 콤보·에어컨·TV·정수기까지 삼성 구독 모델의 월 구독료를 품목별로 모았습니다.
            약정 기간, 방문케어 주기, 선납 할인, 제휴카드 할인을 반영한 실제 납부액은 상담으로 바로 안내해 드립니다.</p>
        <div data-ss="search"></div>
        <ul class="ss-points"><li>구독 모델 1,000여 개</li><li>제휴카드 청구할인</li><li>선납 할인</li><li>방문케어 · 무상수리</li></ul>
    </header>

    <!-- 11월 행사 배너 (시흥몰 메인 슬라이드와 같은 그림 · 2026-11-04 여러 장 · 기간이 지나면 sub_shop.js 가 지운다 · 한 장 남으면 넘김 없음)
         1) AI콤보·TV 행사(글자 없는 그림 + 문구)  2) 구독 페스티벌 최대 20%%  3) 혼수·입주·이사(휴대폰 그림만 있어 휴대폰에서만) -->
    <!-- 홈 배너 — 시흥몰 최근 배너 인용 (AI콤보 blog 166 · TV/QLED blog 165 · 2026-11-05) · 이미지 아래 문구 -->
    <div class="ss-promos" data-ss-slider>
    <a class="ss-promo has-cap" href="https://www.samsungsh.co.kr/board/view.php?&amp;bdId=blog&amp;sno=166" data-cta="promo_combo">
        <img class="ss-promo-pc ss-promo-all" src="https://cdn-saas-web-116-108.cdn-nhncommerce.com/samsungsh70_godomall_com/data/skin/front/designbook_air_RES/img/banner/0518c0bdfbefc9731f1c6873d8ef5a46_31293.png" alt="비스포크 AI 콤보 25/20kg 구독 혜택 적용가 2,743,920원 · 실제 월 구독료 45,610원 (WD90H25AHW) - 삼성스토어 시흥" width="1983" height="793">
        <div class="ss-promo-cap"><b>비스포크 AI 콤보 25/20kg 구독</b><p>정상 총구독가 4,867,200원 → 혜택 적용가 <em>2,743,920원</em> · 실제 월 구독료 <em>45,610원</em> (화이트 WD90H25AHW)</p><strong>AI 콤보 구독 혜택 보기</strong></div>
    </a>
    <a class="ss-promo has-cap" href="https://www.samsungsh.co.kr/board/view.php?&amp;bdId=blog&amp;sno=165" data-cta="promo_tv">
        <img class="ss-promo-pc ss-promo-all" src="https://cdn-saas-web-116-108.cdn-nhncommerce.com/samsungsh70_godomall_com/data/skin/front/designbook_air_RES/img/banner/914a75f108efc04047b4fb4af43fbfde_95717.png" alt="한눈에 보는 삼성 TV 가격 차이 - 85인치 Neo QLED QNH80 벽걸이형 구독 실부담 2,562,160원 · 일반 구매보다 1,297,840원 절약 - 삼성스토어 시흥" width="2172" height="724" loading="lazy">
        <div class="ss-promo-cap"><b>85인치 Neo QLED · Mini LED TV 구독</b><p>Neo QLED QNH80 벽걸이형 구독 실부담 <em>2,562,160원</em> — 일반 구매(3,860,000원)보다 <em>1,297,840원 절약</em> · 75인치 Mini LED MH80 1,395,440원</p><strong>TV 구독 가격 비교 보기</strong></div>
    </a>
    </div>

    <!-- 이달의 혜택 — 시흥몰 맨 위 혜택 띠와 같은 내용 (2026-11-04 · 사은품 문구 2026-11-09) -->
    <section class="ss-sec ss-month">
        <h2>이달의 혜택 <small>2026.11.01 ~ 11.30</small></h2>
        <details class="ss-month-more"><summary><span class="is-open-no">이달의 혜택 4가지 더보기</span><span class="is-open-yes">접기</span></summary>
        <ul class="ss-month-list">
            <li data-until="2026-11-30"><b>🎉 구독 페스티벌 최대 20%% 할인</b><p>상담완료 시, 네이버 페이 1만원 증정 · 매장 방문 구매 완료 시 와인 증정</p>
                <span><a href="https://www.samsungsh.co.kr/main/html.php?htmid=service/subscribe_festival.html" data-cta="month_festival">상세보기</a><a class="is-main" href="https://www.samsungsh.co.kr/main/html.php?htmid=service/SamSungSubscription.html" data-cta="month_festival_consult">구독 상담 신청</a></span></li>
            <li><b>💍 혼수 · 입주 · 이사 최대 1645만원 혜택</b><p>여러 대를 한 번에 — 상시 진행</p>
                <span><a href="https://www.samsungsh.co.kr/board/view.php?&amp;bdId=blog&amp;sno=83" data-cta="month_wedding">상세보기</a><a class="is-main" href="https://www.samsungsh.co.kr/main/html.php?htmid=service/SamSungSubscription.html?evt=wedding" data-cta="month_wedding_consult">상담 신청</a></span></li>
            <li data-until="2026-11-30" id="b2b"><b>🏢 사업자 전용 B2B 구독 페스티벌</b><p>사업자 전용 · 기본 20%% 할인 + 최대 30%% 할인 · 삼성전자 B2B AI 구독 파트너</p>
                <span><a href="https://www.samsungsh.co.kr/board/view.php?&amp;bdId=blog&amp;sno=121" data-cta="month_b2b">상세보기</a><a class="is-main" href="https://www.samsungsh.co.kr/main/html.php?htmid=service/SamSungSubscription.html?evt=b2b" data-cta="month_b2b_consult">사업자 견적 문의</a></span></li>
            <li><b>📱 갤럭시 탭 · 북 구독</b><p>갤럭시 자급제·탭·북도 월 구독으로</p>
                <span><a href="https://www.samsungsh.co.kr/board/view.php?page=1&amp;bdId=blog&amp;sno=132" data-cta="month_galaxy">상세보기</a><a class="is-main" href="/main/html.php?htmid=subscribe/sub_c_galaxy.html" data-cta="month_galaxy_list">구독 가격 보기</a></span></li>
        </ul>
        </details>
    </section>

<section class="ss-sec">
        <h2>월 구독료 가격대별로 보기</h2>
        <p class="ss-sub">월 1만원 미만부터 10만원 이상까지, 예산에 맞는 가격대를 고르면 그 가격대의 대표 모델이 보입니다. 금액은 최저 월 구독료(VAT 포함) 기준이며, 약정·케어·선납·제휴카드에 따라 실제 월 납부액은 달라집니다.</p>
        <div data-ss="bands" data-n="8"></div>
    </section>

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


    <!-- 삼성스토어 시흥 구독 센터 안내 · 회사 소개 (2026-11-07 · 검색엔진이 읽는 본문 ) -->
    <section class="ss-sec ss-about" id="about">
        <h2>삼성스토어 시흥 구독 센터 안내</h2>
        <p><b>삼성스토어 구독센터</b>는 경기도 시흥시 대야동의 <b>삼성스토어 시흥</b>이 운영하는 삼성 가전 구독 안내 페이지입니다. 삼성 AI 구독클럽으로 구독할 수 있는 냉장고, 김치냉장고, 세탁기와 건조기, 비스포크 AI 콤보, 에어컨과 시스템에어컨, TV, 정수기, 공기청정기, 청소기, 식기세척기, 인덕션, 모니터, 갤럭시 탭과 갤럭시 북까지 1,000여 개 모델의 월 구독료를 품목별로 모았습니다. 매장에 오시기 전에 집에서 먼저 모델과 요금을 비교해 보시고, 궁금한 점은 전화나 온라인 상담으로 편하게 물어보세요.</p>
        <h3>삼성전자 공식 위촉 AI 구독 파트너 인증점</h3>
        <p>삼성스토어 시흥은 삼성전자로부터 위촉받은 <b>삼성 AI 구독 파트너 인증점</b>이자 <b>삼성전자 B2B AI 구독 파트너</b>입니다. 화면 맨 위 띠의 [위촉장 보기]에서 위촉장을 직접 확인하실 수 있습니다. 가정에서 쓰는 가전 구독은 물론, 사무실·매장·숙박시설처럼 여러 대가 필요한 사업자 구독까지 한 매장에서 상담해 드립니다.</p>
        <h3>구독센터에서 확인할 수 있는 것</h3>
        <ul>
            <li>모델별 약정 기간과 케어 유형(무상수리·방문케어 등)에 따른 월 구독료와 총구독료</li>
            <li>구독료를 제휴카드로 자동결제할 때 전월 이용실적 구간별 청구할인</li>
            <li>선납 비율에 따라 달라지는 월 구독료와 선납 할인</li>
            <li>적립 예정 멤버십 포인트와, 그 포인트를 구독료로 쓰는 방법</li>
            <li>냉장고·세탁기·TV처럼 여러 대를 함께 구독할 때의 묶음 월 납부 합계(다품목 계산기)</li>
            <li>같은 모델을 산 삼성닷컴 구매 고객 후기의 별점과 요약</li>
        </ul>
        <p>표시된 월 구독료는 부가세가 포함된 기본 요금입니다. 시기별 행사와 제휴카드·선납 조건을 맞추면 실제 납부액은 더 낮아질 수 있으므로, 최종 금액은 상담에서 고객님 조건에 맞춰 다시 계산해 드립니다.</p>
        <h3>상담은 이렇게 진행됩니다</h3>
        <ol>
            <li>구독센터에서 관심 있는 모델과 월 구독료를 확인합니다.</li>
            <li>[구독 상담 신청]을 남기시거나 031-8042-3166으로 전화하시면, 약정 기간·케어 주기·제휴카드·선납 조건을 맞춘 실제 월 납부액을 안내해 드립니다.</li>
            <li>여러 조건을 비교해 보신 뒤 결정하시면 됩니다. 상담 신청만으로 계약이 되지는 않습니다.</li>
            <li>계약 뒤에는 설치 환경을 확인하고 배송·설치 일정을 안내해 드립니다.</li>
        </ol>
        <p class="ss-about-gift">🎁 상담완료 시, 네이버 페이 1만원 증정 · 매장 방문 구매 완료 시 와인 증정</p>
        <h3>구독과 일시불, 어떻게 고를까요?</h3>
        <p>구독은 목돈 없이 매달 나누어 내면서 약정 기간 동안 무상수리나 방문케어를 함께 받는 방법입니다. 한 번에 결제할 여유가 있고 관리 서비스가 따로 필요 없다면 일시불이 더 나을 수도 있습니다. 구독센터의 모델 페이지에서는 시흥몰 일시불 가격과 구독 총액을 나란히 보여 드리므로, 두 방법의 차이를 숫자로 먼저 비교해 보신 뒤 상담에서 생활 방식에 맞는 쪽을 함께 정하시면 됩니다. 자세한 비교는 <a href="/data/gudok/g/subscribe-vs-buy.html">구독 vs 일시불 가이드</a>에서도 확인하실 수 있습니다.</p>
        <h3>혼수·입주·이사와 사업자 구독</h3>
        <p>신혼집 장만, 새 아파트 입주, 이사처럼 한 번에 여러 대가 필요할 때는 품목을 묶어 상담받으시면 다품목 혜택까지 함께 확인할 수 있습니다. 사업자 고객께는 사업자 전용 B2B 구독 혜택과 견적을 따로 안내해 드립니다.</p>
        <h3>회사 소개</h3>
        <p>삼성스토어 시흥은 <b>(주)삼성앤텍</b>이 운영하는 삼성전자 제품 판매 매장입니다. 매장에서 삼성 가전을 직접 보고 비교한 뒤 일시불 구매와 구독 가운데 고객님께 맞는 방법을 고르실 수 있도록 돕고, 온라인 쇼핑몰 samsungsh.co.kr 과 이 구독센터를 함께 운영하고 있습니다.</p>
        <dl class="ss-about-info">
            <dt>상호</dt><dd>(주)삼성앤텍 · 삼성스토어 시흥</dd>
            <dt>대표자</dt><dd>장성원</dd>
            <dt>주소</dt><dd>경기도 시흥시 서해안로1685번길 12 (대야동)</dd>
            <dt>구독 상담</dt><dd><a href="tel:031-8042-3166">031-8042-3166</a></dd>
            <dt>영업시간</dt><dd>매일 10:30 ~ 20:00</dd>
            <dt>사업자등록번호</dt><dd>791-85-02834</dd>
            <dt>통신판매업신고</dt><dd>제2024-경기시흥-2487호</dd>
        </dl>
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


def event_body():
    return '''    <header class="ss-head">
        <p class="ss-crumb"><a href="/main/html.php?htmid=%(dir)s/sub_home.html">구독센터</a> › 구독료 지원 이벤트</p>
        <h1>구독료 지원 이벤트</h1>
        <p class="ss-lead">행사 모델을 정해진 약정 기간으로 구독하면 구독료 몇 개월치에 해당하는 삼성전자 멤버십 포인트를 드립니다.
            지원 개월 수와 품목을 골라 행사 모델을 비교해 보세요.</p>
    </header>

    <section class="ss-sec">
        <div data-ss="event" data-n="12"></div>
    </section>

    <section class="ss-sec">
        <h2>구독료 지원 이벤트, 자주 묻는 질문</h2>
        %(faq)s
    </section>
''' % dict(dir=PAGE_DIR, faq=faq_html([
        ('구독료 지원은 어떻게 받나요?', '행사 모델을 행사에서 정한 약정 기간으로 계약하면, 지원 개월 수만큼의 월 구독료에 해당하는 금액을 삼성전자 멤버십 포인트로 적립해 드립니다.'),
        ('포인트는 어디에 쓸 수 있나요?', '적립된 삼성전자 멤버십 포인트는 구독료 결제에 나눠 쓰거나 삼성전자 제품 구매에 쓸 수 있습니다. 자세한 사용 방법은 상담 때 안내해 드립니다.'),
        ('행사 기간이 지나면 어떻게 되나요?', '행사 기간 안에 신청하고 행사 조건(배송 기한 등)을 지킨 계약에만 적용됩니다. 신청 전에 상담으로 적용 여부를 꼭 확인해 주세요.')]))


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
    t = '삼성스토어 구독센터 | 삼성 가전 구독 가격 비교 · 삼성 AI 구독클럽 · 삼성스토어 시흥'
    d = '삼성스토어 구독센터에서 냉장고·AI 콤보·에어컨·TV·정수기 등 1,000여 개 삼성 가전 구독 모델의 월 구독료와 제휴카드·선납 할인을 한 번에 비교하세요. 삼성전자 공식 위촉 AI 구독 파트너 삼성스토어 시흥 상담 031-8042-3166.'
    k = '삼성스토어 구독센터, 삼성스토어 구독, 삼성스토어 시흥 구독센터, 삼성 구독 가격, 삼성 가전 구독, 삼성 AI 구독클럽, 삼성 AI 콤보 구독, 가전 구독료 비교, 삼성스토어 시흥'
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
    files.append(('sub_event.html', '삼성 구독료 지원 이벤트 · 구독료 지원 행사 모델 | ' + BRAND,
                  '삼성 AI 구독클럽 구독료 지원 이벤트. 약정 기간에 따라 최대 6개월 구독료 상당 삼성전자 멤버십 포인트를 드리는 행사 모델을 품목별·월 구독료순으로 모았습니다.',
                  '삼성 구독료 지원, 삼성 구독 이벤트, 삼성 AI 구독 페스티벌, 구독료 지원 모델, 삼성 가전 구독 행사, 삼성 AI 구독클럽', event_body(), 'event', ''))
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
