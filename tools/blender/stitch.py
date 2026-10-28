"""Stitch rendered tiles into a labelled contact sheet (system python3 + Pillow)."""
import json, math, sys
from PIL import Image, ImageDraw, ImageFont

cfg = json.load(open(sys.argv[1]))
tiles = cfg["tiles"]
ims = [Image.open(p).convert("RGB") for p, _ in tiles]
tw, th = ims[0].size
cols = min(4, len(ims))
rows = math.ceil(len(ims) / cols)
lab = 26
sheet = Image.new("RGB", (cols * tw, rows * (th + lab)), (245, 242, 236))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("DejaVuSans.ttf", 15)
except Exception:
    font = ImageFont.load_default()
for k, (im, (_, text)) in enumerate(zip(ims, tiles)):
    x, y = (k % cols) * tw, (k // cols) * (th + lab)
    sheet.paste(im, (x, y))
    d.text((x + 8, y + th + 4), text, fill=(29, 42, 58), font=font)
sheet.save(cfg["out"], optimize=True)
