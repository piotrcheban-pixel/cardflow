# Красная фаза 7.19 (TDD)

**Дата:** 2026-11-21. **Снимок:** `16766f8` + тесты. Baseline до тестов:
`fvm flutter test --no-pub --exclude-tags golden` → **2365 passed + 16 skipped**
(`baseline-test.txt`).

Правило ретроспективы 0: красная фаза сохраняет фрагмент вывода с
**ожидаемым** поведением (assertion-level), а не только ошибку компиляции.

## 1. Дефект D1/D2 — заглушка вместо ненайденной картинки

`test/integration/image_placeholder_red_7_19_test.dart` — production-проводка
(`app_providers` → пайплайн → `CardGenerationService` → fake HTTP →
drift-БД → `MediaStore`). Ответ модели — формат v5/v8 с `image_query`; поиск
(`FakeCardImageFinder`) возвращает `null`.

Ожидалось: карточка без изображения, `media` пуст, файлов нет.
Получено (`red-a.txt`):

```
00:00 +0 -1: поиск не дал результата: карточка без изображения, заглушек нет [E]
  Expected: empty
    Actual: [
              MediaRow:MediaRow(id: 2977f311-…, cardId: e9d98afa-…,
                path: media/2977f311-….png, mimeType: image/png, size: 22906)
            ]
  ненайденная картинка не должна подменяться нарисованным PNG
  test\integration\image_placeholder_red_7_19_test.dart 143:5
```

`size: 22906` — нарисованный PNG 800×600: точное подтверждение D1 на
production-проводке.

## 2. Дефект D3 — изображение вопроса на обратной стороне

`test/widget/cards/card_sides_red_7_19_test.dart` — `CardContentView` с
`side: card.back`, `revealed: true`, одна иллюстрация карточки.

Ожидалось: `find.byType(CardImageView)` → `findsNothing`.
Получено (`red-b.txt`): `CardImageView` найден на обратной стороне, потому что
`CardContentView` берёт `card.mediaIds.first` независимо от `side`
(`card_content_view.dart:49`).

## 3. Новые контракты (падают компиляцией до реализации)

Тесты написаны на целевой API итерации — они фиксируют контракт до реализации
(по ретроспективе 0 там, где возможно, — assertion-level; здесь — компиляция,
потому что контракт вводится впервые):

| Файл | Контракт |
|---|---|
| `test/unit/api/generation/image_side_selection_test.dart` | v9: `question_image_ids`/`answer_image_ids`, `image.side`, дубли, неизвестные id, чтение v5/v8 |
| `test/unit/domain/card_media_sides_test.dart` | `CardMediaSides` (media_json v2), `Card.questionMediaIds/answerMediaIds`, `CardDraft` с двумя сторонами и загрузками |
| `test/unit/data/card_media_sides_data_test.dart` | запись/чтение сторон, GC, импорт генерации, пурж заглушек, экспорт/импорт, перезапуск |
| `test/unit/data/media_integrity_test.dart` | сигнатуры изображений, отказ от пустых/повреждённых байтов, `MediaIntegrityChecker` |
| `test/widget/cards/card_sides_display_test.dart` | сторона → изображения; явные состояния «нет файла»/«ошибка декодирования» |
| `test/widget/cards/card_form_sides_test.dart` | независимый редактор обеих сторон: добавление, перенос, порядок, удаление, сохранение |

## 4. Итог

- Красная фаза подтверждает **обе** первопричины из `audit.md` на исполняемом
  коде, а не по предположению.
- Ни один существующий тест не ослаблен и не удалён; новые тесты — только
  добавлены.
- Дальше: green по слоям (pipeline → домен/данные → схема → промпт → UI →
  целостность), отдельный коммит на шаг.
