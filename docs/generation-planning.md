# Планирование генерации CardFlow (итерация 7.18, ADR-039/ADR-040)

Документ описывает, как запрос пользователя превращается в `GenerationPlan`:
сколько и каких карточек можно сделать, куда пойдёт материал, какие поля уйдут
модели и как конвейер исполняет план. Источник правды — код
`lib/domain/generation/`; схема ответа — `docs/api-schema.md`; промпт —
`docs/system-prompt.md`.

## 1. Три независимых решения

1. **Input Planner** (`input_planner.dart`) — как подать материал: целиком или
   частями. Не знает о заказанном числе карточек (в сигнатуре нет
   `requestedCards`) — это структурная гарантия независимости.
2. **Card Allocator** (`card_allocator.dart`) — сколько карточек даёт каждый
   раздел с учётом плотности учебных фактов.
3. **Output Batch Planner** (`output_batch_planner.dart`) — как разбить
   распределение на партии с `focus`, лимитом и стабильным префиксом.

`GenerationChunkPlanner.plan` — тонкая фасадная сборка этих трёх решений;
конвейер ничего не досчитывает «на глаз».

## 2. Характеристики модели и происхождение

Каждое значение — `Sourced<T>` (`sourced.dart`): значение + источник +
дата наблюдения + ссылка. Источники: `userConfigured`, `providerApi`,
`officialCatalog`, `assumption`, `unknown`. Отсутствие значения — `unknown`,
никогда не «типовое число семейства».

Лимиты (`model_limits.dart`): окно и семантика (`total`/`inputOnly`/`unknown`),
вход/выход, карточки на запрос, байты тела, изображения (на запрос/на файл/
суммарно), Vision/PDF/reasoning, цены. Слоистый резолвер
`model_limits_resolver.dart`: пользователь > API провайдера > каталог пресета >
допущение > неизвестно. Контекст из пресета не считается пользовательским;
`inferred` Vision — только `assumption`.

Discovery (`model_capability_discovery.dart`, `lib/api/models/model_discovery.dart`):
OpenAI-совместимые (`/models`, политики `idsOnly`/`documented`, OpenRouter —
цены за токен → за 1M, `min(context)`), Anthropic (`after_id`-пагинация),
Gemini (`pageToken`, фильтр `generateContent`), Ollama (`/api/tags` + `/api/show`,
`num_ctx` — допущение), generic — только id. Ошибки discovery не стирают
последнее удачное значение. Кэш — JSON v1 `generation.model_capabilities`
(TTL 7 дней, инвалидация по аккаунту, без ключей/хэшей); план читает **только**
кэш, сеть — явное обновление. Нативный подсчёт входа реализован для
Anthropic/Gemini (`request_token_counter.dart`) и передаётся в план как
`exactInputTokens` (подключение к конвейеру — ограничение L156).

## 3. Вход: инвентарь и бюджет

- Единицы — разделы файлов; пустые/служебные отбрасываются, через `<materials>`
  идут заголовки `## [sN] Заголовок`.
- Оценщик — `ContentTokenEstimator` (`tokensPerCard=300`, `tokensPerImage`,
  консервативно); `tokensPerCard` калибруется по фактам (см. §7).
- `RequestBudget.compute`:
  `input = ceil((P + D) × (1 + m))`, `m = 3 %` для точной оценки и `10 %` для
  оценки приложения; `room = context − input` (семантика `total`) или
  `outputCap` (`inputOnly`); `maxTokens = min(room, desiredOutput,
  maxOutputTokens)`; неизвестный контекст — консервативный режим с
  предупреждением `contextUnconfirmed`. Байтовое тело проверяется отдельно
  (`maxRequestBytes`), переполнение — `payloadLimited`.
- **`D` включает каталог изображений** (7.18.2): `InputImage.catalogTokens`
  считается тем же `imageCatalogLine`, что уходит в `<images>`, и входит в
  `InputPart.totalMaterialTokens`, `materialTokens`, `inputTokens`,
  `GenerationEstimate.catalogTokens` и «Подробнее». Без этого подписи и
  окружающий текст каталога не занимали бюджета (дефект: 24/74/52 токена
  каталога против 0).
