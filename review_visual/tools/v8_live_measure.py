"""Live-app pixel measurements for the CardFlow v8 audit.

Finds the session card by flood-filling its white interior (the page background
is #F8F9FF, so the card is the only large pure-white region) and reports:

  card size / share of the window, both emptiness metrics of the audit method,
  the honest "largest content-free band", and — on the answer side — the four
  rating buttons found by their role fills, their heights and the gaps.

Usage: python review_visual/tools/v8_live_measure.py <png>...
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

MARK = (255, 0, 255)
RATING_FILLS = {
    "again": (255, 218, 214),   # lightErrorContainer
    "hard": (229, 238, 255),    # lightSurfaceContainer
    "good": (108, 248, 187),    # lightSecondaryContainer
    "easy": (226, 223, 255),    # lightPrimaryFixed
}
RATING_LEFT = {"again": None, "hard": None, "good": None, "easy": None}


def bbox_of(mask):
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def longest_run(flags):
    best = (0, 0)
    cur = 0
    start = 0
    for i, v in enumerate(flags):
        if v:
            if cur == 0:
                start = i
            cur += 1
            if cur > best[0]:
                best = (cur, start)
        else:
            cur = 0
    return best


def find_card(img):
    w, h = img.size
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
            if area / (bw * bh) < 0.6:
                continue
            return bb
    return None


def rating_buttons(arr, card):
    """Locate the four rating fills inside/under the card; return boxes."""
    x0, y0, x1, y1 = card
    sub = arr[y0 : y1 + 1, x0 : x1 + 1]
    out = {}
    for name, rgb in RATING_FILLS.items():
        mask = np.abs(sub - np.array(rgb)).max(axis=2) <= 6
        # A button is a wide, short filled block: ignore the thin interval text.
        rows = np.nonzero(mask.sum(axis=1) > 0.05 * sub.shape[1])[0]
        cols = np.nonzero(mask.sum(axis=0) > 0.02 * sub.shape[0])[0]
        if len(rows) == 0 or len(cols) == 0:
            out[name] = None
            continue
        out[name] = {
            "x": int(cols.min()) + x0,
            "w": int(cols.max() - cols.min() + 1),
            "y": int(rows.min()) + y0,
            "h": int(rows.max() - rows.min() + 1),
        }
    return out


def measure(path, inset=12):
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
    inner = arr[y0 + inset : y1 + 1 - inset, x0 + inset : x1 + 1 - inset]
    ih, iw, _ = inner.shape
    diff = np.abs(inner - np.array([255, 255, 255])).max(axis=2)
    loose = diff > 26
    lum = 0.299 * inner[:, :, 0] + 0.587 * inner[:, :, 1] + 0.114 * inner[:, :, 2]
    dark = lum < 200
    out["ink_share"] = round(100.0 * float(loose.mean()), 2)
    out["occupied_rows"] = round(100.0 * float(loose.any(axis=1).mean()), 1)
    lb = bbox_of(loose)
    if lb is not None:
        bw, bh = lb[2] - lb[0] + 1, lb[3] - lb[1] + 1
        out["content_bbox"] = f"{bw}x{bh}"
        out["empty_bbox_loose"] = round(100.0 * (1 - (bw * bh) / (iw * ih)), 1)
    db = bbox_of(dark)
    if db is not None:
        bw, bh = db[2] - db[0] + 1, db[3] - db[1] + 1
        out["content_ink_bbox"] = f"{bw}x{bh}"
        out["empty_bbox_ink"] = round(100.0 * (1 - (bw * bh) / (iw * ih)), 1)
    band, band_start = longest_run(~loose.any(axis=1))
    out["largest_empty_band_rows_px"] = band
    out["largest_empty_band_rows_pct"] = round(100.0 * band / ih, 1)
    out["largest_empty_band_rows_start_pct"] = round(100.0 * band_start / ih, 1)

    buttons = rating_buttons(arr, rect)
    present = {k: v for k, v in buttons.items() if v}
    if len(present) == 4:
        order = ["again", "hard", "good", "easy"]
        heights = [present[k]["h"] for k in order]
        gaps = [
            present[order[i + 1]]["x"]
            - (present[order[i]]["x"] + present[order[i]]["w"])
            for i in range(3)
        ]
        out["rating_button_px"] = f"{present['good']['w']}x{present['good']['h']}"
        out["rating_button_logical"] = (
            f"{present['good']['w'] / 1.5:.1f}x{present['good']['h'] / 1.5:.1f}"
        )
        out["rating_heights_px"] = heights
        out["rating_gaps_px"] = gaps
        out["rating_gaps_logical"] = [round(g / 1.5, 1) for g in gaps]
        out["rating_rows"] = len({present[k]["y"] for k in order})
    else:
        out["rating_button_px"] = None
    return out


def main():
    print(json.dumps([measure(p) for p in sys.argv[1:]], ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
