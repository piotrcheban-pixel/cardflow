"""Контактный лист из скриншотов: сетка уменьшенных копий с подписями.

Использование:
  python contact.py out.png cols thumb_width img1 img2 ...
Подписи — имена файлов (обрезаются до 46 символов).
"""
import os
import sys

from PIL import Image, ImageDraw


def main():
    out = sys.argv[1]
    cols = int(sys.argv[2])
    tw = int(sys.argv[3])
    paths = sys.argv[4:]
    thumbs = []
    for p in paths:
        im = Image.open(p).convert('RGB')
        h = int(im.height * tw / im.width)
        thumbs.append((os.path.basename(p), im.resize((tw, h), Image.LANCZOS)))
    rows = (len(thumbs) + cols - 1) // cols
    cap = 18
    cell_h = max(t[1].height for t in thumbs) + cap + 6
    sheet = Image.new('RGB', (cols * (tw + 6) + 6, rows * cell_h + 6), (240, 240, 244))
    draw = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(thumbs):
        r, c = divmod(i, cols)
        x = 6 + c * (tw + 6)
        y = 6 + r * cell_h
        sheet.paste(im, (x, y))
        draw.text((x + 2, y + im.height + 3), name[:46], fill=(20, 20, 30))
    sheet.save(out)
    print(f'{out}: {sheet.width}x{sheet.height} ({len(thumbs)} img)')


if __name__ == '__main__':
    main()