- **`P` и байты тела** (7.18.2): `GenerationOverheadTokens.fixedBytes` —
  системный промпт + JSON-схема ответа + обёртка сообщения — входит в
  `requestBytes` плана. План и факт сверяются тестом: оценка против
  сериализованного payload (оценка 81 КБ против 110 КБ была дефектом).
- **Reasoning-модели** (7.18.2): до калибровки `max_tokens` включает
  `GenerationPlanningConfig.reasoningReserveTokens` (2048, допущение);
  карточки партии считаются от `max_tokens − резерв`. После ≥2 замеров
  калибровки резерв = 0 (факт `usage` уже содержит рассуждение).
- **Точный подсчёт и изображения** (7.18.3): `RequestTokenCounter` получает
  `attachments` в том же виде, что production: Anthropic — base64
  `image`/`document`-блоки (`anthropicUserContent`), Gemini — `inlineData` в
  `CountTokensRequest.generateContentRequest` (`geminiParts`). Повторная оценка
  изображений не добавляется; кэш (`exactTokenCacheKey`) включает digest байтов,
  MIME и подпись каталога.
- **Состав бюджета** (7.18.3): `RequestBudget` хранит `nativeInputTokens`
  (число `count_tokens`), `estimatedExtraTokens` + `estimatedComponents`
  (например, `response_schema` Gemini, вхождение которого в `totalTokens` не
  подтверждено), `marginTokens` (3 % — только если нативно посчитано всё, иначе
  10 %) и `effectiveBudgetTokens`. `InputAccuracy.exact` — только при нулевой
  добавке; смешанный результат — `estimated`, в «Подробнее» показывается
  составом (число провайдера / добавка / резерв / бюджет).
- **Неизвестный Vision** (7.18.3): `ModelLimits.imageInputSupport`
  (`supported`/`unsupported`/`unknown`) — допущение приложения и отсутствие
  данных не превращаются в `false`; `unknown` + изображения = предупреждение
  `imagesVisionUnconfirmed` и отправка частей, подтверждённое `false` —
  прежнее поведение (каталог/невыполнимый план).
- **`max_request_bytes`** (7.18.3): входит в `ModelLimits.unknownFields`,
  `ModelCapabilities.unknownFields` и блок «Неизвестные лимиты»; 32 МБ —
  допущение приложения, предупреждение о фактическом HTTP payload — отдельное
  (`assumedImageLimits` + проверка сериализованного тела).

## 4. Input Planner (ADR-040 §3)

Стратегии:

- `wholeDocument` — весь материал в один запрос. Проверка:
  `input ≤ context`, `room ≥ minBatchCards` токенов ответа.
- `fragmented` — материал делится на сбалансированные части:
  `Dmax = floor((context − R) / (1 + m)) − P`, где
  `R = min(outputCap, tokensFor(batchCardsCeiling))`, `batchCardsCeiling = 40`;
  части упаковываются в исходном порядке, перекрытие — только для контекста
  (`context_only`), не дублирует карточки.
- `promptOnly`/attachments — пустой `<materials>`, тема в `<wishes>`;
  вложения только при Vision.

`InputPlan` содержит `strategy`, `parts[]` (материал, разделы, оглавление,
изображения части), `inputTokens/maxTokens`, `accuracy`, предупреждения и
`partCount`. Изменение заказа карточек не меняет разбиение входа — это
проверяется тестом `planning_independence_test.dart`.

## 5. Card Allocator (ADR-040 §3.3, 7.20)

`SectionFeatures.of`: число слов, фактов, формул, определений, вопросов,
изображений → плотность и вес. Ёмкость раздела — от слов, плотности и веса и
**мягкая**: это оценка содержательной насыщенности материала.

- Заказ распределяется **целиком**: сначала water-filling до мягкой ёмкости,
  затем остаток — по весам разделов (точная целочисленная раздача наибольших
  остатков, `Σ planned == requestedCards`, ADR-043).
- Оценка ёмкости материала (`estimatedCapacity`) и признак `materialLimited`
  показываются **отдельно** — «материала хватает примерно на M карточек из N»
  (`PlanWarningCode.materialCapacityBelowRequested`). К бюджету модели это
  отношение не имеет.
- `PlanWarningCode.requestedAbovePlan` остаётся только для невыполнимого плана:
  в материалах нет ни одного содержательного раздела.
