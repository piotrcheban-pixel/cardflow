# PROGRESS — CardFlow: генерация v3 (внешняя память прогонов)

## Сделано

**Срез 8 (2026-11-28) — Persistence: черновики, миграция, идемпотентный импорт.**
- **Схема v2** (ADR-051, `lib/data/db/tables.dart`, `app_database.dart`):
  `generation_runs`, `generation_units`, `generation_batches`, `card_drafts`,
  `knowledge_maps`; таблицы SPEC A5 не менялись, `generation_jobs` продолжает
  заполняться (совместимое представление для UI). `schemaVersion = 2`,
  шаговая миграция 1 → 2 (`createTable` + явный `createIndex` — `Migrator`
  индексы сам не создаёт), понижение/неизвестная версия — fail-fast.
  Снимки: `drift_schemas/drift_schema_v2.json` (`schema dump`),
  `test/unit/data/db/migrations/generated/*` и `test/migrations/generated/*`
  (`schema steps` + `schema generate`). `.bak` перед миграцией —
  `backupBeforeMigration` в `database_opener.dart` (ADR-005 §5).
- `lib/data/generation/drift_generation_run_store.dart`: `openRun` (идемпотентен
  по `runId`, не сбрасывает принятое), `saveStage`, `saveBatch`, `saveDraft`
  (`InsertMode.insertOrIgnore` + уникальный `idx_card_drafts_run_hash`),
  `saveDeckId`, `loadRun`, `unitsOfRun`, `latestResumableRunId`;
  `GenerationRunCardSink implements CardSink` — карточка пишется в момент
  принятия, сбой на 5-м батче не теряет первые 4.
- `lib/domain/generation/generation_run_snapshot.dart` + `run_resume.dart`:
  `GenerationBatchStatus` (`pending|running|done|failed`), `GenerationBatchRecord`,
  `RunCardDraft`, `GenerationRunSnapshot` (`resumeBatchIndex`, `resumeStage`,
  `isResumable`), `planGenerationResume` — выполненные партии не
  перезапрашиваются; без единиц карты → `understanding`; все партии выполнены →
  `replenishing`; завершённый прогон не восстанавливается.
- `lib/data/generation/drift_knowledge_map_cache.dart`: `DriftKnowledgeMapCache`
  на `knowledge_maps` — повторный материал не платит за Understanding после
  перезапуска; повреждённая строка — промах. Форматы `knowledge_map_json.dart`
  и `generated_card_json.dart` (v1, строгий разбор).
- `DriftGenerationCardStore.importRunCards`: импорт черновиков **одной
  транзакцией**, идемпотентно по (`run_id`, `content_hash`), отметки
  `imported_card_id`/`imported_at` в той же транзакции; `_resolveDeck` общий с
  `importGeneratedCards`.
- Конвейер, UI и `generationV3` **не менялись** (подключение — S9).

**Срез 7 (2026-11-28) — Replenish и partial.**
- `lib/domain/generation/replenish_stage.dart`: `ReplenishStage` — долг это
  слоты заказа без принятой пары (`unit_id` + `angle`); добор идёт только по
  карточкам долга и единицам **исходного** плана (новые единицы не выдумываются);
  каждая партия несёт `<already_accepted>` своих единиц. В принятое идёт только
  карточка, закрывающая слот; повтор принятого/чужой угол — `surplus` (долг не
  уменьшает и прогресса не даёт). Предохранители: `maxPasses = 3`,
  `maxRequests = max(3, requested)` (вся операция, включая первый проход),
  `tokenBudget` от оценок плана (факт `usage`, при неизвестном — оценка партии),
  `wallClock` 10 мин от начала. Исчерпание → `partial` с точной причиной
  (`ReplenishStopReason`: `max_passes`/`max_requests`/`token_budget`/`wall_clock`/
  `provider_error`/`cancelled`/`no_unit_plan`). `exhausted_material` — не ошибка
  и не повод добирать (уже объявленные исчерпанными единицы не запрашиваются,
  проход без закрытых слотов останавливает добор), число — `materialCapacity`.
  `ready` только при закрытых слотах и `accepted ≥ requested`; отмена сохраняет
  принятое (`partial`; `cancelled` — только без принятого).
- `lib/domain/generation/generation_report.dart`: `GenerationReport.fromReplenish`
  — `requested`, `accepted`, причины машинными кодами, покрытие единиц
  (`UnitCoverage`), расход токенов по этапам (`generating`/`replenishing`),
  версии промптов (подставляет вызывающий слой), длительность; `isComplete`
  требует закрытых слотов.
- `lib/api/generation/cards_batch_engine.dart`: фикс среза 5 — `_addUsage`
  начинал сумму с `const TokenUsage()` и по правилу «неизвестное обнуляет
  сумму» всегда возвращал `null`; теперь «ещё нет расхода» ≠ «неизвестно».
- Старый конвейер, UI, схема БД и `generationV3` **не менялись**; подключение —
  S9 (протокол §9). Prompt-only — `no_unit_plan` без запросов.
- Тесты (+30): `replenish_stage_test.dart` (25),
  `generation_report_test.dart` (4),
  `replenish_stage_wiring_test.dart` (1 — движок со сбоем 3-го батча → этап →
  отчёт на production-проводке).

**Срез 6 (2026-11-27) — Validation и каскад дедупликации.**
- `lib/api/generation/validation/card_validator.dart`: `CardValidator` —
  структурные проверки A8.4 (длины 500/2000, cloze, теги до 3, LaTeX) и
  семантические эвристики с машинным кодом `CardReasonCode` (ответ не в
  вопросе; вопрос самостоятелен — «этот»/«выше»/«см. рис.»; атомарность —
  перечисление >3; осмысленный cloze; язык ru; `quote_ref` по offsets;
  `section_id`/`unit_id` из партии). Вердикт `accepted | warning | rejected`;
  отброшенное не исчезает (`RejectedCard` хранит исходный JSON). Цитата
  принимается только дословно (`substring(start, end) == quote_ref`),
  почти-цитата — `quoteNotLiteral` без offsets, отсутствие — `quoteOutOfRange`
  с обнулением (ARCH §3.3); ищутся только содержательные блоки.
