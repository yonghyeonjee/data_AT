# -*- coding: utf-8 -*-
"""구독센터 모델별 정적 페이지 (2026-11-04) — /data/gudok/m/<모델>.html

왜: view.html?model=… 은 원본 HTML 이 모델마다 같아(제목·canonical·본문 "불러오는 중…")
    네이버(Yeti)·구글이 991개 모델을 한 페이지로 본다. 모델마다 정적 파일을 미리 만들어
    원본 HTML 에 제목·설명(가격)·대표 주소·공유 이미지·상품 구조화 데이터·약정별 월 구독료·관련 모델 링크를 넣는다.
    계산기·특장점·추천은 지금처럼 sub_view.js 가 그 위에 그린다 (모델은 SUB_VIEW_CONFIG.model).

build_gudok.py 가 부른다. 같은 규칙을 쓰는 JS: sub_view.js (이름·경로) · sub_shop.js (SUB_FAMILY)
"""
import json, os, re

# sub_view.js 의 SEG_LABEL_RULES 와 같다
SEG_LABEL_RULES = [
    (r'^Entry_-(\d+)_더무빙$', r'\1형 이하 · 더 무빙스타일'), (r' \+ 4K_-(\d+)$', r' + 보조 TV \1형 이하'), (r'\(2인\)', '(2인 설치)'),
    (r'^Premium_4K_', '프리미엄 4K '), (r'^Premium_', '프리미엄 '), (r'^Entry_', ''), (r'^일반모니터 ', '일반 '),
    (r'(\d+)이하', r'\1형 이하'), (r'(\d+)이상 \((\d+)-(\d+)\)', r'\2~\3형'),
    (r'(^|[ (])(\d{2,3})-(\d{2,3})(?=$|[ )(])', r'\1\2~\3형'), (r'(^|[ _])-(\d{2,3})$', r'\1\2형 이하'),
    (r'_M1/M7$', ' · 스마트 M1/M7'), (r'_OLED$', ' · OLED'), (r'^SD Sound Device ', '사운드바 '),
    (r'^AI로봇청소기_26신제품', 'AI 로봇청소기 2026'), (r'_', ' '),
]
CAT_ICON = {'ref': '🧊', 'kimchi': '🥬', 'water': '💧', 'tv': '📺', 'monitor': '🖥️', 'audio': '🔊', 'laundry': '👕', 'cleaner': '🧹',
            'aircon': '❄️', 'sysaircon': '🌬️', 'cooking': '🍳', 'airpurifier': '🍃', 'dehumid': '💨', 'tab': '📱', 'book': '💻'}
# sub_view.js 의 CENTER 와 같다 (품목 페이지)
CENTER = [('aicombo', 'AI 콤보', 'laundry', r'콤보'), ('washer', '세탁기', 'laundry', r'^(드럼|전자동|세탁기\+건조기)'),
          ('dryer', '건조기', 'laundry', r'^건조기'), ('airdresser', '에어드레서', 'laundry', r'벌식'),
          ('dishwasher', '식기세척기', 'cooking', r'인용|카운터탑'), ('induction', '인덕션·후드', 'cooking', r'전기레인지|인덕션|후드'),
          ('galaxy', '갤럭시 탭·북', 'tab', None), ('galaxy', '갤럭시 탭·북', 'book', None)]


def load_js_obj(path):
    src = open(path, encoding='utf-8').read()
    return json.loads(re.search(r'=\s*(\{.*\})\s*;?\s*$', src, re.S).group(1))


def seg_label(seg):
    s = str(seg or '')
    for a, b in SEG_LABEL_RULES:
        s = re.sub(a, b, s)
    return re.sub(r'\s+', ' ', s).strip()


def family_key(m):
    x = re.match(r'^(.*\d)([A-Z]+?)(N\d)?$', str(m or '').upper())
    if not x:
        return m
    return x.group(1) + (x.group(2)[:-1] if len(x.group(2)) >= 3 else '') + (x.group(3) or '')