- Тихая обрезка заказа запрещена; технический предел — число партий
  (`maxChunks`), а не ёмкость материала.

## 6. Output Batch Planner и сообщение (ADR-040 §7, 7.20)

- Партии: `cardsPerBatch = min(batchCardsCeiling, cardsFor(maxTokens −
  reasoningReserve), maxCardsPerRequest)`; вместимость ограничивает **одну**
  партию, не заказ.
- `batchCount = ⌈total / cardsPerBatch⌉` (целочисленно, без переполнения);
  распределение — заполнение до вместимости и остаток последней партии
  (`OutputBatchPlanner.batchSizes`, ADR-043). Лишний запрос не создаётся, если
  заказ помещается в уже существующие партии.
- `focus` партии — разделы с положительной аллокацией, сгруппированные по
  порядку; разделы, попавшие в соседние партии, не дублируются (кроме
  перекрытия `sN` на границе).
- Изображения: eligibility (Vision, размеры), дедуп байтов, бины по
  `maxImagesPerRequest`/`maxImageBytesPerRequest`; остальное — только каталог.
- Пользовательское сообщение (`generation_prompt.dart`): **стабильный префикс**
  `<materials> → <images> → <outline> (если есть) → <wishes>` и изменяемый
  хвост `<task>`: `<part>k из n`, `<focus>s1, s2`, `<cards>N`,
  `<context_only>`, `<already_created>`. Display-id изображений (`img1…`)
  назначаются один раз по плану, каталог сортируется по id — префикс одинаков
  во всех партиях запуска (кэш префикса у провайдеров).

## 7. Исполнение и обратная связь (ADR-040 §8–9)

- Конвейер шлёт `focus/part/already_created`; дайджест уже принятых карточек —
  ≤ 20 строк по 80 символов (≤ 5 % входа).
- `source_exhausted` или недобор < 50 % партии: разделы помечаются
  исчерпанными; следующие партии не запрашивают их (focus сокращается);
  полностью исчерпанные — пропускаются. Недостача один раз перераспределяется
  одной дополнительной партией по разделам с оставшейся ёмкостью; лимит этой
  партии не больше вместимости одного ответа (`cardsPerBatch`, 7.20), а не
  константы 40.
- Дедуп: `content_hash` (+ обратный для reversed) и почти-дубли по триграммам
  ≥ 0.85 (для сторон < 12 букв — только хеш).
- Восстановление: truncated/413/распознанный 400 дробят только проблемную
  партию; бюджет операций — `generationRecoveryBudget` (≤ max(3, M/2)).
- Калибровка `generation.calibration` v1 (`app_settings`, без схемы БД):
  после прогона пишется `completion_tokens / accepted_cards`; после ≥ 2
  замеров EMA (0.7/0.3) подставляется в `tokensPerCard` следующего плана.
- `generation_jobs.chunk_count` = число **частей входа**, `tokens_used` = факт;
  debug-сводка плана — `GenerationDiagnostics.planSummary`.

## 8. Гарантии и тесты

- Независимость трёх решений: `planning_independence_test.dart` (заказ 1/10/
  100/500 не меняет стратегию и части входа при том же материале).
- Схема ответа: корень `{cards, source_exhausted}`, карточка `section_id`
  (union `string|null`), локальная терпимая схема принимает v5–v7.
- Тесты: `generation_planning_test.dart` (T1–T9), `card_allocator_test.dart`,
  `generation_chunk_planner_test.dart`, `generation_plan_batches_test.dart`,
  `generation_pipeline_v8_test.dart`, `model_discovery_test.dart`,
  `model_discovery_errors_test.dart` (401/таймаут/типы/пустой список),
  `model_limits_resolver_test.dart`, `drift_model_capability_cache_test.dart`,
  `request_token_counter_test.dart`, `drift_token_calibration_store_test.dart`.
- 7.18.2: `image_catalog_budget_test.dart` (каталог в `D`, 0/1/несколько
  изображений, длинные подписи, fragmented, exact), `generation_payload_bytes_test.dart`
  (полный сериализованный payload, `maxRequestBytes`, T5 13+13 МБ/20 МБ,
  политика для OpenAI-совместимого и Anthropic), `reasoning_reserve_test.dart`
  (резерв рассуждения и снятие калибровкой), `generation_exact_tokens_test.dart`
  (exact + изображения).
