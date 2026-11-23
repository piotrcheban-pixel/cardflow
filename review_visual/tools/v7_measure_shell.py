"""Shell-screen content coverage: how much of the content area is actually used.

Background is the app surface #F8F9FF; panels have #C7C4D8 borders and text is
dark. Any pixel differing from the surface by > 10 counts as content.
"""
import json
import sys

import numpy as np
from PIL import Image

SIDEBAR = 360  # 240 logical * 1.5
HEADER = 84    # 56 logical * 1.5


def measure(path):
    arr = np.array(Image.open(path).convert("RGB")).astype(int)
    h, w, _ = arr.shape
    surface = np.array([248, 249, 255])
    diff = np.abs(arr - surface).max(axis=2)
    content = diff > 10
    # Sidebar and app bar are content, but for "used area" count only the main pane.
    pane = content[HEADER:, SIDEBAR:]
    # Density profiles reject stray pixels (scrollbars, shadows, 1-px borders).
    col = pane.sum(axis=0) / max(1, pane.shape[0])
    row = pane.sum(axis=1) / max(1, pane.shape[1])
    cols = np.nonzero(col > 0.05)[0]
    rows = np.nonzero(row > 0.02)[0]
    if len(cols) == 0 or len(rows) == 0:
        return {"file": path.split("\\")[-1], "used": None}
    x0, x1 = int(cols.min()) + SIDEBAR, int(cols.max()) + SIDEBAR
    y0, y1 = int(rows.min()) + HEADER, int(rows.max()) + HEADER
    pane_w = w - SIDEBAR
    pane_h = h - HEADER
    used_w = x1 - x0 + 1
    used_h = y1 - y0 + 1
    # Empty margins inside the pane that content never reaches.
    left_margin = x0 - SIDEBAR
    right_margin = w - x1
    bottom_margin = h - y1
    return {
        "file": path.split("\\")[-1],
        "viewport": f"{w}x{h}",
        "pane": f"{pane_w}x{pane_h}",
        "content_bbox": f"{used_w}x{used_h}",
        "used_pane_width_pct": round(100.0 * used_w / pane_w, 1),
        "used_pane_height_pct": round(100.0 * used_h / pane_h, 1),
        "left_margin_px": left_margin,
        "right_margin_px": right_margin,
        "bottom_margin_px": bottom_margin,
    }


print(json.dumps([measure(p) for p in sys.argv[1:]], ensure_ascii=False, indent=1))
