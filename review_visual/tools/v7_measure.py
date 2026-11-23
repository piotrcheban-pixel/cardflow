"""Pixel measurements for the CardFlow v7 visual audit.

For each image: viewport, card bbox (white card on #F8F9FF), content bbox inside
the card, empty share of the card, and rating-button geometry (by fill colour).
"""
import json
import os
import sys

import numpy as np
from PIL import Image

RATING_FILLS = {
    "again": (255, 218, 214),
    "hard": (229, 238, 255),
    "good": (108, 248, 187),
    "easy": (226, 223, 255),
}


def bbox_of(mask):
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def card_rect(arr):
    """Largest solid-white rectangle = the session card."""
    h, w, _ = arr.shape
    white = np.all(arr > 250, axis=2)
    rows = np.where(white.sum(axis=1) > min(w * 0.25, 400))[0]
    if len(rows) == 0:
        return None
    # contiguous row groups; take the tallest
    groups = []
    start = prev = rows[0]
    for y in rows[1:]:
        if y - prev > 3:
            groups.append((start, prev))
            start = y
        prev = y
    groups.append((start, prev))
    top, bottom = max(groups, key=lambda g: g[1] - g[0])
    mid = (top + bottom) // 2
    row = white[mid]
    xs = np.where(row)[0]
    if len(xs) == 0:
        return None
    # longest run
    best = (xs[0], xs[0])
    start = prev = xs[0]
    for x in xs[1:]:
        if x - prev > 3:
            if prev - start > best[1] - best[0]:
                best = (start, prev)
            start = x
        prev = x
    if prev - start > best[1] - best[0]:
        best = (start, prev)
    return int(best[0]), int(top), int(best[1]), int(bottom)


def measure(path):
    img = Image.open(path).convert("RGB")
    arr = np.array(img).astype(int)
    h, w, _ = arr.shape
    out = {"file": os.path.basename(path), "viewport": f"{w}x{h}"}
    rect = card_rect(arr)
    if rect is None:
        out["card"] = None
        return out
    x0, y0, x1, y1 = rect
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    out["card"] = f"{cw}x{ch}"
    out["card_share_width"] = round(100.0 * cw / w, 1)
    out["card_share_height"] = round(100.0 * ch / h, 1)
    # Content: pixels inside the card that are clearly not card white.
    inner = arr[y0 + 4 : y1 - 3, x0 + 4 : x1 - 3]
    diff = np.abs(inner - np.array([255, 255, 255])).max(axis=2)
    content = diff > 26
    cb = bbox_of(content)
    if cb is None:
        out["content_band"] = "empty"
        out["empty_share_bbox"] = 100.0
    else:
        cw2, ch2 = cb[2] - cb[0] + 1, cb[3] - cb[1] + 1
        out["content_band"] = f"{cw2}x{ch2}"
        out["content_band_share_width"] = round(100.0 * cw2 / cw, 1)
        out["content_band_share_height"] = round(100.0 * ch2 / ch, 1)
        out["empty_share_bbox"] = round(100.0 * (1 - (cw2 * ch2) / (cw * ch)), 1)
        out["ink_share_card"] = round(100.0 * content.mean(), 1)
    # Rating buttons: fill colours with wide horizontal runs.
    for name, rgb in RATING_FILLS.items():
        mask = np.all(np.abs(arr - np.array(rgb)) <= 6, axis=2)
        bb = bbox_of(mask)
        if bb is None:
            continue
        bw, bh = bb[2] - bb[0] + 1, bb[3] - bb[1] + 1
        if bw > 40 and bh > 20:
            out[f"rating_{name}"] = f"{bw}x{bh}"
    return out


def main():
    rows = [measure(p) for p in sys.argv[1:]]
    print(json.dumps(rows, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
