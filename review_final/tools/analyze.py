"""Pixel measurements for the CardFlow visual audit (read-only on screenshots).

Usage: python review_final/tools/analyze.py <shot.png> [mode]
Modes:
  sidebar   - locate the highlighted "Decks" nav item and derive item pitch
  card      - find the review-card rectangle (border outlineVariant) and report
              card geometry + share of window
  rows      - print dark-pixel row profile of a region: rows.txt
"""
from __future__ import annotations

import sys

import numpy as np
from PIL import Image


def load(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int16)


def find_runs(mask: np.ndarray) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    start = None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        elif not v and start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(mask) - 1))
    return runs


def near(color: np.ndarray, target: tuple[int, int, int], tol: int = 4) -> np.ndarray:
    return np.all(np.abs(color - np.array(target)) <= tol, axis=-1)


def sidebar(img: np.ndarray) -> None:
    h, w, _ = img.shape
    strip = img[:, 40:300]
    # selected item background: lightSurfaceContainer #E5EEFF
    mask = near(strip, (229, 238, 255), 3).all(axis=1)
    rows = [r for r in find_runs(mask) if r[1] - r[0] > 20]
    print(f"size={w}x{h}")
    for a, b in rows:
        print(f"selected-bg row {a}..{b} height={b - a + 1} center={(a + b) // 2}")


def card(img: np.ndarray, dpi: float = 1.5) -> None:
    h, w, _ = img.shape
    # outlineVariant light #C7C4D8 -> border of the card
    mask = near(img, (199, 196, 216), 6)
    # horizontal lines: rows where a long run of border color exists
    counts = mask.sum(axis=1)
    big_rows = [i for i, c in enumerate(counts) if c > w * 0.3]
    runs = find_runs(np.isin(np.arange(h), big_rows))
    print(f"image={w}x{h} logical={w / dpi:.1f}x{h / dpi:.1f}")
    for a, b in runs:
        if b - a >= 1:
            row_mask = mask[a + (b - a) // 2]
            cols = np.where(row_mask)[0]
            if cols.size == 0:
                continue
            print(
                f"h-border rows {a}..{b} x={cols[0]}..{cols[-1]} "
                f"width={cols[-1] - cols[0] + 1} "
                f"logical_w={(cols[-1] - cols[0] + 1) / dpi:.1f}"
            )
    # vertical borders (left/right edges of the card)
    col_counts = mask.sum(axis=0)
    big_cols = [i for i, c in enumerate(col_counts) if c > h * 0.25]
    col_runs = find_runs(np.isin(np.arange(w), big_cols))
    for a, b in col_runs:
        print(f"v-border cols {a}..{b}")


def rows(img: np.ndarray, x0: int, x1: int) -> None:
    """Dark-pixel row profile: prints contiguous bands of text-like rows."""
    region = img[:, x0:x1]
    dark = (region.mean(axis=2) < 140).sum(axis=1)
    runs = find_runs(dark > 2)
    for a, b in runs:
        if b - a >= 6:
            print(f"band rows {a}..{b} h={b - a + 1} center={(a + b) // 2} px={int(dark[a:b + 1].max())}")


def main() -> None:
    path = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "sidebar"
    img = load(path)
    if mode == "sidebar":
        sidebar(img)
    elif mode == "card":
        card(img, float(sys.argv[3]) if len(sys.argv) > 3 else 1.5)
    elif mode == "rows":
        rows(img, int(sys.argv[3]), int(sys.argv[4]))
    else:
        raise SystemExit(f"unknown mode {mode}")


if __name__ == "__main__":
    main()
