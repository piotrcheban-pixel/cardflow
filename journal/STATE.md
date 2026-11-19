# STATE — текущее состояние CardFlow

**Дата:** 2026-11-19 · **Итерация:** `TASK 04` «Live API readiness audit &
controlled generation test preparation» — завершена (только аудит и
подготовка; платных запросов нет). Предыдущая итерация `TASK 03` — в истории
ниже. Схема БД и `format_version` не менялись.
**Режим:** ИТЕРАЦИИ.

**Следующий шаг:** **TASK 05 — Controlled Live Generation Testing** — только
по отдельному разрешению владельца: DeepSeek `deepseek-flash`, Test A–C
(5 запросов, ≈ $0.031), затем Test D/E при успехе; бюджет
`CARDFLOW_LIVE_MAX_REQUESTS=15`, `CARDFLOW_LIVE_MAX_COST_USD=0.12`. План,
риски и критерии — `journal/task04/live-test-plan.md`. После TASK 05 —
TASK 02C (UI возможностей/цен, `ProviderCapabilitiesDialog`) и точный
токенизатор/семантический дедуп (L122/L130/L136).

## TASK 04 — готовность к реальной генерации и управляемые испытания (2026-11-19)

**Задача:** после TASK 01/02A/02B-FINAL/03 установить фактическую готовность
к реальной генерации: аудит провайдеров/адаптеров/моделей/ключей, безопасная
инфраструктура live-тестов, предварительная стоимость, тестовые сценарии,
калибровка токенов. **Платные API-запросы запрещены** — только подготовка.

**Факты старта:** `git status --porcelain` → только `?? redesign/` (каталог
владельца не тронут); `HEAD = dba80ec`, ветка `main`, коммиты TASK 03 на
месте. Baseline — **2110 passed + 8 skipped**, `analyze` 0. Прогоны — только
с `--no-pub` (L64).

**Аудит (по коду и официальным страницам, `journal/task04/audit.md`):**
- 9 пресетов-провайдеров обслуживаются 4 адаптерами (OpenAI,
  OpenAI-compatible, Anthropic, Gemini); streaming не реализован; OpenAI не
  передаёт `max_tokens`; Vision/PDF/JSON/usage — по протоколам.
- **Каталог моделей устарел/не подтверждён:** официальная страница DeepSeek
  (2026-11-19) перечисляет `deepseek-flash` (1M контекст, вывод до 384K,
  Vision ✓) и `deepseek-v4-pro`; `deepseek-chat`/`deepseek-reasoner` в ней
  отсутствуют; `claude-3-5-*` нет в актуальной таблице тарифов Anthropic;
  страница тарифов Gemini из окружения недоступна.
- **Тарифы подтверждены только для 4 моделей** (`deepseek-flash`,
  `deepseek-v4-pro`, `gpt-4o`, `gpt-4o-mini`); у остальных цена неизвестна.
- **Ключи/безопасность:** только secure storage, read-back, логи без
  заголовков/тел; `DioException.toString()` (dio 5.11.1) не печатает URI и
  заголовки. Найдено расхождение санитайзеров (диагностика vs
  `providerReason`) — устранено.
- **Дефект:** битый JSON провайдера классифицировался как `network` и
  **повторялся** (лишние платные запросы до 4 на фрагмент).

**Сделано:**
- **Транспорт:** `GenerationHttpClient` запрашивает `ResponseType.plain` и
  разбирает тело сам — битый JSON → `invalidResponse` без повторов;
  подтверждено локальным HTTP-тестом на реальном сокете.
- **Безопасность:** единый `redactSecretsInText` (`log_redaction.dart`) для
  диагностики и `providerReason`: заголовки `Authorization`/`x-api-key`/
  `x-goog-api-key`, `Bearer`, `sk-`/`AIza`/`gsk_`/`xai-`/`nvapi-`, секретные
  query-параметры (`?key=`, `&api_key=`).
- **Инфраструктура live-тестов (`test/live/support/`):** конфигурация по
  окружению с безопасными умолчаниями (`enabled=false`, `maxRequests=0`,
  `maxCost=0`), тарифы с URL/датой проверки, предварительная стоимость
  (неизвестно → `null` + блокировка), бюджет логических запросов + лимит
  HTTP-попыток, план сценариев Test A–E, фикстуры, качество карточек,
  `LiveRunRecord` (провайдер/модель/версия оценщика/оценки и факты токенов/
  байты/изображения/время/статус/recovery), harness на production-адаптерах.
- **Управляемый набор:** `test/live/adaptive_generation_live_test.dart` —
  Test A–E, все пропускаются без `CARDFLOW_LIVE_TESTS=1` + бюджета + ключа.
- **Test F без оплаты:** `local_provider_server.dart` +
  `test/integration/generation_recovery_http_test.dart` (11 тестов: 413, 429 +
  `Retry-After`, таймаут, context overflow, битый JSON, `truncated`, 5xx, 401).
- **Легаси live-тесты** (DeepSeek, метрики картинок, Wikimedia) переведены на
  общий opt-in; обычный прогон стал полностью офлайновым (три Wikimedia-теста
  раньше выполнялись в нём).
- **Список адаптеров** вынесен в `lib/api/providers/generation_adapters.dart`
  (production и live-тесты — один набор).
- **Документация:** раздел S `docs/adaptive-generation-architecture.md`;
  `docs/generation-pipeline.md` (§5 разбор тела ответа, §9 управляемые
  испытания); `journal/KNOWN_LIMITATIONS.md` L137–L142; правило live-тестов в
  `AGENTS.md`; `journal/task04/{audit.md,live-test-plan.md,report.md}`.

**Гейты:** `fvm flutter test --no-pub --exclude-tags golden` →
**2157 passed + 16 skipped** (`All tests passed!`; baseline 2110 + 8,
+47 passed / +8 skipped); `fvm flutter test --no-pub --coverage
--exclude-tags golden` → **2157 passed + 16 skipped**, покрытие рукописного
кода **92.4 % (16200/17535)**; `fvm flutter analyze --no-pub` → **No issues
found!**; `fvm dart format --set-exit-if-changed lib test integration_test
tool` → **499 файлов / 0 changed**; `fvm flutter build windows --release
--no-pub` → **`cardflow.exe`** (63,0 с).

**Остатки (L137–L142):** устаревшие/непроверенные id моделей каталога;
неизвестные тарифы большинства моделей; Vision-флаг пресета DeepSeek неверен
для `deepseek-flash`; 404/402/422 не имеют отдельных кодов; live-тесты не в
CI и требуют ручного запуска; живых платных запросов не было (L142).
Негативные живые контракты по-прежнему не проверяются (ADR-014).

**Стоимость безопасной проверки (оценка):** Test A–C — 5 запросов,
≈ $0.031; A–E — 11 запросов, ≈ $0.072; рекомендуемый бюджет TASK 05 —
15 запросов, $0.12 (`journal/task04/live-test-plan.md` §3).

## TASK 03 — надёжность адаптивной генерации (2026-11-19)

**Задача:** после TASK 02B-FINAL провести аудит по фактическому коду и довести
адаптивную генерацию до надёжного состояния: единая оценка токенов и
калибровка по `usage`, честные возможности модели/fallback, согласованность
prompt-only запросов, восстановление без потери успешного, прозрачный статус
изображений, распределение 1…1000 карточек, UI-диагностика и числовое поле
карточек. Без новой архитектуры и без ослабления тестов.

**Факты старта:** `git status --porcelain` → `?? redesign/` (каталог владельца
не тронут); `HEAD = e0f8e4b` (`docs(journal): note windows build gate for TASK
02B-FINAL`), ветка `main`. Baseline — **2000 passed + 8 skipped**, `analyze` 0.
Прогоны — только с `--no-pub` (L64). Схема БД и `format_version` не менялись.

**Аудит (только по коду, `journal/task03/audit.md`):** подтверждено 27 дефектов
D1–D27. Критичные: prompt-only план в production считался без обвязки
(`GenerationPipeline` вызывал планировщик без `overhead`); сервис повторно
отбирал image-части и мог разойтись с планом; документные изображения уходили
частями без Vision; `truncated` дробил вход раньше сокращения вывода; бюджет
восстановления считался по числу детей, а не дополнительных запросов;
`Retry-After` терялся; не было калибровки; не было compact-состояния
prompt-only; D.5-план занижал `achievableCards` при большом заказе; UI не
показывал частичный успех/fatal/статус изображений и не имел поля количества.

**Сделано:**
- **Оценка и калибровка:** `TokenValue` (`exact|estimate|reserve|unknown`) и
  `TokenCalibrationSample/Report` (`token_accounting.dart`);
  `GenerationRequestEstimator` считает фактически собранный `userContent`
  системный промпт, каноническую схему, каталог, image-части и continuation тем
  же `ContentTokenEstimator`; `GenerationResult` несёт
  `estimatedInputTokens/estimatedOutputTokens/estimatorVersion`;
  `GenerationRunResult.calibration` + `GenerationDiagnostics.tokenCalibration`
  (debug) сравнивают план/запрос/`usage`; отсутствие `usage` фиксируется явно.
- **Возможности/лимиты:** `GenerationRequestLimits` +
  `resolveGenerationRequestLimits` — единый источник лимитов image-частей/байт/
  тела с источником `user|preset|unknown`; планировщик, сервис и UI используют
  его. Fallback 8 частей/10/24/32 МБ остаётся явным конфигурационным
  допущением (`assumedImageLimits`, `assumptionFields`), а не фактом модели.
  `ModelCapabilities.sources`/`GenerationPlan.capabilitySources` — карта
  источников для диагностики. Изображения без поддержки модели больше не
  попадают в `imageParts` (status `unsupportedModel`, предупреждение
  `imagesWithoutVision`).
- **Изображения:** `GenerationPlan.images` (`PlannedImage`) со статусами
  `sentToModel|catalogOnly|unsupportedModel|omittedBudget|omittedPayload`;
  `GenerationRequest.documentImageParts` — префикс каталога, сервис отправляет
  ровно его; дедуп одинаковых байтов перенесён в план
  (`documentImageDigest`), `skippedDocumentImageIds` — в диагностику;
  предпросмотр показывает «передано/только каталог/без поддержки/исключено».
- **Prompt-only:** `GenerationPipeline` строит план через
  `GenerationPlanBuilder.buildPromptOnly` (обвязка не нулевая);
  `GenerationContinuityState` — компактная сводка принятых карточек (до 1200
  токенов, 40 карточек/40 тегов) после исходных `<wishes>`; резерв сводки
  учтён в `PromptOnlyPlanner` и `GenerationEstimate.continuationReserveTokens`;
  при повторе состояние восстанавливается из успешных карточек.
- **Восстановление:** порядок F.4 — лимит → резерв вывода → дробление;
  `GenerationPlanSplitter.withContext` получает оценщик плана и
  `imageTokens`; последняя попытка при `limit == 1` делит на две части
  (`allowLimitOverflow`, заказ не меняется); бюджет — `max(configured,
  fragments/8)` до 64, списание по дополнительным запросам, поля
  `recoveryRequestsUsed/recoveryBudget/recoveryBudgetExhausted`;
  `Retry-After` — в `GenerationChunkFailure.retryAfter` и в предпросмотре.
- **Распределение:** `_tuneSoftTarget` учитывает заказ (цель
  `ceil(requested/cap)`, 80 % среднего, не ниже 512 токенов) — план больше не
  занижает `achievableCards`, когда материала хватает; D.5-укрупнение и
  распределение лимитов сохранены.
