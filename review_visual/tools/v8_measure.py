"""Замеры карточки сессии CardFlow (аудит v7/v8): пустота тремя метриками.

1. bbox — заявленная в MEASUREMENTS.md метрика (bbox содержимого / площадь).
2. ink — доля «чернил» (пикселей, отличных от белого) в карточке.
3. rows — доля полностью пустых строк и **самая длинная сплошная пустая полоса**
   в пикселях и в % высоты карточки (строгая метрика независимого аудитора v8).

Рамка карточки и скругления отсекаются полем 12 px.

Запуск: python review_visual/tools/v8_measure.py <png>...
"""
import json
import os
import sys

import numpy as np
from PIL import Image
import importlib.util

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "v7m", os.path.join(_here, "v7_measure2.py")
)
_v7m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_v7m)


def bbox_of(mask):
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def longest_empty_band(empty_rows):
    """Самая длинная сплошная серия полностью пустых строк."""
    best = current = 0
    for flag in empty_rows:
        current = current + 1 if flag else 0
        best = max(best, current)
    return best


def measure(path):
    img = Image.open(path).convert("RGB")
    arr = np.array(img).astype(int)
    h, w, _ = arr.shape
    out = {"file": os.path.basename(path), "viewport": f"{w}x{h}"}
    rect = _v7m.find_card(img)
    if rect is None:
        out["card"] = None
        return out
    x0, y0, x1, y1 = rect
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    out["card"] = f"{cw}x{ch}"
    out["card_share_width"] = round(100.0 * cw / w, 1)
    out["card_share_height"] = round(100.0 * ch / h, 1)
    inner = arr[y0 + 12 : y1 - 11, x0 + 12 : x1 - 11]
    ih, iw, _ = inner.shape
    diff = np.abs(inner - np.array([255, 255, 255])).max(axis=2)
    content = diff > 26

    # 1. bbox-метрика.
    lb = bbox_of(content)
    if lb is None:
        out["empty_bbox"] = 100.0
    else:
        bw, bh = lb[2] - lb[0] + 1, lb[3] - lb[1] + 1
        out["empty_bbox"] = round(100.0 * (1 - (bw * bh) / (iw * ih)), 1)

    # 2. Чернила.
    out["ink_share"] = round(100.0 * content.mean(), 2)

    # 3. Строки: доля пустых строк и самая длинная полоса.
    rows_has = content.any(axis=1)
    empty_rows = ~rows_has
    out["empty_rows_share"] = round(100.0 * empty_rows.mean(), 1)
    band = longest_empty_band(empty_rows)
    out["longest_empty_band_px"] = int(band)
    out["longest_empty_band_share"] = round(100.0 * band / ih, 1)
    return out


def main():
    print(json.dumps([measure(p) for p in sys.argv[1:]], ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