- `lib/domain/generation/validation/semantic_matcher.dart`: каскад точный ключ →
  нормализованный ключ → символьные шинглы + Жаккар (0.7) → эмбеддинги за
  интерфейсом `TextEmbeddingProvider`; дубль — пара (`DedupPair`), карточки не
  удаляются; сверка с колодой через `existing`.
- `lib/domain/generation/dedup_report.dart`: `DedupLevel` (wire-коды),
  `DedupPair`, `DedupReport` (пары, счётчики по уровням, сильнейший уровень по
  порядку каскада).
- `lib/domain/generation/generation_ledger.dart`: `dedup`/`withDedup` — отчёт по
  уровням в журнале, переживает `record`/`attempt`/`markCause`/`replace`;
  арифметика заказа не менялась.
- Старый валидатор, конвейер, UI, адаптеры и схема БД **не менялись**; новый
  путь не подключён (флаг `generationV3` — S7/S9, протокол §9).
- Тесты (+51): `card_validator_test.dart` (24), `quote_offsets_test.dart` (7),
  `semantic_matcher_test.dart` (14), `dedup_report_test.dart` (6), фикстура
  `test/fixtures/validation/duplicate_pairs.json`.

**Срез 5 (2026-11-27) — Generation: батчи по единицам через существующие
адаптеры.**
- `lib/api/generation/provider_result.dart`: `ProviderResult` (content,
  `ProviderFinishReason` stop/length/refusal/empty/error, usage, refusal,
  rawError, detail) + `ProviderResponseNormalizer` — исход любого из четырёх
  адаптеров в один тип; отмена пробрасывается, остальные исключения —
  результат с кодом. Адаптеры не переписаны.
- `lib/api/generation/cards_batch_port.dart`: `AdapterCardsBatchPort
  implements LlmPort` поверх существующих `buildRequest`/`parseResponse` и
  `GenerationTransport`: промпт `gen-cards-v3`, проекция схемы v3, поштучная
  проверка карточек (обязательные `unit_id`/`angle`/`quote_ref`), спасение
  полных карточек из оборванного ответа, ошибки — `GenerationException`.
- `lib/api/prompts/cards_prompt.dart`: `gen-cards-v3` (единицы с утверждением
  и якорями, `<budget cards>` со строками `<card unit_id angle>`,
  `<already_accepted>` только текущего батча, правила четырёх углов, LaTeX,
  запрет инструкций из материала); копия — `docs/prompts/gen-cards-v3.txt`
  (байтовая сверка тестом).
- `lib/api/generation/cards_batch_engine.dart`: `CardsBatchEngine` —
  последовательный проход по `AllocationPlan`, принятое в `CardSink` по ходу,
  повторы по `RetryPolicy` (429 `Retry-After`, 5xx/таймаут/сеть), 400/401/413/
  402 без повторов, обрезка — деление **по единицам** и добор остатка (для
  неделимой единицы одна повторная попытка), отмена сохраняет принятое;
  `CardsBatchRun` несёт журнал, карточки, `promptVersion`, `cancelled`.
- `lib/api/generation/batch_job_recorder.dart`: `gen-cards-v3` →
  `generation_jobs.prompt_version`; статус задания не меняется (S9).
- `lib/domain/generation/cards_batch.dart`: `CardsBatch`, `AcceptedCard`,
  `splitBatchByUnits` (деление по границе единиц, а не по половине карточек).
- `lib/domain/generation/generation_ledger.dart`: `attempts` у партии и
  прогона (повторы и добор в журнале, не в recovery-бюджете).
- `lib/domain/generation/ports.dart`: `LlmPort.generate(CardsBatch, …)`,
  `CancellationSignal`; `generated_card.dart`: `unitId`/`angle`/`quoteRef`.
- `lib/api/generation/card_json_schema.dart` + `provider_schema.dart` +
  4 адаптера: расширение `gen-cards-v3` отдельной схемой
  (`cardsResponseSchemaV3`), канон A8.4 не изменён, адаптеры получили
  необязательную `responseSchema`.
- Старый конвейер, UI и схема БД не менялись; путь не подключён (флаг
  `GenerationSettings.generationV3` — S7).
- Тесты (+44): `request_ledger_test.dart` (17), `cards_prompt_test.dart` (8),
  `provider_result_test.dart` (12), `cards_batch_port_test.dart` (6),
  `ports_test.dart` (+1).

**Срез 4 (2026-11-27) — Allocation: веса, Гамильтон, упаковка батчей.**
- `lib/domain/generation/model_profile.dart`: `ModelProfile` (`id`,
  `provider`, `contextWindow`, `maxOutputTokens`, `supportsJsonSchema`,
  `supportsVision`, `concurrency`), `batchTokenBudget` (`contextWindow × 40 %`,
  доля — `batchWindowShare`), `maxCardsPerBatch`, `fitsBatch` (выход ≤ предела
  и вход + выход ≤ бюджета); каталог `kModelProfiles` — **4 провайдера**
  (DeepSeek, OpenAI, Anthropic, Gemini; 8 моделей с id из `kProviderPresets`),
  консервативный профиль для неизвестной модели. В логике упаковки чисел нет.
