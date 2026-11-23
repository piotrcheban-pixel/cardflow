"""Палитра и площади: сколько значимых цветов на экране, доли площадей."""
from __future__ import annotations

import sys
from collections import Counter

import numpy as np
from PIL import Image


def palette(path: str, min_share: float = 0.0005) -> None:
    im = Image.open(path).convert('RGB')
    a = np.asarray(im).reshape(-1, 3)
    total = a.shape[0]
    packed = (a[:, 0].astype(np.uint32) << 16) | (a[:, 1].astype(np.uint32) << 8) | a[:, 2]
    values, counts = np.unique(packed, return_counts=True)
    order = np.argsort(-counts)
    print(f'{path}: {im.width}x{im.height} unique_colors={len(values)}')
    shown = 0
    for idx in order:
        share = counts[idx] / total
        if share < min_share:
            break
        v = int(values[idx])
        rgb = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
        print(f'  #{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}  {share * 100:5.2f}%')
        shown += 1
    print(f'  significant colors (>={min_share * 100:.2f}%): {shown}')


if __name__ == '__main__':
    for p in sys.argv[1:]:
        palette(p)
