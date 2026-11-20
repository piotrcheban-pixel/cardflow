# План итерации 7.18 — «Планирование генерации»

**База:** `main`, исходный HEAD `ab57f17`; после аудита — `2873957`
(`759ae31 docs: аудит итерации 7.18` + `2873957 docs: fix audit line references`).
**Задание:** `docs/prompts/iteration-7.18.md`. **Решения:** ADR-039, ADR-040.
**Протокол возобновления:** перечитать этот файл, `journal/STATE.md`,
`journal/iteration-7.18/audit.md` и `git log --oneline -20`; сверять галочки.

## Решения, принятые до кода (отличия от текста задания)

1. **Промпт — `gen-ru-v8`**, не v7: имя v7 уже занято ADR-037/L76
   (`system_prompt.dart:15,328–329`, `docs/prompts/gen-ru-v7.txt`, тесты
   `promptVersion`). v5–v7 сохраняются с байтовыми тестами. ADR-040 §7.
2. **`tokensPerCard = 300`** вместо 1024 (`generation_budget.dart:23`);
   обоснование — ADR-040 §2.
3. **D.1 заменяется формулами §3.4** задания; тесты бюджета/планировщика
   обновляются осознанно (контракт T1–T9, без ослабления).
4. **Поле количества** — существующее `generation-cards-count`; технический
   предел `int.max`, продуктового среза нет.
5. **`GenerationChunkPlanner.plan(...)` сохраняет публичный API**; внутри — три
   независимых решения (Input Planner → Card Allocator → Output Batch Planner).
   `GenerationPlan.chunks` = по одному на запрос (партию).
6. **`CapabilitySource`** приводится к
   `{userConfigured, providerApi, officialCatalog, assumption, unknown}` с
   чтением legacy wire-значений (ADR-039 §5); старые имена не остаются, тесты
   переименовываются механически.

## Контракт новых доменных API (для red-тестов)

```dart
// lib/domain/generation/sourced.dart
enum CapabilitySource { userConfigured, providerApi, officialCatalog, assumption, unknown }
final class Sourced<T> {
  const Sourced(this.value, {required this.source, this.observedAt, this.sourceRef});
  const Sourced.absent({this.sourceRef});
  final T? value; final CapabilitySource source;
  final DateTime? observedAt; final String? sourceRef;
  bool get isKnown;
}

// lib/domain/generation/model_limits.dart
enum ContextSemantics { totalInputPlusOutput, inputOnly, unknown }
final class ModelLimits { … Sourced-поля …, const ModelLimits.absent(); }
ModelLimits mergeModelLimits(List<ModelLimits> layersByPriority);
ModelLimits modelLimitsFromCapabilities(ModelCapabilities caps, {…});

// lib/domain/generation/generation_planning_config.dart
final class GenerationPlanningConfig {
  const GenerationPlanningConfig({tokensPerCard = 300, outputFill = 0.85,
    schemaOverheadTokens = 200, minBatchCards = 5, batchCardsCeiling = 40,
    estimateMargin = 0.10, exactMargin = 0.03,
    unknownContextMaterialTokens = 6000, unknownContextOutputTokens = 2048,
    defaultOutputTokens = 8192});
  int tokensFor(int cards);
  int cardsFor(int tokens);
  int desiredOutputTokens({required int? requestedCards, required int maxOutputTokens});
}

// lib/domain/generation/generation_request_budget.dart
enum InputAccuracy { exact, estimated }
final class RequestBudget {
  factory RequestBudget.compute({required ModelLimits limits,
    required int fixedTokens, required int materialTokens,
    required int desiredOutputTokens, required InputAccuracy accuracy,
    GenerationPlanningConfig config});
  int get inputTokens; int get maxTokens; int get outputCapTokens;
  int? get roomTokens; bool get contextExceeded; int get marginTokens;
}

// lib/domain/generation/input_planner.dart
enum InputStrategy { promptOnly, wholeDocument, fragmented }
final class InputSection { id, title, text, tokens, kind, shortId, images, unitIds, density? }
final class InputPart { index, sections, materialsText, tokens, bytes, outlineText }
final class InputPlan { strategy, parts, fixedTokens, materialTokens, inputTokens,
  maxTokens, accuracy, warnings, budget }
final class InputPlanner { InputPlan plan({sections, limits, fixedTokens,
  desiredOutputTokens, accuracy, config}); }   // без requestedCards

// lib/domain/generation/card_allocator.dart
enum SectionKind { content, service }
final class AllocationSection { id, title, weight, capacity, kind }
final class CardAllocation { planned: Map<String,int>, requested, achievable, belowRequested }
final class CardAllocator { CardAllocation allocate({sections, requestedCards}); }

// lib/domain/generation/output_batch_planner.dart
final class PlannedBatch { index, partIndex, partCount, focusSectionIds, limit }
final class OutputBatchPlanner {
  List<PlannedBatch> plan({input, allocation, maxTokensPerBatch, requestedCards});
}
```

## Чек-лист фаз

### Фаза 1 — ADR и red-тесты
- [x] ADR-039 (`docs/decisions/ADR-039-model-capability-provenance-discovery.md`)
- [x] ADR-040 (`docs/decisions/ADR-040-whole-document-first-planning.md`)
- [x] `plan.md` (этот файл)
- [x] red-тесты §5.1–5.3: `test/unit/domain/generation/generation_planning_test.dart`,
      `card_allocator_test.dart`, `planning_independence_test.dart`
- [x] скелеты API (компилируются, поведение не реализовано) → прогон,
      assertion-level вывод в `journal/iteration-7.18/red-output.md`
- [x] коммит `test:` (`f191375`)

