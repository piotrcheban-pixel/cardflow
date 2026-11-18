# Адаптивная генерация карточек: аудит пайплайна и целевая архитектура

**Статус:** AUDIT + production-интеграция в TASK 02B-FINAL (2026-11-19; факты —
раздел Q). Разделы A–P — снимок TASK 01 (`HEAD = af3172a`); production-код,
лимиты, модели и схема БД на момент аудита **не менялись**.
**Задача:** TASK 01 — CardFlow: generation pipeline audit & adaptive processing architecture.
**Дата:** 2026-11-18. **База:** `main`, `HEAD = af3172a`
(`docs(journal): table of L76 CI runs and runner capacity cancellations`),
`git status --short` → `?? redesign/` (неотслеживаемый пакет владельца).
Все ссылки «файл:строка» даны на этом снимке.
**Связанные документы:** `SPEC.md` A8.1/A8.2/A8.3/A8.4/A8.5/A8.6,
`docs/generation-pipeline.md`, ADR-011/012/013/015/020/021/022/023/024/027/037,
`journal/STATE.md`, `journal/KNOWN_LIMITATIONS.md` (L57–L68, L76–L80, L115–L120, L119).

Правила этого документа:

- **UNKNOWN** — значение, которого нет в репозитории и которое нельзя вывести из кода.
  Такие значения не «додумываются»: для них проектируется явное состояние неизвестности.
- Классификация ограничений: **A** — искусственное продуктовое, **B** — ограничение
  провайдера/API, **C** — инфраструктурное, **D** — защита от runaway.
- Любое утверждение о поведении подтверждено чтением исходников (ссылки в тексте), а не
  предположением.

---

## 0. Контекст и метод

### 0.1 Стартовая сверка (факты команд)

| Проверка | Результат |
|---|---|
| `git status --short` | `?? redesign/` (только каталог владельца; `lib/ui.rar`, записанный в STATE, отсутствует) |
| `git log --oneline -5` | `af3172a`, `9e4bb0f`, `bdc5336`, `19b2c3a`, `9cf28a2` |
| `git branch --show-current` | `main` |
| `journal/STATE.md` | L76 «PDF Visual Intelligence» завершена, следующий шаг — вёрстка по макетам Stitch (L113) |
| Baseline тестов (из STATE/AGENTS) | 1822 passed + 8 skipped, `analyze` 0, `format` 0 (итерация L76) |
| Рабочее дерево | исходники `lib/`, `test/`, `docs/` не изменены этим аудитом |

### 0.2 Расхождения STATE/документации с фактическим кодом

Зафиксированы, исторические записи не переписаны:

1. **STATE, L76.** Последним зафиксирован `bdc5336`; фактический `HEAD = af3172a`
   (два docs-коммита: `9e4bb0f` «record 9/9 green CI», `af3172a` «table of L76 CI runs»).
   Сам факт зелёного CI не меняется; расхождение — только по хешу HEAD.
2. **STATE, L76, рабочее дерево.** Записаны неотслеживаемые `lib/ui.rar` и `redesign/`;
   фактически остался только `redesign/`.
3. **`docs/generation-pipeline.md` устарел** относительно кода (документ описывает
   состояние итерации 3c):
   - «первые ≤ 4 страницы» → фактически `PdfScanRenderer.maxPages = 3`
     (`lib/api/parsers/pdf_scan_renderer.dart:89`);
   - `GenerationModel.contextTokens` → фактически `ProviderAccount.contextTokens`
     (`lib/domain/generation/provider_account.dart:27,74`); `GenerationModel` содержит только
     резервы и формулу (`lib/domain/generation/generation_model.dart`);
   - «вложения — не больше одного файла на MVP-запрос» → фактически фрагмент-группа
     (`groupKey`, страницы одного скана) плюс до 8 image-частей изображений документов
     (`lib/api/generation/generation_images.dart:22`);
   - поиск иллюстраций «Openverse» → фактически цепочка Wikimedia → Wikipedia → Openverse
     → Pixabay/Pexels (`lib/ui/state/app_providers.dart:401-424`);
   - нет описания vision-частей изображений документов (ADR-037).
   Вывод: новые решения оформляются в этом документе; `docs/generation-pipeline.md`
   обновляется в итерации реализации (пункт I, файл 24).

### 0.3 Границы аудита

Не проверялось (в репозитории нет данных): тарифы провайдеров, реальные пределы
изображений/размера запроса у провайдеров, поведения провайдеров при переполнении
контекста (кроме кодов, которые разбирает приложение), live-поведение OpenAI/Gemini/
Anthropic (L1). Всё это в разделе C помечено **UNKNOWN**.

---

## A. Текущий пайплайн генерации (трассировка)

### A.1 Диаграмма потока

```
[UI] lib/ui/generation/generation_screen.dart
  picker/DnD → _attach/_parse (по файлу)
    ├─ JPG/PNG: сигнатура → GenerationAttachment (без ресайза!)
    ├─ парсинг: FileParsingService.parseFile (Isolate.run) → ParsedDocument
    │     └─ PDF с текстом < 50 симв. или scannedPdf:
    │           PdfScanPageExtractor.extractScanPages → PNG-страницы + DocumentImage(области)
    │           (при сбое — fallback: PDF как document-part)
    └─ статусы файла: parsing | parsed | image | scanned | pdfPages | failed
        ↓
_estimatedTokens (эвристика UI: текст + картинки + системный промпт; БЕЗ схемы/каталога/чанков)
        ↓ «Сгенерировать»
GenerationRunRequest{documents, images, documentImages, account, deckName, wishes, targetDeckId}
        ↓ ref.read(generationRunnerProvider)         (lib/ui/state/app_providers.dart:448)
GenerationPipeline.run                           (lib/api/generation/generation_pipeline.dart:137)
 1. systemPromptTokens = estimator.estimate(systemPromptGenRuV7)        :147
 2. job(running) → GenerationJobRepository.save                        :148-159
 3. budget = inputTokenBudget(contextTokens, systemPromptTokens)       :165 (generation_model.dart:28)
 4. chunker.chunkAll(documents, images, budget, documentImages)        :216 (generation_chunker.dart:201)
 5. _withCardLimits(chunks, wishes)                                    :169, :244
 6. пусто → job(error/noMaterials) + throw                             :173-181
 7. estimatedTokens (job-level, приблизительная)                       :183-189
 8. seen = хеши целевой колоды                                         :190-192
 9. _process: последовательный цикл по фрагментам                      :334-497
      for chunk:
        withCatalogIds(chunk.documentImages) → img1…imgN                :372
        progress(sending K из M)                                        :375-381
        caller.generate(GenerationRequest{account, materialsText, wishes,
                       limit, images, documentImages}) → CardGenerationService.generate
                                                       (card_generation_service.dart:92)
          ├─ account.isConfigured? нет → providerNotConfigured          :97-102
          ├─ adapter по protocol                                         :104-106
          ├─ ключ из ApiKeyStore(account.id) → missingApiKey             :107-110
          ├─ _validateAttachments: vision / 10 МБ / PDF-протокол         :116, :316-344
          ├─ TextSanitizer(materials, wishes) → пусто и нет картинок →
          │     noMaterials                                              :118-127
          ├─ materials = текст | имена файлов (image-only)                :128-132
          ├─ buildGenerationUserContent(<materials>,<wishes>,<limit>,<images>)
          │     (generation_prompt.dart:13)                              :136-143
          ├─ _withDocumentImages: supportsVision → selectVisionDocumentImages
          │     (≤ 8 частей, ≤ 24 МБ, дедуп SHA-256, подпись каталога)    :147-151, :288-310
          ├─ _postWithFallbacks (≤ 3 попытки для openai-completions)     :153-162, :212-250
          │     adapter.buildRequest(systemPrompt, userContent,
          │        maxOutputTokens=8192, strictSchema, sendMaxTokens, images)
          │     → httpClient.postJson (Dio; timeouts 15/60/180 c)        :264-280
          │        RetryPolicy: ≤4 попытки, backoff 1..30 c, Retry-After ≤60 c
          │     → adapter.parseResponse: finish_reason length → truncated,
          │        refusal → refused, пустой content → emptyResponse, usage
          ├─ diagnostics.modelResponse (debug-only)                      :166
          ├─ CardsJsonExtractor.decode (BOM, LaTeX-escape repair,
          │     tolerant-извлечение)                                     :168-171
          ├─ CardResponseSchema.splitValid (поштучно; rejectedCards)     :175-182
          ├─ CardContentValidator.validateResponseWithRejects            :183-190
          └─ GenerationResult{cards, usage, rejectedCards}               :191-198
        ошибки: cancelled → стоп; fatal → стоп; truncated && !splitAttempted
                → splitInHalf (1 раз); иначе failure(chunk)              :396-445
        дедуп: contentHashOf(front, back) (+ обратный для basic_reversed) :454-460, :807
        progress(receiving, cards-снимок)                                :461-469
        для каждой новой карточки: _withCardImage                       :470-490, :571
           1) image_id → DocumentImage фрагмента → байты (provider='file')
           2) иначе image.query / image.fallback_query → CardImageFinder
              (бюджет 90 с суммарного поиска, кэш запроса, дедуп URL)
           3) иначе PlaceholderImageGenerator | ничего + CardIssueCode
        _saveProgress(job running, processed, cards, tokens)             :491
10. статус done|partial|error|cancelled, error_code, сохранение job      :499-528
11. GenerationRunResult{cards, failures, tokensUsed, estimatedTokens,
                        duplicatesRemoved, chunkCount, rejectedCards}    :533-546

[UI] GenerationPreviewScreen (generation_preview_screen.dart)
  чекбоксы/редактирование/картинка (убрать, заменить, найти заново)
  «Повторить неудавшиеся» → GenerationPipeline.retryFailed
    (фрагменты восстанавливаются из GenerationChunkFailure: text+images+limit)
  «Импортировать» → DriftGenerationCardStore.importGeneratedCards (одна транзакция)
    дедуп → cards(state=new, fsrs_json) → MediaStore + media → generation_jobs.result_deck_id
        ↓
[UI] экран колоды
```

### A.2 Этапы: вход, функция, артефакт, ошибки

| # | Этап | Вход | Где реализовано | Выход | Ошибки/коды |
|---|---|---|---|---|---|
| 1 | Выбор файлов | пикер/DnD | `file_picker_document_gateway.dart:35-69`, `generation_screen.dart:257-308` | `PickedDocument` | `ParserErrorCode`, ARB |
| 2 | Валидация файла | байты | `file_parsing_service.dart:131-168` | `ParsingOutcome` | `fileTooLarge`, `unsupportedFormat`, `unreadableFile` |
| 3 | Извлечение текста | байты | `lib/api/parsers/*.dart` (`docx/pptx/odt/xlsx/txt/rtf/pdf`) | `ParsedDocument` | `scannedPdf`, `garbledText`, `emptyText`, `encrypted` |
| 4 | PDF-визуал | байты | `pdf_parser.dart`, `pdf_image_extractor.dart`, `pdf_page_regions.dart`, `pdf_scan_pages.dart` | текст + `DocumentImage[]` | fallback `scannedPdf` |
| 5 | Скан-страницы | байты PDF | `pdf_scan_renderer.dart` (`generation_screen.dart:400`) | PNG-страницы, `groupKey` | fallback на PDF-part |
| 6 | Оценка токенов | тексты/картинки | `token_estimator.dart`, `generation_screen.dart:233`, `generation_pipeline.dart:183` | число токенов | — |
| 7 | Бюджет | `contextTokens` | `generation_model.dart:28-39` | `int` бюджет | — |
| 8 | Чанкинг | документы/вложения | `generation_chunker.dart:114-249` | `List<GenerationChunk>` | пусто → `noMaterials` |
| 9 | Лимит карточек | пожелания | `generation_card_limit.dart` | `limit` на фрагмент | `limit < 1` → фрагмент **пропускается** |
| 10 | Сборка запроса | chunk, account | `card_generation_service.dart:92-199`, `generation_prompt.dart` | `ProviderRequest` | `visionUnsupported`, `attachmentTooLarge`, `pdfScanUnsupported` |
| 11 | HTTP | `ProviderRequest` | `generation_http_client.dart:54-88` | JSON | `timeout`, `network`, `rateLimited`, `serverUnavailable`, `invalidApiKey`, `badRequest` |
| 12 | Разбор ответа | JSON | `openai_adapter.dart`, `gemini_adapter.dart`, `anthropic_adapter.dart`, `openai_compatible_adapter.dart` | `ProviderRawResponse` | `truncated`, `refused`, `emptyResponse`, `invalidResponse` |
| 13 | JSON/схема | текст | `cards_json_extractor.dart`, `card_response_schema.dart` | карточки + `rejectedCards` | `invalidResponse` (`json_parse`, `schema_invalid`) |
| 14 | Контент-правила | карточки | `card_content_validator.dart` | `GeneratedCard[]` + `issues` | пометки качества, карточка не отбрасывается |
| 15 | Биллинг-факт | `usage` | адаптеры (`TokenUsage`) | `tokensUsed` | при отсутствии — 0 |
| 16 | Иллюстрации | `image_id`/`image` | `generation_pipeline.dart:571-692`, `lib/api/images/` | `GeneratedCardImage?` | `imageNotFound`, `occlusionImageMissing` |
| 17 | Журнал | прогресс | `drift_generation_job_repository.dart` | `generation_jobs` | `unexpected` |
| 18 | Импорт | карточки | `drift_generation_card_store.dart` | `cards`, `media`, `result_deck_id` | транзакция, дедуп |

Ключевой факт: **все этапы живут в одном приложении**; «сервисов» нет. Единственная
сетевая граница — `GenerationTransport`; единственная граница изолята — парсинг
(`Isolate.run`) и PDFium.

### A.3 Карта вызовов (production-проводка)

`GenerationScreen` → `generationRunnerProvider`
(`lib/ui/state/app_providers.dart:448-457`) →
`GenerationPipeline(caller: cardGenerationServiceProvider, jobRepository:
generationJobRepositoryProvider, cardStore: generationCardStoreProvider, imageFinder:
cardImageFinderProvider, placeholderGenerator: …)`.

`CardGenerationService` (`app_providers.dart:367-374`) получает `generationAdapters`
(`:321-327`), `apiKeyStoreProvider`, `generationHttpClientProvider` (`:358-364`) →
`Dio` (`:333-346`) + `RetryPolicy()` (`:361`).

### A.4 Фактический состав одного запроса

- `system`: системный промпт `gen-ru-v7` (сырой литерал `lib/api/prompts/system_prompt.dart`,
  копия `docs/prompts/gen-ru-v7.txt`, 16 413 символов);
- `user`: `<materials>` (текст фрагмента с `Файл: <имя>`), `<wishes>`, `<limit>`,
  `<images>` (строки каталога `id | файл | подпись | окружающий текст`);
- image/document-части: вложения пользователя (по одной группе на фрагмент) + до 8
  изображений документов (Vision);
- `response_format`/`tools` со схемой A8.4 в проекции протокола;
- `max_tokens`: Anthropic всегда, Gemini `maxOutputTokens`, OpenAI-совместимый — по
  лестнице ADR-021, **OpenAI — не передаёт** (`openai_adapter.dart:24-26,70-88`).

### A.5 Наблюдения по данным (влияют на проект)

1. **Оценки токенов расходятся.** UI (`generation_screen.dart:233-247`) считает системный
   промпт один раз; пайплайн (`generation_pipeline.dart:183-189`) — `chunks.length ×
   (systemPrompt + 512)`; ни одна оценка не включает токены каталога `<images>`, схемы
   ответа, image-частей документов (пайплайн), ретраев и fallback-попыток.
2. **Нет safety margin** в `inputTokenBudget` (`generation_model.dart:33-38`): бюджет
   занимает всё окно минус резерв 8192 и промпт; эвристика 2,5 симв./токен может
   недооценить русский текст — переполнение контекста вероятно на границе.