- **UI:** числовое поле `generation-cards-count` с валидацией (положительное
  целое, технический предел `int`) и передачей в
  `GenerationRunRequest.requestedCards`; предпросмотр плана до запуска тем же
  builder-ом (фрагменты/запросы/запрошено/достижимо + причины ограничений),
  невалидный план блокирует запуск; в предпросмотре результата — постоянные
  баннеры частичного успеха/fatal, сводка изображений, число запросов
  восстановления.
- **Тесты:** новые файлы `token_accounting_test`, `generation_request_limits_test`,
  `generation_continuity_test`, `generation_recovery_budget_test`,
  `generation_request_estimator_test`, `generation_plan_images_test`,
  `generation_distribution_test`, `generation_pipeline_reliability_test`,
  `test/widget/generation` (поле, предпросмотр плана, баннеры). Обновлены
  устаревшие ожидания: `truncated` теперь уменьшает лимит/резерв до дробления;
  план большого заказа достигает заказ; изображения без Vision — каталог, а не
  части; D.5-тест 26 проверяет реальный запас материала. Каждое изменение
  ожидания объяснено в тесте/отчёте.
- **Документация:** раздел R `docs/adaptive-generation-architecture.md`;
  `docs/generation-pipeline.md` (бюджет/план/восстановление/UI);
  `journal/KNOWN_LIMITATIONS.md` L122–L136; этот раздел; 
  `journal/task03/audit.md`.

**Гейты:** `fvm flutter test --no-pub --exclude-tags golden` →
**2110 passed + 8 skipped** (`All tests passed!`; baseline 2000 + 8, +110 net);
`fvm flutter test --no-pub --coverage --exclude-tags golden` → **2110 passed +
8 skipped**, покрытие рукописного кода **92.4 % (16193/17529)**;
`fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**484 файла / 0 changed**; `fvm flutter build windows --release --no-pub` →
**`cardflow.exe`** (60,8 с).

**Остатки (L122–L136):** эвристика/калибровка без токенизатора (L122),
бюджет восстановления — предохранитель (L128), приближённый recovery-пересчёт
(L129), prompt-only сводка без семантического дедупа (L130/L136), парсерные
пределы (L131), возможности/цены не вводятся в UI (L133), отброшенные
парсером изображения не отчитываются (L134), `usage` упавших/обрезанных
ответов недоступен (L135). Реальные платные API не вызывались; `redesign/`
не тронут.

## TASK 02B-FINAL — адаптивный план в production, D.5, prompt-only, снятие лимитов (2026-11-19)

**Задача:** TASK 02B-FINAL — полностью закрыть три незавершённых вопроса после
TASK 02B: второй проход D.5 (укрупнение фрагментов при заказе меньше числа
фрагментов), production-поддержка prompt-only через новую архитектуру и снятие
старых искусственных ограничений (20 карточек/фрагмент, кламп 200, бюджеты
8192/16000/8000/2000/512, 8 image-частей, 1000 токенов/изображение, старый
чанкинг), с интеграцией плана в реальный `GenerationPipeline`.

**Факты старта:** `git status --porcelain` → `?? redesign/` (каталог владельца не
тронут); `HEAD = c01b6fa` (`docs(journal): record TASK 02B adaptive planner`),
ветка `main`; коммиты TASK 01/02A/02B на месте: `8e90618`, `007fcc4`, `a7a89a8`,
`d7d0154`, `c01b6fa`. Baseline — **1965 passed + 8 skipped**, `analyze` 0.
Прогоны — только с `--no-pub` (L64). Схема БД и `format_version` не менялись.

**Сделано:**
- **D.5 (второй проход):** `GenerationChunkPlanner._mergeToRequested/_mergePass/
  _mergePair` — соседние фрагменты укрупняются (сначала с общим документом),
  пока их число больше `requestedCards`; заново проверяются `GenerationBudget`
  (окно/`maxInputTokens`/`maxRequestBytes`), image-лимиты и байты, `bodyBytes`,
  выходной резерв. `UnitSpan` сдвигаются, `unitIds`/порядок сохраняются,
  изображения/вложения дедуплицируются, текст не теряется; при невозможности —
  безопасное число фрагментов + `cardsAboveRequested`; лимиты перераспределяются
  (сумма ≤ заказа, каждый ≥ 1). Тесты: 5/12, 10/25, 1/6, 50/10, невозможность
  по бюджету/изображениям/телу, порядок/покрытие/дубли, 1–100 карточек.
- **Prompt-only:** `lib/domain/generation/prompt_only_request.dart` +
  `prompt_only_planner.dart` (`GenerationMode.promptOnly`, `ChunkKind.promptOnly`):
  нет фиктивных `ContentUnit`; учитываются промпт/схема/обёртка, токены темы в
  каждом запросе, output budget, тело; число запросов =
  `ceil(requested / cardsByOutputCap)`, сумма лимитов = заказ; превышение
  `maxChunks` — явная невыполнимость. `GenerationPlanBuilder.buildPromptOnly`.
- **Снятие лимитов:** `generation_model.dart` удалён (нет клампов 2000/16000/
  8000/8192; `GenerationBudget.compute` — единственный расчёт; `512` — явный
  порог валидности); `kMaxCardsPerChunk`, `kImageTokenEstimate`,
  `distributeCardLimits`, `kMaxRequestedCards` удалены; `requestedCardCount`
  без клампа (BigInt/int.max); лимит карточек — `budgetCardsPerRequestCap` из
  output budget/`maxCardsPerRequest`; `PlannedChunk.limit ≥ 1`, фрагменты не
  пропускаются; UI-оценка без 1000/8, предупреждение — по бюджету модели.
- **Production-интеграция:** `GenerationPipeline` строит `GenerationPlan` до
  первого запроса (материалы — `GenerationPlanBuilder`, тема — `PromptOnlyPlanner`),
  валидирует его (невалидный — ошибка ARB без сети) и исполняет `PlannedChunk`
  последовательно; `GenerationRequest.maxOutputTokens` из плана;
  `GenerationChunkFailure.plannedChunk` для точного повтора; `retryFailed` не
  пересобирает план и не дробит заново. `GenerationRunResult` несёт `plan`,
  `requestedCards`/`achievableCards`/`promptOnly`; предпросмотр показывает
  «запрошено/достижимо» и omitted.
- **Восстановление:** `GenerationPlanSplitter` (F.3) дробит только проблемный
  фрагмент по единицам/страницам с сохранением unitIds/порядка/лимитов;
  `truncated` сначала дробит по единицам, если нечего — сокращает вывод (F.4);
  `contextOverflow` (400 по тексту ошибки/невалидный план) и `payloadTooLarge`
  (413) дробятся; `rateLimited`/сеть/auth/refusal — нет; без повторов для
  auth/refusal/исчерпанного дробления. Бюджет восстановления 12 запросов,
  глубина ≤ 3.
- **Изображения:** `CardGenerationService` берёт число частей/байты из аккаунта
  (`maxImagesPerRequest`, `maxImageBytes`), 8/10/24 МБ — только явные допущения
  при неизвестности; `max_tokens` из плана/аккаунта; не вошедшие изображения
  остаются в каталоге.
- **Тесты (+35 net, старые обновлены):** `generation_plan_merge_test` (11),
  `prompt_only_planner_test` (11), `generation_plan_splitter_test` (5),
  `test/integration/adaptive_generation_flow_test.dart` (10) — small/large/
  prompt-only/partial/retry/429/auth/overflow/invalid plan; HTTP 413/400-context (3);
  сервисные лимиты аккаунта (4); UI-предупреждения плана (2, «достижимо меньше/
  больше запрошенного»); заказы 20/21/50/100/200/201/500/1000 и изображения
  1/8/20/50/100. Обновлены устаревшие ожидания: truncated теперь
  сокращает вывод/дробит по единицам; 1 карточка на 3 фрагмента больше не
  пропускает контент (D.5/L-26); распределение заказа переехало в планировщик;
  `generation_model_test` удалён вместе с удалённым старым бюджетом (его роль
  покрывает `generation_budget_test`).
- **Документация:** раздел Q в `docs/adaptive-generation-architecture.md`
  (production-путь, D.5, prompt-only, таблица всех 44 ограничений со статусами);
  `docs/generation-pipeline.md` (бюджет/планирование/восстановление/ошибки);
  `journal/KNOWN_LIMITATIONS.md` L121–L126 сняты, L127–L133 актуальны.

**Гейты:** `fvm flutter test --no-pub --exclude-tags golden` →
**2000 passed + 8 skipped** (`All tests passed!`; baseline 1965 + 8, +35 net);
`fvm flutter test --no-pub --coverage --exclude-tags golden` → **2000 passed +
8 skipped**, покрытие рукописного кода **91.9 % (15585/16958)** (сгенерированные
`*.g.dart`/локализации исключены; новые файлы: `generation_plan_splitter`
92.9 %, `prompt_only_planner` 95.6 %, `generation_plan` 96.1 %,
`generation_pipeline` 93.1 %, `generation_chunk_planner` 90.0 %);
`fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**471 файл / 0 changed**; `fvm flutter gen-l10n` — новые строки ARB;
`fvm flutter build windows --release --no-pub` → **`cardflow.exe`** (62,2 с).

**Остатки/известные ограничения (L128–L133):** бюджет восстановления 12
запросов; приближённый пересчёт токенов при recovery; prompt-only большие
заказы не разделяют факты между запросами (дедуп только по контенту);
парсерные пределы L-05…L-11/L-32/L-33; UI-поле числа карточек не добавлено
(L-44); реальные пределы провайдеров частично неизвестны (допущения явные);
оценка токенов — эвристика (L122). `GenerationChunker` остался совместимым
фасадом, production его не вызывает.

**Следующий шаг:** TASK 02C — оценщик G (калибровка по `usage`), диалог
стоимости/подтверждения, числовое поле карточек и UI-возможности провайдера
(`ProviderCapabilitiesDialog`).

## TASK 02B — адаптивный планировщик фрагментов (2026-11-18)

**Задача:** TASK 02B — планировщик по разделам D.4–D.7 аудита: бюджет модели,
семантическое дробление текста, изображения как единицы содержимого,
распределение карточек без «универсального 20», отсутствие потерь и дублей.
Интеграция `GenerationPipeline`/`CardGenerationService`/адаптеров/UI/БД **не
выполнялась** (условие этапа), реальные API-запросы не запускались.

**Факты старта:** `git status --porcelain` → `?? redesign/` (каталог владельца
не тронут); `HEAD = a7a89a8` (`docs(journal): record TASK 01 audit and TASK 02A
foundation`), ветка `main`; коммиты предыдущих этапов на месте: `8e90618`
(TASK 01, аудит), `007fcc4` (TASK 02A, контракты), `a7a89a8` (журнал).
Baseline 02A — 1899 passed + 8 skipped, `analyze` 0, `format` 459/0. Прогоны —
только с `--no-pub` (L64).

**Сделано (новые файлы + совместимое расширение старых; production-путь прежний):**
- `lib/domain/generation/content_token_estimator.dart` — минимальный контракт
  оценки единиц (`ContentTokenEstimator`: `version`, `charsPerToken`,
  `estimateText`, `estimateImage`) и `ImageTokenEstimate` с источником и
  пометкой допущения. Эвристика: текст — существующий `TokenEstimator` (2,5
  симв./токен); изображение — `ImageTokenModel` модели, если он есть, иначе
  размерная (750 px/токен) или байтовая (256 байт/токен) эвристика с
  `isAssumption`; универсальных 1000 токенов и `length/3.5` нет. Заменяется
  `GenerationEstimator` этапа G без смены контракта.
