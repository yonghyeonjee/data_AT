# -*- coding: utf-8 -*-
"""구독센터 질문형 가이드 글 (2026-11-04 · 4순위) — /data/gudok/g/<주제>.html

경쟁사(빌리고 인포툰·케어솔루션 블로그)처럼 손님이 검색하는 질문 하나에 글 하나.
숫자(카드 할인·선납·다품목·자동납부)는 데이터센터 정책 파일(sub_policy.js · sub_cards.js)에서 읽어
정책이 바뀌면 다시 빌드할 때 같이 바뀐다. 사은품은 구체 품목을 적지 않는다(상담 완료 시 사은품 · 방문 구매 완료 시 와인).
"""
import json, os, re
import model_pages as MP

e = MP.e
fmt = MP.fmt


def pct(x):
    v = round(float(x) * 100, 1)
    return ('%d' % v if v == int(v) else '%s' % v) + '%'


def tier_key(t):
    m = re.match(r'(\d+)', t)
    return int(m.group(1)) if m else 0


class Guides:
    def __init__(self, sub_dir):
        self.pol = MP.load_js_obj(os.path.join(sub_dir, 'sub_policy.js'))
        self.cards = MP.load_js_obj(os.path.join(sub_dir, 'sub_cards.js'))

    # ---------- 표 ----------
    def card_table(self):
        rows = []
        for name, c in self.cards.items():
            t, base, mm = c.get('t') or {}, c.get('base') or {}, c.get('minMonthly') or {}
            for tier in sorted(t, key=tier_key):
                b = base.get(tier, t[tier]); cb = t[tier] - b
                rows.append('<tr><td>%s</td><td>전월 %s</td><td>월 %s원%s</td><td>%s</td></tr>' % (
                    e(name), e(tier), fmt(t[tier]), (' <small>(청구할인 %s원 + 캐시백 %s원)</small>' % (fmt(b), fmt(cb))) if cb > 0 else '',
                    ('월 구독료 %s원 이상' % fmt(mm[tier])) if mm.get(tier) else '-'))
        return ('<div class="ss-table-wrap"><table class="ss-table"><thead><tr><th>카드</th><th>실적 구간</th><th>월 혜택</th><th>조건</th></tr></thead><tbody>' +
                ''.join(rows) + '</tbody></table></div>')

    def prepay_table(self):
        pp = self.pol.get('prepay') or {}
        rates = pp.get('rates') or {}
        rows = ''.join('<tr><td>제품 금액의 %s</td><td>추가 할인 %s</td></tr>' % (pct(k), pct(v)) for k, v in sorted(rates.items(), key=lambda kv: float(kv[0])))
        mx = pp.get('maxByCat') or {}
        cats = ' · '.join('%s %s' % (e(k), pct(v)) for k, v in sorted(mx.items(), key=lambda kv: (-kv[1], kv[0])))
        return ('<div class="ss-table-wrap"><table class="ss-table"><thead><tr><th>선납 비율</th><th>선납 할인</th></tr></thead><tbody>' + rows +
                '</tbody></table></div>' + ('<p class="ss-note">품목별 최대 선납 비율: %s</p>' % cats if cats else ''))

    def multi_text(self):
        mu = self.pol.get('multi') or {}
        r = mu.get('rates') or {}
        yrs = ' · '.join('%s년 %s' % (k, pct(v)) for k, v in sorted(r.items(), key=lambda kv: int(kv[0])))
        period = ('%s ~ %s' % (mu.get('from', ''), mu.get('to', ''))) if mu.get('from') else ''
        return yrs, period, mu

    def package_table(self):
        b = self.pol.get('bundle') or {}
        tiers = b.get('tiers') or {}
        if not tiers:
            return ''
        return ('<div class="ss-table-wrap"><table class="ss-table"><thead><tr><th>함께 구독한 품목 수</th><th>스마트 패키지 포인트</th></tr></thead><tbody>' +
                ''.join('<tr><td>%s품목</td><td>%sP</td></tr>' % (k, fmt(v)) for k, v in sorted(tiers.items(), key=lambda kv: int(kv[0]))) +
                '</tbody></table></div><p class="ss-note">%s%s</p>' % (e(b.get('text', '')), (' · 기간 %s ~ %s' % (b.get('from'), b.get('to'))) if b.get('from') else ''))

    # ---------- 글 ----------
    def articles(self, links):
        consult = links['consultUrl']
        cat = lambda k, n: '<a href="%s%s.html">%s 구독 가격</a>' % (links['catUrl'], k, n)
        auto = pct((self.pol.get('autopay') or {}).get('rate', 0.05))
        yrs, mperiod, mu = self.multi_text()
        gift = '상담 완료 시 사은품 증정 · 매장 방문 구매 완료 시 와인 증정'
        A = []
        A.append(dict(slug='subscribe-vs-buy', title='삼성 가전, 구독이 나을까 일시불이 나을까?',
            desc='삼성 AI 구독과 일시불 구매를 총 비용·할인·포인트·무상수리 기간으로 비교했습니다. 모델별 실제 비교표로 바로 확인하세요.',
            kw='삼성 구독 일시불 비교, 가전 구독 장단점, 삼성 AI 구독클럽 이득, 구독 vs 구매',
            answer='목돈 없이 시작하고 약정 기간 내내 무상수리를 받으려면 구독, 가장 적은 총액만 보면 제휴카드·선납·포인트를 넣어 계산해 봐야 합니다. 조건을 다 넣으면 구독 총 부담이 일시불보다 낮아지는 모델도 많습니다.',
            body='''<h2>구독 총 부담은 이렇게 계산해요</h2>
<ol><li><b>총 구독금액</b> = 월 구독료 × 약정 개월 수</li>
<li><b>자동납부 할인</b> — 구독료 %(auto)s</li>
<li><b>선납 할인</b> — 신청할 때 일부를 먼저 내면 추가 할인 (<a href="%(g)sprepay.html">선납 할인 안내</a>)</li>
<li><b>제휴카드 청구할인</b> — 전월 실적에 따라 매월 할인 (<a href="%(g)scard-discount.html">카드별 할인표</a>)</li>
<li><b>멤버십 포인트</b> — 적립 예정 포인트를 구독료로 쓰거나 따로 받아 현금처럼 사용 (<a href="%(g)spoints.html">포인트 사용법</a>)</li></ol>
<p>이렇게 뺀 금액이 <b>실제 부담</b>이고, 일시불 판매가와 나란히 놓고 보면 됩니다. 구독센터 모델 페이지의 <b>「일시불 vs 구독 한눈에」</b> 표가 이 계산을 모델마다 자동으로 해 줍니다.</p>
<h2>구독이 유리한 경우</h2>
<ul><li>목돈을 한 번에 쓰기 어렵거나 여러 대를 한꺼번에 바꿀 때 (혼수·입주·이사)</li>
<li>약정 기간 내내 무상수리·정기 케어를 받고 싶을 때</li>
<li>제휴카드 실적을 이미 채우고 있어 청구할인을 바로 받을 수 있을 때</li></ul>
<h2>일시불이 유리한 경우</h2>
<ul><li>제휴카드를 쓰지 않고 선납·포인트 혜택도 받지 않을 때</li>
<li>약정 기간보다 짧게 쓰고 바꿀 계획일 때 (중도 해지는 위약금이 생길 수 있습니다)</li></ul>
<p>정확한 금액은 모델·약정·케어·카드에 따라 달라집니다. %(gift)s.</p>''' % dict(auto=auto, g=links['guideDir'], gift=gift),
            faq=[('구독이 일시불보다 항상 싼가요?', '아닙니다. 제휴카드 청구할인·선납 할인·멤버십 포인트를 받을 때 일시불보다 낮아지는 경우가 많고, 혜택을 받지 않으면 일시불이 더 낮을 수 있습니다. 모델 페이지의 비교표에서 조건별로 확인할 수 있습니다.'),
                 ('구독하면 무상수리는 얼마나 되나요?', '구독 약정 기간 동안 무상수리를 받습니다. 일시불 구매는 제품별 기본 보증 기간이 적용됩니다.')],
            links=[cat('aicombo', 'AI 콤보'), cat('tv', 'TV'), cat('ref', '냉장고')]))
        A.append(dict(slug='card-discount', title='삼성 구독 제휴카드 할인, 실적별로 얼마나 받나요?',
            desc='삼성카드·우리카드·KB국민카드 등 삼성 AI 구독 제휴카드의 전월 실적 구간별 월 청구할인과 캐시백을 한 표로 정리했습니다.',
            kw='삼성 구독 제휴카드, 구독 카드 할인, 삼성카드 구독 할인, 가전 구독 청구할인, 전월 실적',
            answer='구독료를 제휴카드로 자동결제하면 전월 실적 구간에 따라 매월 청구할인(일부 카드는 캐시백 포함)을 받습니다. 높은 구간은 월 구독료가 일정 금액 이상일 때만 적용되는 카드가 있습니다.',
            body='<h2>카드별 · 실적 구간별 월 혜택</h2>' + self.card_table() +
                 '''<p class="ss-note">할인은 월 구독료를 넘지 않습니다. 실적 산정 기준·기간·건수 조건은 카드사 기준을 따르며 바뀔 수 있습니다.</p>
<h2>할인 받는 순서</h2><ol><li>구독 신청 때 제휴카드를 결제 카드로 지정</li><li>전월 실적 구간을 채우면 다음 달 청구할인</li><li>구독센터 계산기에서 카드·실적 구간을 바꿔 월 납부액 확인</li></ol>''',
            faq=[('카드 할인은 몇 개월 받나요?', '카드마다 다르며, 대부분 구독 기간 동안 매월 실적을 채운 달에 적용됩니다. 기간 조건은 상담 때 카드사 기준으로 확인해 드립니다.'),
                 ('여러 대를 구독하면 카드 할인도 여러 번 받나요?', '카드사 기준에 따라 다릅니다. 구독 건마다 적용되는 카드와 한 건만 적용되는 카드가 있어 상담 때 확인해 드립니다.')],
            links=['<a href="%s">제휴카드 혜택 전체</a>' % links['cardUrl'], cat('aicombo', 'AI 콤보')]))
        A.append(dict(slug='prepay', title='삼성 구독 선납하면 얼마나 싸지나요?',
            desc='삼성 AI 구독 선납 비율(20~50%)별 추가 할인율과 품목별 최대 선납 비율. 선납하면 월 구독료가 바로 낮아집니다.',
            kw='삼성 구독 선납, 구독 선납 할인, 선납금, 가전 구독 월 구독료 낮추기',
            answer='신청할 때 제품 금액의 일부를 먼저 내면 남은 기간의 월 구독료가 낮아지고, 선납 비율에 따라 추가 할인을 받습니다. 선납은 신청할 때만 고를 수 있습니다.',
            body='<h2>선납 비율별 할인</h2>' + self.prepay_table() +
                 '<p>%s</p><p class="ss-note">선납금은 구독 신청 시에만 선택할 수 있으며, 구독 기간 중에는 변경이 어렵습니다.</p>' % e((self.pol.get('prepay') or {}).get('help', '')),
            faq=[('선납하면 제휴카드 할인도 그대로 받나요?', '네. 선납 후 남은 월 구독료에 제휴카드 청구할인이 적용됩니다. 다만 월 구독료가 낮아져 일부 카드의 높은 실적 구간 조건(월 구독료 기준)에 못 미칠 수 있어 함께 계산해 드립니다.')],
            links=[cat('tv', 'TV'), cat('aicombo', 'AI 콤보')]))
        A.append(dict(slug='multi-discount', title='삼성 가전 여러 대 같이 구독하면 할인되나요?',
            desc='삼성 AI 구독 다품목 할인(약정 기간별 추가 할인)과 스마트 패키지 포인트를 정리했습니다. 묶음 월 구독료는 다품목 계산기로 바로.',
            kw='삼성 다품목 구독 할인, 가전 묶음 구독, 스마트 패키지, 혼수 가전 구독 할인',
            answer='신규 고객이 2품목 이상 함께 구독하면 대마다 약정 기간에 따라 월 구독료가 추가 할인되고(%s), 스마트 패키지 대상 품목은 품목 수에 따라 포인트를 더 받습니다.' % yrs,
            body='''<h2>다품목 추가 할인</h2><p>%s</p><p class="ss-note">약정 기간별 할인율: %s%s</p>
<h2>스마트 패키지 포인트</h2>%s
<p><a class="ss-btn" href="%s">다품목 계산기로 묶음 월 구독료 계산하기</a></p>''' % (e(mu.get('text', '')), yrs, (' · 기간 ' + mperiod) if mperiod else '', self.package_table(), links['bundleUrl']),
            faq=[('정수기도 다품목 할인이 되나요?', '정수기는 본사 표가 따로 있어 상담 때 안내해 드립니다.'),
                 ('다른 날 따로 신청해도 되나요?', '다품목 할인은 함께 구독할 때 적용됩니다. 신청 시점 조건은 상담 때 확인해 드립니다.')],
            links=['<a href="%s">다품목 구독 계산기</a>' % links['bundleUrl'], '<a href="%swedding.html">혼수·입주 가전 구독</a>' % links['guideDir']]))
        A.append(dict(slug='points', title='삼성 구독 멤버십 포인트, 어떻게 쓰나요?',
            desc='삼성 AI 구독 적립 예정 멤버십 포인트를 구독료로 나눠 쓰기·전액 N개월·따로 받기 세 가지로 쓰는 법과 유지기간(36개월)을 정리했습니다.',
            kw='삼성 구독 포인트, 멤버십 포인트 구독료, 구독료 지원 포인트, 삼성 AI 구독클럽 포인트',
            answer='구독하면 모델별로 멤버십 포인트가 적립됩니다. 포인트 유지기간(36개월) 안에 구독료로 나눠 쓰거나, 처음 몇 달 구독료를 전액 포인트로 내거나, 따로 받아 현금처럼 쓸 수 있습니다.',
            body='''<h2>포인트 쓰는 방법 3가지</h2>
<ol><li><b>구독료로 사용 · 36개월 나눠서</b> — 포인트 ÷ 36 만큼 매월 구독료에서 빠집니다.</li>
<li><b>구독료로 사용 · 전액 N개월</b> — 처음 몇 달은 구독료 전액을 포인트로 내 월 0원.</li>
<li><b>포인트로 따로 받기</b> — 구독료는 그대로 내고, 포인트는 현금처럼 다른 곳에 씁니다.</li></ol>
<p>구독센터 모델 페이지 계산기에서 세 방법을 눌러 보면 월 납부액과 개월별 납부가 바로 바뀝니다.</p>
<h2>얼마나 쌓이나요?</h2><p>적립 예정 포인트는 모델마다 다르며 삼성닷컴 기준(제품분 금액 × 적립률 + 상품별 추가 포인트)을 따릅니다. 행사 기간에는 "N개월 구독료 상당" 포인트가 더해지는 모델도 있습니다.</p>''',
            faq=[('포인트는 언제 들어오나요?', '구독 계약·설치가 끝난 뒤 적립됩니다. 적립 시점은 상담 때 안내해 드립니다.'),
                 ('유지기간이 지나면 어떻게 되나요?', '포인트 유지기간(36개월)이 지나면 남은 포인트는 사라질 수 있어, 계산기는 36개월 안에 다 쓰는 것으로 보여 드립니다.')],
            links=[cat('aicombo', 'AI 콤보'), cat('kimchi', '김치냉장고')]))
        A.append(dict(slug='care', title='방문케어·셀프케어·무상수리, 무엇이 다른가요?',
            desc='삼성 AI 구독 케어 유형(방문케어·셀프케어·무상수리)과 방문 주기에 따라 달라지는 서비스와 월 구독료를 쉽게 정리했습니다.',
            kw='삼성 구독 방문케어, 셀프케어, 무상수리 서비스, 구독 케어 주기, 삼성 구독케어',
            answer='무상수리는 약정 기간 동안 고장 수리를 받는 기본 서비스이고, 방문케어는 전문가가 정기적으로 찾아와 세척·점검·소모품 교체를, 셀프케어는 소모품을 받아 직접 관리하는 방식입니다. 케어가 많을수록 월 구독료가 높아집니다.',
            body='''<h2>케어 유형</h2><ul><li><b>무상수리</b> — 약정 기간 동안 고장 수리 (가장 낮은 월 구독료)</li>
<li><b>방문케어</b> — 전문가 방문 세척·점검·소모품 교체 · 방문 주기(예: 12개월·36개월)에 따라 요금이 다릅니다</li>
<li><b>셀프케어</b> — 소모품 정기 배송으로 직접 관리</li></ul>
<p>고를 수 있는 케어는 품목·모델마다 다릅니다. 구독센터 모델 페이지의 「약정 기간별 월 구독료」 표와 계산기에서 케어별 요금을 확인하세요.</p>''',
            faq=[('케어는 중간에 바꿀 수 있나요?', '케어 유형 변경 가능 여부는 계약 조건에 따라 다릅니다. 상담 때 미리 확인해 드립니다.')],
            links=[cat('water', '정수기'), cat('aircon', '에어컨'), cat('washer', '세탁기')]))
        A.append(dict(slug='b2b', title='사업자도 삼성 가전 구독이 되나요? (B2B 구독)',
            desc='삼성스토어 시흥은 삼성전자 B2B AI 구독 파트너입니다. 매장·사무실·숙박업 등 사업자 가전 구독 견적을 받아 보세요.',
            kw='사업자 가전 구독, B2B 구독, 삼성 B2B AI 구독, 법인 가전 구독, 매장 가전 렌탈',
            answer='네. 삼성스토어 시흥은 삼성전자 한국총괄이 위촉한 B2B AI 구독 파트너로, 사업자 전용 구독 조건으로 견적을 드립니다. 11월에는 사업자 전용 B2B 구독 페스티벌(기본 20% 할인 + 최대 30% 할인)이 진행 중입니다.',
            body='''<h2>이런 곳에 많이 써요</h2><ul><li>매장·카페·사무실의 냉장고·정수기·에어컨·TV·모니터</li><li>숙박업·원룸·셰어하우스의 세탁기·건조기·에어컨</li><li>병의원·학원의 공기청정기·시스템에어컨</li></ul>
<h2>견적 받는 법</h2><ol><li>필요한 품목·수량·설치 장소를 남겨 주세요</li><li>사업자 전용 조건으로 월 구독료를 계산해 드립니다</li><li>계약 후 설치·케어까지 한 번에</li></ol>
<p><a class="ss-btn" href="https://www.samsungsh.co.kr/main/html.php?htmid=service/SamSungSubscription.html?evt=b2b">사업자 구독 견적 문의</a> <a href="https://www.samsungsh.co.kr/board/view.php?&amp;bdId=blog&amp;sno=121">B2B 구독 페스티벌 자세히</a></p>''',
            faq=[('세금계산서 발행이 되나요?', '사업자 구독 조건과 증빙 방법은 견적 때 함께 안내해 드립니다.'),
                 ('가정용과 같은 모델인가요?', '가정용 모델과 업소용 모델 모두 상담 가능합니다. 설치 환경에 맞는 모델을 추천해 드립니다.')],
            links=['<a href="%s">위촉장 보기 · 구독센터 홈</a>' % links['homeUrl'], cat('sysaircon', '시스템에어컨')]))
        A.append(dict(slug='wedding', title='혼수·입주 가전, 구독으로 한 번에 맞추려면?',
            desc='신혼·새 아파트 입주·이사 때 냉장고·세탁기·TV·에어컨을 구독으로 묶어 맞추는 방법. 다품목 할인·스마트 패키지·묶음 계산기까지.',
            kw='혼수 가전 구독, 입주 가전 구독, 신혼 가전 구독, 이사 가전, 가전 패키지 구독',
            answer='여러 대를 한 번에 구독하면 다품목 추가 할인과 스마트 패키지 포인트를 함께 받을 수 있습니다. 다품목 계산기에 담아 묶음 월 납부액을 먼저 보고 상담에서 조건을 맞추세요.',
            body='''<h2>많이 고르는 조합</h2><ul><li>냉장고 + 김치냉장고 + AI 콤보 (주방·세탁 기본)</li><li>TV + 사운드바 + 에어컨 (거실)</li><li>정수기 + 식기세척기 + 인덕션 (주방 추가)</li></ul>
<p><a class="ss-btn" href="%s">다품목 계산기로 묶음 계산하기</a></p>
<p>혼수·입주·이사 혜택은 <a href="https://www.samsungsh.co.kr/board/view.php?&amp;bdId=blog&amp;sno=83">시흥몰 행사 안내</a>에서 확인할 수 있습니다. %s.</p>''' % (links['bundleUrl'], gift),
            faq=[('설치 날짜를 따로 잡을 수 있나요?', '품목별 배송·설치 일정은 상담 때 입주일에 맞춰 조율해 드립니다.')],
            links=['<a href="%smulti-discount.html">다품목 할인 안내</a>' % links['guideDir'], cat('ref', '냉장고'), cat('tv', 'TV')]))
        return A

    def page(self, site, a, links, head, foot, loader):
        url = site.site + links['guideDir'] + a['slug'] + '.html'
        faq = [{'@type': 'Question', 'name': q, 'acceptedAnswer': {'@type': 'Answer', 'text': ans}} for q, ans in a['faq']]
        ld = MP.ld_tag([
            {'@context': 'https://schema.org', '@type': 'Article', 'headline': a['title'], 'description': a['desc'], 'inLanguage': 'ko',
             'author': {'@type': 'Organization', 'name': '삼성스토어 시흥'}, 'publisher': {'@type': 'Organization', 'name': '삼성스토어 시흥'},
             'mainEntityOfPage': url, 'image': MP.OG_IMG},
            {'@context': 'https://schema.org', '@type': 'BreadcrumbList', 'itemListElement': [
                {'@type': 'ListItem', 'position': 1, 'name': '구독센터', 'item': site.site + links['homeUrl']},
                {'@type': 'ListItem', 'position': 2, 'name': '구독 안내', 'item': site.site + links['guideUrl']},
                {'@type': 'ListItem', 'position': 3, 'name': a['title'], 'item': url}]},
            {'@context': 'https://schema.org', '@type': 'FAQPage', 'mainEntity': faq}])
        body = ('<article class="ss-guide">\n<p class="ss-crumb"><a href="%s">구독센터</a> › <a href="%s">구독 안내</a></p>\n<h1>%s</h1>\n'
                '<p class="ss-guide-answer"><b>한 줄 답</b> %s</p>\n%s\n<h2>자주 묻는 질문</h2>\n<dl class="ss-faq">%s</dl>\n'
                '<p class="ss-guide-links">함께 보기: %s</p>\n<p class="ss-guide-cta"><a class="ss-btn" href="%s">구독 상담 신청</a> <span>상담 완료 시 사은품 증정 · 매장 방문 구매 완료 시 와인 증정</span></p>\n</article>\n') % (
            e(links['homeUrl']), e(links['guideUrl']), e(a['title']), e(a['answer']), a['body'],
            ''.join('<dt>%s</dt><dd>%s</dd>' % (e(q), e(ans)) for q, ans in a['faq']), ' · '.join(a['links']),
            e(links['consultUrl'] + '&from=guide&purpose=' + '%EC%8B%A0%EA%B7%9C%EA%B5%AC%EB%8F%85' + '&memo=' + '%5B%EA%B5%AC%EB%8F%85%EA%B0%80%EC%9D%B4%EB%93%9C%5D%20' + a['slug']))
        return head(a['title'] + ' | 삼성스토어 시흥 구독센터', a['desc'], a['kw'], url, og_image=MP.OG_IMG, extra_head=ld) + \
            '<div id="subShopRoot">\n    <div data-ss="nav"></div>\n' + body + '    <section class="ss-sec"><div data-ss="cta"></div></section>\n</div>\n' + foot() + loader() + '</body>\n</html>\n'

    @staticmethod
    def index_html(articles, links):
        return ('<section class="ss-sec ss-guide-list"><h2>구독 가이드 · 자주 찾는 질문</h2><ul>' +
                ''.join('<li><a href="%s%s.html"><b>%s</b><span>%s</span></a></li>' % (links['guideDir'], a['slug'], e(a['title']), e(a['answer'][:60]) + '…') for a in articles) +
                '</ul></section>\n')