3. **Малые окна ломаются гарантированно.** Для `moonshot-v1-8k` (`contextTokens: 8000`,
   `provider_preset.dart:219`) формула даёт отрицательное значение и клампится в
   `kMinInputTokenBudget = 2000` (`generation_model.dart:19,38`); 2000 + ~6566 (промпт) +
   ожидаемый вывод > 8000 → любой запрос превышает окно. Обработки «context length
   exceeded» нет (см. B.5, п.1).
4. **Потеря контента при малом заказе карточек.** `_withCardLimits` распределяет общее
   число по фрагментам (`generation_card_limit.dart:54-126`); фрагменты с `limit == 0`
   молча пропускаются (`generation_pipeline.dart:368-371`). «1 карточка» на 3 фрагмента →
   2 фрагмента не обрабатываются.
5. **Молчаливое урезание запрошенного числа.** `kMaxRequestedCards = 200`
   (`generation_card_limit.dart:12,44`) и `capped = maxPerChunk × chunks`
   (`:62-63`) уменьшают заказ без сообщения пользователю.
6. **Все сбои фрагментов «retryable».** `GenerationChunkFailure.retryable` всегда `true`
   (`generation_run.dart:105`), никто не ставит `false` → кнопка «Повторить неудавшиеся»
   повторяет и детерминированные ошибки (`visionUnsupported`, `attachmentTooLarge`,
   `pdfScanUnsupported`), тратя запросы.
7. **Нет ограничения совокупного размера запроса.** Валидируется каждый файл ≤ 10 МБ
   (`card_generation_service.dart:331`), а image-части документов ≤ 24 МБ
   (`generation_images.dart:25`), но группа «3 страницы скана (до 10 МБ каждая) + 8
   image-частей» даёт тело до ~54 МБ (base64 ≈ 72 МБ) без единой проверки.
8. **Никакой предобработки изображений**: ресайза/перекодирования нет (проверено
   поиском по `lib/`), байты уходят как есть; лимиты провайдера на сторону/байты не
   моделируются (только приложение).
9. **Факт биллинга неполный**: `tokensUsed` суммирует `usage.totalTokens ?? 0`
   (`generation_pipeline.dart:448`), т.е. при отсутствии `usage` расход «0»; цены нет
   вообще (раздел C).

---

## B. Полный перечень существующих ограничений

### B.1 Классификация

- **A — искусственное продуктовое**: не вытекает из API/инфраструктуры, ограничивает
  валидную генерацию, должно быть удалено или заменено расчётом.
- **B — провайдер/API**: существует на стороне сервиса; приложение обязано его
  уважать и обходить оркестрацией (дробление, уменьшение вывода), а не игнорировать.
- **C — инфраструктурное**: память, размер тела, диск, время; требует масштабируемого
  решения (потоковая обработка, бюджеты), а не удаления.
- **D — защита**: от runaway-запросов, бесконечных повторов, OOM; остаётся.

### B.2 Реестр (все найденные точки)

Все строки проверены по коду на `HEAD af3172a`.

#### B.2.1 Документы, файлы, парсинг

| ID | Файл:строка | Значение | Где применяется | Класс | Мешает валидной генерации | Предложение |
|---|---|---|---|---|---|---|
| L-01 | `lib/data/generation/file_picker_document_gateway.dart:29` | `maxFileBytes = 25 МБ` | чтение файла до памяти | C | да, для больших PDF/конспектов | оставить как политику, вынести в конфиг; чтение потоково/порциями там, где возможно |
| L-02 | `lib/api/parsers/file_parsing_service.dart:75,141-146` | дубль лимита 25 МБ | второй барьер после шлюза | C | нет (дубль) | один источник политики (передавать из шлюза) |
| L-03 | `lib/data/generation/file_picker_document_gateway.dart:21,38` | изображения только `jpg/jpeg/png` | фильтр пикера | A | да: WebP/HEIC/GIF отклоняются до парсинга | принимать форматы, которые умеет декодировать платформа; иначе — явная причина (L77) |
| L-04 | `lib/api/parsers/zip_xml.dart:15-17` | 10 000 записей / 32 МБ запись / 120 МБ сумма | ZIP-форматы | D | нет | оставить (безопасность), вынести в конфиг |
| L-05 | `lib/api/parsers/pdf_scan_renderer.dart:89` | `maxPages = 3` | рендер страниц скана | A | да: страницы скана после 3-й не уходят изображениями | планировщик: все страницы как единицы контента, группы по возможностям модели/бюджету запроса |
| L-06 | `lib/api/parsers/pdf_scan_renderer.dart:89` | `maxWidth = 1600 px` | рендер PNG | A | да: мелкий текст на схемах | ресайз под требования модели (image preprocessing), конфигурируемо |
| L-07 | `lib/api/parsers/pdf_parser.dart:43` | `maxScanPages = 3` | области страниц | A | да | то же, что L-05 |
| L-08 | `lib/api/parsers/pdf_parser.dart:44,355-356` | `maxImages = 24` на PDF | изображения документа | A/C | да: 25-й рисунок теряется | не обрезать молча: приоритизация + `omitted` в плане; лимит — бюджет памяти |
| L-09 | `lib/api/parsers/pdf_image_extractor.dart:35` | `kMaxPdfImages = 60` | извлечение XObject | C/D | да, для больших книг | конфигурируемо + отчёт об усечении |
| L-10 | `lib/api/parsers/pdf_image_extractor.dart:32,38,42` | ≥32 px, ≤16 Мп, ≤2600 px сторона | guard-фильтры | C | нет (защита) | оставить; связать с моделью (ресайз вместо отбрасывания) |
| L-11 | `lib/api/parsers/pdf_page_regions.dart:79` | `maxRegions = 3` на страницу | области скана | A | да: 4-я схема теряется | конфиг + план (бюджет), отчёт об усечении |
| L-12 | `lib/api/parsers/document_images.dart:19,22` | мусор < 4 КБ / < 64 px | фильтр | D | нет | оставить (качество), значения — конфиг |
| L-13 | `lib/api/parsers/pdf_page_classifier.dart:12` | 50 символов = «скан» | классификация страниц | A (эвристика) | может: страница с подписью уходит как скан | конфиг; решение по странице, а не по документу (уже так) |
| L-14 | `lib/api/parsers/pdf_text_quality.dart:14-15` | 5 замен / 5 % | «нечитаемый текст» | D | нет | оставить |

#### B.2.2 Чанкинг, бюджеты, карточки

| ID | Файл:строка | Значение | Где применяется | Класс | Мешает валидной генерации | Предложение |
|---|---|---|---|---|---|---|
| L-15 | `lib/domain/generation/generation_model.dart:9` | резерв вывода 8192 | бюджет входа | A | да: для моделей с меньшим выводом резерв завышен, для больших — занижен | резерв = ожидаемый вывод из `limit` и возможностей модели |
| L-16 | `lib/domain/generation/generation_model.dart:13,16,19,22` | 16 000 / 8 000 / 2 000 / 512 | бюджет и минимальный бюджет | A | да: клампинг 2000 гарантирует переполнение на окнах < ~17k | убрать клампинг; при нехватке бюджета — явная ошибка плана; 512 заменить оценкой обёртки |
| L-17 | `lib/domain/generation/generation_model.dart:28-39` | формула `context − 8192 − prompt − 512` | бюджет | A | да: нет safety margin, нет отдельного входного лимита провайдера | `effectiveInputBudget` из раздела D |
| L-18 | `lib/domain/generation/provider_account.dart:15,27,163-165` | `contextTokens = 16000` по умолчанию | бюджет для custom/старых записей | A | да: окно реальной модели неизвестно, для 8k — переполнение, для 128k — лишние запросы | явное состояние «окно неизвестно» + поле в настройках; не подставлять магическое число молча |
| L-19 | `lib/domain/generation/generation_chunker.dart:11` | `kMaxCardsPerChunk = 20` | `<limit>` каждого фрагмента | A | да: больше 20 карточек за один проход невозможно даже при бюджете | `limit` = min(распределённый заказ, потолок по бюджету вывода, потолок модели/конфиг) |
| L-20 | `lib/domain/generation/generation_chunker.dart:14` | `kImageTokenEstimate = 1000` | оценка изображения | A | да: искажает бюджет на 2 порядка для крупных схем | оценщик по размерам/провайдеру (раздел E.4) |
| L-21 | `lib/domain/generation/generation_chunker.dart:320` | `splitInHalf` запрещён для фрагментов с картинками | восстановление при `truncated` | A | да: фрагмент с картинкой не дробится вовсе | дробление по контент-единицам с сохранением изображений |
| L-22 | `lib/domain/generation/generation_chunker.dart:401-451` | жёсткое деление по символам, запас 0,8 | слишком большой раздел | D (граница) | нет, но рвёт формулы/слова | деление по предложениям; жёсткое — последним средством |
| L-23 | `lib/api/generation/generation_pipeline.dart:406-416` | split-once по `splitAttempted` | восстановление после `truncated` | A | да: второй обрез не лечится | `splitDepth` до 3 + бюджет попыток (раздел F) |
| L-24 | `lib/domain/generation/generation_card_limit.dart:12,44` | `kMaxRequestedCards = 200` | разбор числа из пожеланий | A | да: «500 карточек» молча становится 200 | потолок-предохранитель (конфиг), не влияющий на заказ без предупреждения |
| L-25 | `lib/domain/generation/generation_card_limit.dart:62-63` | `capped = maxPerChunk × chunks` | распределение | A | да: сумма заказа уменьшается | предупреждение в плане + подтверждение |
| L-26 | `lib/api/generation/generation_pipeline.dart:368-371` | `limit < 1` → фрагмент пропускается | потеря контента | A | да, критично | минимум 1 карточка на непустой фрагмент; либо уменьшить число фрагментов, либо подтвердить превышение |
| L-27 | `lib/ui/generation/generation_screen.dart:56,895-903` | порог предупреждения 100 000 токенов | UI | A | да: предупреждение не связано с реальным бюджетом (для окна 8k — 2k) | бюджет-осведомлённые предупреждения (раздел H) |

#### B.2.3 Изображения и vision

| ID | Файл:строка | Значение | Где применяется | Класс | Мешает валидной генерации | Предложение |
|---|---|---|---|---|---|---|
| L-28 | `lib/domain/generation/generation_attachment.dart:11` | 10 МБ на вложение | `card_generation_service.dart:331` | A/C | да (Anthropic-лимиты меньше, OpenAI/Gemini — больше) | лимит из возможностей аккаунта + ресайз/перекодирование; общий лимит тела |
| L-29 | `lib/api/generation/generation_images.dart:22` | ≤ 8 image-частей документов | vision-запрос | A | да: 9-я иллюстрация не видна модели | из возможностей модели/бюджета тела; не вошедшие — в каталоге и разрешаются при импорте |
| L-30 | `lib/api/generation/generation_images.dart:25` | ≤ 24 МБ суммарно | image-части | C | да, косвенно | бюджет всего тела запроса (текст + изображения + base64) |
| L-31 | `lib/api/generation/generation_images.dart:98-103` | молчаливое `break`/`continue` при превышении | выбор частей | A | да, без отчёта | возвращать `selected` + `omitted` с причинами; отчёт в план/UI |
| L-32 | `lib/domain/generation/document_image.dart:19` | контекст ≤ 160 символов | каталог `<images>` | A | да: связь рисунка с абзацем теряется | включать контекст по бюджету; усечение — с пометкой в плане |
| L-33 | `lib/api/generation/generation_images.dart:129-137` | `_clean(maxLength: 80)` | файл/подпись | A | да | то же; лимит по бюджету |
| L-34 | `lib/ui/generation/generation_screen.dart:240-243` | оценка vision ≤ 8 частей | UI-оценка | A | нет (согласовано с L-29), но зашито число | оценка из плана |
| L-35 | `lib/domain/generation/provider_account.dart:216-231` | vision по имени модели (`gpt-4o`, `flash`, `vl`…) | legacy/новые записи | A (инференс) | может включать/выключать vision неверно | оставить только как legacy-инференс; в UI — явный переключатель и «неизвестно» |
| L-36 | `lib/domain/generation/provider_protocol.dart:57-63` | PDF только Anthropic/Gemini | протокол | B (факт протокола в приложении) | да для OpenAI-совместимых: PDF-скан уходит страницами | оставить как fallback; страницы — основной путь |

#### B.2.4 Сеть, повторы, эксплуатация

| ID | Файл:строка | Значение | Где применяется | Класс | Мешает валидной генерации | Предложение |
|---|---|---|---|---|---|---|
| L-37 | `lib/api/http/retry_policy.dart:63-66` | ≤ 4 попытки, 1–30 c, Retry-After ≤ 60 c | транспорт | D | нет | оставить; учитывать в оценке запросов/стоимости |
| L-38 | `lib/api/generation/card_generation_service.dart:212-250` | ≤ 3 запроса на фрагмент (лестница ADR-021) | совместимость | D | нет, но умножает стоимость | оставить; включать в оценку и в бюджет повторов |
| L-39 | `lib/ui/state/app_providers.dart:333-340` | 15/60/180 c | Dio | D | нет | оставить; для больших запросов (1M окно) поднять receive-таймаут по возможностям |
| L-40 | `lib/api/generation/generation_pipeline.dart:73` | бюджет поиска картинок 90 c | иллюстрации | D | нет | оставить; вынести в настройки |
| L-41 | `lib/api/images/image_search_service.dart:35-40` | 6 c/провайдер, 20 c/карточка, 4 загрузки | поиск картинок | D | нет | оставить |
| L-42 | `lib/api/generation/generation_diagnostics.dart:18` | 2000 символов debug | debug | D | нет | оставить |
| L-43 | `lib/api/generation/card_content_validator.dart:86,89,92,95` | front 500 / back 2000 / tags 3 / soft 200 | пометки качества | D (продуктовое правило промпта) | нет (пометка, не отброс) | оставить |
| L-44 | `lib/domain/generation/generation_card_limit.dart:19-47` (парсинг только из пожеланий; поля в форме нет — `generation_screen.dart:905-916`) | заказ карточек только текстом | UX | A | да: числа карточек нет в форме | ввести числовое поле «сколько карточек» (опционально) с бюджетом и оценкой |

### B.3 Итог по классам

Ниже — сводка по классам; **точное действие по каждому пункту — в B.4**.

- **Удалить/заменить расчётом (A):** L-15, L-16, L-17, L-18, L-19, L-20, L-21,
  L-23, L-24, L-25, L-26, L-27, L-29, L-31, L-32, L-33, L-34, L-28 (в части
  «универсальный 10 МБ»), L-05, L-06, L-07, L-11, L-08 (в части «обрезать молча»).
- **Сделать конфигурируемыми:** L-01/L-02 (единая политика), L-03, L-09, L-13,
  L-40, L-43.
- **Оставить (B):** L-36 и любые реальные ограничения провайдера; они выносятся в
  `ModelCapabilities` (как данные), а не в код пайплайна.
- **Оставить (C/D):** L-04, L-10, L-12, L-14, L-37, L-38, L-39, L-41, L-42.

### B.4 Решение по каждому ограничению

Действия: **удалить** — убрать из кода; **конфиг** — оставить как настройку/политику;
**возможности** — заменить на данные `ModelCapabilities` (capability detection);
**расчёт** — заменить вычислением (бюджет/план/отчёт); **оставить** — технически
необходимо (B/C/D), менять только параметризацию.