### Фаза 2 — домен
- [x] `sourced.dart`, `model_limits.dart` (слияние по полям, миграция; коммит `04534ba`)
- [x] `generation_planning_config.dart` (формулы `tokensFor/cardsFor/desiredOutput`)
- [x] `generation_request_budget.dart` (P/D/m, total-inputOnly-unknown, байты)
- [x] `input_planner.dart` (whole-first, fragmented, оглавление, изображения по
      разделам, лимиты/дедуп изображений)
- [x] `card_allocator.dart` (density/weight/capacity, water-filling, min 1)
- [x] `output_batch_planner.dart` (focus, балансировка, лимиты ответа и image-частей)
- [x] `GenerationPlan`/`PlannedChunk` расширены (`inputStrategy`, части,
      распределение, `focusSectionIds`, `partIndex/Count`)
- [x] `GenerationChunkPlanner` внутри вызывает три планировщика; prompt-only —
      через `allowPromptOnly` того же интерфейса
- [x] домен без Flutter, тесты §5.1–5.3 зелёные; полный прогон
      **2198 passed + 16 skipped**
- [x] старые тесты D.5/мягкой цели заменены контрактными:
      `generation_chunk_planner_test.dart` (20), новый
      `generation_plan_batches_test.dart` (14) вместо `generation_plan_merge_test.dart`
- [ ] коммит `feat(domain): …` (следующий шаг)

### Фаза 3 — discovery и кэш
- [x] порт `ModelCapabilityDiscovery` (domain), резолверы
      `lib/api/models/model_discovery.dart` (OpenAI-compatible/DeepSeek/
      OpenRouter/Groq/Moonshot, Anthropic, Gemini, Ollama, generic)
- [x] проверка документации провайдеров (web_fetch, URL+дата) → ADR-039 §6
- [x] фикстуры `test/fixtures/discovery/<provider>/*.json` (успех, пагинация,
      неверные поля, пустой список; 401/таймаут — статусом в тесте)
- [x] кэш `generation.model_capabilities` v1 (TTL 7 дней, `lastErrorCode`,
      инвалидация по аккаунту/baseUrl/modelId, без ключей/хэшей)
- [x] миграция legacy (`userConfigured`/`officialCatalog`/`assumption`),
      `inferred` Vision → `assumption`; явный флаг `vision_configured`
- [x] нативный count_tokens (Anthropic/Gemini) + `exactInputTokens` в
      `InputPlanner`/`RequestBudget`; оставшееся подключение к конвейеру — фаза 5
- [x] коммит `feat(generation): …` (следующий шаг)

### Фаза 4 — `gen-ru-v8`
- [ ] `lib/api/prompts/system_prompt.dart`: `systemPromptGenRuV8` +
      `systemPromptVersion = 'gen-ru-v8'` (v5–v7 в коде не меняются)
- [ ] `docs/prompts/gen-ru-v8.txt` + тест байт-в-байт; тесты `promptVersion` → v8
- [ ] сборщик сообщения: префикс `<materials>/<images>/<outline>/<wishes>` +
      хвост `<task>`; байтовый тест одинакового префикса
- [ ] схема: `source_exhausted`, `section_id`, strict `required`; проекции
      OpenAI/Gemini/Anthropic; терпимый разбор v5–v8
- [ ] Anthropic `cache_control: ephemeral` после проверки документации
- [ ] `docs/system-prompt.md`, `docs/api-schema.md`
- [ ] коммит `feat(generation): …`

### Фаза 5 — конвейер
- [ ] выполнение плана: партии, `focus`, `<part>`, `<already_created>`
- [ ] покрытие `planned/generated/accepted`; `source_exhausted`/недобор < 50 %
      → отмена партий; однократное перераспределение
- [ ] дедуп: `content_hash` + триграммы ≥ 0.85
- [ ] восстановление: truncated → половина карточек; 413/распознанный 400 →
      переплан ×0.8; ≤3 на запрос, ≤max(3, M/2) на запуск
- [ ] калибровка `generation.calibration` v1 (EMA, ≥2 замеров)
- [ ] `generation_jobs`: `chunk_count` = части входа, `tokens_used` = факт
- [ ] интеграционный тест на production-проводке (`app_providers`) с fake-транспортом
- [ ] коммит(ы) `feat(generation): …`

### Фаза 6 — UI и ARB
- [ ] карточка «План генерации» (строки §3.10) + «Подробнее»
- [ ] настройки модели: источники/дата, ручной ввод, «Обновить характеристики»,
      «Сбросить к автоматическому»
- [ ] итог после генерации: запрошено/создано/недобор/разделы без карточек
- [ ] новые ARB-ключи (ru), widget-тесты (`scrollUntilVisible`)
- [ ] коммит `feat(ui): …`

### Фаза 7 — ревью, ворота, документация, push, CI
- [ ] снимок → `journal/iteration-7.18/review.md` по чек-листу §11 (15 пунктов)
- [ ] fix-коммиты с регрессионными тестами на каждый high/medium
- [ ] ворота §6 → `journal/iteration-7.18/verify.md`
- [ ] `docs/generation-planning.md`, `docs/system-prompt.md`, `docs/api-schema.md`,
      `AGENTS.md`, `KNOWN_LIMITATIONS.md`, `journal/STATE.md`
- [ ] `journal/iteration-7.18/summary.md`
- [ ] push всех коммитов, один прогон CI (9/9)

## Правила

- Тесты — только `fvm flutter test --no-pub …`; analyze — `--no-pub` (иначе
  зависание на `pub get --example`, L64).
- Живые API-запросы запрещены; discovery и подсчёт токенов — mock/фикстуры.
- Схема БД и `schemaVersion` не меняются; новые данные — JSON v1 в `app_settings`.
- SPEC.md не редактируется; расхождения — ADR.
- Тесты не ослабляются; на каждый зелёный шаг — отдельный коммит.
