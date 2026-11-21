# Итерация 7.18.2 — финальный аудит 7.18 (2026-11-21)

**Задача:** заключительный технический аудит соответствия
`docs/prompts/iteration-7.18.md` без новой архитектуры: каталог изображений в
token accounting (§3.4), реальные байты HTTP (§3.4/T5), полнота discovery
(§3.3), настройки поддержки изображений (§3.10) и проверка архитектуры (§3.4,
§3.5), затем ворота §6 и финальный CI.

**Старт:** `git status --porcelain` → пусто; `HEAD = origin/main = 170a413`;
baseline **2302 passed + 16 skipped**, `analyze` 0. Красная фаза — 15 красных
assertions (`red-7.18.2.md`).

## Находки и коммиты (каждая — отдельным fix-коммитом с регрессионным тестом)

| # | Находка | Коммит |
|---|---|---|
| F1 (high) | Текст каталога `<images>` не входил в `D`/`P`: `materialTokens`/`inputTokens` занижены, `GenerationEstimate.catalogTokens = 0` | `b9b294a` `fix(generation): токены каталога изображений входят в D бюджета (§3.4)` |
| F2 (high) | `count_tokens` считает только текст, а конвейер подставлял его как весь вход → стоимость изображений = 0 | `fe47d5a` `fix(generation): exact-подсчёт не обнуляет стоимость изображений (§3.4)` |
| F3 (high) | `requestBytes` плана без обвязки протокола (промпт/схема/JSON-ключи, +29 КБ) и без проверки фактического тела: 34,7 МБ уходили при лимите 20 МБ | `eb616f8` `fix(generation): requestBytes плана и проверка фактического payload (§3.4, T5)` |
| F4 (medium) | `isReasoningModel` терялся в проекции и не влиял на `max_tokens`: партия карточек обрезалась рассуждением | `76b93e7` `fix(generation): резерв на рассуждение reasoning-модели (§3.4)` |
| F5 (medium) | UI не показывал `supportsImageInput` (источник/дата), допущение не отличалось; `copyWith` терял `visionConfigured` → явный Vision пользователя перекрывался каталогом | `55747b5` `fix(ui): вход изображений с источником, датой и отличием допущения (§3.10)` |
| — | «Подробнее»: каталог и резерв рассуждения видны в деталях плана (§3.4) | `257409b` |
| — | формат/неиспользуемый импорт | `4642bf1` |

## 1. Каталог изображений в token accounting — подтверждение

- `ImageRef.catalogTokens` и `InputImage.catalogTokens` считаются **той же**
  строкой `imageCatalogLine`, что уходит в `<images>` (`GenerationPlanBuilder`
  → `_catalogLineTokens`), и входят в:
  - `InputPart.catalogTokens`/`totalMaterialTokens` (whole, fragmented,
    attachments-only);
  - `InputPlan.materialTokens`, `InputPlan.catalogTokens`, бюджет части
    (`RequestBudget.materialTokens`) → `inputTokens = ceil((P + D) × (1 + m))`;
  - `GenerationEstimate.catalogTokens`, `BudgetTrace.catalogTokens`;
  - «Подробнее» (`plan-detail-catalog`).
- Каталог входит **в `D`**, а не в `P`: это текст пользовательского сообщения
  части (у каждой части — каталог её изображений, включая оставшиеся
  «только каталогом»).
- Exact-режим: `count_tokens` уже посчитал каталог (он в `userContent`),
  поэтому значение не пересчитывается, но показывается в «Подробнее».
- Неизвестная стоимость изображений не равна нулю: `estimateImage` даёт
  консервативную оценку (`256 Б/токен` или `750 px/токен`), помеченную
  `isAssumption`, и в запросе — `assumptions: image_tokens` (L175).

Тесты: `test/unit/api/generation/image_catalog_budget_test.dart` — 6:
без изображений; одно; несколько (сумма); длинные подписи/контекст (рост `D`
равен росту каталога); exact-режим; fragmented (каталог по частям) +
сверка `materialTokens` с составом частей и `inputTokens` с формулой.

## 2. Реальные байты HTTP-запроса — подтверждение

- `serializedRequestBytes(ProviderRequest)` = `utf8(jsonEncode(body)).length` —
  **единственная** мера размера; включает system prompt, user content, схему
  ответа (`response_format`/`tools`), каталог, base64 вложений, ключи JSON и
  протокольную обвязку по построению.
