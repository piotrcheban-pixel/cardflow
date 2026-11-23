"""Статический поиск визуального долга: хардкод кеглей, цветов, отступов."""
from __future__ import annotations

import io
import os
import re
import sys

ROOT = 'lib/ui'
PATTERNS = {
    'fontSize': r'fontSize:\s*[0-9.]+\b',
    'colorLiteral': r'(?:Color\(0x[0-9A-Fa-f]{8}\)|Colors\.[a-zA-Z]+)',
    'radiusLiteral': r'BorderRadius\.circular\((?![A-Za-z_])\s*[0-9.]+',
    'durationLiteral': r'Duration\(\s*milliseconds:\s*[0-9]+',
    'paddingLiteral': r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\([^)]*[0-9]',
}


def main() -> None:
    which = sys.argv[1] if len(sys.argv) > 1 else 'fontSize'
    pattern = re.compile(PATTERNS[which])
    total = 0
    per_file: dict[str, int] = {}
    for dp, _, fs in os.walk(ROOT):
        for f in fs:
            if not f.endswith('.dart'):
                continue
            p = os.path.join(dp, f).replace('\\', '/')
            text = io.open(p, encoding='utf-8').read()
            n = len(pattern.findall(text))
            if n:
                per_file[p] = n
                total += n
    print(f'{which}: {total} occurrences in {len(per_file)} files')
    for p, n in sorted(per_file.items(), key=lambda kv: -kv[1]):
        print(f'  {n:4d}  {p}')


if __name__ == '__main__':
    main()
