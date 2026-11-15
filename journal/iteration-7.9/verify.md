# Итерация 7.9 — verify

**Дата:** 2026-11-15 · Хост: Windows 11, Flutter 3.47.9 / Dart 3.13.7 (FVM).

## Команды и вывод

| Команда | Результат |
|---|---|
| `fvm flutter test --coverage --exclude-tags golden` | **1369 passed + 2 skipped** (`~2 skipped` — live-тесты без ключа в env; отдельный live-прогон см. ниже) |
| `fvm dart run tool/coverage_check.dart --min=80` | **92.8 % (9277/9994)**, порог 80 % пройден |
| `fvm flutter analyze` | `No issues found! (ran in 6.2s)` |
| `fvm dart format lib test` + `--set-exit-if-changed lib test` | 331 файл, **0 changed** |
| `fvm flutter build windows --release` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (80,5 с) |
| `fvm flutter test test/live --tags live` (ключ DeepSeek из Windows User scope, значение не печаталось) | **2 passed**: `LIVE DeepSeek OK: model=deepseek-chat, cards=3, tokens=1351`; `LIVE DeepSeek fallback: strict=400, tolerant=200, max_tokens=8192, cards=2` |

Отдельно проверены production-пути (не только слои):

- рендер PDF-страниц в `Isolate.run` на реальном PDFium — `pdf_scan_renderer_test.dart`;
- production-граф `app_providers` → `GenerationPipeline` → fake HTTP → `ImageSearchService`/
  `FakeCardImageFinder` → реальная drift-БД → `MediaStore` → `media`/`occlusion_json` —
  `test/integration/generation_flow_test.dart` («occlusion + image_query → поиск, media и маска»);
- полный `flutter test` (1369) включает guard-тесты `no_webview`, `ru_strings`, `no_secrets`,
  `architecture` и `ci_pdfium`.

## Критерии приёмки итерации

| # | Критерий | Статус | Доказательство |
|---|---|---|---|
| 1 | Обратная сторона «Ленты» читается слева направо; тест фиксирует отсутствие зеркалирования | **выполнено** | `feed_card_view_test.dart` (2 теста, `m00 > 0`; после анимации); 99,3 % покрытия файла |
| 2 | PDF-скан: < 50 символов → первые ≤ 4 страницы PNG, один фрагмент; модель без Vision — понятная ошибка; сбой рендера — fallback | **выполнено локально** | `pdf_scan_renderer_test.dart` (5 тестов, включая isolate), `generation_screen_test.dart` (4 теста), `generation_chunker_test.dart` (groupKey), `card_generation_service_test.dart` (`pdfScanVisionRequired`); живой Vision — L52/L59 |
| 3 | Схема/промпт `gen-ru-v3`: `image_query`, wire `occlusion`; поиск Openverse без ключа; пайплайн + MediaStore | **выполнено** | `card_schema_test`/`prompt_test`/`content_validator_test`; `image_search_service_test` (8 тестов, fake Dio); `generation_pipeline_test` (6 тестов); `drift_generation_card_store_test` (4 теста); integration production-граф; живой DeepSeek принял v3-схему |
| 4 | Occlusion: базовая прямоугольная маска по центру; без картинки — basic + пометка; карточка показывает изображение | **выполнено** | `occlusion_test` (`kDefaultOcclusionMask`), `generation_pipeline_test`, `drift_generation_card_store_test`, `card_content_test`, `generation_preview_screen_test` |
| 5 | Тесты/analyze/format/build, push и CI | **выполнено** | локальные гейты — см. выше; push `31a5999..63330da`; CI run [`43703387395`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43703387395) — **9/9 job success** (`format + analyze`, `test` × 3 ОС, `build-desktop` × 3, `build-mobile` Android + iOS) |

## Не проверено и почему

- Реальный поиск Openverse (публичная сеть, 429/латентность) — L57.
- Реальная отправка PNG-страниц PDF в Vision-провайдеры (OpenAI/Gemini/Anthropic) — L52/L59.
- Живая генерация с найденной иллюстрацией и живой проверкой occlusion у модели — L57/L52
  (DeepSeek v3-схему принял, но image_query у него обычно `null`).
- Атрибуция CC в БД — L58 (ограничение схемы `media`).
- Замена/удаление иллюстрации basic-карточки в форме — L60.
- Ручная приёмка UI на устройстве (мышь/тач/скринридер) — L11/L37/L42.
