"""Build a contact sheet from screenshots (review_final/tools/contact.py).

Usage: python review_final/tools/contact.py out.png in1.png in2.png ... [--cols N]
Each tile is scaled to a fixed width, labelled with the file name.
"""
from __future__ import annotations

import sys

from PIL import Image, ImageDraw

TILE_W = 820


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cols = 2
    if "--cols" in sys.argv:
        cols = int(sys.argv[sys.argv.index("--cols") + 1])
        args.remove(str(cols))
    out, files = args[0], args[1:]
    tiles = []
    for path in files:
        im = Image.open(path).convert("RGB")
        scale = TILE_W / im.width
        im = im.resize((TILE_W, max(1, round(im.height * scale))), Image.LANCZOS)
        label = path.split("\\")[-1].split("/")[-1]
        canvas = Image.new("RGB", (TILE_W, im.height + 22), (30, 30, 30))
        canvas.paste(im, (0, 22))
        ImageDraw.Draw(canvas).text((6, 5), label, fill=(255, 255, 255))
        tiles.append(canvas)
    rows = (len(tiles) + cols - 1) // cols
    row_heights = [max(t.height for t in tiles[r * cols:(r + 1) * cols]) for r in range(rows)]
    sheet = Image.new("RGB", (TILE_W * cols, sum(row_heights)), (12, 12, 12))
    y = 0
    for r in range(rows):
        for c, tile in enumerate(tiles[r * cols:(r + 1) * cols]):
            sheet.paste(tile, (c * TILE_W, y))
        y += row_heights[r]
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    main()