- `lib/domain/generation/allocation.dart`: `unitDensity` (доля значимых слов
  утверждения, пол `kMinUnitDensity = 0.25`), `kindWeight` (множители вида),
  `unitWeight` = `salience × плотность × тип`; `allocateUnits` — метод
  наибольших остатков на `BigInt` (точная сумма, минимум 1 на отобранную
  единицу, отбор самых весомых при заказе меньше числа единиц, равные
  остатки — по порядку карты); `AllocationAngle`
  (`reverse/cloze/application`), `AllocatedCard.angle` — основная карточка
  `angle == null`, добор только углами, предпочтение по виду единицы и цикл;
  `packBatches` — батчи по единицам (`вход + оценка выхода ≤ 40 % окна`,
  выход ≤ `maxOutputTokens`, общий вход карточек одной единицы, резерв схемы
  только при `supportsJsonSchema`), батч, не влезающий в профиль, —
  `ArgumentError`; `AllocationPlan` — инвариант «Σ бюджетов == заказ»,
  `materialLimited`/`shortfall`, `waves` по `concurrency`.
- Старый планировщик (`CardAllocator`/`GenerationChunkPlanner`/
  `OutputBatchPlanner`), конвейер, UI и схема БД **не менялись**: новый этап не
  подключён к старому пути (протокол §9).
- Тесты (+43): `model_profile_test.dart` (9), `allocation_test.dart` (34), в
  том числе два DoD-property-теста (200 случайных карт; сумма == заказ, минимум
  1, детерминизм, ни один батч не превышает профиль, добор только углами).

**Срез 3 (2026-11-27) — Understanding: KnowledgeMap, промпт gen-map-v1, разбор
и кэш.**
- `lib/domain/generation/knowledge_map.dart`: `KnowledgeUnit` (`id`,
  `sectionId`, `topic`, `kind`, `statement`, `anchors`, `salience`,
  `splittable`), `KnowledgeAnchor`, `KnowledgeMap` (индекс по id **O(1)**,
  `unitsOfSection`, `splittableUnits`, дубли id — `ArgumentError`),
  `KnowledgeUnitKind` (`definition/fact/relation/formula/procedure`) и
  каноническая JSON-схема `gen-map-v1` по образцу A8.4 (strict: все поля в
  `required`, nullable `section_id`, `additionalProperties: false`).
- `lib/api/prompts/understanding_prompt.dart`: отдельная версия `gen-map-v1` —
  только извлечение атомарных единиц, без правил оформления карточек;
  `buildUnderstandingUserContent` (`<section>` + `<block id>`); копия —
  `docs/prompts/gen-map-v1.txt` (тест сверяет байты).
- `lib/api/generation/knowledge_map_caller.dart`: контракт вызова модели
  (`KnowledgeMapRequest`, `KnowledgeMapRawResponse` с `usage`/`truncated`).
- `lib/api/generation/knowledge_map_parser.dart`: id единицы присваивает
  приложение (`ku:<fragmentId>#<индекс ответа>`), `section_id` — подсказка,
  поштучная проверка единиц (схема, `salience` 0..1, якоря из запроса),
  причины `json_parse` / `schema_invalid`.
- `lib/api/generation/understanding_service.dart`: фрагмент = раздел
  `ContentModel`; невалидный/обрезанный ответ или сбой провайдера **помечают
  фрагмент**, остальные обрабатываются; отмена пробрасывается; кэш только
  полной карты; `usage` — только факт из ответов (неизвестное слагаемое делает
  сумму `null`, а не нулём).
- `lib/data/generation/in_memory_knowledge_map_cache.dart`: in-memory
  реализация порта `KnowledgeMapCache<KnowledgeMap>` (БД — срез 7).
- Тесты (+42): `knowledge_map_test.dart` (8), `knowledge_map_parser_test.dart`
  (13 + golden-фикстура), `understanding_prompt_test.dart` (4),
  `understanding_service_test.dart` (11),
  `in_memory_knowledge_map_cache_test.dart` (5).

**Срез 2 (2026-11-27) — журнал прогона, стейт-машина этапов, порты.**
- `lib/domain/generation/generation_ledger.dart`: `GenerationLedger` (суммарно)
  и `GenerationBatchLedger` (по партиям) — `requested`, `generated`, `invalid`,
  `duplicates`, `accepted`, `remaining`; неизменяемые значения, события через
  `record`/`withCause`/`markCause`; `requested` = **сумма бюджетов**
  (`fromBudgets`, `fromPlan`), партии нумеруются подряд с 0. `ShortfallKind` —
  wire-коды TASK (`exhausted_material`, `provider_error`, `truncated`,
  `validation_rejects`, `cancelled`), приоритет прогона — Q7; дубли —
  отдельный счётчик, класс — `validation_rejects` (Q5); у партии без событий
  `shortfall == null`.
- `lib/domain/generation/generation_run.dart`: стейт-машина прогона —
  `GenerationStage` (`planned → understanding → generating → validating →
  dedup → replenishing → ready | partial | failed | cancelled`),
  `GenerationRunState.advanceTo` (недопустимый переход —
  `InvalidGenerationStageTransition`), `GenerationStage.jobStatus` для
  `generation_jobs.status` (SPEC A5). `ready`/`partial` — только из
  `replenishing`, `failed`/`cancelled` — с любого незавершённого этапа.
- `lib/domain/generation/ports.dart`: `LlmPort` (один вызов на партию,
  `batchIndex`), `CardSink` (принятое пишется по ходу), `ProgressSink` (этап +
  журнал), `Clock`, `KnowledgeMapCache<M>` (ключ — документ + хеш; тип карты —
  параметр, Q6). Этапы зависят только от портов.
- Guard `test/guards/architecture_test.dart` расширен: `lib/domain/` не
  импортирует `package:dio/` и `package:drift/` (ADR-050), +1 self-test.
- Старый конвейер, UI, схема БД и публичные типы провайдеров не менялись.
- Тесты (+38): `test/unit/domain/generation/generation_ledger_test.dart` (21),
  `generation_stage_test.dart` (11), `ports_test.dart` (5), guard (+1).

