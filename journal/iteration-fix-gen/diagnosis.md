# Диагностика Д4/Д6 (fix-gen, шаг 1)

**Дата:** 2026-11-15 · **Старт:** `HEAD = origin/main = c95e5a9` · **БД приложения:**
`%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite` (копия, read-only).

## 1. «Не удалось обработать фрагмент…» — откуда берётся

Строка — заголовок списка ошибок предпросмотра
(`generationFailuresTitle = «Не удалось обработать фрагменты»`, ARB).
Её показывает `generation_preview_screen.dart`, когда `GenerationRunResult.failures`
непустой. До fix-gen у ошибки был только `GenerationErrorCode` (грубый код:
`invalidResponse`, `truncated`, …) и `details` (в UI не показываются), поэтому
причина «JSON не разобрался» / «схема не сошлась» / «валидатор отверг» была
неразличима. Импорт при этом падал в двух случаях:

1. Все фрагменты упали → карточек 0 → кнопки «Импортировать» неактивны.
2. Частичный успех, но `_import` проверял `CardDraft.isValid` **каждой**
   выбранной карточки и при первой же невалидной делал `return` без импорта.

## 2. Факты `generation_jobs` (реальная БД, 15.11.2026)

| Задание (id) | status | error_code | chunk | cards | tokens | files |
|---|---|---|---|---|---|---|
| `2c56db4e…` | partial | `truncated` | 11 | 80 | 42 552 | PDF (скан, 30 стр.) |
| `300ab344…` | error | `invalidResponse` | 1 | 0 | 0 | — (без файлов!) |
| `2b2d5c61…` | done | — | 1 | 13 | 4 598 | PDF минералы |
| `24605600…` | error | `invalidResponse` | 1 | 0 | 0 | — |
| `f174e507…` | error | `truncated` | 2 | 0 | 0 | PDF (3 стр.) |

Наблюдения:

- **Д1 подтверждается данными:** задание `300ab344…` без файлов и с пожеланием
  упало `invalidResponse` (карточек 0). Тот же сценарий в 7.10 живым тестом
  проходил, значит причина — не «prompt-only запрещён», а разбор ответа.
- `invalidResponse` при 0 карточек и 0 токенов — **до** ответа модели дело не
  дошло (0 usage — провайдер не вернул usage) либо JSON не разобрался.
- `truncated` — реальная вторая причина: фрагмент PDF-скана 30 страниц
  (11 фрагментов), после split-once часть фрагментов всё равно обрезана.
  Владелец видел «фрагменты» после такой генерации.
- Успешные задания (`2b2d5c61…`, 13 карточек) дали `media_json = []` у всех
  карточек — изображения не добавлялись (Д2/Д3).

## 3. Гипотеза JSON-экранирования LaTeX — подтверждена

Спайк: `dart run` над `jsonDecode` с реальными формами ответа (значение —
кодовые точки строки):

```
OK   {"front":"$\\frac{a}{b}$"} -> 24 5c 66 ... | "$\frac{a}{b}$"      (корректно: два слэша)
OK   {"front":"$\frac{a}{b}$"}  -> 24 0c 72 61 63 ...                  (0x0C = form feed + "rac")
OK   {"front":"$\times$"}       -> 24 09 ...                            (0x09 = tab + "imes")
OK   {"front":"$\beta$"}        -> 24 08 ...                            (0x08 = backspace + "eta")
OK   {"front":"$\rho$"}         -> 24 0d ...                            (0x0D = CR + "ho")
OK   {"front":"$\nabla$"}       -> 24 0a ...                            (0x0A = LF + "abla")
FAIL {"front":"$\alpha$"}       -> FormatException: Unrecognized string escape
FAIL {"front":"$\sum$"}         -> FormatException: Unrecognized string escape
FAIL {"front":"$\Delta$"}       -> FormatException: Unrecognized string escape
FAIL {"front":"$\cdot$"}        -> FormatException: Unrecognized string escape
```

Вывод: одна и та же ошибка модели даёт **оба** дефекта — тихую порчу (Д4:
`\f rac`, `\t imes`, `\b eta`, `\rho` → CR+ho, `\nabla` → LF+abla) и падение
фрагмента (Д6: `json_parse`). Фикстуры закреплены в
`test/unit/api/generation/latex_escape_repair_test.dart` (16 проверок).

Дополнительно проверено, что **валидатор отбрасывал весь фрагмент**:

- `CardResponseSchema.validate` проверял документ целиком → одна карточка без
  `back` (или с лишним ключом) → `invalidResponse` на все карточки;
- `CardContentValidator.validateResponse` бросал `_invalidResponse()` при
  первой структурно непригодной записи;
- экран предпросмотра отказывался импортировать пак, если `CardDraft.isValid`
  ложно **у одной** карточки.

## 4. Как сейчас подбираются картинки (до fix-gen)

1. Модель (`gen-ru-v4`) возвращает `image_query` (обязательный для `basic`/
   `cloze` по правилу 14) — на абстрактных определениях часто `null`.
2. Если `image_query` пуст, `derivedImageQuery` (`image_query.dart`) строил
   запрос из текста вопроса для `basic`-определений («Что такое спайность
   минерала?» → `спайность минерала`). Это и давало случайные картинки.
3. `CompositeCardImageFinder`: Wikimedia Commons (поиск по именам файлов) →
   Wikipedia pageimages (ru → en) → Openverse (CC0/PDM/CC BY/CC BY-SA).
4. Бюджет 90 с суммарного времени поиска; после бюджета карточки импортируются
   без картинок; неудача ставит `CardImageIssue.imageNotFound`.
5. Изображения из DOCX/PPTX/ODT **не извлекались**: `ParsedDocument` не нёс
   изображений, `DocxParser`/`PptxParser`/`OdtParser` читали только текст,
   `word/media`, `ppt/media`, `Pictures/` игнорировались.

## 5. Что исправлено (сводка)

| Дефект | Причина | Исправление | Тест |
|---|---|---|---|
| Д4/Д6 | JSON-экранирование LaTeX | `latex_escape_repair.dart`: до разбора удвоение слэшей команд, после — восстановление управляющих символов; нормализация `\(\)`/`\[\]` | `latex_escape_repair_test.dart`, `latex_render_fix_test.dart` |
| Д6 | одна карточка роняет фрагмент | `CardResponseSchema.splitValid` + `CardContentValidator.validateResponseWithRejects` | `failure_reasons_test.dart`, `card_generation_images_test.dart` |
| Д6 | нет причины сбоя | `GenerationFailureReason` → `generation_jobs.error_code` + `GenerationDiagnostics.fragmentFailure` | `generation_fix_gen_test.dart` |
| Д6 | импорт блокируется невалидной карточкой | предпросмотр пропускает невалидные карточки, импорт успешных | `generation_preview_partial_test.dart` |
| Д2 | производный запрос из вопроса | удалён; `image_query` только от модели; абстрактные понятия → `null` | `card_quality_test.dart`, `generation_fix_gen_test.dart` |
| Д3 | изображения файлов не извлекались | `DocumentImage` в `ParsedDocument`, DOCX/PPTX/ODT-парсеры, каталог `<images>`, `image_id` → байты | `document_images_test.dart`, `card_generation_images_test.dart` |
| Д1 | нет явного prompt-only UI | неактивная кнопка + подсказка; имя колоды из темы; пустые блоки одной строкой | `generation_screen_test.dart`, `deck_name_test.dart` |
| Д5 | нет автоматической оценки качества | мягкие проверки валидатора + eval-набор + live-метрика доли пометок | `card_quality_test.dart`, `quality_eval_test.dart`, live-тест |