- `lib/domain/generation/generation_chunk_planner.dart` — `GenerationChunkPlanner`,
  `GenerationChunkPlannerConfig` (мягкая цель 6000 материала/карточку,
  `maxChunks = 512`, глубина дробления 3, допущения лимитов изображений/тела),
  `GenerationOverheadTokens`, `GenerationPlanCoverage`. Бюджет — по D.1 через
  существующий `GenerationBudget` (`окно − резерв вывода − обвязка − запас
  5 %/≥256`), отдельно `maxInputTokens`/`maxRequestBytes` (base64);
  неизвестное окно — 6000/2048 с `BudgetSource.assumption`; при нехватке
  бюджета план `invalid` (`contextWindowTooSmall`), а не «всё равно 2000».
  Упаковка жадная по единицам, дробление `раздел → абзац → предложение →
  строка → руна`, жёсткое деление не рвёт суррогатную пару; прогресс
  гарантирован (нет зацикливания на пограничном фрагменте — бюджет дробления
  вычитает заголовок файла, повтор без прогресса → `unitTooLarge`).
  Изображения: части с сохранением `img:`-id и каталога документа, остальные —
  `catalogOnly`; подгруппы по лимитам модели, orphan-изображения — отдельные
  фрагменты; всё, что не влезло, — в `omitted` с причиной. Лимит карточек —
  из бюджета вывода и `maxCardsPerRequest`; заказ распределяется без нулей и
  без молчаливого среза (предупреждения `requestedAbovePlan`/
  `cardsAboveRequested`).
- `lib/api/generation/generation_plan_builder.dart` — `ContentInventory` из
  `ParsedDocument`/`GenerationAttachment`/`DocumentImage`: стабильные id,
  непрерывное покрытие текста раздела абзацами (конкатенация = текст раздела),
  каталог документа, страницы вложений по `groupKey`, orphan-изображения;
  фиксированная обвязка (системный промпт `gen-ru-v7`, каноническая JSON-схема,
  обёртка через существующий `buildGenerationUserContent`), пожелания и заказ
  карточек; строка каталога — существующий `imageCatalogLine` (без второй
  реализации формата).
- `lib/domain/generation/generation_plan.dart` — аддитивно: `PlannedChunk.
  materialsText` (in-memory, в БД не пишется), `imagePartIds`/`catalogOnlyIds`
  для проверяемого покрытия, `PlanWarningCode.omittedUnits`,
  `PlanInvalidReason.tooManyChunks`.
- `lib/domain/generation/generation_chunker.dart` — совместимый фасад: новые
  поля `GenerationChunk` (`unitIds`, `splitDepth`, `imageParts`,
  `catalogOnly`) с умолчаниями, методы `planChunks`/`chunksFromPlan`; старые
  `chunkDocuments`/`chunkAll`/`splitInHalf` не изменили поведение
  (`splitInHalf` очищает новые поля и увеличивает глубину).
- Тесты (+66): `generation_chunk_planner_test` (сценарии 1–30, параметризованные
  объёмы 1/3/12/40 абзацев × 0/1/8/20 изображений, линейность, отсутствие
  `kMaxCardsPerChunk`/`kImageTokenEstimate`), `content_token_estimator_test`,
  `generation_plan_builder_test`. Проверяются: покрытие (нет потерь), отсутствие
  дублей частей/страниц, исходный порядок, сохранение `image_id` и связей
  изображение↔раздел после дробления, 1/8/20/50/100 изображений, разные лимиты
  моделей, payload, неизвестное окно, окна 8000/128000/200000/1M,
  недостаточный бюджет, очень большой документ, заказ карточек,
  совместимость старого `GenerationChunker`.

**Гейты:** `fvm flutter test --no-pub --coverage --exclude-tags golden` →
**1965 passed + 8 skipped** (`All tests passed!`; baseline 1899 + 8, +66);
покрытие рукописного кода **92.1 % (15066/16361)**; новые файлы —
`generation_plan_builder` **100 % (135/135)**, `content_token_estimator`
**100 % (24/24)**, `generation_chunk_planner` **90.0 % (812/902)**,
`generation_plan` **96.8 % (90/93)**, `generation_chunker` **95.2 % (237/249)**;
`fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**465 файлов / 0 changed**.

**Ограничения/долги (осознанно вне TASK 02B; L121–L127 в
`journal/KNOWN_LIMITATIONS.md`):** планировщик не подключён к пайплайну
(production-путь — прежний чанкер с 2000-клампом и 20 карточками); оценка
токенов — эвристика без калибровки по `usage`; заказ из пожеланий по-прежнему
режется парсером до 200 (политика L-24, не планировщика); второй проход D.5
(заказ меньше числа фрагментов) не реализован — план предупреждает
`cardsAboveRequested`; prompt-only фрагмент создаёт пайплайн (пустой
`PlannedChunk` запрещён контрактом 02A); дедуп одинаковых байтов изображений
остаётся в сервисе.

**Следующий шаг:** TASK 02C — интеграция плана в `GenerationPipeline`
(план → запросы, восстановление/дробление по единицам, `retryable`), затем
оценщик G, UI/стоимость и БД K1. На TASK 02B работа остановлена.

## TASK 02A — фундамент адаптивной генерации: доменные контракты (2026-11-18)

**Задача:** TASK 02A — только фундамент архитектуры из
`docs/adaptive-generation-architecture.md` (раздел P, шаг 1): возможности
модели, цены, бюджет, единицы содержимого, план. Планировщик, пайплайн, сервис,
адаптеры, UI и БД не менялись.

**Факты старта:** `git status --porcelain` → `M journal/STATE.md`,
`?? docs/adaptive-generation-architecture.md`, `?? redesign/` (TASK 01 сохранён,
каталог владельца не тронут); `HEAD = af3172a`, ветка `main`. Baseline L76 —
1822 passed + 8 skipped (TASK 01 был AUDIT-ONLY, код не менялся).
Прогоны — только с `--no-pub` (L64).

**Сделано (домен + JSON аккаунтов; production-путь прежний):**
- `lib/domain/generation/model_capabilities.dart` — `CapabilitySource`
  (`verified|preset|user|inferred|unknown`), `TokenizerKind`, `ImageTokenModel`
  (E.4), `ModelCapabilities` (nullable-значения + источники групп),
  `resolveModelCapabilities`: аккаунт (user) → каталог пресета (preset) →
  unknown. Окно пользовательской модели **не** подставляется из
  `ProviderAccount.contextTokens` (16 000 — заглушка приложения, L-18),
  `maxOutputTokens` — не 8192 сервиса, strict-схема и image-токены — `null`
  (подтверждённых данных в репозитории нет).
- `generation_pricing.dart` — `GenerationPricing` (nullable цены/валюта),
  `PricingState` (`complete|incomplete|unknown`), `GenerationCost`;
  `costFor` → `null` при неполных ценах и 0 только при явно нулевой цене;
  JSON `input_per_mtok|output_per_mtok|currency`.
- `generation_budget.dart` — `GenerationBudget.compute` по D.1:
  окно − резерв вывода − фиксированная обвязка − запас (5 %, ≥ 256);
  лимиты `maxInputTokens`/`maxRequestBytes` (base64); unknown-стратегия
  6000/2048 с `BudgetSource.assumption`; клампинга 2000 нет —
  `isWorkable`/`shortfallTokens`; `BudgetTrace` (формула, слагаемые,
  источники, `unknownFields`), `GenerationBudgetConfig` (калибруемые
  допущения, не факты модели), `base64EncodedByteLength`.
- `content_unit.dart` — `ContentInventory`, `DocumentUnit`, `SectionUnit`,
  `TextPiece`, `ImageRef` (обёртка над `DocumentImage`), `DocumentCatalog`,
  `AttachmentUnit`/`PageUnit`, `OrphanImageUnit`, `PageRange`; стабильные id
  `doc:<файл>#<раздел>#<фрагмент>`, `img:<файл>#<n>`, `att:<ключ>[#pN]`;
  каталог документа объединяется с изображениями разделов (изображение не
  выпадает), orphan-изображение — отдельная единица.
- `generation_plan.dart` — `GenerationPlan`, `PlannedChunk`, `UnitSpan`,
  `OmittedUnit`/`OmittedReason` (`budget|providerImageCap|payload|unsupported`),
  `PlanValidity` (+ `PlanWarningCode`, `PlanInvalidReason`), `GenerationEstimate`
  (G.6; стоимость nullable). Пустой фрагмент и `limit < 1` запрещены assert-ом;
  `plannedCards`/`plannedRequests` вычисляются из фрагментов (без дубля полей).
  JSON плана не пишется: `plan_json` в БД не добавляется (K.2), материалы в БД
  запрещены (SPEC 3.4), поэтому план — in-memory.
- `provider_account.dart` — JSON аккаунтов v2
  (`ProviderAccounts.version = 2`): nullable `max_output_tokens`,
  `max_images_per_request`, `max_image_bytes`, `max_request_bytes`, `pricing`,
  `capabilities_source`; чтение v1 (поля отсутствуют → неизвестны),
  нулевые/битые значения → `null`, неизвестные ключи игнорируются.

**Решения по nullable/неизвестности:** неизвестная характеристика — `null` +
`CapabilitySource.unknown` (никогда 0); каталог пресета — источник `preset`
(не `verified`: подтверждённой документации в репозитории нет); пользовательские
значения — `user` (явное значение в JSON без источника подписывается `user`
в резолвере — одна логика, без дубля в `fromJson`); цены при неполных данных
дают `null`/`incomplete`, не 0; бюджет при неизвестном окне — консервативное
допущение с явной пометкой source/unknownFields.

**Тесты (+77):** новые `generation_pricing_test` (12),
`model_capabilities_test` (12), `generation_budget_test` (13),
`content_unit_test` (16), `generation_plan_test` (17) и 7 новых в
`provider_account_test` (v2 round-trip, legacy v1, битые/нулевые значения,
pricing с null, copyWith): известные/неизвестные характеристики, сериализация
и десериализация, совместимость старых JSON-конфигураций, отсутствующие
nullable-поля, «unknown ≠ 0», пользовательские значения, валидность
плана/бюджета, «нет потерь» в каталоге изображений.