**Срез 1 (2026-11-27) — ContentModel: Document → Section → Block с якорями.**
- `lib/api/generation/content_model.dart`: `Document`, `Section`, `Block`,
  `NoiseKind`. Инварианты проверяются в конструкторе `Document` (offsets точные
  `text.substring(start, end) == text`, блоки не пересекаются, каждый блок
  целиком в одном разделе, разделы не пересекаются, иерархия замкнута).
  `block(id)`/`section(id)` — индексные карты (**O(1)**), `blockAt(offset)` —
  двоичный поиск, `blocksOfSection`, `childrenOf`, `contentBlocks`/
  `noiseBlocks`, `contentLength`, `Document.empty`.
- `lib/api/generation/content_normalizer.dart`: `ContentNormalizer` — пробелы
  (включая NBSP, типографские и нулевой ширины), `ё→е`, кавычки, тире/дефисы и
  мягкий перенос. Нормализация **не** меняет offsets: `Block.text` — текст
  источника, сравнивается `Block.normalizedText`.
- `lib/api/generation/content_model_builder.dart`: `ContentModelBuilder`
  (`ParsedDocument → Document`; `buildFromOutcome` — ошибка файла даёт пустую
  модель без исключения) и `ContentNoiseDetector` (номер страницы, подпись
  «Рис./Fig. N», оглавление по заголовку раздела и по отточию с номером,
  колонтитул — строка, повторяющаяся в ≥2 разделах первой или последней).
  Блок = строка источника; границы разделов расширены до границ блоков —
  поэтому раздел не рвёт абзац. Иерархия — по нумерации заголовков (`1.` → 0,
  `1.1` → 1), скачок уровня сглаживается, разрыв нумерации делает раздел
  корневым.
- Парсеры и их публичные типы **не менялись**, генерация и LLM не тронуты.
- Тесты (+24): `test/unit/api/generation/content_model_test.dart` (13),
  `content_normalizer_test.dart` (6), `content_model_parsers_test.dart` (5 фикстур:
  PDF, DOCX, PPTX, MD, скан без текстового слоя).

## Проверено

**Срез 8.** Гейты: `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib
test` → **No issues found!**; `.fvm\versions\3.47.9\bin\dart.bat format
--set-exit-if-changed lib test` → **681 files, 0 changed**;
`.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --exclude-tags golden` →
**3109 passed + 17 skipped**, `exit 0` (baseline 3073 + 17 skipped, +36).
DoD-команды: `schema_migration_v2_test.dart` 4 passed,
`drift_generation_run_store_test.dart` 12 passed, `drift_run_import_test.dart`
5 passed, `drift_knowledge_map_cache_test.dart` 12 passed, `schema_test.dart`
27 passed, `test/migrations/migration_test.dart` 5 passed. Красная фаза:
`SchemaVerifier` — «comparing idx_card_drafts_run_hash: The actual schema does
not contain anything with this name» (индекс не создавался `createTable`) и
`Bad state: Too many elements` в тесте восстановления. Итоги —
`journal/generation-v3/verify-s8.md`. БД-тесты только in-memory drift + одна
файловая БД для `.bak`; полный прогон — 3:13.

**Срез 7.** Красная фаза — `journal/generation-v3/red-s7.txt` (**3 прошло /
27 упало**, 0 ошибок компиляции, 51 assertion-level маркер:
`Expected: <3> Actual: <0>`, `Expected: ReplenishStopReason:<…complete>
Actual: <…noUnitPlan>`). Гейты: `.\.fvm\versions\3.47.9\bin\flutter.bat analyze
--no-pub lib test` → **No issues found!**; `.\.fvm\versions\3.47.9\bin\dart.bat
format --set-exit-if-changed lib test` → **665 files, 0 changed**;
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
--exclude-tags golden` → **3073 passed + 17 skipped**, `exit 0` (baseline 3043 +
17 + 30); покрытие рукописного кода **90.9 % (25300/27847)** при пороге 80 %;
`replenish_stage.dart` — **98.8 % (241/244)**, `generation_report.dart` —
**100 % (68/68)**, `cards_batch_engine.dart` — 90.2 % (110/122),
`generation_ledger.dart` — 99.2 % (120/121). Регрессия движка после фикса
`_addUsage` — `request_ledger_test.dart` **17 passed**. DoD: 40/12 →
`partial` + `exhausted_material` (запросов нет), сбой 3-го батча → добор
(4 → 6), `max_passes` после 3 проходов, отмена → `partial` с сохранением
(2 → 3). Полный лог — `green-s7-full.txt`, покрытие — `coverage-s7.txt`,
итоги — `verify-s7.md`.

**Срез 6.** Красная фаза — `journal/generation-v3/red-s6.txt` (**6 прошло /
45 упало**, assertion-level: `Expected: <1> Actual: <0>`,
`Expected: DedupLevel:<DedupLevel.exact> Actual: <null>`,
`Expected: <3> Actual: <0>`, `Expected: throws GenerationException
Actual: <Closure…>`). Гейты: `.\.fvm\versions\3.47.9\bin\flutter.bat analyze
--no-pub lib test` → **No issues found!**; `.\.fvm\versions\3.47.9\bin\dart.bat
format --set-exit-if-changed lib test` → **660 files, 0 changed**;
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
--exclude-tags golden` → **3043 passed + 17 skipped**, `exit 0` (baseline
2992 + 17 + 51); покрытие рукописного кода **90.8 % (24989/27535)** при
пороге 80 %; `card_validator.dart` — 87.7 % (214/244), `semantic_matcher.dart` —
96.4 % (81/84), `dedup_report.dart` — 70.8 % (34/48, непокрыты
`fromWire`/`==`/`toString`), `generation_ledger.dart` — 99.2 % (120/121).
DoD: тест на каждую проверку + ложные срабатывания; фикстура — 3 пары на своих
уровнях, 2 «ловушки» без пар; отчёт по уровням в `GenerationLedger.dedup`.
Полный лог — `journal/generation-v3/green-s6-full.txt`, покрытие —
`coverage-s6.txt`, итоги — `verify-s6.md`.