def clean_name(s):
    s = re.sub(r'\s*\*+\s*$', '', str(s or ''))
    s = re.sub(r'\s*(삼성본사직배송|본사직배송)\s*', ' ', s)
    return re.sub(r'\s{2,}', ' ', s).strip()


def fmt(n):
    return '{:,}'.format(int(round(n)))


class Models:
    """요금표·카탈로그를 읽어 모델마다 이름·사진·세부유형·약정별 요금을 낸다"""

    def __init__(self, sub_dir):
        self.idx = load_js_obj(os.path.join(sub_dir, 'sub_index.js'))
        self.cats = self.idx.get('cats', {})
        cat_path = os.path.join(sub_dir, 'sub_catalog.js')
        self.catalog = load_js_obj(cat_path) if os.path.exists(cat_path) else {'m': {}}
        self.plans = {}
        for c in set(v[0] for v in self.idx['m'].values()):
            p = os.path.join(sub_dir, 'sub_plans_%s.js' % c)
            if os.path.exists(p):
                self.plans[c] = load_js_obj(p)

    def models(self):
        return sorted(self.idx['m'])

    def info(self, m):
        ent = self.idx['m'][m]
        cat, low = ent[0], ent[1]
        plan = self.plans.get(cat, {}).get(m) or {}
        seg = plan.get('s', '')
        c = self.catalog['m'].get(m)
        name = clean_name(c[1]) if c and c[1] else ''
        img = ''
        if c and c[2]:
            img = c[2] if re.match(r'^https?:', c[2]) else (self.catalog.get('img') or '') + c[2]
        return dict(model=m, cat=cat, cat_name=self.cats.get(cat, ''), min=low, seg=seg, plan=plan.get('p', []),
                    name=name, img=img, img_rep=bool(c and re.match(r'^[sgc]$', c[4] or '')),
                    goods=(c[0] if c and c[0] and not (len(c) > 5 and c[5]) else 0), lump=(c[3] if c and len(c) > 3 else 0),
                    sub_only=bool(c and len(c) > 5 and c[5]))

    @staticmethod
    def center_page(i):
        for key, nm, cat, rx in CENTER:
            if cat == i['cat'] and (rx is None or (i['seg'] and re.search(rx, i['seg']))):
                return key, nm
        if i['cat'] in ('laundry', 'cooking'):
            return None
        return i['cat'], i['cat_name']

    @staticmethod
    def model_hint(i):
        m, cat, seg = i['model'], i['cat'], i['seg']
        x = re.match(r'^(KMR|KQ|KU)(\d{2,3})([A-Z]+)', m)
        if cat == 'tv' and x:
            p, size, rest = x.groups()
            line = 'Micro RGB' if p == 'KMR' else (('Mini LED' if rest.startswith('MH') else '더 무빙스타일' if rest.startswith('LS') else 'UHD') if p == 'KU' else
                                                  'Neo QLED' if rest.startswith('QN') else 'OLED' if rest.startswith('S') else 'QLED')
            return '삼성 %s %s형 TV%s' % (line, size, ' 세트' if re.search(r'보조|\+', seg) else '')
        x = re.match(r'^L[SC](\d{2})', m)
        if cat == 'monitor' and x:
            return '삼성 %s형 모니터' % x.group(1)
        return ''

    def product_name(self, i):
        if i['name']:
            return i['name']
        h = self.model_hint(i)
        if h:
            return h
        cp = self.center_page(i)
        kind = cp[1] if cp and cp[0] != 'galaxy' else i['cat_name']
        s = re.sub(r'\s*공통$', '', seg_label(i['seg']))
        if s and kind in s:
            kind = ''
        return re.sub(r'\s+', ' ', '삼성 ' + kind + (' ' + s if s else '')).strip()

    def year_rows(self, i):
        """약정별 가장 낮은 월 구독료 (케어 유형 중) — [(년, 월, 케어)]"""
        best = {}
        for p in i['plan']:
            y, care, monthly = p[0], p[1], p[3]
            if y not in best or monthly < best[y][0]:
                best[y] = (monthly, care)
        return [(y, best[y][0], best[y][1]) for y in sorted(best)]

    def variants(self, i):
        fk = family_key(i['model'])
        P = self.plans.get(i['cat'], {})
        out = [m for m, v in self.idx['m'].items() if m != i['model'] and v[0] == i['cat'] and family_key(m) == fk and
               (m not in P or not i['seg'] or P[m].get('s') == i['seg'])]
        return sorted(out, key=lambda m: self.idx['m'][m][1])

    def siblings(self, i, n=8):
        P = self.plans.get(i['cat'], {})
        fk = family_key(i['model'])
        out = [m for m in P if m != i['model'] and m in self.idx['m'] and (not i['seg'] or P[m].get('s') == i['seg']) and family_key(m) != fk]
        return sorted(out, key=lambda m: self.idx['m'][m][1])[:n]