**Гейты:** `fvm flutter test --no-pub --coverage --exclude-tags golden` →
**1899 passed + 8 skipped** (`All tests passed!`; baseline 1822 + 8, +77);
покрытие рукописного кода **92.7 % (14055/15166)**; новые доменные файлы
**100 %** (`model_capabilities` 48/48, `generation_pricing` 59/59,
`generation_budget` 57/57, `content_unit` 132/132, `generation_plan` 91/91),
`provider_account` 87.4 %; `fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**459 файлов / 0 changed**.

**Ограничения/долги (осознанно вне TASK 02A):**
- планировщик (`generation_chunk_planner`/`generation_plan_builder`), оценщик
  (`generation_estimator`), пайплайн, сервис, адаптеры, UI, классификатор
  ошибок и БД K1 — следующие шаги; старый путь генерации новые контракты ещё
  не использует;
- `ProviderAccount.contextTokens` пока не считается пользовательским окном
  (UI-поля нет); после появления поля источник `user` должен включать его явно;
- редактирование аккаунта в текущем UI создаёт аккаунт без новых полей —
  сохранение возможностей/цен появится с `ProviderCapabilitiesDialog` (I23);
  до этого новые поля UI не заполняет;
- `GenerationPlan`/`ContentInventory` — in-memory: токены единиц считает
  будущий оценщик, собственной оценки в фундаменте нет.

**Следующий шаг:** TASK 02B — планировщик по D.4–D.7 и
`generation_plan_builder`, фасад `generation_chunker`, тесты инвариантов и
«нет потерь»; затем оценщик (G) и пайплайн (F). На TASK 02A работа остановлена.

## TASK 01 — аудит пайплайна генерации и план адаптивной архитектуры (2026-11-18, AUDIT-ONLY)

**Задача:** отдельный трек по запросу владельца (не итерация продукта):
исследовать путь «контент → карточки» и подготовить план адаптивного
токен-осознанного чанкинга, снятия искусственных лимитов, мультимодальной
обработки, бюджетирования контекста/вывода, восстановления после переполнений,
оценки токенов и стоимости, предупреждений перед генерацией.

**Факты старта:** `git status --porcelain` → `?? redesign/` (только каталог
владельца), `HEAD = af3172a` (`docs(journal): table of L76 CI runs and runner
capacity cancellations`), ветка `main`; baseline из L76 — **1822 passed +
8 skipped** (не перепроверялся: код не менялся). Расхождения со STATE, найденные
при сверке: последний зафиксированный в L76 хеш — `bdc5336`, фактический HEAD на
два docs-коммита новее (`9e4bb0f`, `af3172a`); `lib/ui.rar` в дереве отсутствует
(остался только `redesign/`). Исторические записи не переписывались.

**Сделано (только документы; production-код, лимиты, модели, схема БД не менялись):**
- `docs/adaptive-generation-architecture.md` — полный аудит и проект: диаграмма
  пайплайна, реестр **44** ограничений с классификацией A/B/C/D, архитектура
  возможностей модели (`ModelCapabilities`, nullable + источник), адаптивный
  планировщик (формула `effectiveInputBudget`, резерв вывода, мягкая цель,
  инварианты, `GenerationPlan`), мультимодальные единицы контента (ассоциации
  секция↔страница↔изображение), восстановление (категории ошибок, рекурсивное
  дробление, отдельная стратегия для output truncation, бюджеты попыток),
  оценщик токенов/стоимости (unknown ≠ 0), поток предупреждения о стоимости,
  точный список изменяемых/новых файлов с критериями приёмки, изменения модели
  данных (JSON аккаунтов v2; `generation_jobs` + 5 nullable-колонок, K1),
  миграция/совместимость, 30 тест-кейсов по п.10 задания, производительность/память,
  риски и порядок реализации.
- Эта запись в STATE (по конвенции журнала). Других файлов не касались.

**Ключевые дефекты, подтверждённые кодом (входят в план):**
1. Переполнение контекста не обрабатывается: 400/413 сводятся к `badRequest`
   (`generation_http_client.dart:194-281`), дробится только `truncated`
   (`generation_pipeline.dart:406-416`) — большие документы на малом окне
   гарантированно падают.
2. Малое окно ломается формулой: `inputTokenBudget` клампится в 2000
   (`generation_model.dart:19,38`); для `moonshot-v1-8k` (8000) 2000 + системный
   промпт (~6566) + вывод > окна.
3. Молчаливая потеря контента: фрагменты с `limit == 0` пропускаются
   (`generation_pipeline.dart:368-371`), заказ карточек режется 200
   (`generation_card_limit.dart:12,44`) и `maxPerChunk × chunks` (`:62-63`).
4. `splitInHalf` запрещён для фрагментов с картинками и теряет каталог
   (`generation_chunker.dart:320,341-354`).
5. Совокупный размер запроса не ограничен: 3 страницы скана по ≤ 10 МБ + до 8
   image-частей (≤ 24 МБ) → тело до ~54 МБ (base64 ~72 МБ) без проверки.
6. `retryable` всегда `true` (`generation_run.dart:105`) — повтор
   детерминированных ошибок (vision/PDF/размер).
7. Цен и модели стоимости нет вообще; оценка токенов расходится между UI и
   пайплайном, не включает схему, каталог `<images>`, image-части, ретраи.

**Гейты:** не запускались — задача AUDIT-ONLY, `lib/`, `test/`, `pubspec.yaml`
не изменялись; проверка свелась к чтению кода и сверке путей документа
(144 извлечённые ссылки, несуществующих «старых» путей нет; новые пути — план
реализации). `docs/generation-pipeline.md` устарел (≤ 4 страницы вместо 3,
`GenerationModel.contextTokens`, Openverse как единственный поиск) — обновляется
в итерации реализации.

**Следующий шаг:** итерация реализации по разделу P документа (контракты →
планировщик → пайплайн → сервис/адаптеры → UI → БД K1 → документация → live).

## Итерация L76 — PDF Visual Intelligence (2026-11-18, ADR-037)

**Факты старта:** `git status --porcelain` → пусто,
`HEAD = origin/main = 4d6b992` (`docs(cleanup): record green CI for cleanup-1`);
baseline **1775 passed + 8 skipped**, `analyze` 0, `format` 0. Прогоны — только
с `--no-pub` (L64).

**Аудит (факты, не предположения):** `pdfrx 2.12.0`/`pdfrx_engine 0.9.1` даёт
только текст и рендер страниц — API объектов страницы в нём нет (grep
`FPDFPage_GetObject`/`FPDFImageObj_*`/`FPDFFormObj_*` — 0). `FPDFImageObj_GetRenderedBitmap`
отдаёт растр **в размере на странице** (спайк: 300×200 px при выводе 150×100 pt →
150×100). OCR-подсистемы в проекте нет. `DocumentImage` из DOCX отправлялся
модели только строкой каталога — байты не уходили (пробел). Промпт в коде —
`gen-ru-v6`, файла `gen-ru-v7` не было. `syncfusion_flutter_pdf` отклонён
(коммерческая/community-лицензия Syncfusion, pub.dev `unknown`), `pdfx` не нужен.

**Спайки (кодом, три гипотезы):** (1) прямые FFI-вызовы `pdfium_dart` из
изолята после `pdfrxInitialize()` падают — `Cannot invoke native callback from a
different isolate`; (2) в воркер-изоляте `pdfrx`
(`PdfrxEntryFunctions.instance.compute`) извлечение работает, результат
(`Uint8List` + метаданные) передаётся между изолятами; (3) рендер **области**
страницы с масштабом «пиксели изображения / размер на странице» возвращает
исходное разрешение (300×200), маски/цветовые пространства обрабатывает PDFium.

**Сделано:**
- `PdfImageExtractor` (`lib/api/parsers/pdf_image_extractor.dart`) — Image и
  Form XObject, метаданные (`width`/`height`/bpp/colorspace), положение
  (`FPDFPageObj_GetBounds` + матрица формы), порядок на странице, PNG в исходном
  разрешении (резерв — растр PDFium в размере отображения); guard-лимиты
  (≥ 32 px, ≤ 16 млн пикселей, ≤ 60 изображений, ≤ 2600 px сторона).
- `PdfPageClassifier` — постранично `textLayer`/`scanned`/`blank` (порог 50
  символов): смешанный PDF обрабатывается страница за страницей.
- `PdfPageRegionDetector` — сетка «чернил», дилатация, связные компоненты,
  склейка, отсев строк текста/тонких линий, вырезка из полного рендера без
  масштабирования; «одна большая схема» → страница целиком.
- `PdfScanPageExtractor`/`PdfScanDocument` — страницы скана (рендер PDFium,
  номера страниц) + области → `DocumentImage(source: renderedPage/croppedRegion)`.
- `PdfParser` — текст + изображения + рендеры/области; привязка к разделу
  (`ParsedDocumentBuilder.addImageToSection`), страница сохраняется; полностью
  сканированный PDF по-прежнему `scannedPdf` (страницы уходят image-частями).
- `DocumentImage` расширен обратно совместимо: `source`, `rect` (доли 0..1),
  `order`; DOCX/PPTX/ODT без изменений поведения.
- Фильтр `PdfImageFilter` (иконки, тонкие линии, однотонные плашки; повторы по
  SHA-256; небольшие формулы на странице с подписью рисунка сохраняются).
- Vision: `CardGenerationService` добавляет image-части документов для моделей
  с Vision (`selectVisionDocumentImages`: приоритет подпись → область/встроенное
  → площадь; ≤ 8 частей и ≤ 24 МБ, дедуп по SHA-256); перед каждой частью —
  подпись каталога (`GenerationAttachment.label`) во всех трёх протоколах,
  поэтому `image_id` сопоставим однозначно; каталог `<images>` полный, не
  вошедшие изображения разрешаются по `image_id` при импорте.
- `GenerationRunRequest.documentImages` → чанкер кладёт области скана во
  фрагмент своего файла; экран генерации разбирает скан `PdfScanPageExtractor`.
- Промпт `gen-ru-v7` = `gen-ru-v6` дословно + блок «ИЗОБРАЖЕНИЯ ИЗ PDF И
  СКАНОВ» (текст задания + правила каталога/частей/усечения); копия
  `docs/prompts/gen-ru-v7.txt` (тест сверяет байты); v5/v6 сохранены.
- `MediaStore`: парсер не пишет файлы (как DOCX), карточка при импорте пишет
  файл и строку `media` — сквозной путь покрыт интеграционным тестом.

**Гейты итерации:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **1822 passed + 8 skipped** (`All tests passed!`; baseline 1775 + 47 новых);
**набор CI (`--exclude-tags golden,live`) → 1819 passed** (офлайновый прогон);
покрытие рукописного кода **92.5 % (13638/14746)**, новые файлы:
`pdf_image_extractor` 87.3 %, `pdf_page_regions` 93.8 %, `pdf_parser` 91.3 %,
`pdf_scan_pages` 100 %, `document_image` 93.4 %; `fvm flutter analyze --no-pub`
→ **No issues found!**; `fvm dart format --set-exit-if-changed lib test
integration_test tool` → **449 файлов / 0 changed**;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (64,9 с).

**Тесты (47 новых):** `pdf_document_images_test` (10: обычный PDF, Form
XObject, без изображений, повторы, иконка, формула с подписью, скан →
`scannedPdf`, смешанный PDF, битое изображение), `pdf_page_classifier_test` (6),
`pdf_page_regions_test` (6), `pdf_scan_pages_test` (5, реальный PDFium),
`pdf_document_images_vision_test` (6: байты в запросе + подпись, без Vision,
лимит 8/каталог, дедуп, чужой `image_id`, страница скана),
`document_image_test` (7), `generation_chunker` (2: области скана в свой
фрагмент, сироты), `prompt_test` v7 (4: байты, v6 внутри, текст задания, JSON),
`test/integration/pdf_image_flow_test.dart` (1: PDF → изображение → image-part в
запросе → `image_id` → импорт → файл в `MediaStore` байт-в-байт).

**Живая проверка (DeepSeek, `deepseek-chat`, настоящий API):** `fvm flutter test
test/live/openai_compatible_deepseek_live_test.dart --tags live --no-pub` →
**7 passed** с промптом `gen-ru-v7`: `cards=3, tokens=5509`; fallback
`strict=400 → tolerant=200`; prompt-only `cards=3, image_query=3, prompt=gen-ru-v7`;
PDF-скан страницами (`pages=3, cards=2`); статика 20 карточек (пометок 4/20,
`rejected=0`); DOCX с рисунком (`images=1, image_id=4, with_image=4`).
Заодно исправлена устаревшая live-проверка: она ждала в сыром ответе
`image_query` (схема v4/v5), теперь принимает объект `image` (v6+) — тест
остался строгим, но соответствует действующей схеме.

**Ограничения итерации:** L115–L120 (нет локального OCR — текст скана
распознаёт vision-модель; геометрический детектор областей; векторные схемы на
страницах с длинным текстом не вырезаются; координаты вложенных форм — в
системе формы; лимиты 60/24/3 страницы/8 частей/24 МБ; отмена парсинга не
поддерживается). L76 **снято** в объёме «встроенные изображения PDF
извлекаются и используются».

**Красный CI и его причина (разобрано по фактам).** Прогон `481f2cb` дал по
одному падению в `test` на Ubuntu и Windows (остальные 7 job'ов зелёные).
Первая гипотеза — сетевой live-тест (L92) — не подтвердилась: после
`--exclude-tags golden,live` падение повторилось, **и воспроизвелось локально**
тем же фильтром: `test/widget/study/study_modes_test.dart: «карточка с due в
будущем пишется как тренировка»`. Причина — **тест-бомба с датой**: виджет
сравнивает `due` с реальными часами (`isDueForStudy(card, DateTime.now)`), а
фикстура задавала `due = DateTime.utc(2026, 11, 16, 12) + 2 дня`
= 2026-11-18 12:00 UTC — после этого момента due оказывается в прошлом и FSRS
пишется вместо тренировки. Подтверждено прогоном на **базовом коммите
`4d6b992`** (та же ошибка ⇒ дефект не внесён этой итерацией). Исправление:
due считается от текущего момента (`DateTime.now().toUtc() + 30 дней`), тест
по-прежнему проверяет «будущая due → тренировка». Заодно закрыто **L92**:
job `test` теперь `--exclude-tags golden,live` (обычный прогон офлайновый и
детерминированный; live-проверки — по тегу), аннотация падений публикует
строки `Failing tests`/`[E]`, guard `ci_pdfium_test` обновлён. После фикса
(`9cf28a2`) прогон
[`44349211802`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44349211802):
`format + analyze` ✅, `test` Ubuntu ✅, `test` Windows ✅, 6 сборок ✅;
`test` macOS **отменён раннером** — «The job was not acquired by Runner of type
hosted even after multiple attempts» (capacity constraints macOS arm64), шагов
не было, т.е. инфраструктура, а не ошибка кода → итоговый conclusion прогона
`failure` только из-за этого; повторный прогон — после docs-коммита.
Прогон [`44352510436`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44352510436)
(`19b2c3a`): `test` Ubuntu ✅, `test` Windows ✅, `format + analyze` ✅,
`build` android/windows/linux/ios ✅; `test (macos)` и `build macos` снова
**отменены раннером** — 0 шагов, «not acquired by Runner … capacity constraints
macOS arm64» (инфраструктура GitHub; так же было в итерации 7.16).

**Push/CI итерации L76:** `4d6b992..bdc5336`. Финальный прогон
[`44355509340`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44355509340)
(`bdc5336`) — **9/9 job success**: `format + analyze`, `test` × 3 ОС
(Ubuntu/Windows/macOS), `build` desktop × 3 + Android + iOS. Коммиты:
`77dca82` (извлечение PDF-изображений, vision, промпт v7, тесты),
`c21d753` (ADR-037/parsers/dependencies/STATE/limitations), `481f2cb`
(live-проверка схемы v6+), `553a3e6` (CI: `golden,live`, диагностика падений,
L92), `9cf28a2` (тест-бомба с датой), `19b2c3a`/`bdc5336` (STATE: факты
прогонов, инфраструктурные отмены macOS). Рабочее дерево: остались
**неотслеживаемые** файлы владельца (`lib/ui.rar`, `redesign/`) — в коммиты не
попали.

## Итерация cleanup-1 — отказ от «Nocturne» и фикс «Создать колоду» (2026-11-18, ADR-036)

**Факты старта:** `git status --porcelain` → пусто, `HEAD = 4ca8e00`
(этап 3 Nocturne, 43 коммита впереди `origin/main = 8e9db8a`); baseline
**2121 passed + 8 skipped**. Прогоны — только с `--no-pub` (L64).

**Решение владельца:** дизайн-система провалилась (скорость и стабильность);
полное удаление наследия, чистый Material 3, Indigo `#4F46E5`. ADR-035 →
**отменён** ADR-036.

