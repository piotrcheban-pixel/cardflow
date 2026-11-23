"""Independent emptiness metrics for the CardFlow v8 audit (own script).

For each PNG + explicit card rectangle (from the widget-test geometry, device
px = logical px because DPR was 1) it reports:

  A. empty_bbox_loose  -- emptiness of the card by the bbox of pixels that
     differ from the card's white interior (this is the metric of
     review_visual/MEASUREMENTS.md, the one that produced 81-90 % "before").
  B. empty_bbox_ink    -- the same by the bbox of *dark* pixels (text, filled
     buttons); a card border / pale fill cannot stretch it.
  C. ink_share         -- share of actually painted (non-white) pixels.
  D. occupied_rows     -- share of card rows that contain any non-white pixel.
  E. largest_empty_band-- largest run of consecutive rows (and columns) with no
     content at all, in px and % of the card size.  This is the honest
     "giant empty zone inside the card" measure that the bbox metrics hide.

Usage: python review_visual/tools/v8_audit_measure.py
"""
import json
import os
import sys

import numpy as np
from PIL import Image

SHOTS = "review_visual/screenshots/v8"

# card rect x, y, w, h in device px (from review_visual/raw_v8/audit_run1.log)
RECTS = {
    "v8_2k150_Q.png": (239, 113, 1229, 827),
    "v8_2k150_A.png": (239, 113, 1229, 827),
    "v8_2k100_Q.png": (358, 115, 1843, 1325),
    "v8_2k100_A.png": (358, 115, 1843, 1325),
    "v8_4k100_Q.png": (720, 120, 2400, 2040),
    "v8_4k100_A.png": (720, 120, 2400, 2040),
    "v8_fhd90_Q.png": (269, 108, 1382, 972),
    "v8_fhd90_A.png": (269, 108, 1382, 972),
    "v8_390x844_Q.png": (16, 110, 358, 734),
    "v8_390x844_A.png": (16, 110, 358, 734),
    "v8_844x390_Q.png": (16, 110, 812, 280),
    "v8_844x390_A.png": (16, 110, 812, 280),
    "v8_533x400_Q.png": (16, 108, 501, 292),
    "v8_533x400_A.png": (16, 108, 501, 292),
}

# inset to drop the card border + antialiasing of the rounded corners
INSET = 12


def bbox_of(mask):
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def longest_run(flags):
    """Longest run of True values -> (length, start)."""
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


def measure(path, rect):
    img = Image.open(path).convert("RGB")
    arr = np.array(img).astype(int)
    x, y, w, h = rect
    card = arr[y : y + h, x : x + w]
    ch, cw, _ = card.shape
    inner = card[INSET : ch - INSET, INSET : cw - INSET]
    ih, iw, _ = inner.shape

    diff = np.abs(inner - np.array([255, 255, 255])).max(axis=2)
    loose = diff > 26
    lum = 0.299 * inner[:, :, 0] + 0.587 * inner[:, :, 1] + 0.114 * inner[:, :, 2]
    dark = lum < 200

    out = {
        "file": os.path.basename(path),
        "card": f"{cw}x{ch}",
        "empty_bbox_loose": None,
        "empty_bbox_ink": None,
        "ink_share": round(100.0 * float(loose.mean()), 2),
        "occupied_rows": round(100.0 * float(loose.any(axis=1).mean()), 1),
    }
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

    # Honest "giant empty zone": rows/cols with no content at all.
    empty_rows = ~loose.any(axis=1)
    empty_cols = ~loose.any(axis=0)
    band, band_start = longest_run(empty_rows)
    col_band, _ = longest_run(empty_cols)
    out["largest_empty_band_rows_px"] = band
    out["largest_empty_band_rows_pct"] = round(100.0 * band / ih, 1)
    out["largest_empty_band_rows_start_pct"] = round(100.0 * band_start / ih, 1)
    out["largest_empty_band_cols_px"] = col_band
    out["largest_empty_band_cols_pct"] = round(100.0 * col_band / iw, 1)
    return out


def main():
    rows = []
    for name, rect in RECTS.items():
        path = os.path.join(SHOTS, name)
        if not os.path.exists(path):
            rows.append({"file": name, "error": "missing"})
            continue
        rows.append(measure(path, rect))
    print(json.dumps(rows, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
