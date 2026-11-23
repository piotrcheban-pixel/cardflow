"""Измерения геометрии по скриншотам (белые панели, текстовые блоки).

  python measure2.py whitebox <png> [x0 y0 x1 y1] [tol]
      → bbox самой большой связной белой области по строкам/столбцам
  python measure2.py textbox <png> <x0> <y0> <x1> <y1> [thresh]
      → bbox тёмных пикселей (текста) и высота прописной строки
  python measure2.py colrun <png> <x> <y> <dir>
      → длина одноцветного пробега
"""
import sys

from PIL import Image


def whitebox(path, region=None, tol=3):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    x0, y0, x1, y1 = region if region else (0, 0, w, h)
    px = im.load()

    def is_white(x, y):
        r, g, b = px[x, y]
        return r >= 255 - tol and g >= 255 - tol and b >= 255 - tol

    rows = []
    for y in range(y0, y1):
        n = sum(1 for x in range(x0, x1, 2) if is_white(x, y))
        rows.append((y, n))
    # Самая длинная непрерывная серия строк, где белых > 25% ширины.
    best = (0, 0)
    start = None
    thr = (x1 - x0) / 2 / 4
    for y, n in rows:
        if n > thr:
            if start is None:
                start = y
            end = y
        else:
            if start is not None and end - start > best[1] - best[0]:
                best = (start, end)
            start = None
    if start is not None and end - start > best[1] - best[0]:
        best = (start, end)
    ry0, ry1 = best
    # Горизонтальные границы ищем на середине найденной полосы.
    ym = (ry0 + ry1) // 2
    xs = [x for x in range(x0, x1) if is_white(x, ym)]
    if not xs:
        print(f'{path}: белая область не найдена')
        return
    print(f'{path}:')
    print(f'  panel y={ry0}..{ry1} h={ry1 - ry0 + 1}')
    print(f'  panel x={xs[0]}..{xs[-1]} w={xs[-1] - xs[0] + 1}')
    print(f'  at y={ym}')


def textbox(path, x0, y0, x1, y1, thresh=150):
    im = Image.open(path).convert('RGB')
    px = im.load()
    minx, miny, maxx, maxy = 10 ** 9, 10 ** 9, -1, -1
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if (r * 299 + g * 587 + b * 114) / 1000 < thresh:
                minx = min(minx, x)
                maxx = max(maxx, x)
                miny = min(miny, y)
                maxy = max(maxy, y)
    if maxx < 0:
        print(f'{path}: текст не найден в ({x0},{y0})-({x1},{y1})')
        return
    print(f'{path} text bbox=({minx},{miny})-({maxx},{maxy}) w={maxx - minx + 1} h={maxy - miny + 1}')


def colrun(path, x, y, direction):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    px = im.load()
    dx, dy = {'d': (0, 1), 'u': (0, -1), 'r': (1, 0), 'l': (-1, 0)}[direction]
    base = px[x, y]
    n = 0
    cx, cy = x, y
    while 0 <= cx < w and 0 <= cy < h and px[cx, cy] == base:
        n += 1
        cx += dx
        cy += dy
    print(f'{path}: run ({x},{y}) dir={direction} color={base} len={n}')


def main():
    cmd = sys.argv[1]
    a = sys.argv[2:]
    if cmd == 'whitebox':
        region = tuple(int(v) for v in a[1:5]) if len(a) >= 5 else None
        whitebox(a[0], region)
    elif cmd == 'textbox':
        textbox(a[0], int(a[1]), int(a[2]), int(a[3]), int(a[4]))
    elif cmd == 'colrun':
        colrun(a[0], int(a[1]), int(a[2]), a[3])
    else:
        print('unknown cmd')


if __name__ == '__main__':
    main()
