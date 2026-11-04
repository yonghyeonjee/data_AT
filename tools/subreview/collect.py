# -*- coding: utf-8 -*-
"""삼성닷컴 후기 요약 수집 (2026-11-04) — 구독센터 모델 페이지·카드의 "삼성닷컴 후기"

    python -I tools/subreview/collect.py            # sdp/sub/sub_index.js 의 모든 모델
    python -I tools/subreview/collect.py --only WD90H25BHW,KU75MH80AFXKR

만드는 것
  sdp/sub/sub_reviews.js        모델 → [평균 별점, 후기 수, goodsId]  (카드 배지 · 모든 구독센터 화면이 읽는다 · 작게)
  sdp/sub/review/<goodsId>.json 그 상품의 별점 분포 + 최근 후기 발췌 3개 + 삼성닷컴 후기 주소 (모델 페이지가 필요할 때만 받는다)

원본 (공개 · 로그인 없음 · 사람이 삼성닷컴 상품 페이지를 열 때 브라우저가 부르는 것과 같은 요청)
  1) 검색   POST https://sribsrch.ecom.samsung.com/estoresearch-api/v1/scom/sec/search  keyword=<모델>
            → 일반 상품 goodsId · reviewRating · numberOfReviews · linkUrlReview   (구독 상품도 일반 상품 goodsId 의 후기를 쓴다)
  2) 요약   POST https://www.samsung.com/sec/xhr/goods/goodsAdvancedComment       → 별점 분포
  3) 목록   POST https://www.samsung.com/sec/xhr/goods/loadGoodsAdvancedCommentList (최신순 10건)
지킬 것
  - 후기 원문을 옮기지 않는다: 본문 앞부분 60자 발췌 + 날짜·별점·마스킹된 작성자 + "삼성닷컴 후기" 표시 + 원문 링크
  - 작성자 이메일·회원번호 같은 필드는 저장하지 않는다 (HTML 목록의 마스킹된 아이디만)
  - 검색엔진용 별점(AggregateRating) 구조화 데이터는 넣지 않는다 (다른 사이트 후기라서 · 구글 지침)
  - 같은 goodsId 는 한 번만 · 요청 사이 0.35초 · 하루 한 번 정도
"""
import argparse, html, json, os, re, sys, time, urllib.parse, urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SUB = os.path.join(REPO, 'sdp', 'sub')
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
SEARCH = 'https://sribsrch.ecom.samsung.com/estoresearch-api/v1/scom/sec/search'
SUMMARY = 'https://www.samsung.com/sec/xhr/goods/goodsAdvancedComment'
LIST = 'https://www.samsung.com/sec/xhr/goods/loadGoodsAdvancedCommentList'
GAP = 0.35


def post(url, data, extra=None, tries=3):
    body = urllib.parse.urlencode(data).encode()
    h = {'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}
    h.update(extra or {})
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, body, h), timeout=20) as r:
                return r.read().decode('utf-8', 'replace')
        except Exception as ex:   # noqa: BLE001
            if i == tries - 1:
                raise
            time.sleep(1.5 * (i + 1))


def search(model):
    t = post(SEARCH, {'clientCode': 'b2c', 'storeID': '1', 'countryCode': 'sec', 'siteCd': 'sec', 'clientName': 'scom', 'version': 'v2',
                      'startIndex': '0', 'requestCount': '15', 'firstSearchYN': 'true', 'keyword': model, 'projection': '["*"]'},
             {'Origin': 'https://www.samsung.com', 'Referer': 'https://www.samsung.com/sec/aisearch/?searchvalue=' + urllib.parse.quote(model)})
    d = json.loads(t)
    m = model.upper()
    for r in d.get('searchResults') or []:
        cand = [r] + list(r.get('groupedProductList') or [])
        for c in cand:
            if str(c.get('modelCode') or '').upper() == m and c.get('goodsId'):
                try:
                    rating = float(c.get('reviewRating') or 0)
                except ValueError:
                    rating = 0.0
                link = c.get('linkUrlReview') or c.get('pdpURL') or c.get('consumerUrl') or ''
                if link and link.startswith('/'):
                    link = 'https://www.samsung.com' + link
                return dict(goods=c['goodsId'], rating=round(rating, 1), count=int(c.get('numberOfReviews') or 0), link=link)
    return None


def clean(s):
    s = re.sub(r'<br\s*/?>', ' ', s or '')
    s = html.unescape(re.sub(r'<[^>]+>', '', s)).replace('\xa0', ' ')
    s = re.sub(r'#\S+', '', s)            # #삼성전자이벤트참여 같은 꼬리표
    return re.sub(r'\s+', ' ', s).strip()


