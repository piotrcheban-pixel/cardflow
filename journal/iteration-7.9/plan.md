# Итерация 7.9 — «Фиксы UI, PDF-сканы и Rich-генерация с поиском картинок»

**Дата:** 2026-11-15 · **Режим:** ИТЕРАЦИИ · **Owner-note:** 3 задачи после успешной генерации.

## 0. Факты на старте (сверено командами)

- `git status --porcelain` → пусто; `HEAD` = `31a5999` (`docs: record green CI for attachment iteration`),
  `origin/main` = `31a5999`. В `journal/STATE.md` было записано `origin/main = 5ac3789` — **исправляется**
  в этой итерации (docs-коммит `31a5999` уже в origin).
- Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; Android SDK/JDK/Xcode отсутствуют (L2).
- Последний локальный прогон 7.8: 1324 passed + 2 skipped, покрытие 92.7 %, analyze 0.
- CI 7.8 (код-снимок `5ac3789`): run 43650756271 — 9/9 job success.

## 1. Задачи итерации

| # | Задача | Затрагиваемые файлы | Проверка |
|---|---|---|---|
| 1 | Отзеркаленный текст обратной стороны «Ленты» | `lib/ui/review/feed_card_view.dart` | widget-тест: у видимой обратной стороны `m00 > 0` (нет зеркалирования), текст читается |
| 2 | PDF-сканы: текст < 50 символов → первые 3–5 страниц в PNG и image parts | `lib/api/parsers/pdf_scan_renderer.dart`, `file_parsing_service.dart`, `lib/domain/generation/generation_attachment.dart`, `generation_chunker.dart`, `lib/ui/generation/generation_screen.dart`, `card_generation_service.dart` | unit-тест рендера (реальный PDFium, PNG-сигнатура), widget-тест проводки: PDF-скан → 4 PNG → один запрос; без Vision — понятная ошибка |
| 3 | Поиск картинок в интернете + `image_query` | `lib/api/images/image_search_service.dart`, `lib/domain/generation/card_image_finder.dart`, `generated_card.dart`, `card_json_schema.dart`, `system_prompt.dart` (gen-ru-v3), `generation_pipeline.dart` | unit-тесты Openverse-клиента на fake Dio, схема/промпт, пайплайн: query → download → image на карточке; ошибка поиска не валит генерацию |
| 4 | `card_type: "occlusion"` и базовая маска | `card_content_validator.dart`, `lib/domain/cards/occlusion.dart`, `drift_generation_card_store.dart`, `card_content_view.dart`, `generation_preview_screen.dart` | валидатор: wire occlusion → basic + `isOcclusion`; пайплайн: нет картинки → basic + пометка; импорт: media-файл + строка `media` + `media_json` + `occlusion_json` |
| 5 | Завершение | ADR-023, docs, STATE, AGENTS | полный прогон, analyze, format, build windows, CI |

## 2. Решения (будут в ADR-023)

1. **`card_type: "occlusion"` — только wire-значение ответа модели.** По SPEC A5 occlusion — не тип
   карточки, а разметка внутри `basic`; в БД/экспорт остаётся `basic` + `occlusion_json` + media.
   Это сохраняет схему БД, экспорт и ручной редактор.
2. **PDF-скан:** если PDF-парсер извлёк < 50 символов (или поднял `scannedPdf`), первые не более 4 страниц
   рендерятся PDFium (pdfrx) в PNG шириной ≤ 1600 px. Страницы одного PDF — один фрагмент запроса
   (несколько image parts). Модель без Vision → `pdfScanVisionRequired`. Если рендер не удался — fallback
   на PDF-документ для Anthropic/Gemini, иначе понятная ошибка.
3. **Поиск картинок — Openverse API** (`https://api.openverse.org/v1/images/`): открытый эндпоинт без ключа
   (анонимный лимит 1 req/s), только CC0/PDM/CC BY/CC BY-SA, скачивается thumbnail (fallback — оригинал),
   JPEG/PNG, ≤ 5 МБ. Картинки **не генерируются**. Ключ не нужен, настройки не меняются.
4. **Пайплайн:** `image_query` → `CardImageFinder` (порт домена) → байты в `GeneratedCard.image`; запись
   файла/строки `media` — при импорте (`DriftGenerationCardStore`), чтобы не плодить файлы для
   неимпортированных карточек. Ошибка поиска не отменяет карточку.
5. **Occlusion без картинки:** карточка понижается до `basic` с пометкой `occlusionImageMissing`, чтобы
   не импортировать заведомо нерабочую карточку. С найденной картинкой — прямоугольная маска по центру
   (x=0.3, y=0.35, w=0.4, h=0.3).

## 3. Критерии приёмки

1. В «Ленте» обратная сторона читается слева направо; тест на матрицу переворота зелёный.
2. PDF-скан без текста с моделью Vision уходит как PNG-страницы, модель без Vision получает
   `generationErrorPdfScanVisionRequired`; ошибка рендера не роняет приложение.
3. Схема ответа содержит `image_query` (`string|null`) и `occlusion` в `card_type`; промпт — `gen-ru-v3`.
4. `ImageSearchService` ищет и скачивает картинку без ключа; пайплайн привязывает её к карточке;
   импорт сохраняет файл в `MediaStore` и `media`, карточка показывает изображение.
5. Occlusion: карточка с найденной картинкой импортируется как `basic` с маской; без картинки —
   `basic` с пометкой и без маски.
6. Полный прогон: `flutter test --coverage --exclude-tags golden`, `analyze` 0, `dart format` 0 changed,
   `flutter build windows --release` — успешно; CI 9/9.

## 4. Риски

- PDFium в `flutter test` на Windows/CI — уже решён L26 (pinned PDFium); рендер в тесте делает реальный PDF.
- Рендер 4 страниц в изоляте может быть медленным на больших PDF — ограничение 4 страниц и ширина 1600.
- Openverse может быть недоступен/rate-limit — сервис молча возвращает `null`, генерация продолжается
  без картинки (L57).
- Память: до 20 картинок на фрагмент; thumbnail ≤ 5 МБ; для MVP приемлемо, зафиксировать в ADR.
- `image_query` увеличивает схему и требует обновления всех тестовых JSON — учесть при red-фазе.
