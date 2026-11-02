# -*- coding: utf-8 -*-
# 모바일 메인 비주얼 640x800 — 삼성닷컴 공식 사진만 사용, 실제 크기 비율 유지, 서로 겹치지 않게
#   85" Neo QLED KQ85QNH80 : 가로 1,891mm (스탠드 포함 사진)
#   AI 콤보 WD90H25AHS(그레이)·AHW(화이트) : 가로 686mm
# 아래 약 34%(528px~)는 날짜·제목·버튼 문구가 덮으므로 상품은 y 18~505 안에 둔다
from PIL import Image, ImageFilter, ImageDraw
W, H = 640, 800
TOP, BOTTOM = 14, 512
TV_MM, COMBO_MM, GAP_MM, SIDE_MM = 1891, 686, 70, 36     # GAP: TV와 세탁기 사이, SIDE: 세탁기 두 대 사이
def load(p):
    im = Image.open(p).convert('RGBA'); return im.crop(im.getbbox())
tv, ga, wh = load('TV80.png'), load('AHS.png'), load('AHW.png')
tv_h_mm = TV_MM * tv.height / tv.width
co_h_mm = COMBO_MM * ga.height / ga.width
s = (BOTTOM - TOP) / (tv_h_mm + GAP_MM + co_h_mm)           # px per mm
s = min(s, 600 / TV_MM)
def rs(im, mm): w = round(mm * s); return im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
tv, ga, wh = rs(tv, TV_MM), rs(ga, COMBO_MM), rs(wh, COMBO_MM)
side = round(SIDE_MM * s)
# 배경: 밝은 회백 → 아래 바닥색, 위쪽에 아주 옅은 하늘빛
# 배경: 와인·상품권 장과 같은 크림색(254,251,239) — 메인 비주얼 다른 장들과 톤을 맞춘다
bg = Image.new('RGB', (W, H), (254, 251, 239))
def shadow(img, x0, x1, y, h=18, a=120):
    sh = Image.new('L', (W, H), 0); ImageDraw.Draw(sh).ellipse((x0, y - h // 2, x1, y + h // 2), fill=a)
    sh = sh.filter(ImageFilter.GaussianBlur(10))
    return Image.composite(Image.new('RGB', (W, H), (160, 156, 150)), img, sh)
tx = (W - tv.width) // 2; ty = TOP
cy = BOTTOM - ga.height; total = ga.width + side + wh.width; cx = (W - total) // 2
bg = shadow(bg, tx + 20, tx + tv.width - 20, ty + tv.height, 12, 90)
bg = shadow(bg, cx - 14, cx + total + 14, BOTTOM, 20, 140)
bg.paste(tv, (tx, ty), tv)
bg.paste(ga, (cx, cy), ga); bg.paste(wh, (cx + ga.width + side, cy), wh)
bg.save('m_visual_aicombo_1103c.png', optimize=True)
print('scale %.4f px/mm | TV %dx%d @%d,%d | 세탁기 %dx%d x2 @%d,%d → 바닥 %d | 비율 TV:세탁기 가로 = %.2f (실제 %.2f)'
      % (s, tv.width, tv.height, tx, ty, ga.width, ga.height, cx, cy, cy + ga.height, tv.width / ga.width, TV_MM / COMBO_MM))
