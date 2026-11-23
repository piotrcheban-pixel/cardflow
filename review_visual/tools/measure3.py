"""Целевые измерения для отчёта: панели, кнопки, текст, сетки.

Печатает таблицу «метрика = число (physical px; logical px при DPI 1.5)».
"""
import os

from PIL import Image

BASE = os.path.join('review_visual', 'screenshots')


def load(name):
    return Image.open(os.path.join(BASE, name)).convert('RGB')


def bbox_color(im, color, tol=0):
    """bbox всех пикселей заданного цвета."""
    px = im.load()
    w, h = im.size
    minx, miny, maxx, maxy = 10 ** 9, 10 ** 9, -1, -1
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if abs(r - color[0]) <= tol and abs(g - color[1]) <= tol and abs(b - color[2]) <= tol:
                minx = min(minx, x)
                maxx = max(maxx, x)
                miny = min(miny, y)
                maxy = max(maxy, y)
    if maxx < 0:
        return None
    return (minx, miny, maxx, maxy)


def bbox_color_region(im, color, x0, y0, x1, y1, tol=0):
    px = im.load()
    minx, miny, maxx, maxy = 10 ** 9, 10 ** 9, -1, -1
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if abs(r - color[0]) <= tol and abs(g - color[1]) <= tol and abs(b - color[2]) <= tol:
                minx = min(minx, x)
                maxx = max(maxx, x)
                miny = min(miny, y)
                maxy = max(maxy, y)
    if maxx < 0:
        return None
    return (minx, miny, maxx, maxy)


def text_bbox(im, x0, y0, x1, y1, thresh=140):
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
        return None
    return (minx, miny, maxx, maxy)


def line(msg):
    print(msg)


def session():
    for name, w, h in (('session_revealed__1920x1080.png', 1920, 1080),
                       ('session_revealed__2560x1410.png', 2560, 1410)):
        im = load(name)
        line(f'--- {name} ({w}x{h} physical = {w/1.5:.0f}x{h/1.5:.0f} logical) ---')
        # Границы карточки по цвету фона внутри и рамке.
        card = bbox_color_region(im, (248, 249, 255), 0, 200, w, h)
        # Найдём карточку иначе: белые пиксели в теле.
        cx0 = None
        for x in range(w):
            if im.load()[x, 400] == (255, 255, 255):
                cx0 = x
                break
        cx1 = None
        for x in range(w - 1, -1, -1):
            if im.load()[x, 400] == (255, 255, 255):
                cx1 = x
                break
        line(f'  карточка по X: {cx0}..{cx1} = {cx1 - cx0 + 1} px / {(cx1 - cx0 + 1)/1.5:.0f} лог.')
        # Вертикальные границы по рамке outlineVariant.
        px = im.load()
        border = (199, 196, 216)
        rows = [y for y in range(100, h) if sum(1 for x in range(cx0 + 40, cx1 - 40, 4) if px[x, y] == border) > 80]
        line(f'  карточка по Y (рамка): {rows[:2]} .. {rows[-2:] if len(rows) > 1 else ""}')
        # Вопрос и ответ.
        q = text_bbox(im, cx0 + 20, rows[0] + 20, cx1 - 20, rows[0] + 300)
        line(f'  текст в верхней части карточки: bbox={q} h={q[3] - q[1] + 1 if q else None}')
        # Кнопки оценок: цвета заливок.
        again = bbox_color(im, (255, 218, 214))
        good = bbox_color(im, (108, 248, 187))
        easy = bbox_color(im, (226, 223, 255), )
        hard = bbox_color(im, (229, 238, 255))
        for nm, bb in (('Again', again), ('Good', good), ('Easy', easy), ('Hard', hard)):
            if bb:
                line(f'  кнопка {nm}: bbox={bb} w={bb[2]-bb[0]+1} h={bb[3]-bb[1]+1}')
        line('')


def decks():
    im = load('decks__2560x1410.png')
    line('--- decks__2560x1410.png (1707x940 logical) ---')
    # Панель тулбара.
    tb = bbox_color_region(im, (255, 255, 255), 500, 400, 2500, 700)
    line(f'  панель поиска (белая): {tb}')
    # Кнопка «Учить» на первой карточке.
    btn = bbox_color_region(im, (53, 37, 205), 900, 880, 1160, 960)
    line(f'  кнопка «Учить»: {btn} w={btn[2]-btn[0]+1 if btn else None} h={btn[3]-btn[1]+1 if btn else None}')
    line('')


def generation():
    im = load('generation__1920x1080.png')
    line('--- generation__1920x1080.png ---')
    # Отключённая кнопка «Сгенерировать».
    dis = bbox_color_region(im, (211, 228, 254), 200, 950, 1800, 1060, tol=6)
    line(f'  disabled «Сгенерировать»: {dis}')
    if dis:
        px = im.load()
        cx = (dis[0] + dis[2]) // 2
        cy = (dis[1] + dis[3]) // 2
        line(f'  цвет кнопки в центре: {px[cx, cy]}')
        tb = text_bbox(im, dis[0] + 40, dis[1] + 10, dis[2] - 40, dis[3] - 10, 200)
        line(f'  подпись bbox: {tb} h={tb[3]-tb[1]+1 if tb else None}')
        if tb:
            line(f'  цвет подписи: {px[(tb[0]+tb[2])//2, (tb[1]+tb[3])//2]}')
    line('')


def statistics_heatmap():
    im = load('statistics__1920x1080.png')
    line('--- statistics__1920x1080.png: теплокарта ---')
    # Ячейки светло-голубые (211,228,254 / 220,232,255)
    c = bbox_color_region(im, (211, 228, 254), 500, 950, 1900, 1180, tol=4)
    line(f'  область ячеек: {c}')
    if c:
        # Шаг ячеек по горизонтали: ищем провалы цвета.
        px = im.load()
        y = c[1] + 5
        runs = []
        run = 0
        for x in range(c[0], c[2] + 1):
            r, g, b = px[x, y]
            if abs(r - 211) <= 6 and abs(g - 228) <= 6 and abs(b - 254) <= 6:
                run += 1
            else:
                if run:
                    runs.append(run)
                run = 0
        if run:
            runs.append(run)
        line(f'  ширины ячеек на строке y={y}: {runs[:14]}')
    line('')


def buttons_general():
    im = load('session_front__1920x1080.png')
    line('--- session_front__1920x1080.png: «Показать ответ» ---')
    bb = bbox_color_region(im, (53, 37, 205), 300, 700, 1700, 900)
    line(f'  primary-кнопка: {bb} w={bb[2]-bb[0]+1 if bb else None} h={bb[3]-bb[1]+1 if bb else None}')
    line('')


def header():
    im = load('decks__1920x1080.png')
    px = im.load()
    # Высота верхней панели: ищем строку нижней границы (outlineVariant) в левой панели.
    for y in range(40, 120):
        if px[1000, y] == (199, 196, 216):
            line(f'--- decks__1920x1080.png: нижняя граница верхней панели y={y} (={y/1.5:.0f} лог.)')
            break
    # Ширина боковой панели: граница по x.
    for x in range(200, 500):
        if px[x, 600] == (199, 196, 216):
            line(f'    правая граница боковой панели x={x} (={x/1.5:.0f} лог.)')
            break


if __name__ == '__main__':
    session()
    decks()
    generation()
    statistics_heatmap()
    buttons_general()
    header()
