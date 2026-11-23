"""G8: how much of the pane the live screens actually use (CardFlow audit v8).

For each screenshot the pane is given explicitly (sidebar 360 px / header 84 px
of physical px at DPI 150 %; subpages have no sidebar).  "Content" = pixels that
differ from the app surface #F8F9FF by more than 8, then density-profiled so
1-px borders and stray shadows do not stretch the bbox.

Reported per file:
  used_width_pct   -- content bbox width / pane width
  right_margin_px  -- empty space to the right inside the pane
  content_top_pct / content_bottom_pct -- vertical extent of the content block
  empty_below_pct  -- empty space under the content (G8 "giant empty area")

Usage: python review_visual/tools/v8_g8_measure.py
"""
import json

import numpy as np
from PIL import Image

SIDEBAR = 360
HEADER = 84
SURFACE = np.array([248, 249, 255])

# file -> (pane_left, pane_top, note)
FILES = {
    "live_01_decks_2560x1410.png": (SIDEBAR, HEADER, "shell: decks"),
    "live_22_statistics.png": (SIDEBAR, HEADER, "shell: statistics"),
    "live_23_settings.png": (SIDEBAR, HEADER, "shell: settings"),
    "live_02_deck.png": (0, HEADER, "subpage: deck"),
    "live_20_generation.png": (0, HEADER, "subpage: generation"),
    "live_21_constructor.png": (0, HEADER, "subpage: constructor"),
}

STUDY = {
    "live_30_study_test.png": "study: test",
    "live_33_study_typing.png": "study: typing",
    "live_34_study_truefalse.png": "study: true/false",
}


def measure_with_pane(path, left, top, skip_top=0):
    arr = np.array(Image.open(path).convert("RGB")).astype(int)
    h, w, _ = arr.shape
    diff = np.abs(arr - SURFACE).max(axis=2)
    content = diff > 8
    pane = content[top + skip_top : h, left:]
    if pane.size == 0:
        return None
    col = pane.sum(axis=0) / max(1, pane.shape[0])
    row = pane.sum(axis=1) / max(1, pane.shape[1])
    cols = np.nonzero(col > 0.05)[0]
    rows = np.nonzero(row > 0.02)[0]
    if len(cols) == 0 or len(rows) == 0:
        return None
    x0, x1 = int(cols.min()) + left, int(cols.max()) + left
    y0, y1 = int(rows.min()) + top + skip_top, int(rows.max()) + top + skip_top
    pane_w = w - left
    return {
        "viewport": f"{w}x{h}",
        "pane_w": pane_w,
        "content_w": int(x1 - x0 + 1),
        "used_width_pct": round(100.0 * (x1 - x0 + 1) / pane_w, 1),
        "left_margin_px": x0 - left,
        "right_margin_px": w - x1,
        "content_top_pct": round(100.0 * (y0 - top) / (h - top), 1),
        "content_bottom_pct": round(100.0 * (y1 - top) / (h - top), 1),
        "empty_below_pct": round(100.0 * (h - y1) / (h - top), 1),
    }


def main():
    out = []
    for name, (left, top, note) in FILES.items():
        row = measure_with_pane(f"review_visual/screenshots/v8/{name}", left, top)
        out.append({"file": name, "note": note, **(row or {})})
    # Study screens: skip the progress strip (~150 px) to see the content block.
    for name, note in STUDY.items():
        row = measure_with_pane(
            f"review_visual/screenshots/v8/{name}", 0, HEADER, skip_top=150
        )
        out.append({"file": name, "note": note, **(row or {})})
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