**Критический баг «Создать колоду» (белый экран) — найдена корневая причина:**
`showNcDialog` собирал `actions` диалога во внешнем `BuildContext` экрана, а
`DecksScreen` живёт в ветке `StatefulShellRoute` со **своим навигатором**.
`Navigator.of(context).pop()` выталкивал из ветки **экран** вместо маршрута
диалога: `You have popped the last page off of the stack`
(`go_router/src/delegate.dart:178`), белый экран, незавершённый фьючер
`showDialog`, `!debugLocked` на финализации. Воспроизведено на
production-проводке (`CardFlowApp` + `createAppRouter`) — 0 виджетов
`DecksScreen` после закрытия диалога. Исправление: диалог снова
самодостаточный `_DeckNameDialog`, закрывающий себя из собственного `context`;
проверены все 12 мест `showDialog`. Ограждение —
`test/widget/decks/create_deck_dialog_test.dart` (3 случая: открыть/закрыть,
создать, пустое имя).

**Удалено (511 файлов, −28 059 строк):** `lib/ui/design/**` (56 файлов:
`NcAmbientBackground` + Aurora, `NcGlass`/`NcGlassGroup` и все
`BackdropFilter`, 37 компонентов с `rim light` и градиентами, токены
`nc_colors/typography/spacing/radii/depth`, `nc_theme`, `motion_scope`,
`haptics`, Nocturne-переходы), `test/golden/**` (346 PNG), `tool/screenshots/**`
+ `tool/extract_ui_keys.dart` (51), Nocturne-тесты (43), 7 ассетов шрифтов и
зерна, пакет `redesign/`. Восстановлено из `7458346` 46 файлов: экраны этапа 3,
оболочка, тема, `app.dart`, `main.dart`, ARB (88 Nocturne-строк), `pubspec.yaml`
(+`material_color_utilities`, `cupertino_ui` — удалены), `.gitignore`, `docs`.
Ни одна строка `lib/{domain,data,api}` не изменилась.

**Что стало вместо:** `AppTheme` — `ColorScheme.fromSeed` +
`ThemeData(useMaterial3: true)`, акцент Indigo `#4F46E5`; экраны — простые
Material/M3E-виджеты; фон статичен (кадры только по событиям).

**Гейты итерации:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **1775 passed + 8 skipped** (`All tests passed!`; 1771 baseline + 1 сетевой
live + 3 новых); покрытие рукописного кода **92.5 % (12948/13996)**
(`AppTheme` 100 %); `fvm flutter analyze --no-pub` → **No issues found!**;
`fvm dart format --set-exit-if-changed lib test integration_test tool` →
**438 файлов / 0 changed**; `fvm flutter build windows --release --no-pub` →
`cardflow.exe` (65,2 с). **Windows-смоук на реальном процессе**
(`integration_test/session_smoke_windows_test.dart -d windows --no-pub`) →
**All tests passed!** (10 с; debug-сборка 30,4 с) — в смоук добавлен шаг 0:
«Создать колоду» на боевой оболочке открывает и закрывает диалог, экран ветки
остаётся; дальше прежний сквозной сценарий (картинка Basic, дневной лимит,
генерация с настоящим Wikimedia) зелёный.

**Историческое наследие:** журналы `journal/redesign-1..3/` (146 файлов,
29,3 МБ) и ADR-035 сохранены со статусом «отменён» — причины закрытого
направления не переписываются. Новые ограничения — L111–L114 (L-seкция
`KNOWN_LIMITATIONS.md`).

**Коммиты итерации (5):** `ac3f109` — удаление Nocturne и возврат экранов
(+511 файлов удалено), `6de6eca` — Indigo-сид темы, `493f732` — тест диалога
«Создать колоду» на production-проводке, `500c9aa` — шаг диалога в Windows-смоуке,
`ae9227a` — ADR-036/STATE/journal/limitations.

**Push/CI:** `8e9db8a..ae9227a` (44 коммита: этапы 1–3 Nocturne + cleanup-1);
CI run [`44184233645`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/44184233645)
— **9/9 job success** (`format + analyze`, `test` × 3 ОС, `build` desktop × 3 +
Android + iOS).

## Редизайн «Nocturne» — этап 2 «Компоненты» (2026-11-17, ADR-035) — ОТМЕНЁН

**Факты старта:** `git status --porcelain` → пусто, `HEAD = origin/main =
8e9db8a` (`docs: confirm 9/9 CI for docs commit 734c120`). Baseline этапа 1 —
1924 passed + 8 skipped. Прогоны — только с `--no-pub` (L64).

**Гейты этапа 2:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **2036 passed + 8 skipped** (+112 к baseline); покрытие `lib/ui/design/`
**93,8 % (2672/2848)**, `components/` **93,1 % (2116/2272)**, рукописный код
**92,8 % (15825/17047)**; `fvm flutter test --no-pub test/golden` →
**298 passed** (298 PNG, 4,25 МБ); `analyze` **0**; `dart format
--set-exit-if-changed lib test integration_test tool` → **530 / 0 changed**;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (60,0 с).
Красная зона и экраны: `git diff --stat 8e9db8a..HEAD` пуст (19 файлов
Красной зоны, `*_screen.dart`, `app_shell.dart`, `review_chrome.dart`).

**Сделано (шаги 2.1–2.8):** библиотека `lib/ui/design/components/` — 37
компонентов + 7 внутренних примитивов (`NcTappable`, `NcPressScale`,
`NcFocusRing`, `NcSpringBuilder`, `NcStagger`, `NcScrollCollapseScope`,
`NcButtonAppearance`) по REDESIGN-SPEC §8: примитивы, действия, ввод,
структура, оверлеи, прогресс, сессионные. Каждый компонент — на токенах
`NcTheme.of`, пружинах `NcMotion.of` и `NcHaptics`; экспорт — `design.dart`;
ни один не импортирует Riverpod/роутер/домен (guard расширен).
**Глобальный переход тостов:** `showAppMessage` и `showArchivedUndoSnackbar`
в `deck_actions.dart` показывают `NcToast` при прежних сигнатурах, текстах,
«Отменить» и поведении undo; старые экранные тесты зелёные, добавлены два
теста проводки (`test/widget/design/toast_wiring_test.dart`).
**Golden-инфраструктура:** `test/helpers/nc_golden.dart` (8 вариантов:
dark/light × обычный/high-contrast × textScale 1,0/2,0), `nc_harness.dart`,
`glass_budget.dart`; каталог-полотно —
`journal/redesign-2/screenshots/components-catalog-{dark,light}.png`.

**Коммиты этапа (13):** red/green по группам — `9da7782`/`0446cc6` (2.1),
`e207be2`/`60164b9` (2.2), `507a49d`/`b59b672` (2.3), `7adf028`/`6107531`
(2.4), `82363c7` (2.5), `535ffe2`/`20dff64` (2.6), `5f33d0a`/`44e0c41` (2.7)
+ финальный verify/docs-коммит.

**Отклонения/решения (ADR-035, раздел «Этап 2»):** зерно стекла — процедурный
painter (детерминизм golden); `NcIcon3D`-резерв без `BackdropFilter` (бюджет
§4.4); `NcToast` не перехватывает указатель и обновляет полосу шагом 200 мс
(совместимость с `pumpAndSettle` старых тестов); AI-блик одноразовый;
neighbor-squish — доли `flex`; `NcFlip` при `disableAnimations` — кроссфейд
120 мс; golden сняты на Windows.

**Новые ограничения:** L98 (golden на Windows, CI без тега golden),
L99 (squish долями), L100 (NcTopBar/NcFab подключаются на этапе 3),
L101 (3D-ассетов нет — резерв), L102 (бюджет стекла на компонентах, не на
экранах), L103 (ступенчатая полоса тоста).

**Push/CI:** коммиты этапа 2 не пушились — push и прогон 9/9 job — по команде
владельца (AGENTS.md).

