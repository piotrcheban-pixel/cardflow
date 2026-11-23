"""Find red (error-coloured) text bbox centre in a screenshot.

Usage: python find_red.py <png> [x0 y0 x1 y1]
Prints "cx cy n" or "none".
"""
import sys

import numpy as np
from PIL import Image

path = sys.argv[1]
im = np.array(Image.open(path).convert("RGB")).astype(int)
if len(sys.argv) == 6:
    x0, y0, x1, y1 = map(int, sys.argv[2:6])
    im = im[y0:y1, x0:x1]
    ox, oy = x0, y0
else:
    ox, oy = 0, 0
r, g, b = im[:, :, 0], im[:, :, 1], im[:, :, 2]
mask = (r > 110) & (r < 220) & (g < 90) & (b < 90) & (r - g > 60) & (r - b > 60)
ys, xs = np.nonzero(mask)
if len(ys) == 0:
    print("none")
else:
    print(int(xs.mean()) + ox, int(ys.mean()) + oy, len(ys))
