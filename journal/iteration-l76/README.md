# Итерация L76 — PDF Visual Intelligence (2026-11-18, ADR-037)

Закрытие ограничения **L76**: извлечение, обработка, сохранение и использование
визуального содержимого PDF при генерации учебных карточек.

## 1. Аудит (факты, проверено по установленным версиям)

**Старт:** `git status --porcelain` → пусто, `HEAD = origin/main = 4d6b992`
(`docs(cleanup): record green CI for cleanup-1`). Прогоны — только с `--no-pub`
(L64).

| Вопрос | Факт |
|---|---|
| Библиотека PDF | `pdfrx 2.12.0` → `pdfrx_engine 0.9.1` (+ `pdfium_flutter 0.4.1` → `pdfium_dart 0.4.1`) |
| Текст | `PdfPage.loadText()` — работает (парсер 3a + 7.10) |
| Рендер страницы | `PdfPage.render()` → `PdfImage` → PNG (`PdfScanRenderer`, 7.9) |
| Image XObject / Form XObject | **нет API**: в `pdfrx_engine` (`PdfPage`, `native/pdfium.dart`) нет `FPDFPage_GetObject`, `FPDFImageObj_*`, `FPDFFormObj_*` (grep: 0 совпадений) |
| Исходное разрешение | недоступно через `pdfrx`; `FPDFImageObj_GetRenderedBitmap` отдаёт растр **в размере на странице** (проверено спайком: изображение 300×200 px, нарисованное 150×100 pt, вернулось 150×100) |
| Координаты | недоступны через `pdfrx`; PDFium: `FPDFPageObj_GetBounds` + `FPDFPageObj_GetMatrix` |
| OCR | OCR-подсистемы в проекте нет (grep по `lib/`: 0 совпадений); текст скана распознаёт vision-модель (ADR-023/027) |
| MediaStore | файловый (`lib/data/transfer/media_store.dart`); парсеры пишут только при импорте карточки (`DriftGenerationCardStore`) |
| Vision | `GenerationAttachment` + `attachment_parts.dart` (OpenAI/Gemini/Anthropic); `DocumentImage` из DOCX **не** отправлялся частями — только каталог `<images>` (пробел, закрыт этой итерацией) |
| Промпт | в коде `gen-ru-v6` (`systemPromptGenRuV6`), файлы v5/v6; `gen-ru-v7` не существовал |

**Решение по библиотеке.** `syncfusion_flutter_pdf` не взят: коммерческая /
community-лицензия Syncfusion, pub.dev license-tag `unknown` (уже отклонён в
`docs/dependencies.md` §4). `pdfx` не нужен — рендер уже даёт `pdfrx`.
Выбран `pdfium_dart 0.4.1` — те же FFI-биндинги, что `pdfrx` использует
транзитивно; нового нативного стека нет.

## 2. Спайки (три гипотезы, все проверены кодом)

**S1. Прямой FFI из «своего» изолята.** `getPdfium()` + `FPDF_LoadMemDocument64`
+ `FPDFPage_CountObjects` работают в изоляте теста **до** `pdfrxInitialize()`.
После `pdfrxInitialize()` тот же вызов падает на `FPDF_LoadPage`:
`Cannot invoke native callback from a different isolate` (VM,
`runtime_entry.cc:5315`). Воспроизведено и в отдельном `Isolate.run`.

**S2. FFI в воркер-изоляте `pdfrx`.** `PdfrxEntryFunctions.instance.compute(...)`
с функцией верхнего уровня: страницы/объекты/метаданные/`FPDFImageObj_GetRenderedBitmap`
читаются, PNG кодируется, результат (класс с `Uint8List`) передаётся между
изолятами. **Работает** — это и стало архитектурой (ADR-037 §1).

**S3. Исходное разрешение.** `FPDFImageObj_GetRenderedBitmap` даёт размер на
странице (потеря качества для сканов 1224×1584 → 612×792). Рендер области
страницы (`FPDFBitmap_Create` + `FPDFBitmap_FillRect` +
`FPDF_RenderPageBitmap(start_x = -x, start_y = -y, size = страница×scale)`) с
масштабом «пиксели изображения / размер на странице» возвращает 300×200 px —
качество сохранено; цветовые пространства/маски обрабатывает PDFium.

## 3. Реализация

- `lib/api/parsers/pdf_image_extractor.dart` — `PdfImageExtractor`,
  `PdfEmbeddedImage`, `PdfImageExtractionRequest/Result`,
  `extractPdfImagesInWorker` (функция уровня библиотеки для `compute`).