**Следующий шаг:** этап 3 «Каталог» — `NcNavDock`/`NcNavRail` и перевод
экранов вне сессии (оболочка, «Мои колоды», экран колоды, форма карточки,
конструктор, статистика, настройки, провайдеры) с сохранением ключей §9 и
бюджетом стекла ≤ 2 групп на экран.

## Редизайн «Nocturne» — этап 3 «Каталог» (2026-11-17)

**Факты старта:** `git status --porcelain` → пусто, `HEAD = 4b4cc21`
(этап 2 принят; на 15 коммитов впереди `origin/main = 8e9db8a` — push этапа 2
в remote не ушёл, выполняется владельцем). Baseline — 2036 passed + 8 skipped.

**Гейты этапа 3:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **2121 passed + 8 skipped** (+85 к baseline); покрытие рукописного кода
**93,1 % (16799/18043)**, порог 80 % пройден; `--tags golden` → **336 passed**
(экраны этапа 3 + библиотека этапа 2); `analyze` **0**; `dart format
--set-exit-if-changed lib test integration_test` → **541 / 0 changed**;
`fvm flutter build windows --release --no-pub` → `cardflow.exe` (67,2 с);
Windows-смоук `integration_test/session_smoke_windows_test.dart -d windows
--no-pub` → **All tests passed!** (39 с) — смоук переведён на фиксированные
кадры (`settle`), потому что в реальном процессе фон Aurora дрейфует
бесконечно и `pumpAndSettle` не завершается.

**Сделано (шаги 3.1–3.8):** оболочка `NcNavDock`/`NcNavRail`/сайдбар 248
(ключи `shell-nav-*`), «Мои колоды» с сеткой 1/2/3, сводкой и Hero-тегами,
экран колоды (hero-CTA, стат-пилюли, сетка режимов 2×4/4×2, парящий тулбар),
форма карточки + стили контента §9.20, конструктор с пронумерованными
секциями и `NcStepper`, статистика на токенах (`NcColors.heat`), настройки
(`NcSection`/`NcSlider`/`NcChip`/`NcStepper`) и провайдеры (карточки,
`NcDropdown`, проверка ключа бейджем). Guard миграции расширен на 13 файлов,
`ui_keys.txt` — **238 ключей**, Красная зона: `git diff --stat
4b4cc21..HEAD -- <19 файлов>` пуст. Скриншоты — 48 PNG (8 экранов × 2 темы ×
3 ширины), golden экранов — 16 PNG.

**Отклонения (журнал `journal/redesign-3/README.md`):** плитка колоды 92 px
вместо 88 (вмещение двух строк), аватар в конструкторе 40 px (NcIcon3D
запрещает < 40), миниатюры карточек в списке колоды не загружаются,
предпросмотр полей формы свёрнут по умолчанию, fade-out occlusion-маски
заменён мгновенным раскрытием (тесты контента ждут исчезновения после одного
`pump`), подсказка ⌘K в сайдбаре — этап 5.

## Редизайн «Nocturne» — этап 1 «Фундамент» (2026-11-17, ADR-035)

**Факты старта:** `git status --porcelain` → только `?? redesign/` (пакет
документации), `HEAD = origin/main = 7458346` (`docs: record green CI for
7.17`). Baseline: **1771 passed + 8 skipped**, одно падение — живой Wikimedia
(сеть, L92); в STATE 7.17 записано 1772 + 8 (расхождение — тот же live-тест).
Прогоны — только с `--no-pub` (L64).

**Гейты этапа 1:** `fvm flutter test --no-pub --coverage --exclude-tags golden`
→ **1924 passed + 8 skipped** (+152 к baseline); покрытие рукописного кода
**92.8 % (13706/14775)** (`tool/coverage_check.dart --min=80`); `analyze` **0**;
`dart format --set-exit-if-changed lib test integration_test tool` → **0
changed**; `fvm flutter build windows --release --no-pub` → `cardflow.exe`
(61,1 с). Скриншоты: `journal/redesign-1/screenshots/` — 60 PNG (15 экранов ×
2 темы × 390×844 и 1440×900). Красная зона и экраны: `git diff --stat` пуст
(`journal/redesign-1/red-zone.md`).

**Сделано (шаги 1.0–1.7):** ADR-035 (замена SPEC A4 в визуальном слое) и
спайки (`journal/redesign-1/spikes.md`); guard-тесты (`tool/extract_ui_keys.dart`
+ снимок 219 ключей, `design_tokens_test`, `no_network_fonts_test`,
`haptics_test`, изоляция `design/` в `architecture_test`); токены
`lib/ui/design/tokens/` (Nocturne/Porcelain/high-contrast/dynamic HCT,
типографика, сетка, радиусы, глубина, стекло); шрифты Onest/Literata/
JetBrains Mono (переменные, OFL, `LicenseRegistry`) и растровый тест
кириллицы; `NcTheme` (ThemeExtension) + ручной `ColorScheme` §1.5 в
`AppTheme` (публичный API прежний, elevation 0, прозрачный `scaffold`,
18 тем компонентов, шрифт дислексии во всех ролях); движение
(press/snap/gentle/celebrate, длительности, кривые) и `NcMotion`/
`NcHaptics` (throttle 40 мс); `NcAmbientBackground` (Aurora + зерно) и
`NcPageTransitionsBuilder`; подключение в `builder` `MaterialApp.router`
(`NcMotionScope → NcHapticsScope → NcAmbientBackground → M3ETheme`).

**Коммиты этапа:** `8158fc6` (ADR/спайки), `1daef8c` (guard-тесты),
`3559557` (токены), `bed3196` (шрифты), `1787097` (NcTheme/AppTheme),
`42f13df` + `e4fb90f` (движение/отклик), `a4a5e4c` (фон/переходы/проводка),
далее — журнал/verify.

**Отклонения (в ADR-035):** light-акценты Porcelain затемнены минимально
(4,38 → 4,77 : 1) до нормы AA §10; iOS/macOS делегируют Cupertino-переходом
(жест «назад»), `cupertino_ui` запинен 1.1.6; зерно — тайловый PNG, не
`grain.frag` (детерминизм golden/CI); `TextTheme.bodyLarge` — роль `bodyL`
(Onest 16/24), Literata-роль `answer` живёт в `NcTypography`; дрейф Aurora
выключен под `FLUTTER_TEST`.

**Новые ограничения:** L93 (M3E-виджеты не подчиняются теме), L94 (поля
ввода без superellipse), L95 (дрейф Aurora не виден в тестах), L96 (бюджет
стекла не измерен — нет Android SDK), L97 (guard-долг: 29 литералов цвета +
7 файлов с `HapticFeedback.`, burn-down в этапах 3–4).

**Push и CI этапа 1:** `7458346..9a19d97` (9 коммитов + пакет
`redesign/`). CI run
[`43970683883`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43970683883)
— **9/9 job success** (`format + analyze`, `test` × Ubuntu/Windows/macOS,
`build` desktop × Linux/Windows/macOS, `build` mobile Android/iOS). Проверочный
docs-коммит `734c120` (`docs: record green CI for Nocturne stage 1`) — CI run
[`43973443414`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43973443414)
— **9/9 job success** (проверено через GitHub API по SHA, jobs: тот же набор).

**Следующий шаг:** этап 2 «Компоненты» — `lib/ui/design/components/` по
REDESIGN-SPEC §8 (примитивы → действия → ввод → структура → оверлеи →
прогресс → сессионные), golden-тесты, счётчик групп `BackdropFilter`.

## Итерация 7.17 — где остановились (до редизайна)

**Дата:** 2026-11-16 · **Этап:** итерация **7.17** «Глобальный рендер LaTeX и
cloze во всех режимах» (ADR-034) — завершена.

**Факты старта 7.17 (сверено командами):** `git status --porcelain` → пусто,
`HEAD = origin/main = 4dfe10c` (`docs: note cancelled macos/ios jobs and rerun
CI`) — в STATE 7.16 последним записан `aad938f`, после него был docs-коммит,
исправлено. Baseline — **1742 passed + 8 skipped**
(`flutter test --no-pub --exclude-tags golden`), `analyze` **0**, `format` **0**.
Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode нет (L2).
Прогоны — только с `--no-pub` (L64).

## Сверка STATE с кодом (7.17, старт)

Проверено по файлам, расхождения исправлены:

- **Режимы:** `classic`, `feed`, `practice`, `constructor` (`_SessionModeAction`
  в `lib/ui/decks/deck_screen.dart`) + новые `test`, `typing`, `match`,
  `true_false` (7.15/7.16). Маршруты — `/decks/:deckId/{study,feed,practice,
  test,typing,match,true-false}` и `/constructor`. Подтверждено.
- **Рендер карточки:** единая точка — `lib/ui/cards/content/`
  (`CardContentView`, `LatexText`, `ClozeText`, `InlineLatexText`). До 7.17
  новые режимы использовали `CardContentView` только для вопроса.
- **Факты приложения:** копия `%APPDATA%\ru.example\cardflow\cardflow\
  cardflow.sqlite` — 175 карточек, 61 с LaTeX (61 формула в ответах, часть в
  вопросах), 6 cloze; все 78 уникальных формул парсятся `flutter_math_fork`.

## Сверка STATE с кодом (7.14, старт)

Проверено по файлам, расхождения исправлены:

- **Режимы:** реально четыре — `classic`, `feed`, `practice`, `constructor`
  (`_SessionModeAction` в `lib/ui/decks/deck_screen.dart`; маршруты
  `/decks/:deckId/{study,feed,practice}` и `/constructor`). В истории STATE
  конструктор упоминался только в итерации 6 — здесь зафиксировано явно.
- **Промпты генерации:** `gen-ru-v5` — сырой литерал
  `lib/api/prompts/system_prompt.dart`, дословная копия
  `docs/prompts/gen-ru-v5.txt`; механизм версии — константы +
  `CardGenerationService.promptVersion`. Подтверждено.
- **ImageSearchService:** до 7.14 это **Openverse**
  (`lib/api/images/image_search_service.dart`), а цепочка —
  `CompositeCardImageFinder` (Commons → Wikipedia → Openverse). В 7.14
  `ImageSearchService` стал цепочкой провайдеров (ADR-031), старые сервисы
  заменены на `ImageProvider`-реализации.
- **MediaStore:** был только файловый (байты по пути); метаданных
  провайдера/лицензии/isPlaceholder не было, `media` их не хранит. В 7.14
  добавлены побочные `<путь>.meta.json` (`MediaMetadata`), схема БД не менялась.
- **FSRS:** `FsrsScheduler` (`lib/domain/scheduling/scheduler.dart`), маппер
  `fsrs_mapper.dart`, начальное состояние `CardSchedulingMapper.initialScheduling`.
  Подтверждено.
- **Лист режимов:** `showModalBottomSheet` в `_startSession`
  (`lib/ui/decks/deck_screen.dart`), ключи `review-mode-*`. Подтверждено.
- **ARB:** один файл `lib/l10n/app_ru.arb`; `supportedLocales` — только `ru`,
  `app_en.arb` нет. Требование задания «ARB (ru, en)» конфликтует с жёстким
  правилом AGENTS/SPEC (локаль только `ru`) и guard-тестом `ru_strings_test`:
  новые строки добавлялись в `app_ru.arb`; английская локаль не вводилась
  (продуктовое решение, не самовольное изменение).
- **Правило «абстрактные понятия без картинки»** было в валидаторе
  (`_isAbstractCard` + `CardIssueCode.abstractImageQuery`) — удалено в 7.14
  вместе с промптом v6.

## Итерация 7.14 — итог (ADR-031)

