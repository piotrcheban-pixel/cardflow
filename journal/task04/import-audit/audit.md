# TASK 04 — аудит: импорт файлов, генерация, изображения, производительность

**Дата:** 2026-11-27 · **Ветка:** `main` · **Старт:** `HEAD = ddfdde0`
(`docs(journal): CI финального снимка 127dd48 — 9/9`), `git status` — только
прежние неотслеживаемые каталоги аудитов (`audit/`, `review_visual/`, …).

**Baseline до изменений:** `fvm flutter test --no-pub --exclude-tags golden` →
**2750 passed + 17 skipped**, `exit 0`.

> Документы `journal/task04/audit.md` и `journal/task04/report.md` относятся к
> прошлой задаче «TASK 04 — мобильный UX/UI» и **не перезаписывались** (нельзя
> терять пользовательские данные). Отчёт по этой итерации — в этом каталоге:
> `journal/task04/import-audit/{audit.md,report.md}`.

Все причины проверены по исходникам зависимостей, коду приложения и данным
`generation_jobs` копии БД владельца (`%APPDATA%\ru.example\cardflow\...\
cardflow.sqlite`), а не угадыванием.

---

## A. PDF на Android: «Не удалось прочитать файл»

**Первопричина (подтверждена по исходникам пакетов).** `PdfParser` (а также
`PdfScanRenderer` и `PdfImageExtractor`) вызывают `pdfrxInitialize()` **без**
`tmpPath`. В `pdfrx_engine 0.9.1`
(`lib/src/pdfrx_initialize_dart.dart`, `_getPdfrxCacheDirectory`) на
не-Windows платформах каталог кэша вычисляется как

```dart
Directory(path.join(Platform.environment['HOME']!, '.pdfrx'))
```

В процессе Android-приложения переменная `HOME` **не задана**; `!` на `null`
бросает `TypeError` **до** открытия документа. `PdfParser.parse` ловил любое
исключение инициализации и переводил его в `ParserErrorCode.unreadableFile`
(«Не удалось прочитать файл»). На Windows ветка `LOCALAPPDATA`, поэтому
дефект не воспроизводился ни локально, ни в CI.

**Дополнительная (не первопричина) гипотеза о `content://`.** Проверено:
`android_file_picker 2.1.5` (`FileUtils.openFileStream` → `PickerPaths
.uniqueCachedFile`) **копирует** выбранный документ в кэш приложения и отдаёт
`PlatformFile.path` на эту копию; `content://` остаётся только в `identifier`.
То есть pdfrx не получал `content://` и сам по себе этот URI PDF не ломал. Но
устойчивости не было: файл без локального пути `readAsBytes()` бросал
исключение, а `pickDocuments` не ловил его — падал весь выбор.

**Условия воспроизведения:** Android (любая версия), любой корректный PDF с
текстовым слоем, release или debug. На Windows/Linux/macOS/CI — нет.

**Последствия:** PDF полностью не поддерживался на телефоне; сканы падали в
fallback-ветку `pdfDocument` без рендера страниц (а для OpenAI-совместимых
протоколов — в ошибку «PDF-скан не поддерживается»).

**Исправление:**
- `lib/api/parsers/pdfium_bootstrap.dart`: `ensurePdfiumInitialized(
  cacheDirectory:)` задаёт `Pdfrx.cacheDirectoryPath` и вызывает
  `pdfrxInitialize(tmpPath: path)`; значение по умолчанию —
  `Directory.systemTemp/cardflow-pdf`, никогда `HOME`;
- `PdfParser`/`PdfScanRenderer`/`PdfImageExtractor` принимают
  `cacheDirectory` (`withCacheDirectory`);
- `FileParsingService` получает каталог в **main-изоляте**
  (`fileParsingServiceProvider` → `path_provider.getTemporaryDirectory`) и
  передаёт строкой в `Isolate.run` (платформенные каналы в фоновом изоляте
  недоступны);
- `FilePickerDocumentGateway` материализует не-`file` URI во временный файл
  приложения, удаляет копию после разбора (`releaseDocument`), ошибку одного
  файла не распространяет на остальные, а полный отказ доступа отдаёт
  `fileAccessDenied`.