- 7.18.3: `request_token_counter_multimodal_test.dart` (Anthropic image/document
  base64, Gemini inlineData + `generateContentRequest`, несколько изображений,
  ключ кэша по дайджесту/MIME/подписи), `token_breakdown_test.dart`
  (native/estimated/reserve/budget, 3 %/10 %), `unknown_vision_and_limits_test.dart`
  (три состояния Vision, `max_request_bytes`), обновлённые
  `generation_exact_tokens_test.dart` (нет двойного учёта, кэш по байтам,
  mixed Gemini, вложения без текста), `generation_plan_details_test.dart`
  (состав бюджета, unknown Vision, неизвестные лимиты), `generation_screen_test.dart`
  (запуск при неизвестном Vision и блок при подтверждённом false).
- 7.20 (ADR-043): `card_allocator_soft_capacity_test.dart` (мягкая ёмкость не
  режет заказ: 40/32, 12/100, 20/200, свойства 1…500 и 10^6, «авто»),
  `output_batching_7_20_test.dart` (40/16 → 3 партии [16,16,8], 100/12 → 9
  партий [12×8,4], 200/20 → 10, 1/16 и 16/16 → 1 запрос, 17/16 → 2 партии,
  свойство «сумма = заказ, ни одна не больше вместимости» на сетке заказов и
  бюджетов, 512 партий = технический максимум), `card_order_plan_7_20_test.dart`
  (wholeDocument и fragmented обслуживают партии, число партий не выводится из
  числа частей, изменение `maxOutputTokens`/`reasoningReserveTokens`/
  `batchCardsCeiling` меняет партии, но не сумму; `materialCapacityBelowRequested`
  отдельно от `requestedAbovePlan`; `int.max` → `tooManyChunks` без зависания),
  `card_order_batches_flow_7_20_test.dart` (production: 3 партии и 40 карточек,
  предпросмотр == конвейер, `source_exhausted` останавливает очередь, сбой
  партии не теряет предыдущее, recovery без дублей, fragmented), 
  `order_batches_7_20_test.dart` (UI: «Запрошено: N карточек», «Подробнее» с
  числом карточек/максимумом партии/распределением/ёмкостью материала,
  предпросмотр показывает созданное количество и причину недобора).
- Ограничения: `journal/KNOWN_LIMITATIONS.md` L154–L163, L173–L185, L194–L196.


## 9. Характеристики моделей: что известно (7.18.1, 2026-11-21)

Полная сверка с официальной документацией и ссылками — ADR-039 §6a. Коротко
для планирования:

| Провайдер | API отдаёт | Источник в плане | Остаётся unknown/ручное |
|---|---|---|---|
| DeepSeek | окно (`context_window`, total), `max_output_tokens`, `input_modalities` | `providerApi` | отдельный вход, цены |
| Anthropic | `max_input_tokens`, `max_tokens`, `capabilities.image_input/pdf_input` | `providerApi` | единое окно, цены |
| Gemini | `inputTokenLimit`, `outputTokenLimit` | `providerApi` | цены, capabilities-флаги |
| OpenRouter | `context_length` (min с `top_provider`), `max_completion_tokens`, модальности, цены за токен | `providerApi` | стабильность upstream |
| OpenAI | только `id` | — (каталог/ручное) | все лимиты |
| Groq | `context_window` (список моделей) | `providerApi` | `max_completion_tokens` (только retrieve), цены |
| Moonshot | `context_length`, `supports_image_in`, `supports_reasoning` | `providerApi` | семантика окна, вывод |
| MiniMax | только `id` | — (каталог/ручное) | лимиты, цены |
| Ollama | `<arch>.context_length`, `capabilities.vision` | `providerApi` (контекст), семантика `unknown` | рабочий `num_ctx`, вывод |
| OpenAI-совместимый | только `id` | — (ручное) | все лимиты |

Каталог приложения (`provider_preset.dart`) даёт окно только там, где у модели
есть `sourceRef` и дата проверки; иначе это `assumption`. Ручные значения
(`userConfigured`) важнее API/каталога и сохраняются с датой проверки.
Нативный подсчёт входа выполняется один раз на план (Anthropic/Gemini), кэш —
по хэшу содержимого запроса; ошибка деградирует к консервативной оценке, а не
к исключению.