**Срез 5.** Красная фаза — `journal/generation-v3/red-s5.txt` (**9 прошло /
24 упало**, assertion-level: `Expected: <10> Actual: <null>`, `Expected: true
Actual: <false>` для копии промпта, `GenerationException не брошен`).
Гейты: `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` →
**No issues found!**; `.\.fvm\versions\3.47.9\bin\dart.bat format
--set-exit-if-changed lib test` → **0 changed**;
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage
--exclude-tags golden` → **2992 passed + 17 skipped**, `exit 0` (baseline
2948 + 17 + 44); покрытие рукописного кода **90.8 % (24657/27156)** при
пороге 80 %; `cards_prompt.dart` — 100 %, `batch_job_recorder.dart` — 100 %,
`cards_batch_port.dart` — 93.5 %, `cards_batch_engine.dart` — 88.5 %,
`generation_ledger.dart` — 99.2 %. DoD-команда S4
(`test/unit/api/generation/request_ledger_test.dart`) — **17 passed**. Полный
лог — `journal/generation-v3/green-s5-full.txt`, покрытие —
`coverage-s5.txt`, итоги — `verify-s5.md`.

**Срез 4.** Красная фаза — `journal/generation-v3/red-s4.txt` (**9 прошло /
33 упало**, падения assertion-level: `Expected: <40000> Actual: <0>`,
`Expected: a numeric value within <1e-9> of <0.8333…> Actual: <0.0>`,
`Expected: [5, 3, 2] Actual: []`, `Expected: <1000000> Actual: <0>`,
`Expected: AllocationAngle.<cloze> Actual: AllocationAngle.<reverse>`). Гейты:
`.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` → **No issues
found!**; `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed
lib test` → **643 files, 0 changed**; `.\.fvm\versions\3.47.9\bin\flutter.bat
test --no-pub --coverage --exclude-tags golden` → **2948 passed + 17 skipped**,
`exit 0` (baseline 2905 + 17 + 43); покрытие рукописного кода **90.9 %
(24302/26744)** при пороге 80 %; `allocation.dart` — **100.0 % (190/190)** ≥
DoD-порога 95 %, `model_profile.dart` — 100.0 % (30/30). Полный лог —
`journal/generation-v3/green-s4-full.txt`, покрытие —
`coverage-s4.txt`, итоги — `verify-s4.md`.

**Срез 3.** Красная фаза — `journal/generation-v3/red-s3.txt` (29 падений
assertion-level: `Expected: <3> Actual: <0>`, `Expected: true Actual: <false>`,
`Expected: 'gen-map-v1' Actual: 'gen-map-v0'`). Гейты:
`.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` → **No issues
found!**; `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed
lib test` → **639 files, 0 changed**;
`.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --coverage --exclude-tags
golden` → **2905 passed + 17 skipped**, `exit 0` (baseline 2863 + 17 + 42);
покрытие рукописного кода **90.8 % (24082/26524)** при пороге 80 %;
`knowledge_map_parser.dart` — **100 % (61/61)**, `understanding_service.dart` —
95.0 % (95/100), `knowledge_map.dart` — 75 % (48/64, непокрыты только
`==`/`hashCode`/`toString`/`blockIds`), `knowledge_map_caller.dart` — 33.3 %
(2/6, объявления контракта; прецедент `ports.dart`). Полный лог —
`journal/generation-v3/green-s3-full.txt`, итоги — `verify-s3.md`.

**Срез 2.** Красная фаза — `journal/generation-v3/red-s2.txt`: 28 падений
assertion-level (`Expected: <211> Actual: <0>`, `Expected: throws
<Instance of 'AssertionError'>`, `Expected: contains 'принято 3/8'`), а не
только ошибки компиляции. Гейты: `.\.fvm\versions\3.47.9\bin\flutter.bat
analyze --no-pub lib test` → **No issues found!**;
`.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` →
**628 files, 0 changed**; `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub
--coverage --exclude-tags golden` → **2863 passed + 17 skipped**, `exit 0`
(baseline 2825 + 17 + 38 новых); покрытие рукописного кода **90.8 %
(23860/26277)** при пороге 80 %; `generation_ledger.dart` — **100 % (99/99)**;
`generation_run.dart` — 94.7 % (36/38; непокрыты прежние `planWarnings`).
DoD-тесты: property «Σ бюджетов == requested» на 200 случайных планах,
`generating → ready` невозможно (полная матрица 10×10), после сбоя батча
принятое сохраняется. Итоги — `journal/generation-v3/verify-s2.md`.

**Срез 1.** Красная фаза — `journal/generation-v3/red-s1.txt` (assertion-level
падения, не только ошибка компиляции).
- `.\.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` →
  **No issues found!** (0 issues).
- `.\.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` →
  **623 files, 0 changed**.
- `.\.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --exclude-tags golden` →
  **2825 passed + 17 skipped**, `exit 0` (baseline 2801 + 17; +24 новых).
- Пять фикстур DoD: offsets точные, блок восстанавливается по id (`same(...)`),
  раздел не рвёт абзац (блоки в границах своего раздела), скан даёт пустую
  модель без исключения. Итоги — `journal/generation-v3/verify-s1.md`.

## НЕ ПОВТОРЯТЬ

- **`CardsBatchEngine._addUsage` нельзя начинать с `const TokenUsage()` по
  правилу «неизвестное слагаемое обнуляет сумму»**: накопитель — «расхода ещё
  нет», а не «неизвестен». С этим правилом `CardsBatchRun.usage` всегда был
  `null` (нашёл срез 7), и отчёт «расход по этапам» показывал пусто. Сумма
  полей сохраняется, если известно хотя бы одно слагаемое.
- **Прогресс добора считать только по закрытым слотам** (`unit_id` + `angle`),
  а не по числу вернувшихся карточек: иначе повтор принятого закрывает долг и
  `accepted ≥ requested` даёт ложный `ready`. Лишние карточки —
  `ReplenishPass.surplus`, они не входят в accepted.
- **`Migrator.createTable` не создаёт объявленные `@TableIndex`.** Шаг миграции
  обязан вызывать `m.createIndex(idxCardDraftsRunHash)`; иначе `SchemaVerifier`
  падает на «The actual schema does not contain anything with this name», а
  уникальность ключа идемпотентности импорта держится только на коде.
- **`SchemaVerifier.startAt(1)` + `AppDatabase` автоматически делает onUpgrade
  до v2.** Нельзя «поставить» БД на версию 1, открыв `AppDatabase`; для данных
  «до миграции» — `testWithDataIntegrity` (createItems в `Batch`, `RawValuesInsertable`
  + `Variable<Object>(value)`: `Value<T>` — не Expression, а `Expression<D extends Object>`).
- **`generation_jobs` — не view, а живая таблица.** Совместимое с UI
  представление поддерживается записью в обе сущности (`openRun`/`saveStage`/
  `saveDeckId`); не переименовывать и не удалять её поля, даже когда
  `generation_runs` стала источником восстановления.
- **Ключ идемпотентности — `contentHashOf(front, back)`,** а не хеш JSON
  черновика: иначе повторный импорт прогона и дедуп колоды считались бы по
  разным ключам (`cards.content_hash`).
- **Не писать байты изображений в черновик.** `card_drafts.card_json` —
  структура без картинок; байты раздувают транзакцию и дублируют `MediaStore`
  (L220). После перезапуска картинка разрешается заново.
- **Не персистить `DedupReport`.** В БД только счётчики партий; пары живут в
  памяти прогона (L219). Вердикт Completion читает числа журнала.
- **`sqlite3` в 3.9: `Database.dispose()` устарел** — использовать `close()`
  (иначе `analyze` даёт `deprecated_member_use`); drift-`isNull`/`isNotNull`
  конфликтуют с matcher — прятать в импорте или не импортировать drift вовсе.
- **`maxRequests` должен включать первый проход.** Доля `ceil(requested/2)`
  при 3 батчах и 6 карточках равна числу уже сделанных запросов — добор
  запрещён ещё до старта (поймано тестом `maxPasses`). Принято
  `max(3, requested)`.
- **`assert(wallClock > Duration.zero)` в const-конструкторе не компилируется**:
  сравнение `Duration` не вычисляется при компиляции (`Constant evaluation
  error`). Положительность — обязанность вызывающего.
- **План без единиц (prompt-only): `unfilled` считать от `requested − accepted`,
  а не по `plan.cards`.** Иначе пустой план выглядит как «заказ закрыт»
  (`complete`/`ready` при нуле принятого) — поймано тестом `no_unit_plan`.
- **Не расширять `ShortfallKind` ради причин предохранителей.**
  `generation_ledger_test` закрепляет 5 wire-кодов; `max_passes`/`max_requests`/
  `token_budget`/`wall_clock` живут в `ReplenishStopReason`, а отчёт несёт их
  вместе с `ShortfallKind` — точность без ломки журнала.
- **Красную фазу перепроверять на финальном наборе тестов.** Первый прогон
  среза 7 дал 2/19 на ранних ожиданиях; после уточнения `f(requested)` и
  добавления тестов лог перезаписан (3/27, 0 ошибок компиляции) — иначе
  red-коммит не соответствует сохранённому логу.
- **`ReplenishPass.surplus` — не «принято»:** ответ может закрыть 0 слотов, но
  вернуть карточки; такие карточки не идут в `accepted` и не делают `ready`.
- **Валидатор и дедуп среза 6 не подключать к конвейеру/UI.** Это отдельные
  этапы, как Allocation/Generation: подключение — S7 (добор/долг) и S9
  (предпросмотр «показать отброшенные») за флагом `generationV3` (протокол §9).
  Валидатор не переписывает `card_content_validator.dart`: тот обслуживает
  production `gen-ru-v9` и остаётся fallback `contains` для prompt-only.
- **«Буквально совпадает» — это `substring(start, end) == quote_ref`.** Не
  сравнивать через `contains`/нормализацию и не писать offsets для
  почти-цитаты: регистр/«ё»/тире/пробелы дают `quoteNotLiteral` без offsets
  (нормализация меняет длину строки), отсутствие — `quoteOutOfRange` с
  обнулением. Цитату искать только в `contentBlocks`: подпись рисунка — мусор.
- **Шинглы — символьные, не словесные.** На словесных 3-шинглах одна вставка
  слова роняет Жаккара до ≈0,55 при пороге 0,7 — почти-дубль не ловится.
  Проверено на фикстуре; порог `similarityThreshold = 0.7`.
- **«Выше/ниже» ловить только в текстовых ссылках.** Голое «выше» даёт ложное
  срабатывание на «давление выше уровня моря». Рабочая форма —
  `(?:сказан|описан|указан|приведен|приведён|рассмотрен)\p{L}*\s+(?:выше|ниже)`;
  первый зелёный прогон поймал баг: «описан выше» (муж. род) не совпадал с
  формой «описано».
- **`Document` требует, чтобы блок был указан в `section.blockIds`.** Тестовая
  фикстура «строка = блок» падала `Invalid argument(s): Блок … принадлежит …,
  но не указан в blockIds раздела`, а не на логике валидатора.
- **`CardReasonCode.isRejecting` — единственное место, где живёт деление
  «отбросить/пометить».** Не размазывать по проверкам: rejected — только
  структурно непригодная запись (нет строк, неизвестный тип, пустой front),
  всё содержательное — warning (A8.4: не отбрасывать молча).
- **Фикстура дедупа не должна переиспользовать один и тот же текст в разных
  парах**: одинаковые карточки дадут лишние пары (exact вместо normalized),
  и «ловушка» перестанет быть ловушкой.
- **Не создавать `const GenerationLedger(...)`.** После среза 6 конструктор
  не const (`dedup` по умолчанию — `DedupReport.empty()`); `replace` обязан
  передавать `dedup: dedup`, иначе отчёт теряется на первом же `record`.

- **Канон A8.4 не расширять ради `gen-cards-v3`.** Три поля живут в отдельной
  схеме `cardsResponseSchemaV3()` (Q12): добавить их в канон и `required` —
  значит потребовать их и от старого промпта `gen-ru-v9`, который их не знает
  (strict-схема отвергнет ответ, и production-генерация сломается до
  включения нового пути). Адаптеры получили только необязательную
  `responseSchema`.
- **Обрезку делить по остатку долга, а не по всем карточкам единицы.** После
  `truncated` принятые карточки уже есть; повторный запрос целой единицы
  заказал бы их снова (дубли в бюджете). `splitBatchByUnits` получает долг
  (`_debtOf`: пара `unit_id` + `angle`), а не исходные карточки партии.
- **Контекст «уже принято» собирать на момент запроса.** Партия в очереди
  создаётся до ответа предыдущей части: её `accepted` — снимок, поэтому перед
  `port.generate` делается `slice.withAcceptedContext(context)`; без этого
  вторая часть партии видит устаревший контекст (тест поймал: 1 вместо 2).
- **`GenerationLedger.fromPlan` — про старый `GenerationPlan`.** Для
  `AllocationPlan` бюджеты партий берутся
  `GenerationLedger.fromBudgets(plan.batches.map((b) => b.cards.length))`.
- **`ProviderResult.isError` — «нет контента для разбора», а не
  `finishReason == error`.** Иначе обрезанный ответ без контента (Anthropic
  бросает `truncated` до `tool_use`) считался бы не ошибкой, а обрезанный с
  контентом — ошибкой; оба случая важны движку по-разному.
- **Не ждать `usage` от исключения адаптера.** Anthropic при `max_tokens` без
  `tool_use` бросает до разбора расхода: `ProviderResult.usage` — `null`, а не
  выдуманные числа.
- **В тестах фейка-порта, который в обработчике читает `port.calls`, — только
  `late final port; port = _FakeLlmPort(onGenerate: …)`.** Обычный
  `final port = _FakeLlmPort(onGenerate: (b) { if (port.calls…) })` — ошибка
  компиляции «local variable referenced before it is declared».
- **Не изобретать маркер отмены через фиктивный `GenerationResult`.** Цикл
  повторов держать в `run` с локальным флагом `cancelledNow`: иначе появляется
  «магический» результат-заглушка и путаница с причиной партии.
- **Фикстура обрезанного ответа обязана содержать `finish_reason: length`.**
  Иначе порт считает ответ успешным и падает `json_parse` на оборванном JSON
  (наш первый зелёный прогон это поймал).
- **Промпт `gen-cards-v3` не должен содержать подстановок Dart и сырых
  шаблонов** (`$`, `${`, `TODO`); cloze-разметка `{{c1::…}}` в тексте
  допустима и проверяется тестом копии байт в байт.
- **Негативный тест с `const`-конструктором и `assert` — ошибка компиляции, а
  не проверка.** `const KnowledgeAnchor(blockId: '', ...)` внутри `const`-списка
  вычисляется на этапе компиляции: тест не загружается («Constant evaluation
  error»), а не падает assertion-level. Негативные кейсы конструировать без
  `const` (см. `knowledge_map_test.dart`, инварианты).
- **`prefer_initializing_formals` и приватные именованные параметры.**
  Конструктор с `required KnowledgeMapCaller caller` + `_caller = caller` даёт
  info-замечание; `this._caller` в именованном параметре запрещён языком.
  Коллабораторы сервиса/парсера — публичные `final`-поля (`this.caller`,
  `this.cache`, `this.parser`), тесты и последующие этапы читают их напрямую.
- **`KnowledgeMapCache` не дублировать новым интерфейсом.** Порт уже объявлен в
  `lib/domain/generation/ports.dart` (`KnowledgeMapCache<M>`, срез 2, Q6);
  срез 3 добавляет только реализацию `InMemoryKnowledgeMapCache` и подставляет
  `KnowledgeMapCache<KnowledgeMap>`.
- **Кэш карты писать только при полном успехе.** Иначе битый/упавший фрагмент
  «запомнится» как готовая карта, и повторный прогон не позовёт модель.
  Ключ кэша включает версию промпта (`gen-map-v1`), иначе смена промпта вернёт
  карту, построенную другой инструкцией.
- **Не использовать `\b` в регулярках после кириллицы.** В ECMAScript-регулярках
  (Dart `RegExp`) граница слова считается по ASCII: `^\s*(?:рис)\b\.` **не
  ловит** «Рис. 4» — на этом упал первый зелёный прогон. Подпись рисунка
  детектируется без `\b` (`_figureCaption` в `content_model_builder.dart`).
- **PDF-фикстуры — только латиница.** `document_fixtures.dart` собирает PDF в
  latin1 (`_pdfEscape` + `latin1.encode`), кириллица падает с
  `Invalid argument (string): Contains invalid characters`. Русский текст — в
  DOCX/PPTX/MD-фикстурах, PDF-сценарий берёт латинские строки.
- **Многострочная страница PDF — только `buildPdfFromFixturePages`.**
  `buildPdfPages` пишет текст страницы одной `Tj`-строкой (переводы строк в
  литерал не вставляются); `PdfFixturePage(text: 'line1\nline2')` пишет каждую
  строку отдельной `Tj`, и pdfrx отдаёт их через `\n` (проверено пробой).
- **Не проверять «раздел не рвёт абзац» через `ParsedDocumentBuilder`:**
  он всегда разделяет разделы `\n\n`, граница внутри строки не возникнет.
  Такой случай задаётся вручную `ParsedSection(start: 20, end: 43)` — см.
  тест «граница раздела внутри строки не рвёт абзац».
- **Не считать падение `settings_persistence_file_db_test.dart` регрессией.**
  На полном прогоне под нагрузкой он падает `TimeoutException 30s` (файловая
  drift-БД в OneDrive); отдельно и на повторном полном прогоне — зелёный.
- **Не читать `journal/STATE.md` целиком** и не искать «9 срезов» в TASK.txt
  (Q1 в `journal/QUESTIONS.md`): срез 1 = `ContentModel`, а не `MaterialUnit`
  из `BACKLOG.md` (Q3).
- **Const-контекст в тесте не даёт покрытия строке конструктора.** Тест с
  `const GenerationRunState.planned()` вычисляется при компиляции, и lcov не
  считает строку инициализатора исполненной (`generation_run.dart:482` = 0).
  Для покрытия константного конструктора вызывать его без `const`.
- **Проверять арифметику негативного assert-теста.** Тест «validation +
  duplicates > generated» в красной фазе взял `generated: 2, invalid: 1,
  duplicates: 1` — сумма ровно 2, `AssertionError` не бросается. Для нарушения
  нужно `generated: 1`.
- **`GenerationLedger.requested` — только Σ бюджетов партий.** Не выводить
  «цель» из `GenerationPlan.requestedCards`: план может не покрывать заказ
  (`requestedAboveAchievable`), и журнал занизил бы долг; нехватку материала
  показывает план, а не журнал.
- **`ready`/`partial` в стейт-машине — только из `replenishing`.** Это
  дословная цепочка TASK.txt (`dedup → replenishing → ready|partial`);
  `failed`/`cancelled` разрешены с любого незавершённого этапа.
- **`ports.dart` не попадает в lcov** (только объявления портов, 0 исполняемых
  строк) — ожидаемо, прецедент `api_key_store.dart` и репозитории портов.
  Не «чинить» это пустыми реализациями ради процента.
- **«Плотность» единицы — отношение, а не длина.** Доля значимых слов в
  `statement` (пол 0,25), не число символов: иначе нарушается запрет среза 4
  «никакого распределения по числу символов», а короткая формула `PV = nRT`
  проигрывала бы длинной фразе из предлогов. Служебные слова — список
  `_stopWords` в `allocation.dart`.
- **40 % окна — бюджет одного батча, и он не единственный предел.**
  `ModelProfile.fitsBatch` проверяет **и** `output ≤ maxOutputTokens`, **и**
  `input + output ≤ batchTokenBudget`; тест с `outputTokens: 10000` при
  `maxOutputTokens: 8192` — ложное ожидание, которое упало уже после
  реализации (в красной фазе оно маскировалось нулевым стабом).
- **Отрицательные кейсы конструкторов с `assert` конструировать без `const`.**
  Повтор урока среза 3 (там был `KnowledgeAnchor`): `const ModelProfile(...)` с
  нарушенным инвариантом — ошибка компиляции, а не `throwsAssertionError`.
  В срезе 4 так проверяются `ModelProfile`, `UnitBudget`, `AllocationBatch`,
  `AllocationPlan`.
- **Красную фазу не снимать через `Tee-Object | Select-Object -First N`.**
  `Select-Object -First` закрывает пайплайн и обрывает запись лога (в срезе 4
  лог обрезался на 201 строке из 358). Полный вывод — редиректом в файл
  (`flutter test ... > file 2>&1`), хвост — отдельной командой.
- **Инвариант «Σ бюджетов == заказ» — `assert` в `AllocationPlan`, а не
  проверка в сервисе.** План с недобором при непустых единицах
  неконструируем; «материала нет вовсе» — только `units.isEmpty`
  (`materialLimited`). Не добавлять «мягкий» путь, который разрешит
  `cards.length < requested`.
- **Срез 4 не подключает `AllocationPlan` к `GenerationChunkPlanner`.** Старый
  путь планирования остаётся до этапов Generation/Replenish (BACKLOG S4/S7):
  подключение раньше создаст два расходящихся плана.

## СЛЕДУЮЩЕЕ ДЕЙСТВИЕ

Срез 8 закрыт, коммиты — `test`/`feat`/`docs` в `main`. Следующий прогон:
`read TASK.txt` (верхний блок) → верхний блок `journal/STATE.md`
(«Генерация v3 — срез 8») → `journal/generation-v3/verify-s8.md` (раздел
«Ограничения») → `docs/generation/BACKLOG.md` (S9 Completion: `done` ⟺
`принято ≥ requested`, подключение нового пути за флагом `generationV3`).

Если в TASK.txt снова «Срез 8» — **не повторять**: схема v2, миграция и
`drift_schemas/*` готовы (ADR-051), `drift_generation_run_store_test.dart` (12),
`drift_run_import_test.dart` (5), `drift_knowledge_map_cache_test.dart` (12)
зелёные. Следующий шаг — S9: `test/unit/domain/generation/completion_verdict_test.dart`,
затем `.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/domain/generation/completion_verdict_test.dart`.

Не подключать `ReplenishStage`/`GenerationReport`/валидатор/дедуп/журнал прогона
к `GenerationPipeline`, не переводить UI на новый путь, не включать
`generationV3` и не удалять старый путь: включение — S9 за флагом
(ADR-050, протокол §9). Prompt-only остаётся на старом пути (`no_unit_plan`).

Baseline текущего снимка: `flutter test --no-pub --exclude-tags golden` —
**3109 passed + 17 skipped**; `analyze` 0; `dart format` 0 changed;
схема БД — **v2** (не откатывать `schemaVersion` и не удалять
`drift_schema_v1.json`; следующая схема — только новым ADR по ADR-005).

---

**Архив прежнего (незавершённого, другой заход) прогона:**
`PROGRESS_slow_20261122.md` (120 КБ) — читать целиком не нужно, к срезам 0–1
отношения не имеет.