**Как проверено:** guard `test/guards/pdfium_android_cache_test.dart` (нет
`pdfrxInitialize()` вне bootstrap, `tmpPath` обязателен, `HOME` не читается),
`test/unit/api/parsers/pdfium_bootstrap_test.dart` (явный каталог приоритетен,
по умолчанию — systemTemp, зависимость от `HOME` отсутствует),
`pdf_parser_test` (битый/пароль/скан/кириллица/120 страниц/пустой файл),
`file_picker_document_gateway_test` (content:// → временный файл → удаление,
нечитаемый URI, большой файл без чтения в память), `file_parsing_service_test`
(каталог запрашивается только для PDF, ошибка поставщика не ломает разбор).
**Живая проверка на Android-устройстве недоступна** (нет SDK/устройства,
L198/L206) — ограничение зафиксировано в `KNOWN_LIMITATIONS` (L210).

---

## B. Форматы: DOC/DOCX/PPT/PPTX/TXT/RTF/MD

**Причины:**
1. `DocumentFormat` не знал `.ppt` вовсе → `documentFormatFromFileName`
   возвращал `null` → общее «формат не поддерживается»;
2. `.doc`/`.xls` отвечали `unsupportedFormat` с текстом «Сохраните файл как
   DOCX или XLSX» — для `.ppt` такого совета не было вовсе;
3. на Android фильтр пикера `FileType.custom` + `allowedExtensions` строится
   по `MimeTypeMap`: у `.md`/`.rtf` MIME может отсутствовать, плагин пишет
   «will not be filtered by the system picker» и файл **не виден** в диалоге;
4. `_pickFiles` показывал общую строку `parserErrorUnreadableFile` на любую
   ошибку пикера, включая отказ доступа.

**Последствия:** пользователь не мог выбрать `.md`/`.rtf` на телефоне;
`.doc`/`.ppt` не получали конкретного совета; отказ доступа к URI выглядел как
«битый файл».

**Исправление:** `DocumentFormat.ppt`, `isSupportedForParsing` исключает
`.doc/.ppt/.xls`, отдельные коды `docFormatNotSupported`/
`pptFormatNotSupported` и строки «Сохраните файл как .docx/.pptx»
(ADR-049, ADR-003), `FileType.any` на мобильных с проверкой расширения при
разборе, коды `corruptFile`/`passwordProtected`/`fileAccessDenied`, показ
причины пикера через `parserErrorCodeMessage`.

**Как проверено:** `formats_task04_test` (DOCX: кириллица «ё», таблица через
табуляцию, картинка с подписью; PPTX: кириллица, два слайда, картинка слайда;
TXT/MD: UTF-8 и Windows-1251; диагностика импорта), `file_parsing_service_test`
(`.doc`/`.ppt` → собственные коды, `.xls`/`.epub` → `unsupportedFormat`),
`parser_error_message_test` (каждый код → непустая уникальная строка ARB),
`generation_screen_test` (`.doc` показывает совет про `.docx`).

---

## C. «Запрошено 50, получено 32»

**Первопричина (найдена в коде, не косметика).** Когда провайдер обрывал
ответ по лимиту вывода (`finish_reason: length` у OpenAI/OpenAI-compatible,
`MAX_TOKENS` у Gemini, `max_tokens` у Anthropic), **адаптер бросал
`GenerationException(truncated)` до разбора тела**. Сервис не разбирал JSON,
пайплайн считал фрагмент упавшим и **выбрасывал все уже полученные карточки**,
хотя в теле лежали десятки полностью закрытых объектов. Затем восстановление
(F.4) уменьшало лимит и слало новый запрос — платно, заново, и пользователь
видел недобор без причины: числа «запрошено/создано/почему» нигде не
объяснялись, а «ограничение контекста» оставалось догадкой.

Дополнительные вклады в недобор:
- недобор партии без ошибки (`deficit`) не всегда добирался, потому что
  раунды `top-up` включались только при `shortfall > 0`, а при
  `achievable == requested` и «модель отдала меньше лимита» дефицит считался
  верно, но причина недобора не доходила до UI;
- исключение при разрешении изображений могло выйти из цикла партии и
  оборвать запуск (см. D).