**Гейты 7.14:** `test --no-pub --coverage --exclude-tags golden` → **1660
passed + 8 skipped** · покрытие рукописного кода **92.0 % (12159/13218)** ·
`analyze` **0** · `format` **0 changed** · `build windows --release --no-pub` →
`cardflow.exe` (84,4 с) · Windows-смоук
`integration_test/session_smoke_windows_test.dart -d windows --no-pub` →
**All tests passed!** (9 с) — форма+картинка, лимит, сессия, генерация с картинкой.

**Сделано:**
- Промпт `gen-ru-v6` (сырой литерал + `docs/prompts/gen-ru-v6.txt`, тест
  байт-в-байт); v5 сохранён. Обязательный объект `image` у каждой карточки
  (`query`, `fallback_query`, `kind`), канонические якоря схем
  (`free body diagram …`, `force couple diagram …`), запреты (русские слова,
  «image/photo of», имена файлов, LaTeX, одно слово, повторы в колоде).
- Схема: строгая v6 для провайдера; локальная терпимая `localCardItemSchema`
  принимает и v5 (`image_query` строкой/`null`), и карточку без `image`.
- Нормализация `image_query_normalizer.dart`: чистка запрещённых слов,
  не-латиницы, имён файлов и LaTeX; обрезка до 7 слов; сборка из fallback;
  дополнение вида; legacy-вывод kind. Правка → `imageQueryAdjusted`, карточка
  не отбрасывается.
- Цепочка `ImageSearchService` + интерфейс `ImageProvider`
  (`wikimedia`, `wikipedia`, `openverse`, `pixabay`, `pexels`): таймаут 6 с на
  провайдера, бюджет 20 с на карточку, основной запрос → fallback, скачивание
  с лимитом 4 параллельно, фильтры JPEG/PNG/WebP + короткая сторона ≥ 400 px +
  пропорции ≤ 3:1 + безопасный поиск, кэш LRU 32, дедупликация URL, ретрай
  одного 429/5xx с backoff, затем следующий провайдер. Ключи Pixabay/Pexels —
  только `--dart-define`/env; без ключа провайдера нет.
- Заглушки: `PlaceholderImageGenerator` (8 палитр, градиент+паттерн+иконка
  вида, детерминированно от хэша содержимого), PNG 800×450/800×600, флаг
  `isPlaceholder`, провайдер `placeholder`. Метаданные атрибуции
  (`provider`, `sourceUrl`, `author`, `license`, `query`, `fallbackQuery`,
  `kind`) — в `MediaStore` рядом с файлом; GC чистит их вместе с медиа.
- «Найти картинку заново» в редакторе карточки (`CardImageRefresher`) и
  фоновый ретрай заглушек на старте (`main.dart`, ≤ 5 за запуск, ошибки глушатся).
- UI: `CardImageView` (16:9, схема 4:3, cover/contain, скругление 16, fade-in,
  скелетон, max-height 220), полноэкранный просмотр с зумом и атрибуцией;
  картинки в предпросмотре, Классике, Ленте, Тренировке, редакторе; живой
  список карточек во время генерации (`GenerationProgress.cards`).
- Тесты: нормализация, схема/совместимость v5, провайдеры (включая
  Pixabay/Pexels на мок-клиенте), цепочка (приоритет/таймаут/фильтры/ретраи/
  кэш/лимит параллелизма/дедуп), заглушки (детерминизм/флаги), `MediaStore`
  и GC, `CardImageRefresher` (замена заглушки, лимит, ошибки), pipeline
  (заглушка, дедуп URL, fallback/kind), виджеты (фото/схема/заглушка/без
  картинки, overflow 360×640 и 1280×800, fullscreen+атрибуция, «Найти заново»,
  живые карточки).

**Живая проверка (2026-11-16, `deepseek-chat`, настоящая сеть):** две колоды по
18 карточек (`test/live/images_v6_live_test.dart`, отчёт
`journal/iteration-7.14/live-metrics.{md,json}`, картинки в
`journal/iteration-7.14/images/`):

| Колода | Карточек | Настоящих | Заглушек | Провайдеры | Ср. догрузка |
|---|---|---|---|---|---|
| Статика | 18 | 18 (100 %) | 0 | wikipedia 14, wikimedia 4 | 3,5 с |
| Биология | 18 | 18 (100 %) | 0 | wikipedia 10, wikimedia 8 | 1,9 с |

Ручная оценка 10 случайных карточек (`journal/iteration-7.14/relevance.md`):
**Биология 8/10** — цель достигнута; **Статика 1/10** — цель ≥ 7/10 не
достигнута. Выполнена одна итерация правки промпта (канонические якоря схем),
повторный замер: настоящих картинок 100 %, уместность «Статики» осталась низкой
(2/18 по всей колоде), «Биология» — 13/18. Причина — полнотекстовый поиск
Commons/Wikipedia для абстрактных механик совпадает с посторонними статьями
(фазовые диаграммы, карты, портреты); фильтры формата/размера их пропускают.
Ограничение — L84; рекомендация — семантическая проверка релевантности
(vision/LLM) или курируемый источник схем. Заглушка в этих случаях не
включается, т.к. картинка формально найдена.

**Долги 7.14:** L81 (Pixabay/Pexels без ключей), L82 (метаданные вне БД),
L83 (seed заглушки — хэш содержимого), L84 (семантическая релевантность),
L85 (метрики на одной модели), L86 (дедуп URL в пределах запуска).

## Итерация 7.15 — итог (ADR-032)

**Гейты 7.15:** `test --no-pub --coverage --exclude-tags golden` → **1715
passed + 8 skipped** · покрытие рукописного кода **91.7 % (12974/14143)** ·
`analyze` **0** · `format` 0 changed · `build windows --release --no-pub` →
`cardflow.exe` (см. отчёт о прогоне) · Windows-смоук — после 7.16.

**Сделано:**
- Домен: `StudyMode` (`test`, `typing`, `match`, `true_false`; wire-значения для
  `review_logs.mode`), политика FSRS (`isDueForStudy`: новая карточка тоже
  «due» — первая оценка создаёт расписание; будущая `due` — тренировка),
  очередь (`buildStudyQueue`: due/новые, затем будущие), `AnswerType`
  (`short_text|number|formula|long_text`; для ввода — ≤ 60 символов, ≤ 6 слов,
  без LaTeX/переносов), нормализация (NFC через `unorm_dart`, регистр, ё/е,
  пробелы, пунктуация, ответы через `/`/`;`), `AnswerMatcher`
  (`exact|almost|wrong`, Левенштейн 1/2, diff missing/extra), `DistractorGenerator`
  (3 ответа из колоды того же типа, близкой длины; числа — та же единица; без
  дублей; позиция правильного по seed; `aiDistractors` как вход).
- `StudySessionController`: общая очередь/прогресс/итоги/undo/«Повторить
  ошибки»; due → `Scheduler`+`ReviewRepository` (`mode`), будущие →
  `PracticeRepository` (`mode`; undo фильтруется по mode, классический журнал
  не удаляется). Порт тренировки расширен необязательным `mode`.
- Экраны: `MultipleChoiceScreen` (4 варианта, зелёный/красный, автопереход 1,2 с
  кроме reduce motion, пружина+haptics, клавиши 1–4/Enter, итоги и повтор
  ошибок), `TypingScreen` (exact/almost/wrong, diff, «Я был прав» = undo +
  Good, «Показать ответ» = Again, Enter); маршруты
  `/decks/:deckId/{test,typing}`; лист режимов с числом доступных карточек и
  неактивными пунктами при их нехватке; ARB (ru).
- Тесты: 9 domain (тип/матчер/дистракторы/очередь/политика), 8 controller,
  16 widget (Тест/Ввод), 3 листа режимов, mode-scoped undo; полный прогон —
  зелёный.

**Решения/отклонения:** ИИ-дистракторы (batch-запрос на колоду и кэш) в этой
итерации не подключены: генератор принимает `aiDistractors`, но production-
источника ИИ и кэша нет — карточки, для которых в колоде меньше 4 подходящих
ответов, пропускаются в Тесте (L87). Дневные лимиты новые режимы не учитывают
(L88) — FSRS пишется только для due, но лимит новых/повторов может быть
превышен; это осознанное упрощение до обсуждения владельцем.

## Итерация 7.14 — CI

Push `cc88e0c..bf28359`; CI run
[`43901313115`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43901313115)
— **9/9 job success** (format+analyze, test ×3, build desktop ×3, mobile 2).

## Итерация 7.15 — CI

Push `bf28359..df0e873`; CI run
[`43904903386`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43904903386)
— **9/9 job success** (format+analyze, test ×3, build desktop ×3, mobile 2).

## Итерация 7.17 — итог (ADR-034)

**Гейты 7.17:** `test --no-pub --coverage --exclude-tags golden` → **1772
passed + 8 skipped** (baseline 1742 + 8; первый прогон дал 1771 + 8 и одно
падение живого Wikimedia-теста — сеть/rate-limit, повторный зелёный, L92) ·
покрытие рукописного кода **91.9 % (12947/14085)** · `analyze` **0** ·
`format` 0 changed · `build windows --release --no-pub` → `cardflow.exe`
(60,8 с).

**Причина по фактам:** вопрос новых режимов уже рендерился через
`CardContentView`, а остальной текст — сырым `Text`: варианты «Теста», плитки
«Подбора пар» (все 12), утверждение и пояснение «Верно/Неверно», строка
правильного ответа и diff «Ввода ответа», список ошибок на итогах. ЛаТеХ в БД
корректен (78/78 формул парсятся) — ломался только рендер.