def e(s):
    return (str(s).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;'))


def page_meta(M, i):
    title = M.product_name(i)
    full = '%s 구독 가격 월 %s원~ (%s) | 삼성스토어 시흥 구독센터' % (title, fmt(i['min']), i['model'])
    desc = '%s (%s) 삼성 AI 구독 월 %s원부터. 약정 기간·방문케어 주기·선납 할인·제휴카드 할인별 월 구독료를 바로 계산하고 구독 상담을 신청하세요.' % (title, i['model'], fmt(i['min']))
    kw = ', '.join(x for x in [i['model'], title.replace('삼성 ', '') + ' 구독', '삼성 ' + i['cat_name'] + ' 구독', i['model'] + ' 구독', '삼성 AI 구독클럽', '삼성스토어 시흥'] if x)
    return title, full, desc, kw


def json_ld(M, i, title, canon, site, links):
    cp = M.center_page(i)
    crumbs = [{'@type': 'ListItem', 'position': 1, 'name': '구독센터', 'item': site + links['homeUrl']}]
    if cp:
        crumbs.append({'@type': 'ListItem', 'position': 2, 'name': cp[1] + ' 구독', 'item': site + links['catUrl'] + cp[0] + '.html'})
    crumbs.append({'@type': 'ListItem', 'position': len(crumbs) + 1, 'name': title, 'item': canon})
    years = M.year_rows(i)
    prod = {'@context': 'https://schema.org', '@type': 'Product', 'name': title, 'sku': i['model'], 'mpn': i['model'], 'url': canon,
            'brand': {'@type': 'Brand', 'name': 'Samsung'}, 'category': i['cat_name'] + (' > ' + seg_label(i['seg']) if i['seg'] else ''),
            'description': '%s 삼성 AI 구독 · 월 %s원부터 (약정·케어·제휴카드 조건에 따라 달라집니다)' % (title, fmt(i['min'])),
            'offers': {'@type': 'Offer', 'url': canon, 'priceCurrency': 'KRW', 'price': i['min'], 'availability': 'https://schema.org/InStock',
                       'seller': {'@type': 'Organization', 'name': '삼성스토어 시흥'},
                       'priceSpecification': {'@type': 'UnitPriceSpecification', 'price': i['min'], 'priceCurrency': 'KRW',
                                              'referenceQuantity': {'@type': 'QuantitativeValue', 'value': 1, 'unitCode': 'MON'},
                                              **({'billingDuration': max(y for y, _, _ in years) * 12} if years else {})}}}
    if i['img']:
        prod['image'] = i['img']
    data = [prod, {'@context': 'https://schema.org', '@type': 'BreadcrumbList', 'itemListElement': crumbs}]
    return '<script type="application/ld+json">%s</script>\n' % json.dumps(data, ensure_ascii=False).replace('</', '<\\/')


def body_html(M, i, title, links, static_href):
    """sub_view.js 가 그리기 전(또는 JS 없이) 보이는 본문 — 같은 클래스(sv-*)를 써서 바뀔 때 덜 튄다"""
    cp = M.center_page(i)
    find = links['findUrl']
    crumb = '<nav class="sv-crumb"><a href="%s">구독센터</a> › ' % e(links['homeUrl'])
    crumb += ('<a href="%s">%s 구독</a>' % (e(links['catUrl'] + cp[0] + '.html'), e(cp[1])) if cp else
              '<a href="%s">%s</a>' % (e(find + '?cat=' + i['cat']), e(i['cat_name'])))
    if i['seg']:
        crumb += ' › <span>%s</span>' % e(seg_label(i['seg']))
    crumb += '</nav>'
    img = ('<img src="%s" alt="%s">' % (e(i['img']), e(title))) if i['img'] else '<span class="sv-icon">%s</span>' % CAT_ICON.get(i['cat'], '📦')
    head = ('<div class="sv-head"><div class="sv-img">%s</div><div class="sv-info">'
            '<p class="sv-cat">%s%s</p><h1 class="sv-title">%s</h1><p class="sv-model">모델명 <b>%s</b></p>'
            '<p class="sv-price"><small>구독 월</small> %s<small>원~</small></p>'
            '<p class="sv-badge">삼성전자 AI 구독클럽 공식 파트너 · 무상수리 포함</p></div></div>') % (
        img, e(i['cat_name']), (' · ' + e(seg_label(i['seg']))) if i['seg'] else '', e(title), e(i['model']), fmt(i['min']))
    years = M.year_rows(i)
    table = ''
    if years:
        table = ('<section class="sv-static"><h2 class="sv-h2">약정 기간별 월 구독료</h2><table class="sv-static-t"><thead><tr><th>약정</th><th>월 구독료(부터)</th><th>케어</th></tr></thead><tbody>' +
                 ''.join('<tr><td>%d년 (%d개월)</td><td>월 %s원</td><td>%s</td></tr>' % (y, y * 12, fmt(mo), e(care)) for y, mo, care in years) +
                 '</tbody></table><p class="sv-note">자동납부·선납·제휴카드 청구할인을 넣은 실제 월 납부액은 아래 계산기에서 바로 확인할 수 있습니다. '
                 '상담 완료 시 사은품 증정 · 매장 방문 구매 완료 시 와인 증정.</p></section>')
    rel = ''
    var = M.variants(i)
    if var:
        rel += '<section class="sv-static"><h2 class="sv-h2">같은 모델, 다른 색상</h2><ul class="sv-more">' + ''.join(
            '<li><a href="%s"><b>%s</b><span>월 %s원~</span></a></li>' % (e(static_href(m)), e(m), fmt(M.idx['m'][m][1])) for m in var) + '</ul></section>'
    sib = M.siblings(i)
    if sib:
        rel += '<section class="sv-static"><h2 class="sv-h2">같은 유형의 다른 구독 모델</h2><ul class="sv-more">' + ''.join(
            '<li><a href="%s"><b>%s</b><span>월 %s원~</span></a></li>' % (e(static_href(m)), e(m), fmt(M.idx['m'][m][1])) for m in sib) + '</ul>' + \
            ('<p class="sv-more-all"><a href="%s">%s 구독 모델 전체 보기 →</a></p>' % (e(links['catUrl'] + cp[0] + '.html'), e(cp[1])) if cp else '') + '</section>'
    return crumb + head + table + rel


def static_js(models, path):
    """모델별 정적 페이지가 있는 모델 목록 — 구독센터 JS 가 링크를 정적 주소로 바꿀 때 쓴다 (없는 모델은 view.html?model=)"""
    s = '/* 구독센터 모델별 정적 페이지 목록 (tools/gudok/build_gudok.py · 직접 고치지 마세요) */\nwindow.SUB_STATIC={"m":"%s"};\n' % ' '.join(models)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(s)


# ---------- 품목·홈 페이지 원본에 넣는 목록·구조화 데이터 (2026-11-04 · 2순위·3순위) ----------
# sub_shop.js 의 PAGES 세부유형 규칙과 같다
PAGE_SEG = {'aicombo': r'콤보', 'washer': r'^(드럼|전자동|세탁기\+건조기)', 'dryer': r'^건조기', 'airdresser': r'벌식',
            'dishwasher': r'인용|카운터탑', 'induction': r'전기레인지|인덕션|후드'}
OG_IMG = 'https://cdn-saas-web-116-108.cdn-nhncommerce.com/samsungsh70_godomall_com/data/skin/front/designbook_air_RES/img/banner/slider_4269136848/1c46bcff18e426d9029809f031d477f8_66974.png'   # 시흥몰 구독센터 배너 (공유 미리보기)
STORE = {'name': '삼성스토어 시흥', 'legal': '(주)삼성앤텍', 'tel': '031-8042-3166',
         'street': '서해안로1685번길 12', 'locality': '시흥시', 'region': '경기도', 'country': 'KR',
         'hours': ['Mo-Su 10:30-20:00']}


def cat_models(M, key, cats):
    rx = PAGE_SEG.get(key)
    out = []
    for m, v in M.idx['m'].items():
        if v[0] not in cats:
            continue
        seg = (M.plans.get(v[0], {}).get(m) or {}).get('s', '')
        if rx and not (seg and re.search(rx, seg)):
            continue
        out.append(m)
    return sorted(out, key=lambda m: (M.idx['m'][m][1], m))


def cat_list_html(M, models, href):
    """sub_shop.js 가 목록을 그리기 전(또는 JS 없이) 보이는 모델 목록 — 색상만 다른 모델은 한 줄로"""
    fam, order = {}, []
    for m in models:
        k = family_key(m)
        if k not in fam:
            fam[k] = []; order.append(k)
        fam[k].append(m)
    li = []
    for k in order:
        ms = fam[k]; i = M.info(ms[0]); name = M.product_name(i)
        li.append('<li><a href="%s">%s</a> <span>%s · 월 %s원~</span>%s</li>' % (
            e(href(ms[0])), e(name), e(ms[0]), fmt(i['min']),
            (' <small>다른 색상 ' + ' · '.join('<a href="%s">%s</a>' % (e(href(x)), e(x)) for x in ms[1:]) + '</small>') if len(ms) > 1 else ''))
    return '<ul class="ss-static-list">' + ''.join(li) + '</ul>'


def faq_items(body):
    out = []
    for q, a in re.findall(r'<dt>(.*?)</dt>\s*<dd>(.*?)</dd>', body, re.S):
        strip = lambda s: re.sub(r'<[^>]+>', '', s).replace('&amp;', '&').replace('&quot;', '"').replace('&#x27;', "'").replace('&lt;', '<').replace('&gt;', '>').strip()
        out.append({'@type': 'Question', 'name': strip(q), 'acceptedAnswer': {'@type': 'Answer', 'text': strip(a)}})
    return out


def ld_tag(objs):
    """정적 구조화 데이터 — data-ss-static 에 종류를 적어 sub_shop.js 가 같은 종류를 또 넣지 않게 한다"""
    types = ' '.join(o['@type'] for o in objs)
    return '<script type="application/ld+json" data-ss-static="%s">%s</script>\n' % (types, json.dumps(objs if len(objs) > 1 else objs[0], ensure_ascii=False).replace('</', '<\\/'))


def store_ld(site, home):
    s = STORE
    return {'@context': 'https://schema.org', '@type': 'ElectronicsStore', 'name': s['name'], 'legalName': s['legal'], 'url': site + home,
            'telephone': s['tel'], 'image': 'https://db.samsungat.co.kr/sdp/sub/img/partner_cert_2026.jpg',
            'address': {'@type': 'PostalAddress', 'streetAddress': s['street'], 'addressLocality': s['locality'], 'addressRegion': s['region'], 'addressCountry': s['country']},
            'openingHours': s['hours'], 'brand': {'@type': 'Brand', 'name': 'Samsung'},
            'description': '삼성전자 B2B AI 구독 파트너 · 삼성 AI 구독클럽 공식 파트너 매장. 가정·사업자 가전 구독 상담.'}