**Условия воспроизведения:** любой провайдер, у которого ответ упирается в
`max_tokens`/`maximum output`; чаще на заказах 40–100 карточек одной партией.

**Исправление:** `ProviderRawResponse.truncated` вместо исключения;
`CardsJsonExtractor.salvageCards` собирает полные карточки из прерванного
JSON; `GenerationResult.truncated/salvagedCards`;
`GenerationRunResult.truncatedChunks/salvagedCards/imageResolveFailures`;
диагностика `runSummary` с числами; UI-диалог «Создано меньше, чем запрошено»
с причиной и «Продолжить?», строка предпросмотра об обрывах; недостача
добирается существующими раундами `top-up` (ADR-040 §8).

**Как проверено:** `cards_json_extractor_test` (спасение из оборванного JSON,
строки со скобками, обрыв до первой карточки),
`generation_truncation_task04_test` (production-проводка адаптера: обрыв с
полными карточками → 2 карточки сохранены, флаг `truncated`; обрыв без
карточек → доменная ошибка восстановления), `generation_task04_resilience_test`
(заказ 10/50/100, сбой сети в первой партии + обрывы остальных → 50/50 и статус
`done`), `generation_screen_test` и `order_batches_7_20_test` (диалог и строка
предпросмотра), а также существующие `generation_pipeline_v8_test`
(`top-up` до цели) и `adaptive_generation_flow_test`.

---

## D. «Не удалось найти картинку» ломает карточку/чанк

**Причина:** внутри партии поиск уже был `best effort` (`_searchCardImage`
ловит любое исключение, бюджет 90 с суммарного времени), но вызов
`_withCardImages` в цикле партии **не был защищён**: любое исключение вне
`findImage` (например, при разрешении изображений документа или
непредвиденная ошибка домена карточки) выбрасывалось из `_process`, и запуск
падал целиком — уже полученные карточки терялись вместе с заданием.

**Последствия:** одна проблемная картинка могла стоить всего прогона; в UI
«Нет изображения» смешивалось с падением генерации.

**Исправление:** защищённый участок вокруг `_withCardImages`: исключение
сохраняет карточку без картинки (`imageNotFound`), увеличивает
`imageResolveFailures`, пишет диагностику и продолжает партию.

**Как проверено:** `generation_task04_resilience_test` — поиск, который
бросает `StateError`, и поиск, который ничего не находит: все 10 карточек
сохранены, статус `done`, у карточек пометка `imageNotFound` и нет
изображений; `generation_pipeline_test` (существующие кейсы бюджета поиска,
occlusion без картинки, «без finder»).

---

## E. Режим «Лента»: изображение меньше, чем в «Классике»

**Причина:** `feed_card_view.dart` передавал в `CardContentView`
`imageMaxHeight: max(96, min(160, availableHeight * 0.24))`, а
`session_card.dart` — `max(140, availableHeight * 0.42)`; ширина ленты была
`min(textColumn * 0.5, 420)` против `min(columnWidth * 0.36, 420)`; раскладка
«рядом с текстом» включалась по `windowWidth >= 1000` вместо правила
классики `cardWidth >= 760`. На телефоне фото в ленте было в 2–3 раза меньше.

**Последствия:** визуальный дефект «в ленте картинки уменьшили», разные
правила для одного и того же изображения.

**Исправление:** `CardImageBudget.side` — одна функция для обоих режимов
(доля 42 %, минимумы 140/160, ширина колонки до 560; рядом — 36 % колонки до
420 и полная высота), `wideMedia = cardWidth >= 760`, оверлей/лист —
`CardImageBudget.sheet`.

**Как проверено:** `card_image_parity_test` (телефон 390×844: высота фото в
ленте ≥ 85 % от классики и > 160 px; десктоп 1280×900: ширина сопоставима;
юнит-правила бюджета, включая бесконечные ограничения),
`feed_flip_test`/`feed_card_view_test` (регрессии поведения ленты).

---

## F. Лаги анимаций переворота и свайпа

**Причины (три независимые):**
1. `AnimatedBuilder(animation: _flip)` в `SessionCard` и `FeedCardView`
   строил **всё содержимое карточки заново каждый кадр** (в том числе
   `CardContentView`, а в нём — `ImageDimensions.read(bytes)` и создание
   `AnimatedSwitcher`); это микро-фризы при перевороте.