**Сделано:**
- `latexTextSpans()` (`lib/ui/cards/content/latex_spans.dart`) — единый inline-
  рендер текста с формулами (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`): текст —
  `TextSpan`, формулы — `WidgetSpan(Math.tex)`, все сразу; стиль наследует
  родителя, `fontSize`/`color` дозаполняются из темы.
- `CardText` (`lib/ui/cards/content/card_text.dart`) — «текст карточки вне
  карточки»: cloze → `ClozeText`, формулы → `InlineLatexText`, plain → `Text`;
  `style/textAlign/maxLines/overflow/revealed`. `InlineLatexText` переписан на
  общий хелпер (plain-текст остаётся `Text` с `data` — тесты не ломаются).
- `CardContentView.showAllFormulas` — вопрос режимов показывает все формулы
  сразу (пошаговое раскрытие — механика «Классики»); cloze-пропуски скрыты.
- Семантика вариантов «Теста» — без `$` (`plainTextOfLatex` в
  `latex_markup.dart`).
- `AnswerDiffView` (публичный) собирает фрагменты через `latexTextSpans`:
  полная формула рендерится, обрывок остаётся текстом (без падения).
- Домен (ADR-034): `AnswerType.isChoice` + `AnswerTypes.isChoice` (короткий/
  число/**формула**, ≤ 120 символов); `DistractorGenerator`, лист режимов и
  дистракторы «Верно/Неверно» используют `isChoice`; «Ввод ответа» остаётся на
  `isTypable`. `classifyAnswer` относит `\(…\)`/`\[…\]` к `formula`.
- Скриншоты `journal/iteration-7.17/screenshots/` (Тест с формулами в вопросе и
  четырёх вариантах, Пары, Ввод, Верно/Неверно); `tool/screenshots` грузит
  KaTeX-шрифты `packages/flutter_math_fork/KaTeX_*`.
- Тесты: +30 (10 `study_mode_latex_test`, 11 `card_text_test`, 6 доменных,
  1 лист режимов, 2 в существующих наборах). Отчёт —
  `journal/iteration-7.17/README.md`.

**Решения/долги:** формульный ответ теперь допустим в «Тесте» (выбор) и как
дистрактор «Верно/Неверно», но не в «Вводе ответа»: контракт 7.15 «формулы не
строят вопрос» заменён осознанно (ADR-034). L87/L88 не менялись. Схема БД и
`format_version` не менялись.

## Итерация 7.17 — CI

Push `4dfe10c..b199dbc`; CI run
[`43935245725`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43935245725)
— **9/9 job success** (format+analyze, test ×3, build desktop ×3, mobile 2).

## Итерация 7.16 — итог (ADR-033)

**Гейты 7.16:** `test --no-pub --coverage --exclude-tags golden` → **1742
passed + 8 skipped** · покрытие рук��писного кода **91.7 % (13521/14743)** ·
`analyze` 0 · `format` 0 changed · `build windows --release --no-pub` →
`cardflow.exe` (52,4 с).

**Сделано:**
- «Подбор пар»: домен `MatchGame` (6 пар, 12 плиток, перемешивание по seed,
  selected/matched/mismatch/moves, `select → selected|matched|mismatch|ignored`),
  экран `MatchScreen` (сетка 3/4 колонки, таймер с первого тапа, встряхивание
  несовпавшей пары, исчезновение найденной, итог + лучшее время, «Ещё раз»,
  «Готово»); `MatchBestStore` + `DriftMatchBestStore` — JSON v1 в `app_settings`
  (`study.match.best`), схема БД не менялась. FSRS не пишется.
- «Верно/Неверно»: домен `TrueFalseQuestion` (50/50 из правильного ответа или
  дистрактора колоды, seed), экран `TrueFalseScreen` (утверждение, кнопки ✓/✗,
  свайп вправо/влево, плашка результата с правильным ответом, авто-переход 0,9 с
  кроме reduce motion, итоги/повтор ошибок) на общем `StudySessionController`
  (`mode='true_false'`, FSRS только для due, остальные — тренировка).
- Маршруты `/decks/:deckId/{match,true-false}`, пункты листа режимов с числом
  доступных карточек и неактивным состоянием, ARB (ru). Тесты: домен
  (MatchGame/TrueFalse), хранилище на реальной drift-БД, widget (9 сценариев),
  лист режимов, роутер (17 маршрутов).

**Скриншоты (7.14–7.16):** `journal/iteration-7.15/screenshots/` — карточка с
фото/схемой/заглушкой, «Тест» (светлая/тёмная), «Ввод ответа», «Подбор пар»,
«Верно/Неверно» (тёмная); сняты golden-рендером реальных экранов
(`tool/screenshots/screens_test.dart`), README — рядом.

**Решения/долги:** лучшие результаты «Пар» — локальный кэш, не входят в
статистику/экспорт; таймер игры — `Timer.periodic` экрана (L33/L88);
ИИ-дистракторы по-прежнему не подключены (L87).

## Итерация 7.16 — CI

Первый push (`8eedd84`) — CI run
[`43909148956`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43909148956)
**упал только на `format + analyze`** (неиспользуемые импорты в новом
test/tool), все test/build job'ы зелёные. Фикс `ed83795` → CI run
[`43913907014`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43913907014)
— **9/9 job success**. Push 7.16: `ed83795..b58895a` (фикс analyze, скриншоты `3aac099`,
STATE/AGENTS `b58895a`); финальный CI run
[`43915833682`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43915833682)
— **9/9 job success**. Docs-коммит `aad938f` (run
[`43918913669`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43918913669)):
все выполнявшиеся job'ы зелёные, `build macos`/`build ios` **отменены раннером**
(инфраструктура, не ошибка шага) — повторный прогон после docs-правки.

## Итерация fix-gen — итог (архив, v5)

**Причины (диагностика `journal/iteration-fix-gen/diagnosis.md`):**
- Д4/Д6: модель пишет LaTeX одним `\` в JSON → `\frac`→form feed, `\alpha`→
  `FormatException`; фрагмент падал `invalidResponse`, формула молча портилась.
- Д6: все схема- и структурно-невалидные карточки роняли фрагмент; предпросмотр
  не импортировал пак из-за одной невалидной карточки.
- Д3: изображения файлов не извлекались (парсеры читали только текст).
- Д2: производный `image_query` из текста вопроса давал случайные картинки.

**Сделано:**
- Промпт `gen-ru-v5` дословно (`lib/api/prompts/system_prompt.dart` +
  `docs/prompts/gen-ru-v5.txt`, тест байт-в-байт); блоки `<materials>`,
  `<wishes>`, `<limit>`, `<images>`; `Файл: <имя>`; лимит карточек из пожеланий
  делится по фрагментам пропорционально (`generation_card_limit.dart`).
- Схема A8.4 + `image_id`, поштучная проверка, проекции OpenAI/Gemini/Anthropic
  (ADR-029); валидатор: `image_id` вне каталога → null; `image_query` — латиница
  ≤ 7 слов; абстрактные понятия без картинки; tags ≤ 3.
- LaTeX: `latex_escape_repair.dart` (до/после JSON), `\(\)`/`\[\]` → `$…$`,
  `\$` не формула; `LatexText`/`ClozeText`/`InlineLatexText` через `Math.tex`.
- Изображения DOCX/PPTX/ODT (`DocumentImage` + контекст, фильтры мусора) →
  `<images>` фрагмента → `image_id` → байты файла; предпросмотр: убрать/заменить.
- Причины сбоя фрагмента (`GenerationFailureReason`, 13 кодов) в
  `generation_jobs.error_code` и debug-лог; частичный импорт; кнопка неактивна
  только без выбранных карточек; ошибки «Фрагмент K из M: причина».
- Д5: мягкие проверки качества (7 пометок) + eval-набор 3 сценария + live-метрика.
- Д1: кнопка неактивна без файлов/темы, подсказка ARB, имя колоды из темы,
  `source_excerpt` при пустых материалах → null.

**Доказательства:** `journal/iteration-fix-gen/{diagnosis,red-output,review,verify,summary}.md`;
тесты `latex_escape_repair_test`, `latex_render_fix_test`, `document_images_test`,
`card_generation_images_test`, `generation_fix_gen_test`, `card_quality_test`,
`quality_eval_test`, `generation_preview_partial_test`, `failure_reasons_test`,
`generation_failure_message_test`, `prompt_test` (байты).

## Известные ограничения (актуальные)

L1, L2, L4–L8, L10–L16, L18–L20, L23–L25, L27, L28 (только Windows), L30,
L31–L34, L35, L36, L37–L44, L46–L52, L53 (живой PDF-part), L54, L55, L56,
L57–L59 (≤ 3 страниц), L60 (снято 7.12; предпросмотр — fix-gen), L61, L62–L64,
L65, L66 (обновлено L80), L67, L68, L69, L70, L71–L75,
**L76** (изображения внутри PDF не извлекаются), **L77** (только JPEG/PNG из
документов), **L78** (ручные клики/скриншоты владельца), **L79** (причины
сбоя перечнем в `error_code`), **L80** (поштучный отброс карточек моделей,
не следующих strict-схеме), **L81** (Pixabay/Pexels без ключей), **L82**
(атрибуция в побочном JSON, не в БД), **L83** (seed заглушки — хэш
содержимого), **L84** (семантическая релевантность картинок не проверяется),
**L85** (метрики на `deepseek-chat`), **L86** (дедуп URL в пределах запуска),
**L87** (ИИ-дистракторы не подключены: мало ответов → карточка пропускается в
Тесте), **L88** (новые режимы не учитывают дневные лимиты), **L89** (семантика
формул — текст без `$`), **L90** (посимвольный diff для формул не показывается),
**L91** (KaTeX-шрифты в скриншот-харнессе грузятся вручную), **L92** (live-тесты
поиска картинок идут в общем прогоне и зависят от сети).

## История

- 7.17 «Глобальный рендер LaTeX и cloze во всех режимах» (2026-11-16) — ADR-034,
  гейты выше.
- 7.16 «Подбор пар» и «Верно/Неверно» (2026-11-16) — ADR-033, гейты выше.
- 7.15 «Тест» и «Ввод ответа» (2026-11-16) — ADR-032, гейты выше.
- 7.14 «Картинка у каждой карточки» (2026-11-16) — ADR-031, CI run `43901313115` 9/9.
- fix-gen «Исправление генерации» (2026-11-16) — ADR-029/030.
- 7.12 «Фикс UX картинок, лимитов и поиска ИИ» — CI run `43750931989` 9/9.
- 7.11 «FSRS новых карточек, картинки, сканы и Practice Mode» — CI run
  `43742161910` 9/9.
- 7.10 «Prompt-only, PDF и картинки» — CI run `43728048903` 9/9.
- 7.9 «PDF-сканы, иллюстрации и occlusion» — CI run `43703387395` 9/9.
- 7.8 «Вложения и Vision» — ADR-022, CI run `43650756271` 9/9.
- 7.6 «Пустой ответ LLM» — CI runs `43637919516`/`43639479927` 9/9.
- 7.5 «Провайдеры и ключи» — ADR-020, CI run `43632334916` 9/9.

## TASK 05 — Controlled Live Generation Validation, подготовка A–C (2026-11-19)

**Старт:** `git status --porcelain` → только `?? redesign/`; `HEAD = 6bdf3e4`;
baseline **2157 passed + 16 skipped**, `analyze` 0.

**Сделано (без единого платного запроса):**
- каталог DeepSeek приведён к официальной странице 2026-11-19:
  добавлены `deepseek-flash` (default, 1M, Vision) и `deepseek-v4-pro` (1M),
  legacy `deepseek-chat`/`deepseek-reasoner` оставлены для сохранённых
  аккаунтов; это убрало «1 карточку на запрос» у unknown-модели (L137/L139
  обновлены, L147);
- live-инфраструктура: logical/HTTP/attempts/retries разделены, бюджеты общие
  на файл (`LiveRecordingCaller`, `LiveProbeTransport`, `LiveAttemptLimiter`),
  `LiveCostGuard` резервирует стоимость каждой физической попытки до отправки,
  strict-400 освобождает резерв; отчёт содержит цены, estimated/actual cost,
  `requestCosts[]`, latency; `note` редактируется;
- сценарии A–C: A = 5 карточек (1 запрос), B = 40 (6 запросов, continuity),
  C = DOCX с 3 Heading1 через production `DocxParser`; importability
  проверяется `CardDraft.validate()`;
- `CARDFLOW_LIVE_SCENARIOS` — явный список id, чтобы A–C не задевали Test D;
- ручная рубрика 8 критериев 0/1/2 + `LiveDocumentAssessment` для Test C;
- артефакты: `journal/task05/{audit,test-plan,budget,readiness-report}.md`,
  `journal/task05/results/README.md`; `docs/generation-pipeline.md` §9.

**Гейты:** `test --no-pub --exclude-tags golden` → **2177 passed + 16 skipped**;
`test/unit/live` → **48 passed**; Test F (`generation_recovery_http_test`) →
**11 passed**; `test/live --tags live` → **16 skipped, 0 запросов**; `analyze`
0; `format` **500 файлов / 0 changed**; `build windows --release --no-pub` →
`cardflow.exe` (62,1 с); `--coverage` → **92.4 % (16202/17535)**.

**Коммиты:** `4e385ff` (каталог DeepSeek), `e401c69` (live-инфраструктура и
A–C), docs-коммит `docs(journal): record TASK 05 live readiness` (аудит, план,
бюджет, отчёт). Push не выполнялся.

**Платные запросы:** не выполнялись. `DEEPSEEK_API_KEY` present в Windows
User scope, значение не выводилось. Готовность A–C — YES, запуск только по
отдельному разрешению (`journal/task05/readiness-report.md`). Ограничения:
L143–L148 (биллинг 400/повторов, thinking mode, live-импорт в БД, legacy
DeepSeek, ручная приёмка).
