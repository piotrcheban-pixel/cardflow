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

## 5. Card Allocator (ADR-040 §3.3)

`SectionFeatures.of`: число слов, фактов, формул, определений, вопросов,
изображений → плотность и вес. Ёмкость раздела — от токенов, плотности и
веса; распределение — water-filling до ёмкости, недостижимый избыток
распределяется largest remainder. Сумма `achievableCards` ≤ достижимого
материала; заказ выше — `requestedAbovePlan`, а не «срез».

## 6. Output Batch Planner и сообщение (ADR-040 §7)

- Партии: `cardsPerBatch = min(batchCardsCeiling, cardsFor(maxTokens),
  maxCardsPerRequest)`; `<= maxCardsPerRequest` всегда.
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
  одной дополнительной партией по разделам с оставшейся ёмкостью.
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
  `model_limits_resolver_test.dart`, `drift_model_capability_cache_test.dart`,
  `request_token_counter_test.dart`, `drift_token_calibration_store_test.dart`.
- Ограничения: `journal/KNOWN_LIMITATIONS.md` L154–L161.