| ID | Действие | Замена/обоснование |
|---|---|---|
| L-01 | конфиг | единая политика размера файла; потоковое чтение там, где возможно |
| L-02 | удалить (дубль) | один источник политики из шлюза |
| L-03 | конфиг + возможности | форматы по доступным декодерам; иначе понятная ошибка |
| L-04 | оставить (D), конфиг | защита ZIP-парсеров |
| L-05 | расчёт (планировщик) | страницы скана — единицы контента; группы по лимитам |
| L-06 | конфиг + расчёт | ресайз под требования модели вместо фиксированных 1600 px |
| L-07 | расчёт (планировщик) | то же, что L-05 |
| L-08 | расчёт + отчёт | приоритизация изображений, `omitted` вместо молчаливого среза |
| L-09 | конфиг + отчёт | бюджет памяти, отчёт об усечении |
| L-10 | оставить (C), связать с ресайзом | guard-фильтры + уменьшение вместо отбрасывания |
| L-11 | конфиг + отчёт | число областей из бюджета, `omitted` |
| L-12 | оставить (D) | фильтр мусора |
| L-13 | конфиг | порог «скан» настраиваемый |
| L-14 | оставить (D) | проверка читаемости PDF |
| L-15 | расчёт | резерв = ожидаемый вывод по `limit` и возможностям |
| L-16 | удалить клампы; конфиг `minWorkableInputTokens` | 512/2000/16000/8000 заменяются `GenerationBudget` |
| L-17 | расчёт | `effectiveInputBudget` (D.1) вместо фиксированной формулы |
| L-18 | возможности + UI | явное «окно неизвестно» + поле ввода пользователя |
| L-19 | возможности + расчёт | потолок карточек из бюджета вывода/модели |
| L-20 | расчёт (ImageTokenModel) | оценка по размерам/провайдеру (E.4) |
| L-21 | расчёт (recovery) | дробление по единицам с сохранением изображений |
| L-22 | оставить как последнее средство | деление по предложениям до жёсткого среза |
| L-23 | расчёт (recovery) | `splitDepth` + бюджет попыток |
| L-24 | конфиг-предохранитель + предупреждение | заказ не режется молча |
| L-25 | расчёт + предупреждение | распределение без потерь (D.7) |
| L-26 | удалить | минимум 1 карточка на непустой фрагмент |
| L-27 | расчёт | предупреждения по плану/бюджету (раздел H) |
| L-28 | возможности + расчёт | лимит из аккаунта, ресайз, общий бюджет тела |
| L-29 | возможности + расчёт | число частей из возможностей/бюджета |
| L-30 | расчёт | бюджет всего тела запроса |
| L-31 | расчёт + отчёт | `selected`/`omitted(reason)` без молчаливых потерь |
| L-32 | расчёт + отчёт | контекст по бюджету, усечение с пометкой |
| L-33 | расчёт + отчёт | то же |
| L-34 | расчёт | оценка из плана, без зашитого числа |
| L-35 | оставить (I) + UI | legacy-инференс; явный переключатель и «неизвестно» |
| L-36 | оставить (B) | ограничение протокола, fallback страницами |
| L-37 | оставить (D) | повторы/backoff |
| L-38 | оставить (D) | лестница совместимости, учесть в оценке |
| L-39 | оставить (D), конфиг | таймауты по возможностям |
| L-40 | оставить (D), конфиг | бюджет поиска иллюстраций |
| L-41 | оставить (D) | таймауты/параллелизм поиска |
| L-42 | оставить (D) | debug-диагностика |
| L-43 | оставить | продуктовые правила качества |
| L-44 | конфиг + UI | числовое поле «сколько карточек» с бюджетом |

### B.5 Дефекты, найденные попутно (не «лимиты», но блокируют задачу)

1. **Нет обработки переполнения контекста.** Классификатор HTTP
   (`generation_http_client.dart:194-281`) сводит 400/413 к `badRequest`; пайплайн
   дробит только `truncated` (`generation_pipeline.dart:406-416`). Значит запрос,
   превысивший окно/размер тела, просто помечается ошибкой фрагмента и повторяется
   кнопкой без изменения. Это главный практический блокер «очень больших документов».
2. **`retryable` всегда true** (`generation_run.dart:105`) → повтор
   `visionUnsupported`/`attachmentTooLarge`/`pdfScanUnsupported` заведомо бесполезен.
3. **`splitInHalf` теряет каталог изображений** (у детей `documentImages: const []`,
   `generation_chunker.dart:341-354`) → после дробления `image_id` из ответа модели не
   разрешается (пункт A.5).
4. **Нет предварительной проверки выполнимости плана**: «single unit больше бюджета»
   (например, один абзац 200k символов при окне 8k) обрабатывается только
   `_hardSplit` по символам, без явного состояния плана.
5. **Порядок ошибок при Vision**: `_validateAttachments` бросает по первому файлу
   (`card_generation_service.dart:316-344`), остальные не проверяются — сообщение
   может быть про PDF, хотя проблема в размере другого файла.
6. **`generation_jobs` не хранит план/оценку**: только `chunk_count`, `cards_count`,
   `tokens_used`, `error_code` (`lib/data/db/tables.dart:226-267`) → после сбоя нельзя
   восстановить, что именно планировалось (оценка живёт только в памяти результата).

---

## C. Возможности провайдера и модели

### C.1 Как устроено сейчас

| Что | Где | Формат |
|---|---|---|
| Каталог провайдеров/моделей | `lib/domain/generation/provider_preset.dart:96-281` | статический `const` в коде приложения |
| Окно контекста модели | `ProviderPresetModel.contextTokens` (`provider_preset.dart:29`) | число в каталоге |
| Vision модели | `ProviderPresetModel.supportsVision` (`provider_preset.dart:32`) | bool в каталоге |
| Аккаунт | `lib/domain/generation/provider_account.dart` | JSON v1 в `app_settings` (`generation.providers`): `id,label,preset_id,protocol,base_url,model,context_tokens,requires_api_key,supports_vision` (`:117-127`) |
| Окно custom-аккаунта | `kCustomProviderContextTokens = 16000` (`provider_account.dart:15,27,163-165`) | константа; **UI-поля нет** (проверено `generation_settings_screen.dart`, `provider_account_dialogs.dart`) |
| Макс. вывод | `CardGenerationService.maxOutputTokens = 8192` (`card_generation_service.dart:47`) | константа; модели не знают |
| Цены | — | **отсутствуют в репозитории** |
| Точный токенизатор | — | отсутствует; эвристика `TokenEstimator(charsPerToken: 2.5)` (`token_estimator.dart:15`) |
| JSON-вывод | протокол (strict/лестница/tools/responseSchema) | `generation_provider_adapter.dart`, ADR-021 |
| PDF как документ | `ProviderProtocol.supportsPdfAttachments` (`provider_protocol.dart:57-63`) | enum-свойство |

### C.2 Матрица возможностей: значение, источник, проверенность

Обозначения источника: **P** — статический каталог приложения, **U** — пользовательский
ввод (JSON/UI), **I** — вывод из имени/протокола, **?** — отсутствует.

| Возможность | Значение сейчас | Источник | Проверено в репозитории | Комментарий |
|---|---|---|---|---|
| Окно контекста | 8 000–1 048 576 по пресетам (`provider_preset.dart:106…276`) | P | **нет** (нет ссылок на документацию/дату) | 16 000 для custom (U отсутствует) |
| Макс. вход | = окно (отдельного лимита нет) | I | нет | у части провайдеров вход и выход ограничены раздельно — **UNKNOWN** |
| Макс. вывод | 8192 на все модели | P (жёстко) | нет | Anthropic требует явно, OpenAI adapter не передаёт |
| Цена входа/выхода | — | ? | — | **UNKNOWN**; оценка стоимости невозможна без ввода |
| Модальности | `supportsVision`, PDF по протоколу | P/I/U | нет | vision-toggle для custom (`provider_account_dialogs.dart:343,403-409`) |
| Макс. изображений/запрос | 8 (только документные части) | P (константа) | нет | вложения пользователя — по одной группе на фрагмент |
| Макс. байт изображения | 10 МБ на вложение, 24 МБ на части документов | P | нет | реальные пределы провайдеров **UNKNOWN** |
| Макс. сторона изображения | 1600 px (рендер) / 2600 px (PDF-картинка) | P | нет | требований моделей нет |
| JSON output | strict schema / tools / responseSchema | P | частично (live DeepSeek) | нет декларативной возможности «strict schema supported» |
| Токенизатор | нет | ? | — | **UNKNOWN** |
| Ограничения запроса | `max_tokens`-лестница, PDF-протокол, таймауты | P | ADR-021 | нет данных о пределе размера тела |

### C.3 Целевая модель `ModelCapabilities` (новый файл, раздел J)

Проект исходит из того, что **все значения nullable** и имеют источник. Значение
попадает в планировщик только с пометкой источника; отсутствие значения — это не «0»
и не «по умолчанию 20 карточек», а состояние «неизвестно» с явной стратегией.

```dart
// lib/domain/generation/model_capabilities.dart (проект, не реализовано)
enum CapabilitySource { verified, preset, user, inferred, unknown }

class ModelCapabilities {
  final int? contextWindowTokens;   // общий контекст
  final int? maxInputTokens;        // если провайдер публикует отдельный входной лимит
  final int? maxOutputTokens;       // жёсткий лимит вывода
  final int? maxCardsPerRequest;    // если провайдер/модель ограничивает структурированный вывод
  final int? maxImagesPerRequest;
  final int? maxImageBytesPerImage;
  final int? maxImageBytesPerRequest;
  final int? maxImageSidePx;
  final int? maxRequestBytes;       // тело запроса
  final bool supportsVision;
  final bool supportsPdfDocumentPart;
  final bool supportsStrictJsonSchema;
  final TokenizerKind tokenizer;    // exact | heuristic | unknown
  final ImageTokenModel imageTokens;
  final GenerationPricing? pricing; // null = неизвестно
  final CapabilitySource contextSource, outputSource, imageSource, pricingSource;
}
```

Порядок разрешения: **user (аккаунт) → verified preset → protocol default → unknown**.
Никаких чисел «из головы»: каталог может содержать значение только вместе с
`sourceDocument`/`verifiedAt` (поля метаданных), иначе значение остаётся `null`.

`ProviderAccount` получает JSON **v2** (см. раздел K): `max_output_tokens`,
`max_images_per_request`, `max_image_bytes`, `max_request_bytes`, `pricing
{input_per_mtok, output_per_mtok, currency}`, `capabilities_source`. Чтение v1
обязательно (все новые поля `null`, поведение — как «неизвестно»).

### C.4 Провайдеры: как представлены и что это значит

- **OpenAI** (`provider_protocol.openai`): фиксированный `base_url` пресета, strict
  `response_format`, `max_tokens` не отправляется. Возможности протокола известны
  (strict/vision), лимиты модели — **UNKNOWN**, кроме окна каталога (P).
- **Anthropic** (`anthropicMessages`): `max_tokens` обязателен; PDF через
  `anthropic-beta`; инструмент `emit_cards`. Размер изображения/PDF и максимум
  изображений — **UNKNOWN** в репозитории.
- **Gemini** (`geminiGenerateContent`): `responseSchema`, `maxOutputTokens`, PDF
  `inlineData`. Ограничения inline/изображений — **UNKNOWN**.
- **OpenRouter**: представлен как `openai-completions` с `baseUrl
  https://openrouter.ai/api/v1` и статическим списком моделей
  (`provider_preset.dart:180-204`). Это агрегатор: у него есть собственные метаданные
  моделей (цены/лимиты), но приложение их **не запрашивает** и не хранит. Каталог
  OpenRouter-моделей — P, проверенность — нет.
- **Ollama**: `openai-completions`, `http://localhost:11434/v1`, без ключа
  (`provider_preset.dart:262-280`). Реальное окно зависит от локальной сборки модели —
  каталог (131072/32768) **не является** проверенным значением; пользователь должен
  иметь возможность указать его сам.
- **Пользовательская модель**: `presetId == null`, `baseUrl`/`model` вручную,
  `contextTokens = 16000` по умолчанию, `supportsVision` — переключатель; цены и лимиты
  изображений задать **негде**. Это ключевой пробел для «custom model» сценария.

### C.5 Политика UNKNOWN

1. Неизвестное окно → планировщик использует **консервативные допущения**
   (`unknownContextAssumptions`: вход ≤ 6 000, вывод ≤ 2 048 — конфиг, не «метаданные
   модели») и помечает план `budgetSource: assumption`.
2. Неизвестная цена → стоимость `null`, `pricingState: unknown`; UI пишет «стоимость
   неизвестна», а не «$0.00».
3. Неизвестные лимиты изображений → консервативный размер частей
   (`imageTokens.defaultConservative`) и явная пометка в плане.
4. Прогресс и ошибки не выдают предположения за факты: в `GenerationEstimate` есть
   список `unknownFields`.

---

## D. Адаптивный планировщик фрагментов

### D.1 Точная формула входного бюджета

```
systemPromptTokens = estimate(systemPrompt)                       // один раз на версию
schemaTokens       = estimate(jsonEncode(schemaProjection))       // один раз на протокол
wrapperTokens      = estimate(skeleton of <materials>/<wishes>/<limit>/<images>)
perChunkLabels     = estimate(image catalog lines + image part labels)
imageTokens        = Σ imageTokenModel(unit)   // раздел E.4
fixedOverhead      = systemPromptTokens + schemaTokens + wrapperTokens
                     + perChunkLabels + imageTokens

outputCap          = caps.maxOutputTokens ?? config.defaultOutputCap
expectedOutput     = min(outputCap, limit × perCardOutputTokens + jsonEnvelopeTokens)
reservedOutput     = expectedOutput            // резерв по ожиданию, а не по максимуму
safetyMargin       = caps.contextWindowTokens != null
                       ? max(256, round(0.05 × caps.contextWindowTokens))
                       : config.unknownSafetyMargin

inputBudget =
  caps.contextWindowTokens != null
    ? caps.contextWindowTokens − reservedOutput − fixedOverhead − safetyMargin
    : config.unknownInputBudget                       // assumption, не «магия»

if (caps.maxInputTokens != null)
    inputBudget = min(inputBudget, caps.maxInputTokens − fixedOverhead);

if (caps.maxRequestBytes != null)                         // ограничение тела
    inputBudget = min(inputBudget, estimateTextForBytes(caps.maxRequestBytes − imageBytes));

if (inputBudget < minWorkableInputTokens)   // 512, конфиг
    → plan.invalid(reason: contextWindowTooSmall, needed: …, available: …)
```

Отличия от текущего (`generation_model.dart:28-39`): нет клампинга в 2000; резерв
зависит от заказа и модели; есть safety margin; учитываются схема, каталог и
изображения; при недостижимом бюджете план **невалиден**, а не «всё равно 2000».

### D.2 Резерв вывода

- `perCardOutputTokens` — из правил промпта (`front` ~1–3 предложения, `back` ≤ 200
  символов) и структуры JSON; значение калибруется на живых прогонах (раздел G.7) и
  хранится конфигом, а не «магическим» 8192.
- `jsonEnvelopeTokens` — `{"cards":[…]}` + пробелы.
- `outputCap` берётся из возможностей модели; если неизвестен — консервативный
  `config.defaultOutputCap` (например, 4096) и пометка `assumption`.
- `limit` на фрагмент ≤ `floor((outputCap − envelope) / perCardOutputTokens)`;
  это и есть «потолок по бюджету вывода», который заменяет `kMaxCardsPerChunk = 20`.

### D.3 Мягкая цель заполнения (не «делить окно на два»)

Жёсткий бюджет — только верхняя граница. Второй, мягкий, критерий — полезность:
20 карточек не требуют 1M входных токенов. Планировщик заполняет фрагмент до

```
softTarget = min(inputBudget, max(minChunkTokens, limit × tokensPerCardMaterial))
```

где `tokensPerCardMaterial` — конфиг (ориентир 6 000–8 000 токенов материала на
карточку; значение подлежит калибровке, это **не** метаданные провайдера). Смысл:
не платить за 1M контекста ради 20 карточек и не рисковать переполнением; при этом
жёсткий бюджет всё ещё позволяет увеличить фрагмент, если мягкая цель недостижима
(например, один неразрывный раздел больше цели — он всё равно уйдёт целиком, пока
помещается в бюджет).

### D.4 Инварианты планировщика (соответствие п.5 задания)

