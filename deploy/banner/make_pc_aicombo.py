# -*- coding: utf-8 -*-
# PC 메인 비주얼 1916x821 — 삼성닷컴 공식 85" Neo QLED + AI 콤보 2대, 실제 비율, 겹침 없음.
# PC 문구(날짜·제목·버튼)는 왼쪽 0~900px 에 얹히므로 상품은 오른쪽 1150~1850 에 둔다. 배경은 와인·상품권 장과 같은 크림색.
from PIL import Image, ImageFilter, ImageDraw
W, H = 1916, 821
TV_MM, COMBO_MM, SIDE_MM = 1891, 686, 36
def load(p):
    im = Image.open(p).convert('RGBA'); return im.crop(im.getbbox())
tv, ga, wh = load('TV80.png'), load('AHS.png'), load('AHW.png')
s = 560 / TV_MM                                   # TV 가로 560px
def rs(im, mm): w = round(mm * s); return im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
tv, ga, wh = rs(tv, TV_MM), rs(ga, COMBO_MM), rs(wh, COMBO_MM); side = round(SIDE_MM * s)
bg = Image.new('RGB', (W, H), (254, 251, 239))
def shadow(img, x0, x1, y, h, a):
    sh = Image.new('L', (W, H), 0); ImageDraw.Draw(sh).ellipse((x0, y - h // 2, x1, y + h // 2), fill=a)
    return Image.composite(Image.new('RGB', (W, H), (205, 198, 182)), img, sh.filter(ImageFilter.GaussianBlur(12)))
cx_center = 1500
tx = cx_center - tv.width // 2; ty = 62
total = ga.width + side + wh.width; cx = cx_center - total // 2; cy = ty + tv.height + 40
bg = shadow(bg, tx + 30, tx + tv.width - 30, ty + tv.height, 14, 90)
bg = shadow(bg, cx - 16, cx + total + 16, cy + ga.height, 24, 140)
bg.paste(tv, (tx, ty), tv); bg.paste(ga, (cx, cy), ga); bg.paste(wh, (cx + ga.width + side, cy), wh)
bg.save('pc_visual_aicombo_1103.png', optimize=True)
print('TV %dx%d @%d,%d | 세탁기 %dx%d @%d,%d → 바닥 %d' % (tv.width, tv.height, tx, ty, ga.width, ga.height, cx, cy, cy + ga.height))
