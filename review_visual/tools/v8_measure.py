"""Две метрики пустоты карточки для доказательств аудита v7 (CardFlow).

1. bbox-пустота: доля площади карточки вне bbox пикселей, отличных от белого
   (метрика, заявленная в review_visual/MEASUREMENTS.md; рамка карточки при этом
   попадает в bbox, поэтому она дополнительно отсекается по внутренней области).
2. ink-bbox-пустота: строгая метрика — учитываются только «тёмные» пиксели
   (контрастный текст и заливки), рамка/пастель не считаются. Она заведомо
   пессимистичнее, поэтому выдерживать нужно обе.

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
    # Внутренняя область без рамки/скруглений: 12 px по краю.
    inner = arr[y0 + 12 : y1 - 11, x0 + 12 : x1 - 11]
    ih, iw, _ = inner.shape

    # 1. «Отлично от белого» внутри внутренней области.
    diff = np.abs(inner - np.array([255, 255, 255])).max(axis=2)
    loose = diff > 26
    lb = bbox_of(loose)
    if lb is None:
        out["empty_loose"] = 100.0
    else:
        bw, bh = lb[2] - lb[0] + 1, lb[3] - lb[1] + 1
        out["content_loose"] = f"{bw}x{bh}"
        out["empty_loose"] = round(100.0 * (1 - (bw * bh) / (iw * ih)), 1)

    # 2. Строгая метрика: только тёмные пиксели (текст, заливки действий).
    lum = (
        0.299 * inner[:, :, 0] + 0.587 * inner[:, :, 1] + 0.114 * inner[:, :, 2]
    )
    dark = lum < 200
    db = bbox_of(dark)
    if db is None:
        out["empty_ink"] = 100.0
    else:
        bw, bh = db[2] - db[0] + 1, db[3] - db[1] + 1
        out["content_ink"] = f"{bw}x{bh}"
        out["empty_ink"] = round(100.0 * (1 - (bw * bh) / (iw * ih)), 1)
        out["ink_share"] = round(100.0 * dark.mean(), 2)
    return out


def main():
    print(json.dumps([measure(p) for p in sys.argv[1:]], ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
