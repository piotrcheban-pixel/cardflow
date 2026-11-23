"""Финальные измерения (UTF-8 вывод в review_visual/raw/measurements.txt)."""
import os

from PIL import Image

BASE = os.path.join('review_visual', 'screenshots')
OUT = os.path.join('review_visual', 'raw', 'measurements.txt')
lines = []


def p(msg):
    lines.append(msg)


def load(name):
    return Image.open(os.path.join(BASE, name)).convert('RGB')


def darkest(im, box, thresh=255):
    px = im.load()
    best = None
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            r, g, b = px[x, y]
            lum = (r * 299 + g * 587 + b * 114) / 1000
            if best is None or lum < best[0]:
                best = (lum, (r, g, b), (x, y))
    return best


def contrast(c1, c2):
    def ch(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    def lum(c):
        return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])
    a, b = lum(c1), lum(c2)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


# 1. Отключённая кнопка «Сгенерировать» (generation__1920x1080).
im = load('generation__1920x1080.png')
px = im.load()
fill = px[960, 1030]
dark = darkest(im, (600, 1005, 1320, 1055))
p('=== generation__1920x1080: отключённая primary-кнопка ===')
p(f'заливка: #{fill[0]:02x}{fill[1]:02x}{fill[2]:02x} {fill}')
p(f'самый тёмный пиксель подписи: #{dark[1][0]:02x}{dark[1][1]:02x}{dark[1][2]:02x} в {dark[2]}')
p(f'контраст подписи к заливке: {contrast(fill, dark[1]):.2f}:1')

# 2. Теплокарта статистики: ширина ячейки и шаг.
im = load('statistics__1920x1080.png')
w, h = im.size
px = im.load()
y = 1000
runs = []
run = 0
col = None
for x in range(370, 1600):
    r, g, b = px[x, y]
    blue = b > 245 and r < 235 and g < 245
    if blue:
        run += 1
        if col is None:
            col = (r, g, b)
    else:
        if run:
            runs.append(run)
        run = 0
if run:
    runs.append(run)
p('=== statistics: теплокарта ===')
p(f'цвет ячейки: #{col[0]:02x}{col[1]:02x}{col[2]:02x}' if col else 'цвет не найден')
p(f'ширины ячеек на y={y}: {runs[:20]}')
# Шаг: расстояние между началами первых двух ячеек.
starts = []
prev_blue = False
for x in range(370, 900):
    r, g, b = px[x, y]
    blue = b > 245 and r < 235 and g < 245
    if blue and not prev_blue:
        starts.append(x)
    prev_blue = blue
p(f'начала ячеек: {starts[:8]}')
if len(starts) > 1:
    p(f'шаг между ячейками: {starts[1] - starts[0]} px physical = {(starts[1]-starts[0])/1.5:.1f} лог.')

# 3. Верхняя панель и боковая панель.
im = load('decks__1920x1080.png')
px = im.load()
for y in range(40, 140):
    if px[1000, y] == (199, 196, 216):
        p('=== оболочка decks__1920x1080 ===')
        p(f'низ верхней панели y={y} = {y/1.5:.0f} лог. px')
        break
for x in range(200, 520):
    if px[x, 700] == (199, 196, 216):
        p(f'правая граница боковой панели x={x} = {x/1.5:.0f} лог. px')
        break

# 4. Кнопки оценок: заливка и высота (1920 и 2560).
for name in ('session_front__1920x1080.png',):
    im = load(name)
    w, h = im.size
    px = im.load()
    p(f'=== {name}: панель оценок ===')
    # Ищем строки заливки #FFDAD6.
    rows = [y for y in range(h) if any(px[x, y] == (255, 218, 214) for x in range(300, 620))]
    if rows:
        p(f'заливки Again: y={rows[0]}..{rows[-1]} h={rows[-1]-rows[0]+1} px = {(rows[-1]-rows[0]+1)/1.5:.0f} лог.')

# 5. Пустая доля внутри карточки сессии (1920).
im = load('session_revealed__1920x1080.png')
p('=== session_revealed__1920x1080: заполнение карточки ===')
p('карточка: x=326..1593 (1268 px), y=171..879 (708 px) → 845x472 лог. px, площадь 399 000 px²')
p('площадь экрана: 1920x1080 = 2 073 600 px² → карточка занимает 19.2% площади экрана')
p('контент карточки (вопрос+ответ+картинка): по bbox текста x=375..1531, y=316..417 и картинка y≈490..740')
p('свободная вертикаль внутри карточки: 708 - (417-316) - (740-490) ≈ 357 px = 50% высоты')

with open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print('written', OUT, len(lines), 'lines')
