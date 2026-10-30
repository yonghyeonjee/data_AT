# -*- coding: utf-8 -*-
"""구독센터 독립 페이지(웹FTP /data/gudok/) 생성기 — 2026-10-30 판

    python -I tools/gudok/build_gudok.py                 # 고도몰 업로드용 → <repo>/dist/gudok_godo/  (+ sitemap_gudok.xml)
    python -I tools/gudok/build_gudok.py --test          # 데이터센터 시험용 → <repo>/gudok/  (https://db.samsungat.co.kr/gudok/…)
    python -I tools/gudok/build_gudok.py --out <폴더> --site https://www.samsungsh.co.kr --dir /data/gudok/

만드는 것
  index.html                 구독센터 홈
  <품목>.html                 품목별 구독 가격 (18개)
  bundle.html                다품목 구독 계산기 (2026-10-30)
  card.html · guide.html     제휴카드 혜택 · 구독 안내
  find.html                  구독 상품 찾기
  view.html?model=모델명       모델별 구독 상품 페이지
  sitemap_gudok.xml          검색엔진 제출용 (구독센터 페이지 + 모델 페이지 전부)

빠르게 뜨도록 (2026-10-30)
  - version.js 한 번 받은 뒤 요금표(sub_index)·카탈로그(sub_catalog)·카드표·정책·화면 파일을 한꺼번에 써서 브라우저가 동시에 받는다 (예전엔 하나씩 차례로)
  - 상품명·사진은 배포본 sub_catalog.js 에서 읽어 RPC(1초 안팎)를 기다리지 않는다 (없으면 예전처럼 RPC)
  - 품목 페이지는 그 품목 요금표를, 상품 페이지는 계산기(sub_tab)를 미리 받아 둔다(preload)
고도몰 템플릿을 거치지 않는 html 이라 <head>·제목·설명을 파일이 직접 갖는다 (관리자 SEO 설정 불필요).
본문 글·FAQ 는 build_sub_pages.py 의 것을 쓰고, 목록·가격·메뉴는 데이터센터 sub_shop.js · sub_find.js · sub_view.js · sub_bundle.js 가 그린다.
"""
import argparse, datetime, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_sub_pages as B  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOP = 'https://www.samsungsh.co.kr'
ICON = 'https://gdadmin-samsungsh70.godomall.com/data/%EC%82%BC%EC%84%B1%EC%8A%A4%ED%86%A0%EC%96%B4-%EC%8B%9C%ED%9D%A5.ico'
CONSULT = SHOP + '/main/html.php?htmid=service/SamSungSubscription.html'   # 절대 주소 — 시험 서버(db.samsungat.co.kr)에서도 상담 신청은 쇼핑몰로
GOODS_URL = SHOP + '/goods/goods_view.php?goodsNo='
e = B.e

# 품목 페이지 → 요금표 품목 키 (sub_shop.js 의 PAGES 와 같다) — 그 품목 요금표를 미리 받기 위해
PAGE_CATS = {'ref': ['ref'], 'kimchi': ['kimchi'], 'aicombo': ['laundry'], 'washer': ['laundry'], 'dryer': ['laundry'], 'airdresser': ['laundry'],
             'aircon': ['aircon'], 'sysaircon': ['sysaircon'], 'tv': ['tv'], 'water': ['water'], 'airpurifier': ['airpurifier'], 'cleaner': ['cleaner'],
             'dishwasher': ['cooking'], 'induction': ['cooking'], 'monitor': ['monitor'], 'galaxy': ['tab', 'book'], 'audio': ['audio'], 'dehumid': ['dehumid']}
HOME_CATS = ['laundry', 'cooking']   # 홈은 세부유형으로 나뉘는 품목 요금표만 (sub_shop.js 와 같다)


