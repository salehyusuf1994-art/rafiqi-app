"""أيقونة «نقاء»: موجة صوت ذهبية على مربع داكن بزوايا دائرية"""
import sys
from PIL import Image, ImageDraw

S = 512
img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle((16, 16, S - 16, S - 16), radius=120, fill=(14, 16, 24, 255), outline=(227, 194, 128, 110), width=10)
gold = (227, 194, 128, 255)
bars = [(0.18, 0.10), (0.30, 0.30), (0.42, 0.58), (0.54, 0.40), (0.66, 0.22), (0.78, 0.08)]
for x, h in bars:
    cx = int(S * x)
    half = int(S * h / 2) + 14
    d.rounded_rectangle((cx - 20, S // 2 - half, cx + 20, S // 2 + half), radius=20, fill=gold)
img.save(sys.argv[1], sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