- План: `GenerationOverheadTokens.fixedBytes` (промпт + `jsonEncode(schema)` +
  обёртка) входит в байты `InputPlan` и `PlannedChunk.bodyBytes`, поэтому
  `requestBytes` плана перестал занижаться (проверка: оценка 110 379 Б против
  фактических 110 290 Б на тестовом запросе).
- Сервис проверяет **фактические** байты после `adapter.buildRequest` и до
  отправки: превышение `maxRequestBytes` → `GenerationException(payloadTooLarge)`
  (в debug-details — оба числа), запрос не уходит; `GenerationResult.requestBytes`
  несёт измерение.
- T5: 13 МБ + 13 МБ при лимите 20 МБ — на уровне плана одна картинка
  `sentToModel`, вторая `omittedPayload` + `payloadLimited` (T5 в
  `generation_planning_test.dart`); на уровне HTTP одна часть уходит
  (17,4 МБ ≤ 20 МБ, `sentDocumentImageIds = [img1]`), две — `payloadTooLarge`
  без отправки. Ни одна картинка не пропадает молча.
- Протокол-независимость: тот же механизм проверен для OpenAI-совместимого
  (`image_url` data URI) и Anthropic (`image.source.base64` + `system`).

Тесты: `test/unit/api/generation/generation_payload_bytes_test.dart` — 7.

## 3. Discovery провайдеров — таблица

Полная таблица с источниками, датой, фикстурами и ручными полями —
`journal/iteration-7.18/discovery-7.18.2.md`. Кратко:

| Провайдер | Discovery | Извлекается | unknown |
|---|---|---|---|
| DeepSeek | `GET {base}/models`, `documented` | id, `context_window` (total), `max_output_tokens`, `input_modalities` | отдельный вход, цены, tokenizer |
| Anthropic | `/v1/models` + пагинация | id, `max_input_tokens` (окно+вход), `max_tokens`, `capabilities.image_input/pdf_input` | единое окно, цены |
| Gemini | `v1beta/models` + `pageToken` | id, `inputTokenLimit`, `outputTokenLimit`, методы | цены, capabilities-флаги |
| OpenRouter | `documented`, `pricingIsPerToken` | min(`context_length`,`top_provider`), max output, модальности, цены | стабильность upstream |
| OpenAI | `idsOnly` | только id | все лимиты |
| Groq | `documented`, семантика `unknown` | id, `context_window`, `max_completion_tokens` | семантика окна, вход, цены |
| Moonshot | `documented`, семантика `unknown` | id, `context_length`, `supports_image_in`, `supports_reasoning` | семантика окна, вывод, цены |
| MiniMax | `idsOnly` | только id | лимиты, цены, capabilities |
| Ollama | `/api/tags` + `/api/show` | список, `<arch>.context_length`, `capabilities` | семантика окна (`num_ctx`), вывод, цены |
| OpenAI-совместимый | `idsOnly` | только id | все лимиты |

Ошибки: 14 тестов `model_discovery_errors_test.dart` — 401/403, таймаут,
пустой список, неверный тип, отсутствующее поле, не-объект — по всем четырём
резолверам; зелёные **до** правок (дефекта не было). Кэш не стирает последнее
удачное значение, TTL 7 дней, инвалидация по `baseUrl`/`modelId`/ключу.

## 4. supportsImageInput — результаты проверки

- Источник: `Sourced<bool>` из `resolveModelLimits` (`userConfigured` >
  `providerApi` > `officialCatalog` > `assumption` > `unknown`), дата —
  `observedAt` (discovery или дата ручного сохранения).
- UI (блок «Характеристики модели»): строка «Вход изображений»
  (`capability-image-input`) со значением («поддерживается» / «не
  поддерживается» / «неизвестно»), источником и датой; `unknown` не выдаётся
  за поддержку; допущение — курсив + «допущение приложения».
- Сброс (`withAutomaticCapabilities`) сохраняет явно заданный Vision; ручной
  ввод контекста/входа/выхода не затрагивает другие настройки аккаунта.
- Найден и исправлен дефект: `ProviderAccount.copyWith` не переносил
  `visionConfigured`, поэтому копия аккаунта (экран генерации) теряла
  пользовательский источник и каталог перекрывал Vision; `_requestAccount`
  теперь уважает `visionConfigured`.
- Тесты: `model_capability_section_test.dart` (+3 новых: значение/источник/дата,
  unknown, допущение курсивом), `generation_screen_test.dart` (+1: явный Vision
  разрешает запуск), `model_capability_settings_test.dart` (+1: `copyWith` и
  приоритет `userConfigured`), существующий тест сброса.

## 5. reasoning reserve — результаты проверки

