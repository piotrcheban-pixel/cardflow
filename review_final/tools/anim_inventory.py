"""Инвентаризация анимаций и длительностей в lib/ui (для ANIMATIONS.md)."""
from __future__ import annotations

import io
import os
import re

PAT = re.compile(
    r'(AnimationController|CurvedAnimation|TweenAnimationBuilder|AnimatedSwitcher|'
    r'AnimatedContainer|AnimatedOpacity|AnimatedAlign|AnimatedPadding|'
    r'AnimatedDefaultTextStyle|SlideTransition|FadeTransition|ScaleTransition|'
    r'RotationTransition|SpringSimulation|animateTo|AppMotion\.|'
    r'Duration\(milliseconds:\s*\d+\)|PageTransitionsBuilder)'
)


def main() -> None:
    rows: list[tuple[str, int, str]] = []
    for dp, _, fs in os.walk('lib/ui'):
        for f in fs:
            if not f.endswith('.dart'):
                continue
            p = os.path.join(dp, f).replace('\\', '/')
            for i, line in enumerate(io.open(p, encoding='utf-8'), 1):
                if PAT.search(line):
                    rows.append((p, i, line.strip()[:130]))
    for p, i, line in rows:
        print(f'{p}:{i}: {line}')
    print(f'\nTOTAL {len(rows)}')


if __name__ == '__main__':
    main()