1. **Максимум контекста без риска**: заполнение до `min(inputBudget, softTarget)`;
   никогда не превышать `inputBudget` и `maxRequestBytes`.
2. **Минимум запросов**: упаковка жадная по порядку; один фрагмент на всё, что
   помещается; изображения одной секции не размножают запросы без необходимости.
3. **Семантические границы**: раздел → абзац → предложение → строка → руна.
   Предложение режется только если оно само больше бюджета.
4. **Не рвать предложения/разделы** без нужды: границы предпочитаются ближе к
   целевому размеру, но без пересечения границ разделов, пока раздел помещается.
5. **Страницы**: номер страницы — часть единицы (PDF/PPTX); страницы одного файла
   сохраняют порядок; фрагмент не смешивает страницы разных файлов.
6. **Связи текст↔изображение**: изображение наследует `documentId/sectionIndex/page`;
   попадает в фрагмент, где находится его секция (первый фрагмент секции); каталог
   документа доступен всем фрагментам этого документа (раздел E.2).
7. **Лимиты изображений модели**: число частей и байты — из возможностей; при
   превышении — подгруппы, а не отбрасывание.
8. **Бюджет вывода**: `limit` каждого фрагмента ≤ потолка по выводу; сумма по плану
   согласована с заказом (см. D.7).
9. **Нет пустых фрагментов**: каждый фрагмент содержит текст ≥ 1 руны, либо ≥ 1
   image-часть, либо ≥ 1 строку каталога; иначе он не создаётся.
10. **Нет молчаливых потерь**: каждая единица либо в фрагменте, либо в
    `plan.omitted` с причиной (`budget`, `providerImageCap`, `payload`, `unsupported`);
    UI показывает предупреждение, оценка — учитывает.

### D.5 Алгоритм (проект)

```
1. inventory = collectUnits(documents, attachments, documentImages)
   - секции → текст-единицы (абзацы/строки/предложения), у каждой sectionKey
   - DocumentImage → ImageUnit(sectionKey | orphan)
   - GenerationAttachment → AttachmentUnit(groupKey, pages)
   - DocumentImage без секции → OrphanUnit(file)
2. tokens = estimator.estimateUnit(unit)   // инкрементально, без повторного рендера
3. если units пусто и <wishes> непусто → один text-only фрагмент (prompt-only, ADR-024)
4. для каждой секции: если textTokens(section) > budget:
      рекурсивно splitText(section) по иерархии границ
5. упаковка:
   for unit in order:
      если unit — AttachmentUnit:
          сгруппировать страницы по groupKey; если суммарные токены/байты > бюджета
          → подгруппы (страницы по порядку) — новые фрагменты
      иначе:
          candidate = current + unit
          если fits(candidate, budget, softTarget, imageCaps) → current = candidate
          иначе → закрыть current, начать новый
6. лимит карточек: distribute(requested, chunks) с минимумом 1 для непустых
7. проверить инварианты; сформировать GenerationPlan
```

`fits` учитывает: суммарные токены текста + изображений + меток, число image-частей,
байты частей, суммарный размер тела (текст + base64).

Порядок «сначала упаковка, потом лимит» не конфликтует с `softTarget`: до упаковки
берётся `limitTarget = min(requested ?? cardsByOutputCap, cardsByOutputCap)`, от него
считается `softTarget`; после упаковки выполняется распределение заказа (D.7) и, если
лимиты изменились настолько, что меняется `softTarget`, планировщик делает **второй
проход** (не больше двух проходов; результат детерминирован). Второй проход нужен
только при явном заказе карточек.

### D.6 Дробление (recursive split)

- Причина дробления — только переполнение входа/размера (не rate limit, не auth).
- Дробление по **контент-единицам** (абзацы → предложения → строки), с сохранением
  порядка и привязок; картинки остаются у своих секций (при дроблении текста без
  картинок картинки не теряются — они остаются в каталоге и в `plan`).
- `splitDepth` (0..3), `splitAttempts` на фрагмент (≤2), общий бюджет попыток
  (`maxTotalRequests = plannedRequests + retryAllowance`).
- Дети наследуют `limit` (согласованно: сумма лимитов детей = лимит родителя, каждый
  ≥ 1, если родитель ≥ числа детей).
- Фрагмент с изображениями дробится по тексту; image-части перераспределяются по
  возможностям провайдера (например, 10 картинок → 6 + 4, каждая подгруппа с
  контекстными строками каталога).

### D.7 Распределение лимита карточек без потерь

Правила:

1. Если пользователь не указал число — `limit = cardsByOutputCap` на фрагмент.
2. Если указал `total`:
   - `total < chunks` → **не** пропускать фрагменты; варианты: (а) уменьшить число
     фрагментов, увеличив бюджет до `inputBudget` (если позволяет жёсткий бюджет и
     `softTarget`), (б) оставить все фрагменты, выдать минимум 1 карточку на каждый и
     предупредить, что сумма превысит заказ. Рекомендация: (а), если возможно; иначе
     (б) с подтверждением в диалоге стоимости (раздел H).
   - `total > chunks × cardsByOutputCap` → план невыполним: предупредить и
     предложить увеличить число фрагментов (не клампить молча).
   - распределение — пропорционально объёму; каждый непустой фрагмент получает ≥1;
     сумма = min(total, потолок) с явным `plan.requestedCards` и
     `plan.plannedCards`.
3. `limit` никогда не равен 0 у запланированного фрагмента.

### D.8 `GenerationPlan` (новый артефакт)

```
GenerationPlan {
  List<PlannedChunk> chunks;
  List<OmittedUnit> omitted;            // причина, единица, токены
  int requestedCards;                   // из пожеланий/поля
  int plannedCards;                     // сумма limit
  int plannedRequests;                  // chunks (+ retryAllowance отдельно)
  int retryAllowanceRequests;
  GenerationEstimate estimate;          // раздел G
  BudgetTrace budget;                   // формула, слагаемые, источник значений
  List<String> unknownFields;           // 'context_window','pricing','image_limits'
  PlanValidity validity;                // valid | warnings | invalid(reason)
}

PlannedChunk {
  int index; ChunkKind kind;            // text | mixed | images | catalog
  List<UnitSpan> units;                 // ids + offsets/tokens
  List<DocumentImage> imageParts;       // что уйдёт частями
  List<DocumentImage> catalogOnly;      // что останется только в каталоге
  List<GenerationAttachment> attachments;
  int textTokens, imageTokens, totalTokens, bodyBytes;
  int limit;
  int splitDepth;
}
```

План строится **до** первого API-запроса и живёт в `GenerationRunResult`, в
`generation_jobs` (после K1) и в UI.

---

## E. Мультимодальное представление контента

### E.1 ContentUnit

```
ContentInventory
 ├─ DocumentUnit(fileName, format, pageCount?, sections[])
 │    ├─ SectionUnit(sectionIndex, title?, pageRange?, text, tokens)
 │    │    ├─ TextPiece(абзац|предложение|строка, order, tokens)
 │    │    └─ ImageRef(imageId, page?, order?, rect?, caption?, context?, tokens)
 │    └─ DocumentCatalog(все ImageRef документа)
 ├─ AttachmentUnit(fileName, mediaType, groupKey?, pages[])
 │    └─ PageUnit(pageNumber, bytes, tokens)
 └─ OrphanImageUnit(fileName)           // изображение без текстовой секции
```

Инварианты модели:

- `ImageRef` всегда знает `documentId` + `sectionIndex` (или помечен orphan);
  `DocumentImage` уже содержит `sectionIndex`, `page`, `order`, `rect`
  (`lib/domain/generation/document_image.dart:94-152`) — представление строится поверх
  него без изменения доменной сущности.
- Текст режется только по `TextPiece`; «сырых» `materialsText`-строк в планировщике
  нет (сейчас `GenerationChunk.materialsText` — единственный носитель, из-за чего
  картинки и текст разъезжаются при дроблении).
- Каждая единица имеет стабильный id (`doc:<file>#<section>#<piece>`,
  `img:<file>#<n>`), который пишется в план и в failures — повтор не пересобирает
  текст заново.

### E.2 Ассоциация изображение ↔ текст ↔ страница

- Изображение принадлежит секции из `DocumentImage.sectionIndex`
  (`parsed_document_builder.dart:99-105`).
- Фрагмент включает изображения секций, чьи `TextPiece` попали в фрагмент
  (текущее поведение `generation_chunker.dart:252-264`).
- **Каталог `<images>` — на уровне документа.** Каждый фрагмент документа получает
  каталог всех его изображений (строки каталога, без байтов). Это чинит два дефекта:
  (а) изображение из другой секции больше не «невидимо» модели; (б) `image_id`
  разрешается при импорте по карте документа, а не по списку фрагмента
  (`generation_pipeline.dart:583-608`, `generation_images.dart:28-33`).
- Байты image-частей отправляются только для изображений этого фрагмента; выбор —
  по приоритету подписи/области/площади (`generation_images.dart:111-123`), но с
  учётом возможностей модели и бюджета тела.
- Изображения без секции (orphan) гарантированно получают собственный фрагмент
  (каталог + части), не теряются.

### E.3 Группировка и разбиение изображений

- Подпись и окружающий текст **никогда** не отделяются от изображения: `ImageRef`
  несёт их, строка каталога строится из него.
- Несколько изображений одной секции группируются; если группа > `maxImagesPerRequest`
  (или > бюджета тела), она делится на подгруппы по порядку; каждая подгруппа получает
  контекст секции (текст фрагмента, где она лежит) и пометку каталога.
- Страницы PDF-скана — один `AttachmentUnit` с порядком; `maxPages` больше нет:
  планировщик режет страницы по возможностям/бюджету (например, 3 страницы в
  фрагмент, если изображения большие; 10 — если модель и тело позволяют).
- Изображения, не отправленные частями (лимит/бюджет), остаются в
  `catalogOnly` и разрешаются по `image_id` при импорте — это уже работает для
  каталога (`generation_pipeline.dart:583-608`) и должно сохраниться.

### E.4 Оценка токенов изображения

```dart
abstract interface class ImageTokenModel {
  int estimate({required int? width, required int? height, required int bytes});
  String get source;   // 'provider_formula' | 'dimension_heuristic' | 'byte_heuristic' | 'conservative_default'
}
```

- **Приоритет 1 — провайдерная формула**, только если возможности аккаунта содержат
  `imageTokenFormula` + `imageTokenFormulaSource` (документация + дата). В репозитории
  таких данных **нет** → сейчас эта ветка не активируется (UNKNOWN).
- **Приоритет 2 — dimension heuristic**: `tokens ≈ ceil(width × height / K)` с
  коэффициентом `K` из конфига (стартовое значение — консервативное, калибруется); для
  неизвестных размеров — `byte heuristic`.
- **Приоритет 3 — conservative default** (для полностью неизвестного случая), с
  пометкой в `GenerationEstimate.unknownFields`.
- Универсальный `kImageTokenEstimate = 1000` **не используется** в новой архитектуре;
  он остаётся только как deprecated-значение для старых тестов до их перевода.

### E.5 Бюджет тела запроса

```
bodyBytes ≈ utf8(text) + Σ(4 × ceil(bytes/3))      // base64 + JSON-обёртка
limit     = min(caps.maxRequestBytes ?? config.safetyMaxBodyBytes,
                provider documented limit — UNKNOWN → config)
```

При превышении: сокращаются image-части (в `catalogOnly`), затем текст режется по
границам; при невозможности — `plan.invalid(payloadTooLarge)` с указанием, что именно
не влезает. Ресайз изображений (image preprocessing) — часть реализации: уменьшение
стороны/перекодирование в JPEG для больших схем, чтобы не отбрасывать содержимое.

### E.6 Инварианты (соответствие п.6 задания)

1. 20 изображений разных секций → каждое в своём фрагменте со своей секцией.
2. Несколько изображений одной секции — вместе, пока позволяют лимиты.
3. Изображение без текста — отдельная единица, не отбрасывается.
4. Подпись/контекст не теряются (усечение — только по бюджету и с отчётом).
5. Ни одно изображение не исчезает без записи в `plan.omitted`/`catalogOnly`.
6. Порядок изображений (page, order) сохраняется в частях запроса.

---

## F. Восстановление и повторы

### F.1 Категории ошибок (новый классификатор)

`lib/api/generation/generation_failure_classifier.dart` — чистый маппинг
`GenerationException`/HTTP-ответа/`finish_reason` → `FailureCategory`:

| Категория | Признаки (без секретов) | Действие |
|---|---|---|
| `contextOverflow` | 400 + `context length`, `maximum context`, `prompt is too long`, `input is too long`, `context_length_exceeded`, `tokens exceed` | split по единицам, повтор только затронутого |
| `inputTooLarge` | 413, `request entity too large`, `payload too large`, `request too large` | сократить image-части → split текста |
| `outputTruncated` | `finish_reason=length`, `MAX_TOKENS`, `stop_reason=max_tokens` | уменьшить `limit`, поднять `outputCap`, только затем split |
| `rateLimited` | 429 | backoff, **не** дробить |
| `providerUnavailable` | 5xx/529/overloaded | backoff, не дробить |
| `network` | таймаут/обрыв | backoff, не дробить |
| `auth` | 401/403 | fatal, без повторов |
| `invalidRequest` | 400 без известных признаков | 1 повтор с упрощением (лестница), затем failure |
| `unsupportedImage` | 400 про `image`/`media type` | убрать эту часть, повторить (текст+каталог) |
| `unsupportedModality` | 400 про `vision`/`modalities` | выключить vision-части, повторить текст/PDF-fallback |
| `malformedOutput` | JSON/схема/refusal/safety | 1 ремонтный повтор (tolerant/схема), затем failure |
| `emptyOutput` | пустой `content`/`cards=[]` | не повторять (валидный пустой ответ), статус как сейчас |
| `cancelled` | отмена | стоп |

Классификация сообщений — только по очищенному `providerReason`
(`generation_http_client.dart:289-321`), без логирования тел; паттерны — константы в
`provider_error_signatures.dart` с указанием, для какого протокола они проверены.

### F.2 Матрица восстановления

Границы: у каждой единицы работы есть `attempts`, `splitDepth`, история действий.
Глобальный бюджет запроса `RetryBudget`:

```
maxTotalRequests  = plan.plannedRequests + config.retryAllowance
maxSplitsPerUnit  = 2
maxSplitDepth     = 3
maxAttemptsPerChunk = 3   (включая первичный)
```

Правила: (1) дробить можно только при `contextOverflow`/`inputTooLarge`;
(2) при `outputTruncated` сначала уменьшить `limit` (half) и/или поднять
`reservedOutput` в пределах `maxOutputTokens`; (3) при rate limit/сети — только
backoff (существующий `RetryPolicy`), без дробления; (4) при auth/config — fatal;
(5) успешные результаты предыдущих попыток сохраняются; (6) исчерпание бюджета →
failure с причиной `retryExhausted`, без бесконечного цикла.

### F.3 Рекурсивное дробление

- Точка деления выбирается по границам `TextPiece` (абзац → предложение → строка),
  ближе к середине токенов, а не рун.
- `splitDepth` растёт у детей; по достижении 3 — жёсткое деление по предложениям/
  рунам (с защитой от разрыва суррогатной пары) и пометка `forced`.
- Изображения не теряются: остаются в родительском каталоге/детском каталоге и
  перераспределяются по лимитам.
- Лимит карточек детей: делится пополам с минимумом 1; сумма = лимит родителя.

### F.4 Output truncation — отдельная стратегия

Обрезка вывода **не** решается дроблением входа (сейчас именно так:
`generation_pipeline.dart:406-416`). Порядок:

1. Если `limit` > 1: уменьшить `limit` вдвое (proportional to expected output) и
   повторить тот же фрагмент.
2. Если `limit == 1`: поднять `reservedOutput` до `caps.maxOutputTokens` (если есть
   запас) и/или отправить инструкцию «ответ короче» (без потери схемы) — 1 попытка.
