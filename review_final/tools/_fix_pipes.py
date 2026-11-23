"""Экранирование вертикальных черт внутри markdown-таблиц (для отчётов аудита)."""
import io
import re
import sys

FILES = [
    'review_final/REPORT.md',
    'review_final/GATES.md',
    'review_final/MEASUREMENTS.md',
    'review_final/CHECKLIST.md',
    'review_final/ANIMATIONS.md',
]

# Лог-ключи вида decks|2k150, classicQ|4k100, IMG 2k150|tall..., MEAS ...|
PATTERNS = [
    re.compile(r'([A-Za-zА-Яа-я_]+)\|(\d+k?\d*)'),
    re.compile(r'(\d+x\d+\|)'),
]


def fix(path: str) -> int:
    text = io.open(path, encoding='utf-8').read()
    out_lines = []
    changed = 0
    for line in text.split('\n'):
        if line.strip().startswith('|') and line.count('|') >= 3:
            new = line
            # внутри ячеек таблицы экранируем "слово|цифра" и "размер|"
            new = re.sub(r'([A-Za-zА-Яа-я_0-9]+)\|(?=\d)', r'\1\\|', new)
            new = re.sub(r'(\d+x\d+)\|(?=[A-Za-zА-Яа-я_])', r'\1\\|', new)
            if new != line:
                changed += 1
            out_lines.append(new)
        else:
            out_lines.append(line)
    io.open(path, 'w', encoding='utf-8').write('\n'.join(out_lines))
    return changed


if __name__ == '__main__':
    for f in FILES:
        try:
            n = fix(f)
            print(f'{f}: {n} lines escaped')
        except FileNotFoundError:
            print(f'{f}: missing')
