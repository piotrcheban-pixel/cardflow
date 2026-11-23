"""Контраст WCAG для пар цветов визуальной системы CardFlow.

Константы взяты из lib/ui/theme/app_tokens.dart (light/dark) и из замеров
пикселей на рендерах. Формула WCAG 2.1 (relative luminance).
"""
from __future__ import annotations


def srgb_to_lin(c: float) -> float:
    c /= 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(hex_color: str) -> float:
    h = hex_color.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * srgb_to_lin(r) + 0.7152 * srgb_to_lin(g) + 0.0722 * srgb_to_lin(b)


def ratio(fg: str, bg: str) -> float:
    l1, l2 = lum(fg), lum(bg)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


PAIRS = [
    # (label, fg, bg, min required)
    ('light body on card', '#0B1C30', '#FFFFFF', 4.5),
    ('light muted text (onSurfaceVariant) on card', '#464555', '#FFFFFF', 4.5),
    ('light overline on card', '#464555', '#FFFFFF', 4.5),
    ('light primary text on surface', '#3525CD', '#F8F9FF', 4.5),
    ('light onPrimary on primary (filled btn)', '#FFFFFF', '#3525CD', 4.5),
    ('rating Again text', '#93000A', '#FFDAD6', 4.5),
    ('rating Hard text', '#0B1C30', '#E5EEFF', 4.5),
    ('rating Good text', '#00714D', '#6CF8BB', 4.5),
    ('rating Easy text', '#0F0069', '#E2DFFF', 4.5),
    ('interval again (tertiary) on card', '#95002B', '#FFFFFF', 4.5),
    ('interval hard (onSurfaceVariant) on card', '#464555', '#FFFFFF', 4.5),
    ('interval good (secondary) on card', '#006C49', '#FFFFFF', 4.5),
    ('interval easy (primary) on card', '#3525CD', '#FFFFFF', 4.5),
    ('danger chip text on errorContainer/2 over white', '#BA1A1A', '#FFECEA', 4.5),
    ('info chip on primaryFixed', '#0F0069', '#E2DFFF', 4.5),
    ('success chip on secondaryContainer', '#00714D', '#6CF8BB', 4.5),
    ('light outline (#777587) on white (helper)', '#777587', '#FFFFFF', 4.5),
    ('light outlineVariant border on white (non-text)', '#C7C4D8', '#FFFFFF', 3.0),
    ('card border on surface (visibility)', '#C7C4D8', '#F8F9FF', 1.2),
    ('dark body on card', '#F1F5F9', '#111827', 4.5),
    ('dark muted on card', '#CBD5E1', '#111827', 4.5),
    ('dark overline on card', '#CBD5E1', '#111827', 4.5),
    ('dark primary text on surface', '#818CF8', '#090E1A', 4.5),
    ('dark filled btn white on #4F46E5', '#FFFFFF', '#4F46E5', 4.5),
    ('dark rating Again', '#FECACA', '#450A0A', 4.5),
    ('dark rating Hard', '#F1F5F9', '#1E293B', 4.5),
    ('dark rating Good', '#A7F3D0', '#065F46', 4.5),
    ('dark rating Easy', '#E2DFFF', '#282463', 4.5),
    ('dark Hard fill vs card surface (button affordance)', '#1E293B', '#111827', 1.3),
    ('dark card border vs background', '#293548', '#090E1A', 1.3),
    ('dark interval again on card', '#FB7185', '#111827', 4.5),
    ('dark interval good on card', '#34D399', '#111827', 4.5),
    ('dark onPrimaryContainer', '#EEF2FF', '#4F46E5', 4.5),
]

if __name__ == '__main__':
    fails = 0
    for label, fg, bg, need in PAIRS:
        r = ratio(fg, bg)
        ok = 'OK ' if r >= need else 'FAIL'
        if r < need:
            fails += 1
        print(f'{ok} {r:5.2f} (need {need:3.1f})  {label}: {fg} on {bg}')
    print(f'\n{len(PAIRS)} pairs, {fails} below requirement')