3. Если всё равно обрезка: split по тексту (маловероятно помогает, но ограниченно) —
   1 попытка.
4. Затем failure `outputTruncated` с advise «уменьшите число карточек/выберите модель
   с большим выводом».

### F.5 Частичный успех и повтор

- Пайплайн сохраняет карточки каждого успешного фрагмента (как сейчас).
- `GenerationChunkFailure` получает `chunkId`, `unitIds`, `category`, `splitDepth`,
  `attempts`, `retryable` (по категории), `omittedReason`.
- `retryFailed` восстанавливает фрагмент по `unitIds` (а не по строке текста), поэтому
  повторяется ровно то, что упало, с сохранением ассоциаций изображений.
- `retryable=false` для `unsupportedImage`/`unsupportedModality`/`invalidRequest` после
  исчерпания упрощений, `attachmentTooLarge` (после ресайза не должно возникать),
  `cancelled`. Кнопка «Повторить неудавшиеся» фильтрует по этому флагу.

---

## G. Оценка токенов и стоимости

### G.1 Текст

`TokenEstimator` расширяется до консервативной script-aware эвристики:

| Класс символов | Символов на токен | Обоснование |
|---|---|---|
| кириллица | ≤ 2,2 | BPE русских текстов обычно 2–3 симв./токен; берём нижнюю границу (переоценка) |
| латиница/цифры | ≤ 3,5 | переоценка относительно ~4 |
| пунктуация/пробелы | 2,0 | смешанные последовательности |
| CJK | 1,0 | worst case |

Значение — **оценка сверху** (консервативная): лучше мельче нарезать, чем переполнить.
Калибровка на `usage.prompt_tokens` (раздел G.7) правит коэффициенты, а не структуру.

### G.2 Обвязка и схема

- `systemPromptTokens` — один раз на версию промпта (кэш).
- `wrapperTokens` — оценка скелета `<materials></materials><wishes></wishes>
  <limit>N</limit><images></images>` + `Файл: <имя>` для каждого файла.
- `schemaTokens` — сериализованная проекция схемы (OpenAI/Gemini/Anthropic — разные;
  считается один раз на протокол).
- `catalogTokens` — строки `<images>` (id/файл/подпись/контекст) по факту, а не
  константой.

### G.3 Изображения

`Σ imageTokenModel(unit)` (раздел E.4) + метки частей (label) как текст.

### G.4 Вывод

`expectedOutput = min(outputCap, limit × perCardOutputTokens + envelope)`;
в оценке показываются и `reservedOutput`, и `expectedOutput`, чтобы пользователь видел
разницу между «резервом» и «ожиданием».

### G.5 Стоимость

```dart
class GenerationPricing {
  final double inputPerMillion;   // валюта
  final double outputPerMillion;
  final String currency;
}
```

`inputCost = inputTokens / 1e6 × inputPerMillion`, `outputCost` аналогично,
`totalCost = inputCost + outputCost`. Если хотя бы одна цена неизвестна —
`totalCost = null`, `pricingState = incomplete|unknown`, **никогда не 0**. Оценка
включает все запланированные запросы; ретраи — отдельной строкой
(`retryAllowanceCost`), чтобы «стоимость» не была заниженной.

### G.6 `GenerationEstimate`

```
inputTextTokens, imageTokens, fixedPromptTokens, wrapperTokens, schemaTokens,
catalogTokens, reservedOutputTokens, expectedOutputTokens, totalTokens,
plannedChunks, plannedRequests, retryAllowanceRequests,
inputCost?, outputCost?, totalCost?, currency,
pricingState (complete|incomplete|unknown),
unknownFields (…), confidence (0..1), estimatorVersion
```

Считается **до первого запроса** (в `GenerationPipeline.run` до цикла и в UI при
изменении входа), сохраняется в результате и (после K1) в `generation_jobs`.

### G.7 Калибровка и погрешность

- Юнит-тесты: заранее известные тексты → ожидаемые диапазоны; property-тесты
  «оценка ≥ факт» на фикстурах с реальными токенизаторами (в репозитории точных
  токенизаторов нет — используются зафиксированные `usage` из live-прогонов).
- Live-тест (тег `live`): большой документ → сравнить `usage.prompt_tokens` с оценкой;
  допустимое расхождение — конфиг (цель ±15 %, оценка не ниже факта).
- При систематической недооценке — увеличить коэффициенты, а не уменьшать
  `safetyMargin`.

---

## H. Поток предупреждения о стоимости (UX)

### H.1 Состояния

1. **Нет плана** (нет материалов/темы) — блок генерации, подсказка (как сейчас).
2. **План валиден, оценка полная** — панель: «≈ N фрагментов · M запросов ·
   X входных · Y выходных токенов · ≈ Z (в валюте цены аккаунта)». Если цена
   неизвестна — «Стоимость неизвестна: укажите цены в настройках провайдера».
3. **План с предупреждениями** (превышены пороги, неизвестны возможности, часть
   изображений только в каталоге, сумма карточек больше заказа) — панель с жёлтой
   пометкой и ссылкой «Подробнее» (список предупреждений).
4. **План невалиден** (unit не влезает даже после дробления, нет Vision при
   изображениях, окно неизвестно и материал больше консервативного бюджета) — кнопка
   «Сгенерировать» блокируется с объяснением и действиями (уменьшить материал,
   выбрать другую модель, указать окно/цены).

### H.2 Подтверждение перед запуском

Если `chunks > warnChunks`, `totalTokens > warnTokens`, `totalCost > warnCost` или
`pricingState != complete` (при запланированной стоимости), показывается диалог:

```
Сгенерировать карточки?
- Фрагментов: 42; запросов: 42 (+ до R на повторы, R — конфиг)
- Вход: ≈ 118 000 токенов; выход: ≈ 9 000 токенов
- Стоимость: ≈ 0,07 USD (пример по ценам аккаунта) | Стоимость неизвестна
- Предупреждения: 3 изображения только в каталоге; сумма карточек 63 при заказе 20
[Отмена] [Сгенерировать]
```

Пороги — `AppSettings` JSON (`app_settings`, ключ `generation.cost`), без изменения
схемы БД: `warnChunks`, `warnTokens`, `warnCost`, `blockCost` (по умолчанию `null` —
без жёсткой блокировки).

### H.3 После генерации

- Предпросмотр/итог: фактические токены (`usage`) и итоговая стоимость (если цены
  известны), рядом — оценка и расхождение.
- Ошибки фрагментов — по категориям (раздел F), а не одной строкой.

### H.4 ARB

Новые строки (в итерации реализации): стоимость/токены/фрагменты/запросы, «цены не
заданы», «окно модели неизвестно», «часть изображений только в каталоге», «повтор
недоступен для этой ошибки», «план невыполним: причина». Локаль — только `ru`
(AGENTS), с plural-формами для чисел.

---

## I. Файлы, которые нужно изменить

Столбцы: текущая ответственность → требуемое изменение → зависимости → ожидаемое
поведение → критерии приёмки. Порядок — по слоям.

| # | Файл | Сейчас | Изменение | Зависимости | Ожидаемое поведение | Приёмка |
|---|---|---|---|---|---|---|
| 1 | `lib/domain/generation/generation_model.dart` | константы резервов и `inputTokenBudget` | заменить формулу на `GenerationBudget` из возможностей; убрать клампинг 2000; оставить deprecated-константы только для чтения | `model_capabilities.dart`, `generation_budget.dart` | бюджет считается по D.1, при нехватке — invalid plan | табличные тесты; отсутствие 8192 в формуле (grep-тест) |
| 2 | `lib/domain/generation/generation_chunker.dart` | нарезка по строкам-сегментам, `materialsText` | фасад над `generation_chunk_planner.dart`; `GenerationChunk` получает `unitIds`, `splitDepth`, `imageParts`, `catalogOnly`, `tokenTrace`; обратная совместимость полей | content_unit, plan, estimator | старые вызовы работают; новый путь — план | все текущие тесты чанкера зелёные; новые — инварианты D.4 |
| 3 | `lib/domain/generation/generation_card_limit.dart` | разбор числа, распределение с 200 | убрать клампинг заказа; распределение: минимум 1, потолок из возможностей; отчёт о сокращении | model_capabilities | заказ больше 200 не режется молча; фрагменты без 0 | property-тесты распределения; тест «1 карточка, 3 фрагмента» |
| 4 | `lib/domain/generation/provider_preset.dart` | каталог моделей (окно, vision) | опциональные поля возможностей/цен с метаданными источника; **без выдуманных чисел** | — | каталог остаётся источником «preset», неизвестное — null | round-trip/const-тесты; ни одно значение не добавлено без источника |
| 5 | `lib/domain/generation/provider_account.dart` | JSON v1, контекст 16000 | JSON v2: capabilities/pricing; чтение v1; `contextTokens` остаётся для совместимости | — | старые записи читаются, новые поля null | тесты legacy-JSON (v1), round-trip v2, неизвестные ключи игнорируются |
| 6 | `lib/domain/generation/generation_attachment.dart` | универсальный лимит 10 МБ | лимит из возможностей; помощники `base64Bytes`, `fitsPayload`; безопасный потолок | model_capabilities | вложение больше лимита модели → ресайз/понятная ошибка | тест границ, тест «без универсального 10 МБ в сервисе» |
| 7 | `lib/domain/generation/generation_run.dart` | запрос/результат/ошибки | `GenerationRunRequest.plan`, `GenerationRunResult.plan/estimate`; failure: `unitIds`, `category`, `splitDepth`, `attempts`; новые фазы прогресса (`planning`, `estimating`) | plan, estimate, failure classifier | UI получает план и причины; повтор по unitIds | тесты сериализации/обратной совместимости конструкторов |
| 8 | `lib/domain/generation/generation_error.dart` | 19 кодов | добавить `contextLengthExceeded`, `requestTooLarge`, `imageRejected` (и маппинг в ARB) | failure classifier | новые коды доходят до UI строкой | тест маппинга кодов → ARB |
| 9 | `lib/domain/generation/generation_failure_reason.dart` | 13 причин | добавить `contextOverflow`, `inputTooLarge`, `imageUnsupported`, `modalityUnsupported`, `retryExhausted` | classifier | причина в `generation_jobs.error_code`/логе | тест `forErrorCode`, тест строк ARB |
| 10 | `lib/domain/generation/token_estimator.dart` | 2,5 симв./токен | script-aware оценка + `estimateJson`, кэш по строке (не по объекту) | — | оценка консервативна и детерминирована | табличные тесты коэффициентов; тест «оценка ≥ факт» на фикстурах |
| 11 | `lib/api/generation/generation_pipeline.dart` | чанкинг+цикл+split-once | этап планирования (plan), бюджет попыток, рекурсивное восстановление, повтор по unitIds, сохранение плана/оценки, прогресс plan/estimate | plan builder, classifier, recovery | большие документы обрабатываются; потери нет; повторы ограничены | интеграционные тесты F; счётчик запросов ≤ бюджета |
| 12 | `lib/api/generation/card_generation_service.dart` | сборка запроса, валидация вложений, лестница | `maxOutputTokens` из плана/возможностей; лимиты изображений из возможностей; payload budget; классификация ошибок; упрощения при `invalidRequest` | capabilities, classifier | нет универсального 10 МБ/8192; ошибки категоризованы | тесты на fake-адаптере: 413/400-context/unsupported image |
| 13 | `lib/api/generation/generation_images.dart` | выбор ≤8/≤24 МБ с молчаливым break | выбор по бюджету с `selected/omitted(reason)`; каталог документа отдельно от частей | capabilities, estimator | ничего не пропадает без отчёта | тесты: 20/50 изображений, лимиты модели, отчёт |
| 14 | `lib/api/generation/generation_prompt.dart` | сборка user-блока | функция `estimateWrapperTokens()` и компактный каталог при нехватке бюджета | estimator | оценка обвязки совпадает с фактом | тест «оценка == длина собранного блока + запас» |
| 15 | `lib/api/providers/openai_adapter.dart` | не передаёт лимит | опционально `max_completion_tokens`/`max_tokens` по возможности; не менять strict-схему | capabilities | вывод ограничивается там, где модель это принимает | тесты запроса с/без лимита |
| 16 | `lib/api/providers/openai_compatible_adapter.dart` | лестница `max_tokens` | принимать план (лимит вывода), не регрессировать ADR-021 | capabilities | лестница сохраняется | существующие тесты + новые |
| 17 | `lib/api/providers/anthropic_adapter.dart` | `max_tokens` 8192 | `max_tokens` из плана в пределах возможностей | capabilities | нет обрезки из-за заниженного лимита | тест значения из плана |
| 18 | `lib/api/providers/gemini_adapter.dart` | `maxOutputTokens` 8192 | то же | capabilities | то же | тест |
| 19 | `lib/api/http/generation_http_client.dart` | классификация по статусу | распознавать context/413 по безопасной причине; не логировать тела; пробросить `FailureCategory` | classifier | ошибки категоризованы, повторы по политике | тесты на fake Dio: 400 context, 413, 429 |
| 20 | `lib/api/http/retry_policy.dart` | backoff | без изменения семантики; добавить `maxTotalDelay`/учёт бюджета (опционально) | — | rate limit не дробит фрагмент | существующие тесты + тест бюджета |
| 21 | `lib/ui/generation/generation_screen.dart` | форма, оценка, запуск | панель плана/оценки (debounce), диалог подтверждения, числовое поле карточек, никакого порога 100k | plan builder, estimate, ARB | пользователь видит объём/стоимость/предупреждения до запуска | widget-тесты: панель, диалог, отмена, invalid plan |
| 22 | `lib/ui/generation/generation_preview_screen.dart` | предпросмотр/повтор/импорт | показ категорий ошибок, плана и факта/оценки; повтор только `retryable` | plan/result | повтор не тратит запросы на детерминированные ошибки | widget-тесты: retryable=false, категории |
| 23 | `lib/ui/settings/provider_account_dialogs.dart` | CRUD аккаунта | поля возможностей/цен (nullable, «не задано»), явный vision-переключатель | provider_account | пользователь может задать окно/лимиты/цены | widget-тесты: сохранение nullable, legacy без полей |
| 24 | `lib/ui/settings/generation_settings_screen.dart` | список аккаунтов | показ «возможности не заданы» и ссылки на редактирование | — | состояние UNKNOWN видно | widget-тест |
| 25 | `lib/ui/state/app_providers.dart` | проводка | providers для capabilities resolver/planner/estimator; `CardGenerationService` без жёстких 8192 | новые доменные файлы | production-граф использует новый путь | integration-тест production-графа |
| 26 | `lib/l10n/app_ru.arb` + `lib/l10n/*.dart` | строки | новые строки H.4 | — | нет сырых литералов | `ru_strings_test`, `fvm flutter gen-l10n` |
| 27 | `lib/data/db/tables.dart` | `generation_jobs` | +5 nullable-колонок плана/оценки/стоимости (вариант K1) | — | план и стоимость сохраняются | drift-тест + dump v2 |
| 28 | `lib/data/db/app_database.dart` + `.g.dart` | schemaVersion 1, fail-fast | schemaVersion 2 + `onUpgrade` ALTER TABLE; перегенерировать `.g.dart` | tables | миграция с v1 без потерь | `test/migrations/migration_test.dart` + новый тест v1→v2 |
| 29 | `lib/data/generation/drift_generation_job_repository.dart` | upsert/чтение | новые поля | tables | job хранит план/оценку | тест round-trip |
| 30 | `docs/generation-pipeline.md` | устаревшее описание | обновить разделы 1/3/4/8 после реализации | — | документация = код | ревью, ссылки на новые файлы |
| 31 | `journal/KNOWN_LIMITATIONS.md` | L57–L120 | закрыть/обновить L119 (частично), L59, L77; добавить новые ограничения | — | ограничения соответствуют фактам | запись в конце итерации |

### I.1 Явно вне изменений этого плана

