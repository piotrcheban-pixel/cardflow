"""3-column contact sheet for the resolution matrix."""
import sys
from PIL import Image, ImageDraw

out = sys.argv[1]
width = int(sys.argv[2])
paths = sys.argv[3:]
cols = 3
thumbs = []
for p in paths:
    im = Image.open(p).convert("RGB")
    h = round(width * im.height / im.width)
    thumbs.append((p, im.resize((width, h), Image.LANCZOS)))
rows = (len(thumbs) + cols - 1) // cols
row_h = max(t[1].height for t in thumbs) + 22
sheet = Image.new("RGB", (cols * width + 8 * (cols + 1), rows * row_h + 8), (235, 235, 240))
draw = ImageDraw.Draw(sheet)
for i, (p, im) in enumerate(thumbs):
    r, c = divmod(i, cols)
    x = 8 + c * (width + 8)
    y = 8 + r * row_h
    draw.text((x, y), p.split("__")[-1].replace(".png", "") + " " + p.split("\\")[-1].split("__")[0], fill=(10, 10, 10))
    sheet.paste(im, (x, y + 16))
sheet.save(out)
print("SHEET", out, sheet.size)
