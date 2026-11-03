# -*- coding: utf-8 -*-
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
F = os.path.expandvars(r'%LOCALAPPDATA%\Microsoft\Windows\Fonts')
bold = os.path.join(F, 'Pretendard-ExtraBold.otf'); med = os.path.join(F, 'Pretendard-Medium.otf'); semi = os.path.join(F, 'Pretendard-SemiBold.otf')
W, H = 540, 320
bg = Image.open('gen_bg.png').convert('RGB')
# 1536x864 -> 540x304 ; crop to 540x320 by scaling to height 320 (width 569) and cropping right-biased
bg = bg.resize((620, round(bg.height * 620 / bg.width)), Image.LANCZOS)
x0 = bg.width - W; y0 = (bg.height - H) // 2
im = bg.crop((x0, y0, x0 + W, y0 + H))
d = ImageDraw.Draw(im)
title = ['삼성 구독센터', '한눈에 비교']
sub = ['월 구독료 · 선납 할인 · 카드 혜택을', '모델별로 바로 비교해 보세요']
y = 46
for t in title:
    d.text((40, y), t, font=ImageFont.truetype(bold, 40), fill=(17, 17, 17)); y += 50
fs = ImageFont.truetype(med, 15)
for i, t in enumerate(sub): d.text((40, y + 10 + i * 22), t, font=fs, fill=(60, 60, 60))
# button like existing banners: dark rounded rect with white text
bx, by, bw, bh = 40, 240, 112, 36
d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=8, fill=(34, 34, 34))
f = ImageFont.truetype(semi, 15); tw = d.textlength('자세히 보기', font=f)
d.text((bx + (bw - tw) / 2, by + 8), '자세히 보기', font=f, fill=(255, 255, 255))
im.save('gudok_center_banner_1102.png', optimize=True)
print(im.size, os.path.getsize('gudok_center_banner_1102.png'))