- Промпт `gen-ru-v7` **не меняется** (стабильность схемы/байтовых тестов); при
  необходимости «короче ответ» — отдельная версия промпта и ADR.
- Дедупликация/импорт (`DriftGenerationCardStore`) не меняются, кроме приёма плана.
- Экспорт/импорт колод (`format_version`) не меняется (в `generation_jobs` нет обмена).

---

## J. Новые файлы

| # | Файл | Назначение | Зависимости | Приёмка |
|---|---|---|---|---|
| 1 | `lib/domain/generation/model_capabilities.dart` | `ModelCapabilities`, `CapabilitySource`, `TokenizerKind`, resolver из `ProviderAccount`+пресета | provider_preset, provider_account | табличные тесты источников; UNKNOWN не превращается в число |
| 2 | `lib/domain/generation/generation_pricing.dart` | `GenerationPricing`, `Money`/валюта, расчёт стоимости, `pricingState` | — | тесты: известные/неизвестные цены; никогда 0 при unknown |
| 3 | `lib/domain/generation/generation_budget.dart` | `GenerationBudget` по D.1: `BudgetTrace`, safety margin, unknown-стратегии, `minWorkableInputTokens` | model_capabilities, estimator | табличные тесты (окна 8k/32k/128k/1M, unknown); нет клампинга |
| 4 | `lib/domain/generation/content_unit.dart` | `ContentInventory`, `DocumentUnit/SectionUnit/TextPiece/ImageRef/AttachmentUnit/OrphanImageUnit`, стабильные id | parsed_document, document_image, generation_attachment | тесты инвариантов (порядок, ассоциации, отсутствие потерь) |
| 5 | `lib/domain/generation/generation_chunk_planner.dart` | планировщик D.4–D.7: упаковка, границы, изображения, лимиты, omitted | content_unit, budget, estimator, capabilities | property/табличные тесты 20+ сценариев |
| 6 | `lib/domain/generation/generation_plan.dart` | `GenerationPlan`, `PlannedChunk`, `OmittedUnit`, `PlanValidity`, `UnitSpan` | content_unit, estimate | тесты сериализации/валидности |
| 7 | `lib/domain/generation/generation_estimator.dart` | оценка работы G.1–G.6 (текст/схема/каталог/изображения/вывод/цена), кэш | token_estimator, capabilities, pricing | табличные тесты; «неизвестно» не равно нулю |
| 8 | `lib/domain/generation/generation_recovery.dart` | `FailureCategory`, `RecoveryAction`, `RecoveryBudget`, решение по ошибке (чистые правила) | plan, run | тесты F.2 (22 кейса) |
| 9 | `lib/api/generation/generation_failure_classifier.dart` | маппинг `GenerationException`/HTTP/`finish_reason` → категория | provider_error_signatures | тесты на все категории, без утечки тел |
| 10 | `lib/api/generation/provider_error_signatures.dart` | безопасные regex-признаки провайдерских ошибок + протокол, где проверено | — | тест: сигнатуры не срабатывают на случайных текстах; добавление — с комментарием-источником |
| 11 | `lib/api/generation/generation_plan_builder.dart` | оркестрация: ParsedDocument/Attachment/DocumentImage → `ContentInventory` → `GenerationPlan` | content_unit, planner, budget, estimator | интеграционные тесты (docx/pdf/scan/mixed) |
| 12 | `lib/ui/generation/generation_plan_panel.dart` | панель плана/оценки/предупреждений | plan, estimate, ARB | widget-тесты состояний H.1 |
| 13 | `lib/ui/generation/generation_cost_dialog.dart` | подтверждение H.2 | plan/estimate | widget-тесты: показ/скрытие, стоимость unknown |
| 14 | `lib/ui/settings/provider_capabilities_dialog.dart` | ввод возможностей/цен (nullable) | provider_account | widget-тесты: пустые поля, валидация |
| 15 | `test/unit/domain/generation/model_capabilities_test.dart` | источники/UNKNOWN | — | — |
| 16 | `test/unit/domain/generation/generation_budget_test.dart` | формула, 8k-регресс | — | — |
| 17 | `test/unit/domain/generation/generation_estimator_test.dart` | текст/изображения/цена/неизвестность | — | — |
| 18 | `test/unit/domain/generation/generation_chunk_planner_test.dart` | 20+ сценариев п.10 задания | — | — |
| 19 | `test/unit/domain/generation/generation_recovery_test.dart` | категории/действия/бюджет | — | — |
| 20 | `test/unit/domain/generation/content_unit_test.dart` | ассоциации/порядок | — | — |
| 21 | `test/unit/api/generation/generation_failure_classifier_test.dart` | классификация | — | — |
| 22 | `test/unit/api/generation/generation_plan_builder_test.dart` | inventory→plan | — | — |
| 23 | `test/unit/api/generation/generation_pipeline_recovery_test.dart` | split-once→recursive, бюджеты, partial | — | — |
| 24 | `test/unit/api/generation/generation_pipeline_payload_test.dart` | 413/payload/изображения | — | — |
| 25 | `test/widget/generation/generation_plan_panel_test.dart` | панель/предупреждения | — | — |
| 26 | `test/widget/generation/generation_cost_dialog_test.dart` | подтверждение | — | — |
| 27 | `test/integration/adaptive_generation_flow_test.dart` | production-граф: drift in-memory + fake transport + большой документ + изображения | — | — |
| 28 | `test/unit/data/generation/generation_job_plan_persistence_test.dart` | поля плана в `generation_jobs` (K1) | — | — |
| 29 | `test/widget/settings/provider_capabilities_dialog_test.dart` | ввод возможностей/цен (nullable) в UI | — | — |
| 30 | `test/live/adaptive_generation_live_test.dart` | живая калибровка оценки на большом документе (тег `live`) | — | — |

---

## K. Модель данных

### K.1 `ProviderAccount` JSON — версия 2 (без схемы БД)

`app_settings.value_json`, ключ `generation.providers` (`ProviderAccounts.version = 1`,
`provider_account.dart:241-242`). Новое — обратно совместимое:

```json
{
  "version": 2,
  "accounts": [{
    "id": "deepseek",
    "label": "DeepSeek",
    "preset_id": "deepseek",
    "protocol": "openai-completions",
    "base_url": "https://api.deepseek.com",
    "model": "deepseek-chat",
    "context_tokens": 128000,               // остаётся для v1-совместимости
    "requires_api_key": true,
    "supports_vision": false,
    "max_output_tokens": null,              // null = неизвестно
    "max_images_per_request": null,
    "max_image_bytes": null,
    "max_request_bytes": null,
    "pricing": {"input_per_mtok": null, "output_per_mtok": null, "currency": "USD"},
    "capabilities_source": "user"           // verified|preset|user|inferred|unknown
  }],
  "active_id": "deepseek"
}
```

Правила: чтение v1/v2; запись v2 при сохранении; `null` — «неизвестно»; неизвестные
ключи игнорируются; секретов в JSON нет (ключ только в `ApiKeyStore`).

### K.2 `generation_jobs` — вариант K1 (рекомендуемый)

Добавить nullable-колонки (`lib/data/db/tables.dart:226-267`):

| Колонка | Тип | Смысл |
|---|---|---|
| `planned_chunks` | int? | число фрагментов по плану |
| `estimated_input_tokens` | int? | оценка входа (текст+изображения+обвязка) |
| `estimated_output_tokens` | int? | резерв/ожидание вывода |
| `estimated_cost_micros` | int? | стоимость в микроединицах валюты; null при неизвестной цене |
| `pricing_state` | text? | `complete` / `incomplete` / `unknown` |

`plan_json` (полный план) — **не** добавляется: план восстанавливается из результата
и журнала оценок; хранение полного текста материалов в БД запрещено (SPEC 3.4).

### K.3 Вариант K2 (без изменения БД)

Оценка/план остаются только в `GenerationRunResult` и debug-логе. Плюс: нулевой риск
миграции. Минус: после закрытия приложения нельзя разобрать «почему было дорого/долго»;
`generation_jobs` остаётся без плана. Рекомендация — K1, потому что ADR-005 требует
явной миграции, а не запрещает её; объём изменения — 5 nullable-колонок, экспорт колод
не затрагивается.

### K.4 Доменные структуры (без БД)

`GenerationPlan`, `PlannedChunk`, `GenerationEstimate`, `ModelCapabilities`,
`GenerationPricing` — immutable-классы домена (без Flutter/DB), как принято в проекте.

---

## L. Миграции и обратная совместимость

1. **Аккаунты провайдеров.** JSON v1 читается без изменений; v2 пишется только при
   сохранении аккаунта; `context_tokens` сохраняется (legacy-ключи и тесты не ломаются).
   `ProviderAccount.fromJson` обязан игнорировать неизвестные ключи (как сейчас).
2. **`GenerationChunk`/`GenerationChunkFailure`.** Новые поля — с значениями по
   умолчанию; старые конструкторы/тесты продолжают компилироваться; `materialsText`
   остаётся для совместимости (deprecated-путь), но новый планировщик его не использует.
3. **`GenerationPipeline.run/retryFailed`.** Сигнатуры сохраняются; план — опциональный
   параметр/результат. `CardGenerationService.maxOutputTokens` остаётся параметром
   конструктора (тесты), но в production переопределяется планом.
4. **БД.** Если K1: `schemaVersion` 1→2, `onUpgrade` с `ALTER TABLE generation_jobs ADD
   COLUMN …` (все nullable), новый dump `drift_schemas/drift_schema_v2.json`,
   перегенерация `test/migrations/generated/schema.dart`, тест v1→v2 (существующие данные
   сохраняются, новые колонки null). `GeneratedHelper.versions` должен стать `[1, 2]`
   после добавления dump; текущий тест `migration_test.dart:24-30` проверит это.
5. **Экспорт/импорт.** `docs/archive-format.md` (границы SPEC 0.4 п.4): `generation_jobs`
   в архив не входит → `format_version` не меняется.
6. **Тесты/фикстуры.** Промпт `gen-ru-v7` не меняется → байтовые тесты промпта
   остаются. Оценки токенов меняются → тесты, фиксирующие конкретные числа
   (`generation_model_test.dart`, `token_estimator_test.dart`,
   `generation_chunker_test.dart`), обновляются осознанно с новыми ожиданиями; live-метрики
   (STATE/AGENTS) пересчитываются в итерации реализации.
7. **Ограничения.** L119 (лимиты визуального содержимого) частично закрывается;
   L59/L77 обновляются; новые ограничения (например, «провайдерные цены вводятся
   вручную») фиксируются в `journal/KNOWN_LIMITATIONS.md`.

---

## M. План тестов

Слой/файл — по конвенциям проекта: `test/unit/domain/generation/`,
`test/unit/api/generation/`, `test/widget/generation/`, `test/integration/`,
`test/live/` (тег `live`). Все прогоны — с `--no-pub` (L64).

| # | Кейс (п.10 задания) | Слой | Файл | Ожидаемое утверждение |
|---|---|---|---|---|
| 1 | Маленький текст | unit | `generation_chunk_planner_test.dart` | 1 фрагмент, 1 запрос, потерь нет |
| 2 | Большой текст | unit | `generation_chunk_planner_test.dart` | число фрагментов = ceil по бюджету; каждый ≤ budget |
| 3 | Текст больше окна | unit | `generation_chunk_planner_test.dart` | дробится по границам, ни один фрагмент не превышает `inputBudget` |
| 4 | Большой заказ вывода | unit | `generation_card_limit_test.dart` | `limit ≤ cardsByOutputCap`; при невыполнимости — invalid/warning |
| 5 | Одно изображение | unit | `generation_chunk_planner_test.dart` | отдельный фрагмент/группа, каталог содержит строку |
| 6 | Восемь изображений | unit | `generation_chunk_planner_test.dart` | 8 частей в пределах лимита модели |
| 7 | Двадцать изображений | unit | `generation_chunk_planner_test.dart` | подгруппы по лимиту; `omitted` пуст |
| 8 | Пятьдесят изображений | unit | `generation_chunk_planner_test.dart` | >1 фрагмента; ни одно не потеряно без `omitted` |
| 9 | Смешанный текст+изображения | unit + integration | `generation_chunk_planner_test.dart`, `adaptive_generation_flow_test.dart` | ассоциации секция↔изображение сохранены |
| 10 | Несколько изображений одной секции | unit | `content_unit_test.dart` | группируются, подпись не теряется |
| 11 | Изображения больше лимита модели | unit | `generation_chunk_planner_test.dart` | подгруппы + `omitted` с причиной `providerImageCap` |
| 12 | Неизвестное окно | unit | `generation_budget_test.dart` | `budgetSource: assumption`, предупреждение, нет клампа 2000 |
| 13 | Неизвестная цена | unit | `generation_estimator_test.dart` | `totalCost == null`, `pricingState != complete` |
| 14 | Кастомная модель | unit + widget | `model_capabilities_test.dart`, `provider_account_test.dart` (расширить), `provider_capabilities_dialog_test.dart` | значения nullable; сохранение/чтение |
| 15 | Большой PDF | integration | `adaptive_generation_flow_test.dart` (программная фикстура) | страницы/секции как единицы; план валиден |
| 16 | Переполнение контекста | unit | `generation_pipeline_recovery_test.dart` | split, повтор только затронутой единицы, остальные сохранены |
| 17 | Обрезка вывода | unit | `generation_pipeline_recovery_test.dart` | сначала уменьшение `limit`, split не первым шагом |
| 18 | Rate limit | unit | `generation_pipeline_recovery_test.dart` | backoff, фрагмент не дробится, число запросов ≤ бюджета |
| 19 | Таймаут сети | unit | `generation_pipeline_recovery_test.dart` | backoff, статус partial/retryable |
| 20 | Частичный сбой фрагмента | unit + integration | `generation_pipeline_recovery_test.dart` | карточки успешных фрагментов сохранены |
| 21 | Исчерпание повторов | unit | `generation_pipeline_recovery_test.dart` | `retryExhausted`, запросы ≤ `maxTotalRequests` |
| 22 | Частичный успешный результат | widget | `generation_preview_partial_test.dart` (расширить) | предпросмотр/импорт частичного результата |
| 23 | 413 / payload | unit | `generation_pipeline_payload_test.dart` | сокращение image-частей; повтор; отчёт |
| 24 | Auth/config | unit | `generation_pipeline_recovery_test.dart` | fatal, без повторов |
| 25 | Unsupported image | unit | `generation_pipeline_recovery_test.dart` | удаление части, повтор без неё |
| 26 | Malformed JSON/схема | unit | `generation_pipeline_recovery_test.dart` | 1 ремонтный повтор, затем failure |
| 27 | Подтверждение стоимости | widget | `generation_cost_dialog_test.dart` | порог/unknown → диалог; отмена не запускает |
| 28 | Панель плана | widget | `generation_plan_panel_test.dart` | суммы/предупреждения соответствуют плану |
| 29 | Production-граф | integration | `adaptive_generation_flow_test.dart` | drift in-memory + fake transport: план→запросы→импорт |
| 30 | Оценка vs факт (live) | live | `test/live/adaptive_generation_live_test.dart` | расхождение в допуске, оценка не ниже факта |

Отдельно:

- **Линейность планировщика**: тест с инжектированным считающим оценщиком — число
  вызовов `≤ pieces × 3` (защита от повторного рендера/квадратичной упаковки).
- **Отсутствие «магического» 20**: grep-тест `kMaxCardsPerChunk` не используется в
  production-пути (или помечен deprecated).
- **Контракт неизвестности**: тест, что при `pricing == null` ни одно поле стоимости
  не равно `0`.
- **Регресс moonshot-8k**: план для окна 8 000 не создаёт фрагмент, который заведомо
  превышает окно; при недостатке — invalid с причиной (раньше — 2000 и гарантированный 400).

---

## N. Производительность и память

### N.1 Планировщик