- `lib/api/parsers/pdf_page_classifier.dart` — постраничная классификация
  (`textLayer`/`scanned`/`blank`, порог 50 символов).
- `lib/api/parsers/pdf_page_regions.dart` — `PdfPageRegionDetector`
  (сетка анализа, дилатация, связные компоненты, склейка, отсев текста,
  вырезка из полного растра).
- `lib/api/parsers/pdf_scan_pages.dart` — `PdfScanPageExtractor`,
  `PdfScanDocument`/`PdfScanPage`, `documentImages()`, `attachments()`.
- `lib/api/parsers/pdf_scan_renderer.dart` — `renderPages()` с номерами страниц,
  общий `pdfScanPageToPng()`.
- `lib/api/parsers/pdf_parser.dart` — текст + классификация + изображения +
  сканы/области, привязка к разделам (`addImageToSection`).
- `lib/domain/generation/document_image.dart` — `source`/`rect`/`order`
  (обратно совместимо).
- `lib/api/parsers/document_images.dart` — `PdfImageFilter`,
  `pageHasFigureContext`, `pdfPageCaption`, `pdfPageContextText`.
- `lib/api/generation/generation_images.dart` — страница в строке каталога,
  `selectVisionDocumentImages` (приоритет/лимиты/дедуп).
- `lib/api/generation/card_generation_service.dart` — image-части документов
  для Vision-моделей + подпись каталога.
- `lib/api/providers/attachment_parts.dart` — текстовая подпись перед
  image-частью во всех трёх протоколах.
- `lib/domain/generation/generation_chunker.dart` / `generation_run.dart` /
  `generation_pipeline.dart` — `GenerationRunRequest.documentImages` →
  фрагмент своего файла.
- `lib/ui/generation/generation_screen.dart` — скан через
  `PdfScanPageExtractor`, области → `DocumentImage`, оценка токенов.
- Промпт: `systemPromptGenRuV7` (v6 + блок про PDF), `docs/prompts/gen-ru-v7.txt`,
  версия `gen-ru-v7`.

## 4. Тесты и результаты

| Проверка | Результат |
|---|---|
| `fvm flutter test --no-pub test/unit/api/parsers/pdf_document_images_test.dart` | **10 passed** (обычный PDF, Form XObject, без изображений, повторы, иконка, формула с подписью, скан → `scannedPdf`, смешанный PDF, битое изображение) |
| `pdf_page_classifier_test` | **6 passed** |
| `pdf_page_regions_test` | **6 passed** (схема выделяется, текст нет, «вся страница», пустая страница, не-PNG, порядок) |
| `pdf_scan_pages_test` | **5 passed** (реальный PDFium: рендер, области, вся страница, вложения, битый PDF) |
| `pdf_document_images_vision_test` | **6 passed** (vision видит байты + подпись, без Vision — только каталог, лимит 8/каталог полный, дедуп, чужой `image_id`, страница скана) |
| `test/unit/domain/generation/document_image_test.dart` | **7 passed** |
| `generation_chunker_test` | **16 passed** (в т.ч. области скана в свой фрагмент, сироты) |
| `test/integration/pdf_image_flow_test.dart` | **1 passed** (PDF → изображение → запрос к модели с image-part → `image_id` → импорт → файл в `MediaStore` байт-в-байт) |
| Полный прогон | см. `journal/STATE.md` раздела итерации |

## 5. Ограничения

См. `journal/KNOWN_LIMITATIONS.md` L115–L120 (OCR, геометрия областей, векторные
схемы на текстовых страницах, координаты вложенных форм, лимиты, отмена
парсинга).

## 6. Красный CI и причина (найдено 2026-11-18)

Прогон `481f2cb` — по одному падению в `test` на Ubuntu и Windows. После
исключения live-тегов падение повторилось и воспроизвелось локально:
`test/widget/study/study_modes_test.dart` → «карточка с due в будущем пишется
как тренировка». Причина — **тест-бомба с датой**: экран сравнивает `due` с
реальными часами, а фикстура задавала `due = 2026-11-16 12:00 UTC + 2 дня`,
и с 2026-11-18 12:00 UTC эта дата в прошлом → FSRS пишется вместо тренировки.
На базовом коммите `4d6b992` тест падает так же (дефект не внесён итерацией).
Исправление: `due` от текущего момента (+30 дней). Дополнительно закрыто L92:
job `test` → `--exclude-tags golden,live`, диагностическая аннотация печатает
`Failing tests`/`[E]`. Набор CI локально: **1819 passed**.
