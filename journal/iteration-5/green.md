# Итерация 5 — зелёная фаза

**Дата:** 2026-11-14 · **Шаг:** 3

## Реализовано

- Домен: строгая модель `OcclusionDocument` (версия 1, нормализованные координаты, immutable),
  cloze-группы, LaTeX-сегменты, расширенный `CardDraft` с медиа/разметкой и валидацией.
- Данные: транзакционное создание/обновление/удаление изображения и `media`, откат при ошибке файла,
  чтение медиа для сессий, безопасный `listMedia`, conservative GC, production-провайдеры и запуск GC.
- UI: общий `CardContentView` в классике и ленте; cloze с пошаговым и общим раскрытием; нативный LaTeX
  с шагами и fallback; occlusion с масками, show/hide; редактор масок pointer-жестами; форма cloze и
  Image Occlusion (picker, рисование, удаление, сохранение).
- Интеграция: `create → export → import` переносит `occlusion_json`, `latex`, медиа; production-экраны
  классики и ленты загружают байты через `CardMediaRepository`.
- i18n: новые строки ARB, `gen-l10n`; guard разрешает только маркер синтаксиса `c` из `{{c1::…}}`.

## Доказательства

```text
fvm dart format lib test                          → 252 files, 0 changed
fvm flutter analyze                               → No issues found! (4.9 s)
fvm flutter test --coverage --exclude-tags golden → 1013 passed + 1 skipped
fvm dart run tool/coverage_check.dart             → 92.8% (6443/6942), порог 80% пройден
```

Новые файлы: domain 4, data 3, UI content 4 + редактор; тесты domain/data/widget/integration.
Следующий шаг — независимое ревью снимка; при отсутствии reviewer — Lead-ревью по чек-листу (L35).