Текущий чанкер на каждый сегмент заново рендерит и оценивает кандидата
(`generation_chunker.dart:168-170` и `401-434`): суммарная работа квадратична по числу
сегментов (m сегментов на фрагмент → O(m²) символов). Для 10 МБ текста с 50 тыс. абзацев
это недопустимо. Проект:

- прогрев: каждый `TextPiece` оценён один раз; упаковка — инкрементальная
  (`currentTokens += piece.tokens`), без `render` кандидата;
- проверка лимитов изображений/байтов — O(1) на единицу;
- итоговая сборка текста — один `StringBuffer` на фрагмент, O(total);
- цель: планирование 10 МБ текста ≤ 500 мс на десктопе (замер в тесте-бенчмарке,
  без жёсткого ассерта по времени — по числу операций).

### N.2 Память

Текущий пик: все `ParsedDocument.text` + все байты вложений и изображений документов +
base64-копии (×1,33) в момент запроса + PNG-страницы (1600 px). Для 50 файлов по 25 МБ
это сотни МБ — риск OOM (L25). Проект:

- после парсинга файла байты не хранятся, если это не вложение; для изображений
  документов — байты только у выбранных кандидатов (приоритизация до чтения байтов),
  остальные — метаданные + ленивое чтение;
- вложения (JPG/PNG/PDF-скан) — ленивое чтение из `DocumentGateway` по мере
  отправки фрагмента, с ограниченным кэшем;
- base64 не материализуется целиком: сериализация тела по частям (или явный учёт
  пика в бюджете тела);
- после отправки фрагмента его байты освобождаются;
- страницы скана рендерятся по одной и освобождаются после отправки/отказа;
- оценщик UI кэширует токены по документу (сейчас при каждом нажатии клавиши
  пересчитывает все тексты — `generation_screen.dart:233-247`).

### N.3 Время и параллелизм

Запросы последовательны (порядок, rate limit). Для плана из 40 фрагментов время =
40 × (латентность + при необходимости поиск картинок). Проект: прогресс с ETA
(`plannedChunks/plannedRequests` известны заранее), поиск картинок вне критического
пути прогресса (как сейчас), опционально — ограниченный параллелизм по возможностям
аккаунта (вне этого плана, отдельный ADR).

---

## O. Критические риски

| # | Риск | Влияние | Смягчение |
|---|---|---|---|
| 1 | Возможности моделей неизвестны/неверны (окно, вывод, изображения) | неверный бюджет → 400 «context length» или лишние запросы/стоимость | явный UNKNOWN-режим, ввод пользователем, консервативные допущения, предупреждения; проверять на moonshot-8k |
| 2 | Эвристика токенов недооценивает текст | переполнение, потеря фрагмента | консервативные коэффициенты, safety margin 5 %, запрет на «бюджет впритык», калибровка на `usage` |
| 3 | Провайдерные формулы изображений введены без источника | то же | не активировать `provider_formula` без `verified` + документа/даты; по умолчанию — dimension heuristic |
| 4 | Миграция БД (K1) | потеря данных/сломанный старт | nullable-колонки, `onUpgrade` только ALTER, dump v2, тест v1→v2 на реальном файле |
| 5 | Изменение чанкинга ломает существующие тесты/метрики | красный CI, сдвиг live-метрик | поэтапно: сначала новые структуры рядом, затем фасад; обновление тестов отдельными коммитами |
| 6 | Стоимость показывается «0» при неизвестных ценах | пользователь не узнает о тратах | тест-инвариант «unknown ≠ 0», `pricingState` в UI/БД |
| 7 | Ретраи/лестница умножают запросы | неожиданная стоимость/латентность | `retryAllowance` в оценке и в подтверждении; `maxTotalRequests` |
| 8 | Payload-бюджет занижен | 413 на больших сканах | бюджет тела из возможностей + safety; уменьшение image-частей до отказа |
| 9 | Потеря контента при дроблении/лимитах | карточки не сделаны из части материала | инварианты D.4/E.6, `plan.omitted`, тесты на «нет потерь» |
| 10 | `image_id` из другого фрагмента не разрешается | карточка без картинки, пометка `imageIdUnknown` | каталог на уровне документа + карта импорта (раздел E.2) |
| 11 | Определённые ошибки повторяются кнопкой | бессмысленные запросы/стоимость | `retryable=false` по категории |
| 12 | Промпт `gen-ru-v7` не рассчитан на рост `limit` | больше карточек, обрезка вывода | не менять промпт в этой итерации; ограничивать `limit` бюджетом вывода; отдельный ADR на промпт |

---

## P. Порядок реализации (для следующей задачи)

1. **Контракты и данные (без сети):** `model_capabilities`, `generation_pricing`,
   `generation_budget`, `content_unit`, `generation_plan`, `generation_estimator` +
   unit-тесты. Код старый не меняется.
2. **Планировщик:** `generation_chunk_planner` + `generation_plan_builder`; фасад
   `generation_chunker`; тесты инвариантов и «нет потерь».
3. **Пайплайн:** plan в `GenerationPipeline`, рекурсивное восстановление,
   `retryable`, бюджет запросов; unit/integration на fake-транспорте.
4. **Сервис/адаптеры:** лимиты из возможностей, payload budget, классификатор ошибок,
   новые коды/причины + ARB.
5. **UI:** панель плана/оценки, диалог стоимости, настройки возможностей/цен,
   числовое поле карточек; widget-тесты.
6. **БД (K1):** schemaVersion 2, миграция, dump v2, `generation_jobs` поля,
   тест v1→v2.
7. **Документация и ограничения:** обновить `docs/generation-pipeline.md`,
   ADR-038 «Адаптивная генерация» (создать в итерации реализации), запись
   `journal/KNOWN_LIMITATIONS.md`.
8. **Живая проверка:** `deepseek-chat` большой документ + PDF-скан + изображения;
   сравнить оценку и `usage`; зафиксировать метрики в `journal/STATE.md`.

Гейты итерации реализации: `fvm flutter test --no-pub --coverage --exclude-tags golden`,
`fvm flutter analyze --no-pub`, `fvm dart format --set-exit-if-changed lib test
integration_test tool`, `fvm flutter build windows --release --no-pub`, Windows-смоук
`integration_test/session_smoke_windows_test.dart -d windows --no-pub`, live-тесты
(тег `live`) при наличии ключей.

---

## Приложение 1. Быстрая карта «где что лежит» (для реализации)

| Что нужно | Файл |
|---|---|
| Каталог моделей/провайдеров | `lib/domain/generation/provider_preset.dart` |
| Аккаунт/JSON | `lib/domain/generation/provider_account.dart` |
| Бюджет | `lib/domain/generation/generation_model.dart` (заменяется `generation_budget.dart`) |
| Чанкер | `lib/domain/generation/generation_chunker.dart` |
| Лимит карточек | `lib/domain/generation/generation_card_limit.dart` |
| Оценщик | `lib/domain/generation/token_estimator.dart` |
| Пайплайн | `lib/api/generation/generation_pipeline.dart` |
| Сервис вызова | `lib/api/generation/card_generation_service.dart` |
| Адаптеры | `lib/api/providers/{openai,openai_compatible,anthropic,gemini}_adapter.dart` |
| HTTP/ретраи | `lib/api/http/generation_http_client.dart`, `retry_policy.dart` |
| Схема ответа | `lib/api/generation/{card_json_schema,provider_schema,card_response_schema}.dart` |
| Каталог изображений/vision | `lib/api/generation/generation_images.dart` |
| Парсеры/лимиты PDF | `lib/api/parsers/{pdf_parser,pdf_image_extractor,pdf_page_regions,pdf_scan_renderer,pdf_scan_pages}.dart` |
| Экран генерации | `lib/ui/generation/generation_screen.dart` |
| Предпросмотр/повтор/импорт | `lib/ui/generation/generation_preview_screen.dart` |
| Настройки провайдеров | `lib/ui/settings/{generation_settings_screen,provider_account_dialogs}.dart` |
| Проводка | `lib/ui/state/app_providers.dart` |
| Журнал заданий | `lib/domain/generation/generation_job.dart`, `lib/data/generation/drift_generation_job_repository.dart`, `lib/data/db/tables.dart` |
| Промпт | `lib/api/prompts/system_prompt.dart`, `docs/prompts/gen-ru-v7.txt` |
| Ошибки/причины | `lib/domain/generation/{generation_error,generation_failure_reason}.dart`, `lib/ui/generation/generation_error_message.dart` |

## Приложение 2. Сводка UNKNOWN (не выдумывать при реализации)

1. Окна контекста и максимальный вывод для всех моделей каталога — значения каталога
   не подтверждены документацией в репозитории.
2. Цены всех провайдеров/моделей.
3. Лимиты изображений (штук, байт, сторон) у OpenAI/Anthropic/Gemini/OpenRouter.
4. Лимиты размера тела запроса у провайдеров.
5. Наличие точных токенизаторов и их поведение на русском тексте.
6. Поведение провайдеров при переполнении контекста сверх известных кодов (тексты
   ошибок могут различаться по версиям API).
7. Лимиты структурированного вывода (максимум карточек/элементов) у моделей.

Всё перечисленное в реализации оформляется как **nullable-возможности с источником
и датой проверки**; до проверки действует консервативная стратегия и явные
предупреждения.

---

## Q. TASK 02B-FINAL: реализованное состояние (2026-11-19)

**Статус:** production-интеграция выполнена. Разделы A–P выше — исторический аудит
TASK 01 и проектные решения; этот раздел фиксирует, что фактически сделано в
TASK 02B-FINAL и какие ограничения остаются.

### Q.1 Production-путь

```
GenerationRunRequest
  → ContentInventory (документы/изображения/вложения)
      или PromptOnlyRequest (нет материалов, есть тема)
  → GenerationPlan (GenerationPlanBuilder → GenerationChunkPlanner /
      PromptOnlyPlanner): бюджет D.1, фрагменты, изображения, лимиты карточек,
      D.5-укрупнение, предупреждения/omitted
  → PlannedChunk → GenerationRequest (materials, wishes, limit, image-parts,
      catalog, maxOutputTokens из плана)
  → CardGenerationService → адаптер провайдера → HTTP
  → CardsJsonExtractor/схема/валидатор → GeneratedCard
  → восстановление (split/reduce output) при context overflow/413/truncated
  → GenerationRunResult (карточки, failures, plan, requested/achievable,
      tokens, duplicates) → предпросмотр → импорт
```

`GenerationPipeline` больше не вызывает `GenerationChunker.chunkDocuments/
chunkAll` и не перераспределяет лимиты: план — единственный источник фрагментов,
лимитов и image-частей (D.4/D.7). Старый `GenerationChunker` остался
совместимым фасадом (`chunksFromPlan`, legacy-методы) и не входит в
production-путь.

### Q.2 D.5: второй проход (укрупнение)

Реализация — `GenerationChunkPlanner._mergeToRequested/_mergePass/_mergePair`
(`lib/domain/generation/generation_chunk_planner.dart`):

- если `requestedCards != null` и фрагментов больше заказа, соседние фрагменты
  объединяются, сначала с общим документом, затем любые соседние; порядок
  сохраняется;
- объединение проверяет заново: `inputBudget`/окно/`maxInputTokens`/
  `maxRequestBytes`/`pause image-частей`/байты изображений/`bodyBytes`/
  выходной резерв (`GenerationBudget.compute` с `_limitTarget`);
- `unitIds`/`UnitSpan` объединяются со сдвигом смещений, изображения и
  вложения дедуплицируются по id/ключу, текст склеивается разделителем
  (символы не теряются и не дублируются);
- если объединить нельзя без превышения лимитов — план остаётся с безопасным
  числом фрагментов, сохраняет `requestedCards`, выставляет
  `cardsAboveRequested`; UI показывает «запрошено/достижимо»;
- после укрупнения лимиты распределяются заново (`_distributeLimits`,
  D.7): каждый фрагмент ≥ 1, сумма = `min(requested, chunks × cardsByOutput)`;
  при заказе меньше числа фрагментов каждый получает 1 (не ноль) и
  предупреждение о превышении заказа.

### Q.3 Prompt-only план

`PromptOnlyPlanner` + `PromptOnlyRequest` (`GenerationMode.promptOnly`,
`ChunkKind.promptOnly`) строят план без материалов:

- никаких пустых `ContentUnit`/`TextPiece`/`DocumentInventory`: единицы
  содержимого пусты по контракту, `<materials>` в запросе пуст, тема уходит в
  `<wishes>`;
- учитываются системный промпт, схема, обёртка, токены пользовательского
  запроса в каждом запросе, output budget, тело запроса;
- число запросов = `ceil(requestedCards / cardsByOutputCap)`; сумма лимитов
  равна заказу (если он выполним), при превышении `maxChunks` план невалиден
  `tooManyChunks` (заказ не режется);
- UI сохранён: тема/пожелания из существующего поля, точка входа — тот же
  экран генерации; `GenerationPlan.estimate` считает обвязку на каждый запрос.

### Q.4 Что снято/замещено в TASK 02B-FINAL

| Что | Было | Стало |
|---|---|---|
| 20 карточек на фрагмент | `kMaxCardsPerChunk = 20` | удалено; `budgetCardsPerRequestCap` из output budget/`maxCardsPerRequest` |
| заказ из пожеланий | клампинг 200 | без клампа; `BigInt` + `int.max`, невыполнимость — явно |
| старый бюджет | `generation_model.dart`: 8192/16000/8000/2000/512 | файл удалён; `GenerationBudget.compute` (D.1) — единственный расчёт |
| `contextTokens=16000` | окно модели | legacy-поле JSON; планировщик не считает его окном (unknown → assumption) |
| 8 image-parts | универсальная константа | `account.maxImagesPerRequest`; 8 — только явное допущение, когда модель не сообщает лимит |
| 24 МБ image-parts | универсальная константа | `account.maxImageBytes`/`maxRequestBytes`; допущение — только при неизвестности |
| 1000 токенов на изображение | `kImageTokenEstimate` | удалено; `ContentTokenEstimator`/`ImageTokenEstimate` (модель или размерная/байтовая эвристика) |
| старый чанкинг в production | `chunkAll`/`chunkDocuments`/`splitInHalf` | план — авторитет; recovery — `GenerationPlanSplitter` по единицам/страницам |
| пропуск фрагмента `limit < 1` | молчаливый `continue` | невозможно: `PlannedChunk.limit ≥ 1`, фрагменты не пропускаются |
| молчаливое усечение заказа | `requestedAbovePlan` без UI | предупреждение плана + строка в предпросмотре «запрошено/достижимо» |
| UI-порог 100 000 токенов | константа | сравнение с входным бюджетом выбранной модели |
| отключение изображений | 8 частей на любую модель | `maxImagesPerRequest` аккаунта; не вошедшие остаются в каталоге |

### Q.5 Актуальная таблица 44 ограничений TASK 01

Статусы: **REMOVED** — искусственное ограничение удалено; **ADAPTIVE** —
заменено расчётом/возможностями модели и используется production-путём;
**PROVIDER** — реальное ограничение протокола/провайдера; **INFRASTRUCTURE** —
техническое (память/тело/транспорт); **SAFETY** — защита; **UNRESOLVED** — пока
не устранено.

