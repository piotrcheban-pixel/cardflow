"""Измерительный инструмент визуального аудитора CardFlow.

Только чтение PNG и печать чисел. Ничего в проекте не меняет.

Команды:
  overflow  <png...>                  — поиск полос переполнения Flutter (жёлто-чёрные)
  crop      <png> <x0> <y0> <x1> <y1> <out> [scale]
  rows      <png> <x0> <y0> <x1> <y1>  — строки с непустыми пикселями (границы текста)
  cols      <png> <x0> <y0> <x1> <y1>  — столбцы с непустыми пикселями
  colors    <png> <x0> <y0> <x1> <y1> [top]
  at        <png> <x> <y>
  contrast  <#rrggbb> <#rrggbb>
  run       <png> <x> <y> <dx> <dy>    — длина одноцветного пробега (для теней/границ)
"""
import sys
from collections import Counter

from PIL import Image


def load(path):
    return Image.open(path).convert('RGB')


def is_overflow(px):
    r, g, b = px
    yellow = r > 200 and g > 180 and b < 90
    black = r < 50 and g < 50 and b < 50
    return yellow or black


def cmd_overflow(args):
    for path in args:
        im = load(path)
        w, h = im.size
        px = im.load()
        # Полосы переполнения — диагональные штрихи: ищем строки с большим
        # числом чисто-жёлтых пикселей.
        rows = []
        for y in range(h):
            c = 0
            for x in range(0, w, 2):
                r, g, b = px[x, y]
                if r > 230 and g > 220 and b < 60:
                    c += 1
            if c > 5:
                rows.append((y, c))
        if rows:
            print(f'{path}: OVERFLOW rows={len(rows)} first={rows[0]} last={rows[-1]} max={max(r[1] for r in rows)}')
        else:
            print(f'{path}: ok ({w}x{h})')


def cmd_crop(args):
    path, x0, y0, x1, y1, out = args[0], int(args[1]), int(args[2]), int(args[3]), int(args[4]), args[5]
    scale = float(args[6]) if len(args) > 6 else 1.0
    im = load(path).crop((x0, y0, x1, y1))
    if scale != 1.0:
        im = im.resize((int(im.width * scale), int(im.height * scale)), Image.NEAREST)
    im.save(out)
    print(f'{out}: {im.width}x{im.height}')


def _bounds(im, x0, y0, x1, y1, thresh=128):
    px = im.load()
    rows = []
    cols = []
    for y in range(y0, y1):
        dark = 0
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if (r * 299 + g * 587 + b * 114) / 1000 < thresh:
                dark += 1
        rows.append((y, dark))
    for x in range(x0, x1):
        dark = 0
        for y in range(y0, y1):
            r, g, b = px[x, y]
            if (r * 299 + g * 587 + b * 114) / 1000 < thresh:
                dark += 1
        cols.append((x, dark))
    return rows, cols


def cmd_rows(args):
    path = args[0]
    x0, y0, x1, y1 = (int(v) for v in args[1:5])
    thresh = int(args[5]) if len(args) > 5 else 128
    im = load(path)
    rows, _ = _bounds(im, x0, y0, x1, y1, thresh)
    bands = []
    start = None
    for y, dark in rows:
        if dark > 0 and start is None:
            start = y
        elif dark == 0 and start is not None:
            bands.append((start, y - 1, y - start))
            start = None
    if start is not None:
        bands.append((start, y1 - 1, y1 - start))
    print(f'{path} rows in ({x0},{y0})-({x1},{y1}) thresh={thresh}:')
    prev_end = None
    for a, b, n in bands:
        gap = '' if prev_end is None else f' gap={a - prev_end - 1}'
        print(f'  y={a}..{b} h={n}{gap}')
        prev_end = b


def cmd_cols(args):
    path = args[0]
    x0, y0, x1, y1 = (int(v) for v in args[1:5])
    thresh = int(args[5]) if len(args) > 5 else 128
    im = load(path)
    _, cols = _bounds(im, x0, y0, x1, y1, thresh)
    bands = []
    start = None
    for x, dark in cols:
        if dark > 0 and start is None:
            start = x
        elif dark == 0 and start is not None:
            bands.append((start, x - 1, x - start))
            start = None
    if start is not None:
        bands.append((start, x1 - 1, x1 - start))
    print(f'{path} cols in ({x0},{y0})-({x1},{y1}) thresh={thresh}:')
    for a, b, n in bands:
        print(f'  x={a}..{b} w={n}')


def cmd_colors(args):
    path = args[0]
    x0, y0, x1, y1 = (int(v) for v in args[1:5])
    top = int(args[5]) if len(args) > 5 else 8
    im = load(path).crop((x0, y0, x1, y1))
    c = Counter(im.getdata())
    total = im.width * im.height
    for color, n in c.most_common(top):
        hexv = '#%02x%02x%02x' % color
        print(f'  {hexv} {n} ({100.0 * n / total:.1f}%)')


def cmd_at(args):
    path = args[0]
    x, y = int(args[1]), int(args[2])
    im = load(path)
    r, g, b = im.load()[x, y]
    print(f'#{r:02x}{g:02x}{b:02x} ({r},{g},{b})')


def _lum(rgb):
    def ch(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def cmd_contrast(args):
    def parse(s):
        s = s.lstrip('#')
        return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))
    a, b = parse(args[0]), parse(args[1])
    la, lb = _lum(a), _lum(b)
    hi, lo = max(la, lb), min(la, lb)
    ratio = (hi + 0.05) / (lo + 0.05)
    print(f'{args[0]} vs {args[1]}: {ratio:.2f}:1')


def cmd_run(args):
    path = args[0]
    x, y, dx, dy = (int(v) for v in args[1:5])
    im = load(path)
    px = im.load()
    w, h = im.size
    base = px[x, y]
    n = 0
    cx, cy = x, y
    while 0 <= cx < w and 0 <= cy < h and px[cx, cy] == base:
        n += 1
        cx += dx
        cy += dy
    print(f'run from ({x},{y}) dir=({dx},{dy}) color={base} len={n}')


def main():
    cmd = sys.argv[1]
    args = sys.argv[2:]
    {
        'overflow': cmd_overflow,
        'crop': cmd_crop,
        'rows': cmd_rows,
        'cols': cmd_cols,
        'colors': cmd_colors,
        'at': cmd_at,
        'contrast': cmd_contrast,
        'run': cmd_run,
    }[cmd](args)


if __name__ == '__main__':
    main()