2. `BoxShadow` (`AppShadows.card`) пересчитывался каждый кадр: тень входит в
   `BoxDecoration`, которая пересобирается внутри анимации.
3. `Image.memory` без `cacheWidth` декодировал оригинал (до 4K) в память ради
   слота ~300 px; плюс `_FeedFace` ставил `addPostFrameCallback` в `build` —
   по колбэку на кадр.

**Исправление:** сторона выбирается один раз на середине переворота
(listener контроллера), `AnimatedBuilder` двигает только `Transform` над
`RepaintBoundary(child: face)`; тень рисуется только в покое (`_animating` на
статусах контроллеров); `CardImageView` — `RepaintBoundary` + `cacheWidth` по
слоту и DPR (≤ 4096 px, без апскейла); `_FeedFace` планирует проверку
переполнения не чаще раза на кадр.

**Как проверено:** `card_animation_performance_test` — `CardContentView` внутри
`RepaintBoundary`; экземпляр `CardContentView` идентичен между кадрами
анимации (классика и лента); тени нет во время движения и она возвращается в
покое; `Image.image` — `ResizeImage` с `width ≤ слот × DPR`.

---

## G. Логирование и диагностика

- `ParserDiagnostics` (`lib/api/parsers/parser_diagnostics.dart`, debug-only,
  no-op в release): имя файла, источник (`file`/`content`/`memory`), размер,
  MIME, формат, выбранный парсер, каталог PDFium, страницы/разделы/символы/
  изображения, код ошибки и техническая причина. Текст документа не пишется.
- `GenerationDiagnostics.runSummary`: `запрошено/создано/партий/упало/
  оборвано/спасено/сбоев картинок/исчерпанных разделов`;
  `partialResponse` — сколько карточек спасено из обрыва.

**Как проверено:** `formats_task04_test` (диагностика пишет файл/формат/парсер
и не содержит текст; `enabled: false` — no-op).

---

## H. Пустой ContentInventory

`ParsedDocument` не может быть пустым (инварианты конструктора), а
`GenerationPipeline.run` при `plan.chunks.isEmpty` пишет задание `error`,
бросает `noMaterials` и **не** возвращает «успех с 0 карточек». Это поведение
проверено существующим тестом «нет материала после нарезки — noMaterials,
задание error»; в этой итерации менять его не потребовалось.

---

## Сводка «причина → исправление → проверка»

| # | Первопричина | Файлы | Проверка |
|---|---|---|---|
| A | `pdfrxInitialize()` без `tmpPath` → `HOME!` на Android | `pdfium_bootstrap.dart`, `pdf_parser.dart`, `pdf_scan_renderer.dart`, `pdf_image_extractor.dart`, `file_parsing_service.dart`, `app_providers.dart` | guard + bootstrap/parser/service/gateway тесты |
| B | нет `.ppt`, общий код для `.doc`, MIME-фильтр пикера, общая строка ошибки | `document_format.dart`, `parser_exception.dart`, ARB, `parser_error_message.dart`, `file_picker_document_gateway.dart`, `generation_screen.dart` | `formats_task04_test`, `file_parsing_service_test`, ARB-тесты, widget-тест экрана |
| C | обрыв ответа → исключение → потеря карточек | `generation_provider_adapter.dart`, `openai*_adapter.dart`, `gemini_adapter.dart`, `anthropic_adapter.dart`, `cards_json_extractor.dart`, `card_generation_service.dart`, `generation_result.dart`, `generation_run.dart`, `generation_pipeline.dart`, `generation_diagnostics.dart`, UI генерации | extractor/service/pipeline/widget-тесты |
| D | исключение картинки выходит из цикла партии | `generation_pipeline.dart` | resilience-тесты best effort |
| E | разные формулы размера фото в ленте и классике | `card_image_view.dart` (`CardImageBudget`), `session_card.dart`, `feed_card_view.dart` | parity-тест телефон/десктоп + юнит-правила |
| F | перестройка содержимого каждый кадр, тень каждый кадр, 4K-декод | `session_card.dart`, `feed_card_view.dart`, `card_image_view.dart` | performance-тест (RB, идентичность между кадрами, тень, `cacheWidth`) |