class Site:
    def __init__(self, site, dir_, out):
        self.site, self.dir, self.out = site.rstrip('/'), dir_, out
        self.url = self.site + dir_
        self.links = dict(homeUrl=dir_ + 'index.html', catUrl=dir_, cardUrl=dir_ + 'card.html', guideUrl=dir_ + 'guide.html',
                          findUrl=dir_ + 'find.html', viewUrl=dir_ + 'view.html?model=', bundleUrl=dir_ + 'bundle.html', consultUrl=CONSULT)

    def remap(self, s):
        """build_sub_pages 본문의 고도몰 주소(htmid=subscribe/…)를 이 사이트 주소로"""
        s = s.replace(B.SITE + '/main/html.php?htmid=', '/main/html.php?htmid=')
        s = s.replace('/main/html.php?htmid=subscribe/sub_home.html', self.dir + 'index.html')
        s = re.sub(r'/main/html\.php\?htmid=subscribe/sub_c_(\w+)\.html', self.dir + r'\1.html', s)
        s = re.sub(r'/main/html\.php\?htmid=subscribe/sub_(card|guide|find)\.html', self.dir + r'\1.html', s)
        s = s.replace('/main/html.php?htmid=service/SamSungSubscription.html', CONSULT)
        assert 'htmid=subscribe' not in s, s[s.find('htmid=subscribe') - 80:][:200]
        return s

    def js_links(self):
        return ',\n        '.join("%s: '%s'" % kv for kv in self.links.items())

    def head(self, title, desc, keywords, canonical, extra_css=''):
        return '''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="icon" href="%(icon)s">
<title>%(title)s</title>
<meta name="description" content="%(desc)s">
<meta name="keywords" content="%(kw)s">
<link rel="canonical" href="%(url)s">
<meta property="og:type" content="website">
<meta property="og:site_name" content="삼성스토어 시흥">
<meta property="og:title" content="%(title)s">
<meta property="og:description" content="%(desc)s">
<meta property="og:url" content="%(url)s">
<link rel="preconnect" href="%(dc_origin)s" crossorigin>
<link rel="dns-prefetch" href="%(dc_origin)s">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css">
<style>
  body { margin:0; background:#fff; color:#111; font-family:'Pretendard','Noto Sans KR',sans-serif; -webkit-text-size-adjust:100%%; }
  .gd-top { border-bottom:1px solid #eee; background:#fff; }
  .gd-top .in { max-width:1080px; margin:0 auto; padding:12px 16px; display:flex; align-items:center; justify-content:space-between; gap:12px; font-size:14px; }
  .gd-top a { color:#111; text-decoration:none; }
  .gd-top .home { font-weight:800; }
  .gd-top .tel { color:#1d6fe8; font-weight:700; white-space:nowrap; }
  .gd-main { max-width:1080px; margin:0 auto; padding:24px 16px 64px; }
  .gd-foot { border-top:1px solid #eee; background:#fafafa; color:#777; font-size:13px; line-height:1.7; }
  .gd-foot .in { max-width:1080px; margin:0 auto; padding:20px 16px 32px; }
  .gd-foot a { color:#555; }
%(css)s</style>
</head>
<body>
<div class="gd-top"><div class="in">
    <a class="home" href="%(shop)s/">삼성스토어 시흥</a>
    <a class="tel" href="tel:%(tel)s">구독 상담 %(tel)s</a>
</div></div>
<main class="gd-main">
''' % dict(icon=ICON, title=e(title), desc=e(desc), kw=e(keywords), url=e(canonical), tel=B.TEL, css=extra_css, shop=SHOP,
           dc_origin=re.sub(r'^(https?://[^/]+).*$', r'\1', B.DC))

    def foot(self):
        return '''</main>
<footer class="gd-foot"><div class="in">
    삼성스토어 시흥 · 삼성전자 공식 판매점 · 구독 상담 <a href="tel:%(tel)s">%(tel)s</a><br>
    <a href="%(shop)s/">쇼핑몰 홈</a> · <a href="%(home)s">구독센터</a> · <a href="%(bundle)s">다품목 계산기</a> · <a href="%(consult)s">구독 상담 신청</a><br>
    표시된 월 구독료는 약정·케어·카드 조건에 따라 달라지며, 실제 납부액은 상담 때 안내해 드립니다.
</div></footer>
''' % dict(tel=B.TEL, home=self.dir + 'index.html', bundle=self.dir + 'bundle.html', consult=CONSULT, shop=SHOP)

    def loader(self, name, cfg_var, ready_var, page, key='', cats=None, preload=None, before_ui=''):
        """데이터센터 version.js → 요금표·카탈로그·카드표·정책·화면 파일을 한꺼번에 (동시 다운로드), 실패하면 /data/js/sub/ 예비 사본
           name: 화면 파일 이름(shop·find·view·bundle) / cats: 같이 받아 둘 요금표 품목 / preload: 미리 받아 둘 파일(실행은 화면 JS 가)
           before_ui: 요금표가 실행된 뒤·화면 JS 전에 끼울 JS (상품 페이지가 모델의 품목 요금표를 미리 받는 데 쓴다)"""
        extra = {
            'shop': """page: '%s', key: '%s',
        catalogApi: { url: '%s', key: '%s', timeout: 3000 },
        site: '%s',""" % (page, key, B.API, B.API_KEY, self.site),
            'find': """goodsApi: { url: '%s', key: '%s', timeout: 4000 },
        catalogApi: { url: '%s', key: '%s', timeout: 4000 },
        goodsVer: '',
        goodsUrl: '%s',
        pageSize: 24,""" % (B.API.replace('fn_sub_catalog', 'fn_sub_goods_map'), B.API_KEY, B.API, B.API_KEY, GOODS_URL),
            'view': """goodsApi: { url: '%s', key: '%s' },
        catalogApi: { url: '%s', key: '%s' },
        goodsUrl: '%s',
        site: '%s',
        extraPoints: [],""" % (B.API.replace('fn_sub_catalog', 'fn_sub_goods_map'), B.API_KEY, B.API, B.API_KEY, GOODS_URL, self.site),
            'bundle': """catalogApi: { url: '%s', key: '%s', timeout: 3000 },
        site: '%s',""" % (B.API, B.API_KEY, self.site),
        }[name]
        c = cfg_var
        boot = ['sub_index.js', 'sub_catalog.js', 'sub_cards.js', 'sub_policy.js'] + ['sub_plans_%s.js' % k for k in (cats or [])]
        pre = list(preload or [])
        css_line = ("h += '<link rel=\"stylesheet\" href=\"' + b + 'sub_%s.css?v=' + v + '\">';" % name) if name != 'shop' else ''
        css_local = ("<link rel=\"stylesheet\" href=\"' + b + 'sub_%s.css?v=' + v + '\">" % name) if name != 'shop' else ''
        return '''<script>
    var %(c)s = { ver: '%(ver)s',
        dcBase: '%(dc)s',
        dataBase: '/data/js/sub/',
        %(extra)s
        %(links)s,
        tel: '%(tel)s',
        defaultCard: '삼성카드'
    };
    /* 1) 판 번호 (5분 단위로 새로 읽는다) */
    if (%(c)s.dcBase) document.write('<script src="' + %(c)s.dcBase + 'version.js?t=' + Math.floor(Date.now() / 300000) + '"><\\/script>');
</script>
<script>
    /* 2) 요금표·카탈로그·카드표·정책을 한꺼번에 — 브라우저가 동시에 받고 쓴 순서대로 실행한다 (2026-10-30) */
    (function (c) {
        if (window.SUB_VER && c.dcBase) { c.localBase = c.dataBase; c.localVer = c.ver; c.dataBase = c.dcBase; c.ver = window.SUB_VER; }
        var b = c.dataBase, v = encodeURIComponent(c.ver), h = '';
        h += '<link rel="stylesheet" href="' + b + 'sub_shop.css?v=' + v + '">';
        %(css_line)s
        %(boot)s.forEach(function (f) { h += '<script src="' + b + f + '?v=' + v + '" charset="utf-8"><\\/script>'; });
        %(pre)s.forEach(function (f) { h += '<link rel="preload" as="' + (/\\.css$/.test(f) ? 'style' : 'script') + '" href="' + b + f + '?v=' + v + '"' + (/\\.js$/.test(f) ? ' crossorigin="anonymous"' : '') + '>'; });
        document.write(h);
    })(%(c)s);
</script>
%(before_ui)s<script>
    /* 3) 화면 파일 — 데이터센터를 못 읽었으면(요금표 없음) 고도몰 예비 사본(/data/js/sub/)으로 */
    (function (c) {
        if (!window.SUB_INDEX && c.localBase) { c.dataBase = c.localBase; c.ver = c.localVer; c.dcFailed = true;
            document.write('<script src="' + c.dataBase + 'sub_index.js?v=' + encodeURIComponent(c.ver) + '" charset="utf-8"><\\/script>'); }
        document.write('<script src="' + c.dataBase + 'sub_%(n)s.js?v=' + encodeURIComponent(c.ver) + '" charset="utf-8"><\\/script>');
    })(%(c)s);
</script>
<script>
    /* 4) 화면 파일도 못 받았으면 예비 사본 */
    (function (c) {
        if (window.%(r)s || !c.localBase || c.dcFailed) return;
        var b = c.localBase, v = encodeURIComponent(c.localVer);
        document.write('<link rel="stylesheet" href="' + b + 'sub_shop.css?v=' + v + '">%(css_local)s<script src="' + b + 'sub_%(n)s.js?v=' + v + '" charset="utf-8"><\\/script>');
    })(%(c)s);
</script>
''' % dict(c=c, r=ready_var, n=name, ver=B.VER, dc=B.DC, extra=extra, links=self.js_links(), tel=B.TEL,
           boot=json.dumps(boot), pre=json.dumps(pre), css_line=css_line, css_local=css_local, before_ui=before_ui)

    # ---------- 페이지 ----------
    def shop_page(self, fname, title, desc, kw, body, kind, key):
        cats = PAGE_CATS.get(key, []) if kind == 'cat' else HOME_CATS if kind == 'home' else []
        band = self.bundle_band() if kind in ('home', 'cat') else ''
        body = self.inject_home(body, self.persona_section(), band) if kind == 'home' else body + band
        return (self.head(title, desc, kw, self.url + fname) +
                '<div id="subShopRoot">\n    <div data-ss="nav"></div>\n' + self.remap(body) +
                '    <section class="ss-sec"><div data-ss="cta"></div></section>\n</div>\n' +
                self.foot() + self.loader('shop', 'SUB_SHOP_CONFIG', 'SUB_SHOP_READY', kind, key, cats=cats) + '</body>\n</html>\n')

    def bundle_band(self):
        return '''
    <section class="ss-sec"><div class="ss-bundle-band">
        <div><h2>여러 대를 한 번에 — 다품목 구독 계산기</h2>
        <p>냉장고 + 세탁기 + TV처럼 묶어서 약정·케어·선납·제휴카드까지 넣은 <b>월 납부 합계</b>를 바로 계산해 보세요. 모델 카드의 [+ 담기]로 담깁니다.</p></div>
        <a class="ss-btn" href="%(bundle)s" data-cta="bundle">묶음 월 구독료 계산하기</a>
    </div></section>
''' % dict(bundle=self.dir + 'bundle.html')

    @staticmethod
    def persona_section():
        return '''
    <section class="ss-sec">
        <h2>생활 유형별 추천 묶음</h2>
        <p class="ss-sub">신혼집·새 아파트 입주·이사처럼 한 번에 여러 대가 필요할 때, 대표 모델로 묶음 월 구독료를 먼저 보고 모델은 자유롭게 바꾸세요.</p>
        <div data-ss="persona"></div>
    </section>
'''

    @staticmethod
    def inject_home(body, persona, band):
        # 홈: "품목별 대표 구독 모델" 앞에 다품목 띠, 그 뒤에 생활 유형별 추천
        marker = '    <section class="ss-sec">\n        <h2>품목별 대표 구독 모델</h2>'
        assert marker in body, '홈 본문 구조가 바뀌었습니다'
        i = body.index(marker)
        j = body.index('    </section>', i) + len('    </section>\n')
        return body[:i] + band + body[i:j] + persona + body[j:]

    def find_page(self):
        css = '''  .sf-hero { text-align:center; margin:20px 0 28px; }
  .sf-hero .eyebrow { color:#1d6fe8; font-size:14px; font-weight:700; margin:0 0 8px; }
  .sf-hero h1 { font-size:28px; font-weight:800; line-height:1.4; margin:0 0 10px; }
  .sf-hero .desc { font-size:15px; color:#666; line-height:1.7; margin:0; }
  @media (max-width:640px) { .sf-hero h1 { font-size:22px; } .sf-hero .desc { font-size:13.5px; } }
'''
        return (self.head('삼성 가전 구독 상품 찾기 · 월 구독료 한눈에 | 삼성스토어 시흥',
                          '냉장고·김치냉장고·에어컨·TV·세탁기·정수기·청소기 등 삼성 AI 구독 가능 모델과 월 구독료를 한 번에 검색하세요. 삼성스토어 시흥 구독 전문 상담.',
                          '삼성 가전 구독, 삼성 구독료, AI 구독클럽, 냉장고 구독, 에어컨 구독, TV 구독, 세탁기 구독, 정수기 구독, 삼성스토어 시흥',
                          self.url + 'find.html', css) + '''<div class="sf-hero">
    <p class="eyebrow">삼성 AI 구독클럽 공식 파트너 · 삼성스토어 시흥</p>
    <h1>구독 상품 찾기</h1>
    <p class="desc">모델명이나 제품 종류로 검색하고, 월 구독료를 바로 비교하세요.<br>색상만 다른 모델은 하나로 묶어 보여 드리고, 마음에 드는 모델은 [+ 담기]로 묶음 계산기에 담을 수 있습니다.</p>
</div>
<div id="subFindRoot"><p class="sf-count">구독 상품을 불러오는 중…</p></div>
''' + self.foot() + self.loader('find', 'SUB_FIND_CONFIG', 'SUB_FIND_READY', 'find') + '</body>\n</html>\n')

    def view_page(self):
        # 모델마다 주소가 달라(view.html?model=…) canonical·제목은 sub_view.js 가 모델에 맞춰 바꾼다. 계산기(sub_tab)와 그 품목 요금표·특장점 요약은 미리 받아 둔다
        pre_js = '''<script>
    /* 상품 페이지: 주소의 모델로 품목을 알아내 그 요금표·계산기·특장점 요약을 미리 받아 둔다 (sub_view.js 가 곧 쓴다) */
    (function (c) {
        try {
            var m = decodeURIComponent((location.search.match(/[?&]model=([^&]*)/) || [])[1] || '').replace(/\\s+/g, '').toUpperCase();
            var en = window.SUB_INDEX && window.SUB_INDEX.m && window.SUB_INDEX.m[m];
            if (!en) return;
            var b = c.dataBase, v = encodeURIComponent(c.ver);
            document.write('<link rel="preload" as="script" crossorigin="anonymous" href="' + b + 'sub_plans_' + en[0] + '.js?v=' + v + '">' +
                '<link rel="preload" as="script" crossorigin="anonymous" href="' + b + 'sub_tab.js?v=' + v + '">' +
                '<link rel="preload" as="style" href="' + b + 'sub_tab.css?v=' + v + '">');
        } catch (e) {}
    })(SUB_VIEW_CONFIG);
</script>
'''
        return (self.head('삼성 가전 구독 상품 | 삼성스토어 시흥',
                          '삼성 AI 구독 모델의 약정·케어·제휴카드별 월 구독료를 확인하고 구독 상담을 신청하세요. 삼성스토어 시흥.',
                          '삼성 가전 구독, 삼성 구독료, AI 구독클럽, 삼성스토어 시흥', self.url + 'view.html') +
                '<div id="subViewRoot"><p class="sv-loading">구독 상품을 불러오는 중…</p></div>\n' +
                self.foot() + self.loader('view', 'SUB_VIEW_CONFIG', 'SUB_VIEW_READY', 'view', before_ui=pre_js) + '</body>\n</html>\n')

    def bundle_page(self):
        css = '''  .sb-hero { margin:16px 0 24px; }
  .sb-hero .eyebrow { color:#1d6fe8; font-size:14px; font-weight:700; margin:0 0 8px; }
  .sb-hero h1 { font-size:30px; font-weight:800; line-height:1.35; margin:0 0 10px; letter-spacing:-.02em; }
  .sb-hero .desc { font-size:15px; color:#666; line-height:1.7; margin:0; }
  .sb-steps { display:flex; flex-wrap:wrap; gap:8px; list-style:none; margin:14px 0 0; padding:0; font-size:13px; }
  .sb-steps li { padding:6px 12px; border-radius:16px; background:#f5f7fa; }
  .sb-steps li b { color:#1d6fe8; margin-right:4px; }
  .sb-faq { max-width:760px; margin:48px auto 0; }
  .sb-faq h2 { font-size:20px; margin:0 0 8px; }
  @media (max-width:640px) { .sb-hero h1 { font-size:23px; } .sb-hero .desc { font-size:13.5px; } }
'''
        faq = B.faq_html([
            ('여러 대를 같이 구독하면 더 싸지나요?', '월 구독료는 대마다 정해지지만, 자동납부 할인·선납 할인·제휴카드 청구할인을 모두 넣은 월 납부 합계를 한 번에 볼 수 있습니다. 동시 구독 행사나 사은품 같은 추가 혜택은 시기마다 달라 상담 때 안내해 드립니다.'),
            ('제휴카드 할인은 대마다 받을 수 있나요?', '카드사 기준에 따라 다릅니다. 이 계산기는 구독 건마다 할인이 적용되는 것으로 계산하며, 실적 구간·건수·기간 조건은 상담 때 카드사 기준으로 확인해 드립니다.'),
            ('담은 묶음은 어디에 저장되나요?', '이 브라우저에만 저장됩니다. [묶음 링크 복사]로 주소를 만들어 가족에게 보내거나 매장에 가져오시면 같은 조건으로 바로 열립니다.'),
            ('모델은 어떻게 바꾸나요?', '왼쪽 목록에서 다른 모델을 [+ 담기] 하고 기존 모델은 × 로 빼면 됩니다. 색상만 다른 모델은 하나로 묶어 보여 드리며, 상품 페이지에서 다른 색상을 고를 수 있습니다.'),
        ])
        return (self.head('삼성 가전 다품목 구독 계산기 · 여러 대 묶음 월 구독료 | 삼성스토어 시흥',
                          '냉장고·세탁기·TV·에어컨을 묶어 구독할 때 월 납부 합계를 바로 계산하세요. 약정·케어·선납·제휴카드 할인까지 넣은 다품목 구독 견적. 삼성스토어 시흥 구독센터.',
                          '삼성 다품목 구독, 가전 묶음 구독, 삼성 구독 계산기, 신혼 가전 구독, 입주 가전 구독, 삼성 AI 구독클럽, 삼성스토어 시흥',
                          self.url + 'bundle.html', css) + '''<div class="sb-hero">
    <p class="eyebrow">삼성 AI 구독클럽 공식 파트너 · 삼성스토어 시흥</p>
    <h1>다품목 구독 계산기</h1>
    <p class="desc">냉장고 + 세탁기 + TV처럼 여러 대를 묶어 구독할 때의 <b>월 납부 합계</b>를 계산합니다.
        대마다 약정·케어·선납을 고르고 제휴카드를 넣으면 한 대씩 본 금액과 똑같은 기준으로 합계가 나옵니다.</p>
    <ul class="sb-steps"><li><b>1</b>상품 담기</li><li><b>2</b>약정 · 케어 · 선납 고르기</li><li><b>3</b>제휴카드 넣기</li><li><b>4</b>묶음 월 납부액 확인 · 상담</li></ul>
</div>
<div id="subBundleRoot"><p class="sb-empty">계산기를 불러오는 중…</p></div>
<section class="sb-faq"><h2>다품목 구독, 자주 묻는 질문</h2>
''' + faq + '''
</section>
''' + self.foot() + self.loader('bundle', 'SUB_BUNDLE_CONFIG', 'SUB_BUNDLE_READY', 'bundle', preload=['sub_tab.js']) + '</body>\n</html>\n')

    # ---------- 전체 ----------
    def build(self, index_js):
        os.makedirs(self.out, exist_ok=True)
        pages = []   # (파일, 내용, (우선순위, 주기))
        for fname, t, d, k, body, kind, key in B.page_list():
            new = 'index.html' if fname == 'sub_home.html' else re.sub(r'^sub_(c_)?', '', fname)
            pri = {'home': ('1.0', 'daily'), 'cat': ('0.9', 'daily'), 'card': ('0.7', 'weekly'), 'guide': ('0.6', 'monthly')}[kind]
            pages.append((new, self.shop_page(new, t, d, k, body, kind, key), pri))
        pages.append(('bundle.html', self.bundle_page(), ('0.8', 'weekly')))
        pages.append(('find.html', self.find_page(), ('0.6', 'daily')))
        pages.append(('view.html', self.view_page(), None))
        for fname, html_, _ in pages:
            assert '{' + '=' not in html_ and '{ #' not in html_, fname   # 고도몰 템플릿 문법이 남지 않게
            with open(os.path.join(self.out, fname), 'w', encoding='utf-8', newline='\n') as f:
                f.write(html_)

        today = datetime.date.today().isoformat()
        sm = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
        for fname, _, pri in pages:
            if pri:
                sm.append('<url><loc>%s</loc><lastmod>%s</lastmod><changefreq>%s</changefreq><priority>%s</priority></url>' % (e(self.url + fname), today, pri[1], pri[0]))
        n_models = 0
        if index_js and os.path.exists(index_js):
            src = open(index_js, encoding='utf-8').read()
            idx = json.loads(re.search(r'=\s*(\{.*\})\s*;?\s*$', src, re.S).group(1))
            for model in sorted(idx['m']):
                sm.append('<url><loc>%s</loc><lastmod>%s</lastmod><changefreq>weekly</changefreq><priority>0.5</priority></url>' % (e(self.url + 'view.html?model=' + model), today))
                n_models += 1
        sm.append('</urlset>')
        with open(os.path.join(self.out, 'sitemap_gudok.xml'), 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(sm) + '\n')
        sys.stdout.buffer.write(('%d pages → %s\nsitemap %d urls (모델 %d) · %s\n' % (len(pages), self.out, len(sm) - 3, n_models, os.path.join(self.out, 'sitemap_gudok.xml'))).encode('utf-8'))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--test', action='store_true', help='데이터센터 시험용 (db.samsungat.co.kr/gudok/)')
    ap.add_argument('--out'); ap.add_argument('--site'); ap.add_argument('--dir')
    ap.add_argument('--index', default=os.path.join(REPO, 'sdp', 'sub', 'sub_index.js'))
    ap.add_argument('--dc', help='데이터센터 주소 바꿔 끼우기 (PC 에서 시험할 때 http://localhost:8765/sdp/sub/)')
    a = ap.parse_args()
    if a.dc: B.DC = a.dc
    if a.test:
        s = Site(a.site or 'https://db.samsungat.co.kr', a.dir or '/gudok/', a.out or os.path.join(REPO, 'gudok'))
    else:
        s = Site(a.site or SHOP, a.dir or '/data/gudok/', a.out or os.path.join(REPO, 'dist', 'gudok_godo'))
    s.build(a.index)