| ID | Ограничение | Старое значение | Текущее поведение | Статус | Обоснование/место |
|---|---|---|---|---|---|
| L-01 | размер файла | 25 МБ | без изменений | INFRASTRUCTURE | `file_picker_document_gateway.dart`; политика чтения файла, не генерации |
| L-02 | дубль лимита | 25 МБ | без изменений | INFRASTRUCTURE | `file_parsing_service.dart`; второй барьер |
| L-03 | форматы изображений | jpg/png | без изменений | UNRESOLVED | `file_picker_document_gateway.dart`; нужен платформенный декодер/ADR |
| L-04 | ZIP-лимиты | 10k/32/120 МБ | без изменений | SAFETY | `zip_xml.dart`; защита распаковки |
| L-05 | страницы PDF-скана | ≤ 3 | без изменений | UNRESOLVED | `pdf_scan_renderer.dart`; парсер, не планировщик |
| L-06 | ширина рендера | 1600 px | без изменений | UNRESOLVED | `pdf_scan_renderer.dart`; ресайз под модель — отдельный шаг |
| L-07 | области скана | ≤ 3 страниц | без изменений | UNRESOLVED | `pdf_parser.dart` |
| L-08 | изображения PDF | ≤ 24 | без изменений | UNRESOLVED | `pdf_parser.dart`; приоритизация/omitted — следующий шаг парсера |
| L-09 | XObject-лимит | 60 | без изменений | INFRASTRUCTURE | `pdf_image_extractor.dart`; память |
| L-10 | guard-фильтры PDF | 32 px/16 Мп/2600 px | без изменений | INFRASTRUCTURE | `pdf_image_extractor.dart` |
| L-11 | области на страницу | ≤ 3 | без изменений | UNRESOLVED | `pdf_page_regions.dart` |
| L-12 | фильтр мусора | <4 КБ/<64 px | без изменений | SAFETY | `document_images.dart` |
| L-13 | порог «скан» | 50 символов | без изменений | SAFETY | `pdf_page_classifier.dart`; эвристика классификации |
| L-14 | нечитаемый PDF | 5 замен/5 % | без изменений | SAFETY | `pdf_text_quality.dart` |
| L-15 | резерв вывода | 8192 | из возможностей; 8192 — конфиг-допущение, ≤ половины окна | ADAPTIVE | `budgetOutputCapTokens`, `GenerationBudgetConfig` |
| L-16 | клампы бюджета | 16000/8000/2000/512 | клампов нет; 512 — явный порог валидности | ADAPTIVE | `generation_budget.dart`; `generation_model.dart` удалён |
| L-17 | формула бюджета | `context−8192−prompt−512` | D.1 с каталогом/изображениями/запасом | ADAPTIVE | `GenerationBudget.compute` |
| L-18 | окно custom | 16000 | окно модели unknown → `BudgetSource.assumption`; поле JSON legacy | ADAPTIVE | `resolveModelCapabilities`; `provider_account.dart` |
| L-19 | карточек на фрагмент | 20 | `budgetCardsPerRequestCap` | REMOVED | `kMaxCardsPerChunk` удалён; planner D.2 |
| L-20 | токены изображения | 1000 | оценщик модели/размер/байты | REMOVED | `content_token_estimator.dart` |
| L-21 | splitInHalf+картинки | запрещено | plan-splitter делит по единицам/страницам с изображениями | ADAPTIVE | `generation_plan_splitter.dart`; legacy-фасад не в production |
| L-22 | жёсткое деление | по символам | иерархия раздел→абзац→предложение→строка→руна | ADAPTIVE | `_splitToBudget/_hardSplit` |
| L-23 | split-once | 1 раз | splitDepth ≤ 3 + бюджет восстановления 12, `truncated` сначала сокращает вывод | ADAPTIVE | `GenerationPipeline._recoveryFor` |
| L-24 | потолок заказа | 200 | без клампа; BigInt/int.max; `tooManyChunks`/`requestedAbovePlan` | REMOVED | `generation_card_limit.dart` |
| L-25 | срез распределения | `maxPerChunk×chunks` | распределение без молчаливого среза; предупреждение | ADAPTIVE | `_distributeLimits` |
| L-26 | пропуск `limit<1` | молча | невозможно; каждый фрагмент получает ≥1 | REMOVED | `PlannedChunk.limit ≥ 1`; pipeline не пропускает |
| L-27 | UI-порог 100k | 100000 | сравнение с бюджетом модели | ADAPTIVE | `generation_screen.dart:_estimateExceedsInputBudget` |
| L-28 | размер вложения | 10 МБ | `account.maxImageBytes` иначе inline-политика | ADAPTIVE | `CardGenerationService._validateAttachments` |
| L-29 | image-parts | 8 | `account.maxImagesPerRequest`; 8 — допущение при неизвестности | ADAPTIVE | planner `_prepareBudget`; service `_withDocumentImages` |
| L-30 | байты image-parts | 24 МБ | `account.maxImageBytes`/`maxRequestBytes`; допущение при неизвестности | ADAPTIVE | plan `_evaluate`; service |
| L-31 | молчаливое усечение | break/continue | `catalogOnly`/`omitted` в плане; не вошедшие остаются в каталоге | ADAPTIVE | `_selectCatalog`, `selectVisionDocumentImages` |
| L-32 | контекст каталога | 160 символов | без изменений | UNRESOLVED | `document_image.dart`; формат строки каталога |
| L-33 | файл/подпись | 80 символов | без изменений | UNRESOLVED | `generation_images.dart:_clean` |
| L-34 | UI-оценка vision | ≤ 8 | из `maxImagesPerRequest`/конфига | REMOVED | `generation_screen.dart` |
| L-35 | vision по имени | эвристика | legacy-инференс сохранён; v2-поле `supports_vision` | UNRESOLVED | `provider_account.dart`; UI-переключатель уже есть |
| L-36 | PDF как документ | Anthropic/Gemini | без изменений | PROVIDER | `provider_protocol.dart` |
| L-37 | повторы транспорта | 4/1–30 c | без изменений | INFRASTRUCTURE | `retry_policy.dart` |
| L-38 | лестница совместимости | ≤ 3 | без изменений | PROVIDER | `card_generation_service.dart` |
| L-39 | таймауты Dio | 15/60/180 c | без изменений | INFRASTRUCTURE | `app_providers.dart` |
| L-40 | поиск иллюстраций | 90 c | без изменений | SAFETY | `generation_pipeline.dart` |
| L-41 | таймауты поиска | 6/20 c, 4 загрузки | без изменений | SAFETY | `image_search_service.dart` |
| L-42 | debug-диагностика | 2000 символов | без изменений | SAFETY | `generation_diagnostics.dart` |
| L-43 | контент-правила | 500/2000/3/200 | без изменений | SAFETY | `card_content_validator.dart` |
| L-44 | число карточек только текстом | поля нет | `GenerationRunRequest.requestedCards` и парсер без клампа; UI-поле не добавлено (сохранён существующий UI) | UNRESOLVED | `generation_run.dart`, `generation_screen.dart` |

### Q.6 Остающиеся ограничения и технические предохранители

- `GenerationChunkPlannerConfig`: `maxChunks = 512`, `maxSplitDepth = 3`,
  допущения 8 частей/10 МБ/24 МБ/32 МБ — явные поля, не «магические» числа
  модели; попадают в `unknownFields`.
- `GenerationPipeline.maxRecoveryRequests = 12` — предел дополнительных
  запросов восстановления за запуск; после него фрагмент фиксируется ошибкой.
- Легаси-фасад `GenerationChunker` (методы `chunkDocuments`/`chunkAll`/
  `splitInHalf`) остаётся для обратной совместимости тестов/вызовов; в
  production не используется и лимиты плана не переприменяет.
- Оценка токенов остаётся эвристикой (2,5 симв./токен, изображения —
  размер/байты); калибровка по `usage` — этап G.
- Парсерные пределы L-05…L-11, L-32/L-33 и отсутствие числового поля L-44 — вне
  объёма этого этапа; см. `journal/KNOWN_LIMITATIONS.md` L128–L133.

## R. TASK 03: надёжность, калибровка и прозрачность (2026-11-19)

**Статус:** выполнено по фактическому коду; схема БД и `format_version` не
менялись. Аудит и перечень подтверждённых дефектов — `journal/task03/audit.md`.
Ниже — что изменено относительно раздела Q и что осталось.

### R.1 Единая оценка входа и калибровка

- `lib/domain/generation/token_accounting.dart` — `TokenValue` с видом
  `exact | estimate | reserve | unknown`, `TokenCalibrationSample` и
  `TokenCalibrationReport`. Неизвестное значение — `null`, не 0; оценка никогда
  не подписывается как факт.
- `lib/api/generation/generation_request_estimator.dart` — оценка **фактически
  собранного** `userContent` (материалы + пожелания + каталог + сводка
  продолжения), системного промпта, канонической схемы и image-частей тем же
  `ContentTokenEstimator`, что у планировщика. Сервис сохраняет
  `estimatedInputTokens`/`estimatedOutputTokens`/`estimatorVersion` в
  `GenerationResult`; пайплайн сравнивает их с `usage` провайдера и с оценкой
  плана (`TokenCalibrationSample`: `plannedInput`/`requestInput`/`actual*`).
- `GenerationRunResult.calibration` — отчёт запуска: отношения «факт/оценка»,
  разброс, число ответов без `usage` и число упавших запросов (у них `usage`
  нет). Debug-диагностика `GenerationDiagnostics.tokenCalibration` печатает
  сводку и отклонения > 20 %; release — no-op.
- Оценка остаётся консервативной эвристикой: `estimated*` — `estimate`,
  `max_tokens` — `reserve`, `usage` — `exact`. Факт одного запроса не
  используется как гарантия для другого; калибровка только собирает выборку.

### R.2 Возможности модели и лимиты запроса

- `lib/domain/generation/generation_request_limits.dart` — единый резолвер
  лимитов (`maxImagesPerRequest`, байты изображения/запроса, тело запроса) с
  источником каждого значения (`user`/`preset`/`unknown`). Планировщик, сервис
  и UI используют его; расхождение «8 в плане, 8 в сервисе, 24 МБ отдельно»
  устранено.
- Fallback `8` image-частей и `10/24/32 МБ` остаются **конфигурационными
  допущениями приложения** (`GenerationChunkPlannerConfig`), только когда
  аккаунт не сообщает лимит. Они попадают в `unknownFields` плана
  (`max_images_per_request`, `max_image_bytes`, `max_request_bytes`),
  `GenerationRequestLimits.assumptionFields` и предупреждение плана
  `assumedImageLimits`; за подтверждённую возможность модели не выдаются.
- `ModelCapabilities.sources` и `GenerationPlan.capabilitySources` — карта
  источник→значение для диагностики (`context_window`, `max_output_tokens`,
  `image_limits`, `pricing`, `max_cards_per_request`, `tokenizer`).
- Документные изображения при модели без поддержки изображений больше не
  попадают в `imageParts`: план помечает их `unsupportedModel`/`catalogOnly` и
  предупреждает `imagesWithoutVision`; байты не отправляются, `image_id` при
  импорте разрешается из локального каталога.

### R.3 Прозрачность изображений

- `GenerationPlan.images` — `PlannedImage` со статусом
  `sentToModel | catalogOnly | unsupportedModel | omittedBudget |
  omittedPayload` и геттерами `imagesSentToModel`/`imagesCatalogOnly`/
  `imagesUnsupported`/`imagesOmitted`.
- Контракт запроса: `GenerationRequest.documentImageParts` — **префикс**
  `documentImages`; сервис отправляет ровно его, не переранжируя и не урезая
  повторно. Легаси-режим (`null`) сохраняет старый отбор
  `selectVisionDocumentImages` для совместимости.
- Планировщик дедуплицирует одинаковые байты image-частей (SHA-256,
  `documentImageDigest`); второе изображение остаётся в каталоге, сервис
  дополнительно фиксирует `skippedDocumentImageIds` для диагностики.
- Предпросмотр показывает сводку «передано модели / только в каталоге / без
  поддержки изображений / исключено», поэтому «осталось в каталоге» больше не
  выглядит как «модель это видела».

### R.4 Prompt-only: согласованность нескольких запросов

- `lib/domain/generation/generation_continuity.dart` —
  `GenerationContinuityState`: компактная сводка уже **принятых** карточек
  (front/back до 140/80 символов, до 40 карточек, до 40 тегов, бюджет
  `kPromptOnlyContinuationMaxTokens = 1200`). Сводка добавляется в `<wishes>`
  после исходного текста пользователя; сам текст не переписывается.
- `PromptOnlyPlanner` резервирует `continuationReserveTokens` в бюджете
  каждого запроса после первого (`GenerationEstimate.continuationReserveTokens`)
  и учитывает байты в проверке тела; сводка не растёт бесконечно.
- Пайплайн ведёт состояние в рамках запуска; при повторе упавших фрагментов
  состояние инициализируется карточками предыдущего результата. Дедупликация
  карточек по `contentHashOf` остаётся последним барьером.

### R.5 Восстановление

- Порядок `truncated` приведён к F.4: (1) уменьшить ожидаемый вывод
  (лимит вдвое), (2) поднять резерв вывода до `outputCap` без изменения входа,
  (3) разделить вход по единицам; при `limit == 1` последняя попытка делит
  фрагмент на две части по 1 карточке (`allowLimitOverflow`) — осознанное
  исключение только для recovery, заказ пользователя не меняется.
- `contextOverflow`/`payloadTooLarge` делят вход сразу; `429`, сеть,
  auth, refusal, невалидный JSON не дробятся. `Retry-After` переносится в
  `GenerationChunkFailure.retryAfter` и показывается в предпросмотре.
- Бюджет восстановления — `generationRecoveryBudget`: `max(configured,
  plannedRequests/8)`, верхняя граница 64, `0` — явное отключение. Списание
  идёт по **дополнительным** запросам (новая попытка/дети минус заменяемый),
  а не по числу детей. В результате — `recoveryRequestsUsed`/`recoveryBudget`/
  `recoveryBudgetExhausted`.
- `GenerationPlanSplitter.withContext` получает оценщик плана и
  `capabilities.imageTokens`; при дроблении сохраняются `unitIds`, порядок,
  image-части/каталог и их id.

### R.6 Распределение карточек (D.5)

- `_tuneSoftTarget` учитывает заказ: при `outputCap` карточек на запрос
  целевое число фрагментов `ceil(requested/cap)`; мягкая цель —
  80 % среднего объёма материала на фрагмент, но не ниже
  `minSoftTargetMaterialTokens` (512). Это устраняет скрытое занижение
  `achievableCards`, когда материала хватает на весь заказ.
- D.5-укрупнение и распределение лимитов не менялись по контракту: сумма
  лимитов ≤ заказа (или 1 на фрагмент при невозможности укрупнения),
  `requestedCards` не подменяется, предупреждения `requestedAbovePlan`/
  `cardsAboveRequested` показывают реальную причину.

### R.7 UI и диагностика

- Числовое поле «Сколько карточек» (`generation-cards-count`): валидация
  положительного целого, технический предел `int` (не продуктовые 20/200),
  значение уходит в `GenerationRunRequest.requestedCards`; пусто — прежний
  разбор из пожеланий.
- Предпросмотр плана до запуска строится **тем же** `GenerationPlanBuilder`
  (кэш по входам): «фрагментов/запросов/запрошено/достижимо», предупреждения
  `unknownCapabilities`, `assumedImageLimits`, `imagesWithoutVision`,
  `catalogOnlyImages`, `omittedUnits`, `requestedAbovePlan`,
  `cardsAboveRequested`; невалидный план блокирует запуск с причиной.
- Предпросмотр результата: постоянные баннеры «частичный результат» и
  «генерация остановлена» (fatal), сводка изображений, число запросов
  восстановления; `Retry-After` — в причине фрагмента.

### R.8 Что осталось (см. `journal/KNOWN_LIMITATIONS.md` L122–L136)

- Точного токенизатора провайдера нет; оценка остаётся эвристикой, а
  калибровка — статистикой, не гарантией.
- `usage` обрезанного/невалидного ответа адаптеры не возвращают: такие
  запросы учитываются как «без usage» и не калибруются.
- Семантический дедуп prompt-only не реализован: сводка снижает повторы, но
  модель может повторить факт, не попавший в компактное состояние (бюджет
  1200 токенов).
- Парсеры не сообщают, какие изображения отброшены фильтрами; план видит
  только извлечённые изображения.
- `ProviderCapabilitiesDialog` (ввод возможностей/цен в UI) не добавлен;
  `capabilitySources` доступен в плане/диагностике.
- Реальные пределы провайдеров и негативные live-контракты не проверялись.
