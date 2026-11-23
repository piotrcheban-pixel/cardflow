"""Contact sheet builder for v7 audit screenshots."""
import sys
from PIL import Image, ImageDraw

paths = sys.argv[2:]
out = sys.argv[1]
cols = 2
width = 860
thumbs = []
for p in paths:
    im = Image.open(p).convert("RGB")
    h = round(width * im.height / im.width)
    thumbs.append((p, im.resize((width, h), Image.LANCZOS)))
rows = (len(thumbs) + cols - 1) // cols
row_h = max(t[1].height for t in thumbs) + 26
sheet = Image.new("RGB", (cols * width + 10 * (cols + 1), rows * row_h + 10), (240, 240, 245))
draw = ImageDraw.Draw(sheet)
for i, (p, im) in enumerate(thumbs):
    r, c = divmod(i, cols)
    x = 10 + c * (width + 10)
    y = 10 + r * row_h
    draw.text((x, y), p.split("\\")[-1], fill=(20, 20, 20))
    sheet.paste(im, (x, y + 20))
sheet.save(out)
print("SHEET", out, sheet.size)