- `isReasoningModel` из discovery (`supports_reasoning` у Moonshot, кэш
  `generation.model_capabilities`) доезжает до планировщика
  (`ModelCapabilities.isReasoningModel` ↔ `ModelLimits.isReasoningModel`).
- `GenerationPlanningConfig.reasoningReserveTokens = 2048` (допущение):
  `desiredOutput = min(outputCap, tokensFor(cards) + резерв)`,
  `wholeCapable` проверяет `maxTokens ≥ tokensFor(minBatchCards) + резерв`,
  `R` части включает резерв, `OutputBatchPlanner.cardsPerBatch` считает
  карточки от `maxTokens − резерв`.
- Калибровка (`generationPlanBuilderFor(calibration)`) ставит резерв 0: факт
  `completion_tokens / принятые карточки` уже включает рассуждение.
- Прозрачность: `GenerationPlan.reasoningReserveTokens` + строка
  «Резерв на рассуждение» в «Подробнее».
- Тесты: `reasoning_reserve_test.dart` — 5 (признак и источник; ёмкость партии
  20 → 10 карточек при 2 партиях; желаемый вывод 4048; отсутствие регрессии у
  обычной модели; снятие резерва калибровкой).

## 6. Архитектурная проверка (§5)

| Пункт | Результат | Чем подтверждено |
|---|---|---|
| reasoning reserve | **был дефект**, исправлен (см. §5) | `reasoning_reserve_test.dart` |
| единый `GenerationPlan` во всех режимах | да: `buildRunPlan` (материалы и prompt-only) — единственная точка | `prompt_only_unified_test.dart`, `generation_plan_entry.dart` |
| одинаковый сборщик предпросмотра и production | да: `_currentPlanPreview` → `buildRunPlan`; конвейер → `_buildPlan` с тем же builder’ом и `GenerationPlanBuilder` | `generation_screen_test.dart` («лимиты из кэша discovery»), `generation_pipeline_v8_test.dart` |
| кэш нативного подсчёта по содержимому | да: `exactTokenCacheKey` = sha256(account+protocol+baseUrl+model+system+userContent); хранит и ошибки; ключи не попадают | `generation_exact_tokens_test.dart` («повторный запуск — кэш без сети») |
| независимость Input Planner от числа карточек | да: в `InputPlanner.plan` нет `requestedCards`; `R` не зависит от заказа | `planning_independence_test.dart`, T4 |
| нет повторного вычитания лимита выхода | да: `inputOnly` — `inputTokens ≤ context` без вычитания `maxTokens`; total — `room = context − input` один раз | T3/T7/T9 в `generation_planning_test.dart` |
| частичный результат после recovery | да: принятые карточки сохраняются, повтор досылает упавшие части | `generation_overflow_replan_test.dart` (6), `generation_recovery_http_test.dart` |

## 7. Новые тесты (итого +38)

- `test/unit/api/generation/image_catalog_budget_test.dart` — 6 (F1).
- `test/unit/api/generation/generation_payload_bytes_test.dart` — 7 (F3/T5,
  включая Anthropic).
- `test/unit/domain/generation/reasoning_reserve_test.dart` — 5 (F4).
- `test/integration/generation_exact_tokens_test.dart` +1 (F2).
- `test/unit/api/models/model_discovery_errors_test.dart` — 14 (аудит §3.3).
- `test/widget/settings/model_capability_section_test.dart` +3, изменён 1
  (F5; счётчик «неизвестно» 2 → 3).
- `test/widget/generation/generation_screen_test.dart` +1 (F5).
- `test/unit/domain/generation/model_capability_settings_test.dart` +1 (F5).
- `test/widget/generation/generation_plan_details_test.dart` +1 проверка
  (каталог в «Подробнее»).

Итог полного набора: **2302 + 16 skipped** (baseline) → **2340 + 16 skipped**
(финальный прогон).

## 8. Ворота §6

`journal/iteration-7.18/verify-7.18.2.md`: `gen-l10n` ок; `format` 546/0;
`analyze` 0; полный набор **2340 passed + 16 skipped + 0 failed**; покрытие
**92,0 % (19581/21286)**; Windows Release — `cardflow.exe` (69,6 с); Windows
smoke — `All tests passed!` (11 с). Живых API-запросов нет.

## 9. Итог

- Схема БД/`schemaVersion` и `format_version` не менялись; `SPEC.md` не
  редактировался.
- Ограничения: L174–L178 (см. `journal/KNOWN_LIMITATIONS.md`), L173 снят.
- Итерация считается завершённой только после push и зелёного CI: см.
  `journal/STATE.md` (финальный HEAD, run id, 9/9 job).
