from PIL import Image
import sys

path = sys.argv[1] if len(sys.argv) > 1 else r'review_visual/screenshots/v5/05_classic_answer_2560x1410.png'
im = Image.open(path).convert('RGB')
W, H = im.size
print('PNG', path, W, H)

def runs(seq):
    out = []
    start = None
    for i, v in enumerate(seq):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, len(seq) - 1))
    return out

# rating buttons fill rows/cols (Again color)
x0 = 600
col = [im.getpixel((x0, y)) for y in range(H)]
mask = [c[0] > 240 and 200 < c[1] < 235 and 195 < c[2] < 230 for c in col]
print('again vertical runs at x=%d:' % x0, runs(mask))
# horizontal at button middle
ymid = 1340
row = [im.getpixel((x, ymid)) for x in range(W)]
mask2 = [c[0] > 240 and 200 < c[1] < 235 and 195 < c[2] < 230 for c in row]
print('again horizontal runs at y=%d:' % ymid, runs(mask2))

# card border: light gray outline #C7C4D8 on surface #F8F9FF; detect non-bg white card #FFFFFF
# card interior white 255,255,255
def iswhite(c):
    return c[0] > 252 and c[1] > 252 and c[2] > 252
col2 = [im.getpixel((W // 2, y)) for y in range(H)]
wmask = [iswhite(c) for c in col2]
print('white card vertical runs at center:', runs(wmask)[:10])
row2 = [im.getpixel((x, H // 3)) for x in range(W)]
wmask2 = [iswhite(c) for c in row2]
print('white card horizontal runs at H/3:', [r for r in runs(wmask2) if r[1] - r[0] > 50])

# progress bar: find primary color rows near top
for y in range(120, 190):
    c = im.getpixel((W // 2, y))
    if c == (53, 37, 205) or (c[2] > 180 and c[0] < 120):
        print('primary row near progress', y, c)
        break

# button text color sample rows for question: bounding box of dark text in question area
# find dark pixels in card top area
def bbox_dark(x1, y1, x2, y2, thr=100):
    xs, ys = [], []
    for y in range(y1, y2):
        for x in range(x1, x2):
            c = im.getpixel((x, y))
            if c[0] < thr and c[1] < thr and c[2] < thr:
                xs.append(x); ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))
print('question dark bbox', bbox_dark(600, 380, 2000, 560))
print('answer dark bbox', bbox_dark(700, 940, 1800, 1040))
print('label VOPROS bbox', bbox_dark(600, 330, 760, 380, thr=120))
