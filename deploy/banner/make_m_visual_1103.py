# -*- coding: utf-8 -*-
# 모바일 메인 비주얼 640x800 : 문구가 아래 34% 를 덮으므로 TV+세탁건조기 장면을 위쪽 0~470px 안에 통째로 넣는다
from PIL import Image, ImageFilter, ImageDraw
pc = Image.open('c7990a51786a1cad3d66d676b907d718_21387.PNG').convert('RGB')   # 1983x793 (PC 1번 장)
W, H = 640, 800
s = 0.66
cx0, cx1 = 1060, 1983                       # 장면 영역 (세탁기 1280~1865, TV 1335~1895)
crop = pc.crop((cx0, 0, cx1, pc.height))
sc = crop.resize((round(crop.width * s), round(crop.height * s)), Image.LANCZOS)   # 550x444
# 배경: 원본 오른쪽 벽·바닥 톤을 크게 흐려 깔고, 아래로 갈수록 밝게
base = pc.crop((1100, 0, 1983, 793)).resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(40))
fade = Image.new('RGB', (W, H), (247, 245, 241))
grad = Image.linear_gradient('L').resize((W, H))
base = Image.composite(fade, base, grad.point(lambda v: min(255, int(v * 1.6))))
# 장면 붙이기 (가운데 정렬, 위 18px) — 가장자리는 부드럽게 섞는다
x = (W - sc.width) // 2 + 10; y = 12
mask = Image.new('L', sc.size, 255); d = ImageDraw.Draw(mask)
fe = 40
for i in range(fe):
    a = int(255 * i / fe)
    d.rectangle((i, i, sc.width - 1 - i, sc.height - 1 - i), outline=a)
base.paste(sc, (x, y), mask)
base.save('m_washer_tv_1103b.png', optimize=True)
print('scene', sc.size, 'at', x, y, '-> washer bottom y≈', y + round(680 * s), '(문구 시작 ≈528)')
