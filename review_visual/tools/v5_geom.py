from PIL import Image


def runs(mask):
    out = []
    s = None
    for i, v in enumerate(mask):
        if v and s is None:
            s = i
        elif not v and s is not None:
            out.append((s, i - 1))
            s = None
    if s is not None:
        out.append((s, len(mask) - 1))
    return out


def bbox_color(im, x1, y1, x2, y2, pred):
    xs, ys = [], []
    for y in range(y1, y2):
        for x in range(x1, x2):
            if pred(im.getpixel((x, y))):
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))


def yellow(c):
    return c[0] > 200 and c[1] > 190 and c[2] < 190


def white(c):
    return c[0] > 251 and c[1] > 251 and c[2] > 251


def card_rect(path):
    im = Image.open(path).convert('RGB')
    W, H = im.size
    # find widest white horizontal run
    best = None
    for y in range(100, H - 1, 3):
        row = [im.getpixel((x, y)) for x in range(0, W, 2)]
        rr = [(a * 2, b * 2) for a, b in runs([white(c) for c in row]) if b - a > 120]
        if rr:
            r = max(rr, key=lambda t: t[1] - t[0])
            if best is None or r[1] - r[0] > best[1] - best[0]:
                best = r
    if best is None:
        return im, None
    cx = (best[0] + best[1]) // 2
    col = [im.getpixel((cx, y)) for y in range(0, H)]
    rr = [(a, b) for a, b in runs([white(c) for c in col]) if b - a > 100]
    if not rr:
        return im, None
    top = None
    for a, b in rr:
        if a > 80:
            top = (a, b)
            break
    if top is None:
        top = rr[0]
    return im, (best[0], top[0], best[1], top[1])


def report(path, label):
    im, rect = card_rect(path)
    W, H = im.size
    print(f'== {label} {path} png={W}x{H}')
    if rect:
        print('card rect(px): x %d..%d y %d..%d  w=%d h=%d logical(hdpi?)/1.5=(%.1f x %.1f)' % (
            rect[0], rect[2], rect[1], rect[3], rect[2] - rect[0] + 1, rect[3] - rect[1] + 1,
            (rect[2] - rect[0] + 1) / 1.5, (rect[3] - rect[1] + 1) / 1.5))
    ib = bbox_color(im, 0, 0, W, H, yellow)
    if ib:
        print('image bbox(px): x %d..%d y %d..%d w=%d h=%d' % (ib[0], ib[2], ib[1], ib[3], ib[2] - ib[0] + 1, ib[3] - ib[1] + 1))
        if rect:
            print('image share of card: width %.1f%% height %.1f%%' % (
                100 * (ib[2] - ib[0] + 1) / (rect[2] - rect[0] + 1), 100 * (ib[3] - ib[1] + 1) / (rect[3] - rect[1] + 1)))
    # rating Again button height at a column near 30% width
    x = int(W * 0.28)
    col = [im.getpixel((x, y)) for y in range(H // 2, H)]
    m = [c[0] > 240 and 200 < c[1] < 235 and 195 < c[2] < 230 for c in col]
    rr = [(a + H // 2, b + H // 2) for a, b in runs(m) if b - a > 20]
    if rr:
        a, b = rr[0]
        print('again button vertical run(px): %d..%d h=%d logical=%.1f' % (a, b, b - a + 1, (b - a + 1) / 1.5))


report(r'review_visual/screenshots/v5/05_classic_answer_2560x1410.png', 'classic answer 2K')
report(r'review_visual/screenshots/v5/05_classic_answer_1920x1080.png', 'classic answer 1920')
report(r'review_visual/screenshots/v5/05_classic_answer_390x844.png', 'classic answer 390')
report(r'review_visual/screenshots/v5/05_classic_answer_800x600.png', 'classic answer 800')
report(r'review_visual/screenshots/v5/14_feed_answer_2560x1410.png', 'feed answer 2K')
report(r'review_visual/screenshots/v5/16_test_390x844.png', 'test 390')

# save button bbox in new card form 2K (primary fill)
im = Image.open(r'review_visual/screenshots/v5/30_card_form_new_2560.png').convert('RGB')
bb = bbox_color(im, 0, 1200, im.size[0], im.size[1], lambda c: c == (53, 37, 205))
print('form save primary bbox', bb, 'logical h', (bb[3] - bb[1] + 1) / 1.5 if bb else None)

# add card button height
im = Image.open(r'review_visual/screenshots/v5/29_deck_for_form_2560.png').convert('RGB')
print('add-card border bbox', bbox_color(im, 1740, 440, 2120, 580, lambda c: 190 <= c[0] <= 215 and 185 <= c[1] <= 210 and 205 <= c[2] <= 230))
