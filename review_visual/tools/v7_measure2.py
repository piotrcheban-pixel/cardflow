"""Pixel measurements for the CardFlow v7 visual audit (v2).

Card is found by flood-filling the white card interior from the content centre,
so text inside the card does not break the bbox. Rating buttons are matched by
their fill colours and rejected unless the matched pixels actually fill their
bbox.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

RATING_FILLS = {
    "again": (255, 218, 214),
    "hard": (229, 238, 255),
    "good": (108, 248, 187),
    "easy": (226, 223, 255),
}
MARK = (255, 0, 255)


def bbox_of(mask):
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def find_card(img):
    w, h = img.size
    # Try several seed points along the vertical centre line (the card is centred).
    for cy in (h // 2, int(h * 0.45), int(h * 0.35), int(h * 0.55), int(h * 0.25)):
        for cx in (w // 2, int(w * 0.45), int(w * 0.55)):
            probe = img.copy()
            p = probe.getpixel((cx, cy))
            if min(p) < 250:
                continue
            ImageDraw.floodfill(probe, (cx, cy), MARK, thresh=10)
            arr = np.array(probe)
            mask = np.all(arr == np.array(MARK), axis=2)
            area = int(mask.sum())
            if area < 0.02 * w * h:
                continue
            bb = bbox_of(mask)
            bw, bh = bb[2] - bb[0] + 1, bb[3] - bb[1] + 1
            if bw < 150 or bh < 80:
                continue
            # The card must be a solid-ish rectangle.
            if area / (bw * bh) < 0.6:
                continue
            return bb
    return None


def measure(path):
    img = Image.open(path).convert("RGB")
    arr = np.array(img).astype(int)
    h, w, _ = arr.shape
    out = {"file": os.path.basename(path), "viewport": f"{w}x{h}"}
    rect = find_card(img)
    if rect is None:
        out["card"] = None
        return out
    x0, y0, x1, y1 = rect
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    out["card"] = f"{cw}x{ch}"
    out["card_share_width"] = round(100.0 * cw / w, 1)
    out["card_share_height"] = round(100.0 * ch / h, 1)
    inner = arr[y0 + 5 : y1 - 4, x0 + 5 : x1 - 4]
    diff = np.abs(inner - np.array([255, 255, 255])).max(axis=2)
    content = diff > 26
    cb = bbox_of(content)
    if cb is None:
        out["content_band"] = "empty"
        out["empty_share_bbox"] = 100.0
        out["ink_share_card"] = 0.0
    else:
        cw2, ch2 = cb[2] - cb[0] + 1, cb[3] - cb[1] + 1
        out["content_band"] = f"{cw2}x{ch2}"
        out["content_band_share_width"] = round(100.0 * cw2 / cw, 1)
        out["content_band_share_height"] = round(100.0 * ch2 / ch, 1)
        out["empty_share_bbox"] = round(100.0 * (1 - (cw2 * ch2) / (cw * ch)), 1)
        out["ink_share_card"] = round(100.0 * content.mean(), 1)
    for name, rgb in RATING_FILLS.items():
        mask = np.all(np.abs(arr - np.array(rgb)) <= 4, axis=2)
        bb = bbox_of(mask)
        if bb is None:
            continue
        bw, bh = bb[2] - bb[0] + 1, bb[3] - bb[1] + 1
        fill = mask[bb[1] : bb[3] + 1, bb[0] : bb[2] + 1].mean()
        if bw > 40 and bh > 20 and fill > 0.6:
            out[f"rating_{name}"] = f"{bw}x{bh}"
    return out


def main():
    rows = [measure(p) for p in sys.argv[1:]]
    print(json.dumps(rows, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