def detail(goods):
    out = {}
    t = post(SUMMARY, {'goodsId': goods, 'goodsTpCd': '10', 'goodsCmntKwdTp': 'GOODS_CMNT_KWD_G', 'sort': '', 'sord': 'asc', 'page': '1',
                       'multiGoodsIdsYn': 'N', 'aiscGoodsCmntYn': 'N'}, {'X-Requested-With': 'XMLHttpRequest'})
    dist = re.findall(r'<span class="total">\s*\(?\s*([\d,]+)', t)
    if len(dist) >= 5:
        out['dist'] = [int(x.replace(',', '')) for x in dist[:5]]   # 최고·만족·보통·별로·나쁨
    time.sleep(GAP)
    t = post(LIST, {'goodsId': goods, 'goodsTpCd': '10', 'goodsCmntKwdTp': 'GOODS_CMNT_KWD_G', 'sort': 'SYS_REG_DTM', 'sord': 'desc', 'page': '1',
                    'multiGoodsIdsYn': 'N', 'aiscGoodsCmntYn': 'N'}, {'X-Requested-With': 'XMLHttpRequest'})
    seen, items = set(), []
    for li in re.split(r'<li id="cmntList\d+">', t)[1:]:
        g = lambda p: (re.search(p, li, re.S) or [None, None])[1]
        body = clean(g(r'<div class="txt-box">\s*<p>(.*?)</p>'))
        user = (g(r'class="userid">([^<]*)') or '').strip()
        key = user + '|' + body[:40]   # 같은 사람이 같은 글을 두 번 올린 것은 하나로
        if len(body) < 12 or key in seen or re.fullmatch(r'(한달|1개월) ?(사용 ?)?(상품평|후기).*', body):
            continue
        seen.add(key)
        star = int(g(r'star-count">\s*(\d)') or 0)
        items.append({'d': g(r'class="date">\s*([\d-]+)') or '', 's': star, 'u': (g(r'class="userid">([^<]*)') or '').strip()[:12],
                      'v': clean(g(r'class="title-box">\s*<span>([^<]*)'))[:40], 't': body[:60] + ('…' if len(body) > 60 else ''),
                      'p': 1 if 'goods_comment/' in li else 0})
    # 최근 것 중 별점 높은 순으로 3개 (나쁜 후기도 있으면 전체 분포로 보여 준다)
    out['recent'] = sorted(items, key=lambda x: (-x['s'], -int(x['d'].replace('-', '') or 0)))[:3]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    a = ap.parse_args()
    src = open(os.path.join(SUB, 'sub_index.js'), encoding='utf-8').read()
    idx = json.loads(re.search(r'=\s*(\{.*\})\s*;?\s*$', src, re.S).group(1))
    models = [m.strip().upper() for m in a.only.split(',') if m.strip()] or sorted(idx['m'])
    rpath = os.path.join(SUB, 'sub_reviews.js')
    old = {}
    if os.path.exists(rpath):
        try:
            old = json.loads(re.search(r'=\s*(\{.*\})\s*;?\s*$', open(rpath, encoding='utf-8').read(), re.S).group(1)).get('m', {})
        except Exception:   # noqa: BLE001
            old = {}
    res = dict(old)
    rdir = os.path.join(SUB, 'review'); os.makedirs(rdir, exist_ok=True)
    done_goods, n_ok, n_none = {}, 0, 0
    for i, m in enumerate(models):
        try:
            s = search(m)
        except Exception as ex:   # noqa: BLE001
            sys.stdout.buffer.write(('! %s 검색 실패 %s\n' % (m, ex)).encode('utf-8')); time.sleep(GAP); continue
        time.sleep(GAP)
        if not s or s['count'] <= 0:
            res.pop(m, None); n_none += 1; continue
        res[m] = [s['rating'], s['count'], s['goods']]
        n_ok += 1
        if s['goods'] not in done_goods:
            try:
                d = detail(s['goods'])
            except Exception as ex:   # noqa: BLE001
                d = {}
                sys.stdout.buffer.write(('! %s 후기 목록 실패 %s\n' % (m, ex)).encode('utf-8'))
            d.update(rating=s['rating'], count=s['count'], link=s['link'], at=time.strftime('%Y-%m-%d'))
            with open(os.path.join(rdir, s['goods'] + '.json'), 'w', encoding='utf-8', newline='\n') as f:
                json.dump(d, f, ensure_ascii=False, separators=(',', ':'))
            done_goods[s['goods']] = 1
            time.sleep(GAP)
        if i % 50 == 0:
            sys.stdout.buffer.write(('%d/%d · 후기 있음 %d · 없음 %d\n' % (i, len(models), n_ok, n_none)).encode('utf-8')); sys.stdout.flush()
    with open(rpath, 'w', encoding='utf-8', newline='\n') as f:
        f.write('/* 삼성닷컴 후기 요약 — 모델 → [평균 별점, 후기 수, goodsId] (tools/subreview/collect.py · %s · 직접 고치지 마세요) */\nwindow.SUB_REVIEWS=%s;\n' % (
            time.strftime('%Y-%m-%d'), json.dumps({'at': time.strftime('%Y-%m-%d'), 'm': res}, ensure_ascii=False, separators=(',', ':'))))
    sys.stdout.buffer.write(('끝 · 모델 %d · 후기 있음 %d · 없음 %d · 상품 %d\n' % (len(models), n_ok, n_none, len(done_goods))).encode('utf-8'))


if __name__ == '__main__':
    main()
