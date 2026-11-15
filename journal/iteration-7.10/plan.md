# Итерация 7.10 — «Фикс генерации без файлов, PDF и картинок»

**Дата:** 2026-11-15 · **Режим:** ИТЕРАЦИИ · **Источник:** owner note (3 критических бага)

## Сверка со STATE.md

| Что записано | Факт (команды этой сессии) |
|---|---|
| `HEAD = origin/main = 31a5999` (STATE.md §Факты) | `HEAD = origin/main = bdb0bd1` (`docs: record green CI for iteration 7.9`) — STATE отстал на docs-коммит, код-снимок `63330da` + docs |
| рабочее дерево пусто | `git status --porcelain` → пусто |
| 1369 passed + 2 skipped (локально) | baseline: `fvm flutter test --no-pub --exclude-tags golden` → **1369 passed + 2 skipped** |

Замечание окружения: `fvm flutter test` без `--no-pub` зависает на `dart pub get --example`
(сеть pub в этой сессии недоступна/тащится), поэтому все прогоны — `--no-pub`
(зависимости уже разрешены, `.dart_tool/package_config.json` на месте).

## Баги владельца

1. **Без файлов нельзя сгенерировать карточки.** UI требует ≥ 1 файл (`generationNoFilesError`),
   пайплайн при пустых `documents`/`images` не создаёт ни одного фрагмента →
   `GenerationErrorCode.noMaterials`. Пожелания (`<wishes>`) в этом сценарии не используются.
2. **PDF → «Модель вернула неожиданный ответ».** `TextSanitizer` удаляет только ASCII-управляющие
   (`\u0000–\u001F`, `\u007F`); PDFium отдаёт из PDF **C1-управляющие `U+0080–U+009F`** и, при
   битом ToUnicode, **U+FFFD / одиночные суррогаты** — спайк этой сессии:
   `buildPdf('\u0080\u0081\u0082')` → `codes=[128,129,130]`;
   Type0 + ToUnicode → `codes=[65533,65533,65533]` и `codes=[55296,55296]`.
   Такие символы уходят в JSON запроса: провайдер отвечает 400 либо мусорным 200
   (не JSON) → `invalidResponse` → ARB «Модель вернула неожиданный ответ».
   `buildGenerationUserContent` при пустом тексте бросает `ArgumentError` — ещё один путь.
3. **Word: картинки в карточках не появились.** `image_query` есть в strict-схеме, но правило 14
   промпта факультативно («если нужна иллюстрация»), поэтому модель отдаёт `null`.
   Проводка `ImageSearchService` (`cardImageFinderProvider` → `GenerationPipeline.imageFinder`) есть,
   но её вызов и сохранение в `MediaStore` проверены только через `FakeCardImageFinder`.

## Решения (ADR-024)

1. **Prompt-only.** Экран: файлы необязательны; запуск разрешён, если есть пожелания
   (тема/описание). Пайплайн: `chunks.isEmpty` + непустые `wishes` → один фрагмент с пустым
   `materialsText`; `buildGenerationUserContent` допускает пустой `<materials>`; сервис
   `noMaterials` только когда нет ни текста, ни вложений, ни пожеланий. Промпт `gen-ru-v4`:
   пустой `<materials>` + `<wishes>` = тема, карточки по общим знаниям.
2. **PDF.** `TextSanitizer` дополнительно удаляет Unicode Cc/Cf (кроме `\t`, `\n`), одиночные
   суррогаты и заменяет `U+2028/U+2029` на `\n`; `PdfTextQuality` считает долю `U+FFFD`
   после нормализации UTF-8: ≥ 5 замен и ≥ 5 % → `ParserErrorCode.garbledText`
   (ARB «PDF содержит нечитаемый текст»). Диагностика API — `GenerationDiagnostics`:
   debug-only (не в release), редактирует секреты, ограничивает длину; пишет тело ошибки
   провайдера и сырой ответ модели. Для 400 UI уже показывает причину провайдера
   (`providerReason` → `generationErrorBadRequestReason`) — путь закрепляется сквозным тестом.
3. **Картинки.** Промпт v4: для `basic`/`cloze`, если карточка описывает объект, животное или
   понятие — `image_query` **обязателен** на английском. Интеграционный тест поднимает
   production-провайд `cardImageFinderProvider` с `ImageSearchService` поверх fake-Dio
   (Openverse JSON + JPEG) → картинка скачана, прикреплена к карточке, импортирована в `media`.

## Red-фаза (assertion-level)

- `test/unit/api/generation/prompt_test.dart`: версия `gen-ru-v4`, правило пустого `<materials>`,
  обязательный `image_query` для basic/cloze, пустой `<materials>` без `ArgumentError`.
- `test/unit/domain/text_sanitizer_test.dart`: C1, BOM/zero-width, одиночные суррогаты,
  U+2028; идемпотентность.
- `test/unit/api/parsers/pdf_text_quality_test.dart`: порог U+FFFD (5 замен / 5 %),
  нормализация UTF-8 (одиночные суррогаты), читаемый текст без ошибки.
- `test/unit/api/parsers/pdf_parser_test.dart`: программная фикстура Type0/ToUnicode с 10×U+FFFD
  → `ParserErrorCode.garbledText`; PDF с C1-символами парсится и не содержит их.
- `test/integration/generation_flow_test.dart`: (а) без файлов + wishes → HTTP-тело с пустым
  `<materials>` и `<wishes>`, job `done`, `files=[]`; (б) 400 с телом → причина в UI-строке;
  (в) real `ImageSearchService` → картинка → `media`/файл.
- `test/widget/generation/generation_screen_test.dart`: старт без файлов с темой → `run` вызван;
  без файлов и без темы → ARB-строка, `run` не вызван; оценка токенов видна для prompt-only.
- `test/unit/api/http/generation_http_client_test.dart`: тело ошибки уходит в
  `GenerationDiagnostics` (редакция секретов, без release-логов).
- `test/unit/api/generation/card_generation_service_test.dart`: сырой ответ модели пишется в
  диагностику; `image_query` присутствует в каноне.

## Гейты

`fvm flutter test --no-pub --coverage --exclude-tags golden`, `fvm flutter analyze`,
`fvm dart format lib test` + `--set-exit-if-changed`, `fvm flutter build windows --release`,
live DeepSeek (`card_image_query` presence, key из User scope).
