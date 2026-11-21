# Аудит 7.20 — заказ карточек не ограничен бюджетом одного ответа

**Дата:** 2026-11-21 · **Ветка:** `main` · **Старт:** `git status --porcelain` → пусто,
`HEAD = origin/main = 0d3c35b` (журнальный коммит 7.19).
**Живых API-запросов нет** (запрет задания). Все выводы — по коду и прогонам
локальных тестов/зондов на `GenerationPlanBuilder` (без сети).

## 0. Что именно наблюдал владелец

> «Запрошено 40 карточек, план может выдать 32: бюджета модели не хватает на
> весь заказ».

Это строка ARB `generationPlanRequestedAboveAchievable`
(`lib/l10n/app_ru.arb:1285`), которую показывает
`lib/ui/generation/plan_warning_message.dart:30` для
`PlanWarningCode.requestedAbovePlan`. Код ставится в
`lib/domain/generation/generation_chunk_planner.dart:404`
(`if (allocation.belowRequested)`) — то есть **всегда**, когда
`CardAllocation.achievable < requestedCards`.

## 1. Цепочка «поле количества → план»

| # | Участок | Файл:строка | Что делает | Вердикт |
|---|---|---|---|---|
| 1 | Числовое поле | `generation_screen.dart:1199-1214`, `_requestedCards` `:293-302` | парсит `BigInt`, отдаёт `int`, ограничение только `int.max` | ок: значение не режется |
| 2 | `GenerationRunRequest.requestedCards` | `generation_run.dart:30-33,57` | хранит заказ без клампа | ок |
| 3 | Единая точка плана | `generation_plan_entry.dart:35-64` | `request.requestedCards ?? requestedCardCount(wishes)` | ок |
| 4 | Сборщик | `generation_plan_builder.dart:194-204` | передаёт заказ в планировщик | ок |
| 5 | **Распределение** | `card_allocator.dart:350-360` | `totalCapacity = Σ capacity`; **`target = min(requested, totalCapacity)`** | **ПЕРВОПРИЧИНА** |
| 6 | Партии | `output_batch_planner.dart:70-142` | `perBatch = min(ceiling, cardsFor(maxTokens))`, `count = ceil(total/perBatch)` | по бюджету одного ответа — верно |
| 7 | Заголовок плана | `generation_chunk_planner.dart:402-425` | `requestedAbovePlan`, если `allocation.belowRequested` | верно по коду, **неверно по смыслу** |
| 8 | Сообщение | `plan_warning_message.dart:30-34` → ARB `:1285` | «бюджета модели не хватает на весь заказ» | **ложная причина** |

## 2. Точка, где 40 превращается в 32

`lib/domain/generation/card_allocator.dart:354-360`:

```dart
final int totalCapacity = unlimited ? requested : items.fold<int>(0, (sum, s) => sum + s.capacity!);
final int target = math.min(requested, totalCapacity);   // ← ЗДЕСЬ
```

`capacity` — **мягкая** ёмкость раздела
(`SectionFeatures.of`: `capacity = ceil(meaningfulWords / 40 × density)`,
`card_allocator.dart:53`), в документации прямо названа мягкой
(`card_allocator.dart:72-73`, ADR-040 §5). Но `allocate` использует её как
**жёсткий потолок суммы**: `target = min(requested, Σ capacity)`, а разница
попадает в `belowRequested` → `requestedAbovePlan` → сообщение про «бюджет
модели». Для материала, у которого эвристика насчитала 32, заказ 40
превращается в «план может выдать 32».

Проверено зондом (`test/scratch_7_20_probe_test.dart`, локально, без сети):

```
sections=1 chars=6400 out=8192 req=40  → alloc=8  achievable=8  warnings=[requestedAbovePlan]
sections=8 chars=800  out=8192 req=40  → alloc=16 achievable=16 warnings=[requestedAbovePlan]
sections=8 chars=800  out=2000 req=40  → alloc=16 achievable=16 warnings=[requestedAbovePlan]
sections=8 chars=800  out=64000 req=40 → alloc=16 achievable=16 warnings=[requestedAbovePlan]
sections=8 chars=800  out=8192 req=100 → alloc=16 achievable=16 warnings=[requestedAbovePlan]
sections=20 …         req=100          → alloc=80 achievable=80 warnings=[requestedAbovePlan]
```

Главное в этом выводе: **`achievable` не зависит от `maxOutputTokens`** и
меняется только от объёма материала. То есть заказ обрезает Card Allocator, а
UI объясняет обрезку бюджетом выхода модели.

Второй зонд (`test/scratch_7_20_probe2_test.dart`) показывает, что при
`maxOutputTokens = 8192` и reasoning-резерве 2048 (`GenerationPlanningConfig`:
`cardsFor(8192 − 2048) = 16`) каждая партия вмещает ровно **16** карточек —
отсюда «40 / 16» из задания и «32 = 2 × 16» у владельца, если ёмкость
материала округлилась к 32.

## 3. Ответы на проверки задания

| Проверка | Ответ |
|---|---|
| где вычисляется `achievable` | `CardAllocation.achievable` = сумма `planned` (`card_allocator.dart:427`), в план попадает как `GenerationPlan.plannedCards/achievableCards` (`generation_plan.dart:772-785`) |
| где вызывается `cardsFor(maxTokens)` | `output_batch_planner.dart:155` (партия), `generation_chunk_planner.dart:366` (`_syntheticAllocation` — **только** режим «авто» без разделов), `:1051` (`_batchesWithoutSections`), `generation_planning_config.dart:147-163` (желаемый вывод) |
| где используется `maxOutputTokens` | `GenerationPlanningConfig.outputCapFor → desiredOutputTokens`; `RequestBudget.compute` ограничивает `maxTokens`; `OutputBatchPlanner.cardsPerBatch` — размер одной партии |
| где учитывается `batchCardsCeiling` | `cardsPerBatch` (`output_batch_planner.dart:156`) — потолок **партии**; `desiredOutputTokens` (`generation_planning_config.dart:154-162`) — резерв запроса. **Сумму заказа не ограничивает** |
| `cardsPerBatch` как максимальное общее количество? | Нет. `count = ceil(total / perBatch)`; сумма `sizes == total` (проверено свойством `_balanced`) |
| обрезается ли `requestedCards` перед `GenerationPipeline`? | Нет: ни в `GenerationRunRequest`, ни в `buildRunPlan`, ни в `GenerationPlanBuilder` |
| ограничивает ли `CardAllocator` заказ бюджетом одного ответа? | Прямого `maxOutputTokens` в нём нет, но **мягкая ёмкость используется как жёсткий потолок суммы** — это и есть «заказ ограничен оценкой, а не достижимостью». Ошибка класса «ограничение планировщика выдано за бюджет модели» |
| смешаны ли `maxInputTokens` и `maxOutputTokens`? | Нет: `RequestBudget` читает `limits.maxInputTokens` только как лимит входа (`:135,171`), `maxOutputTokens` — как потолок вывода (`:137,142-151`). Разделение проверено тестами 7.18 |
| старый расчёт в preview? | Нет: предпросмотр и конвейер строят один `GenerationPlan` (`generation_plan_entry.dart`, §0.11), `generation_screen.dart:394-406` |
| теряются ли партии при fragmented? | Нет: `_totalFor(part)` суммируется по всем частям, `_balancedSizes` сохраняет сумму; проверено зондом (`req=100 → batches=21, sum=100`) |

## 4. Прочие находки, влияющие на заявку

| # | Находка | Где | Влияние |
|---|---|---|---|
| F1 (high) | Мягкая ёмкость материала работает как жёсткий потолок заказа; `belowRequested` смешивает «материала мало» и «план невыполним» | `card_allocator.dart:354-360,432` | 40 → 32/16/8, сообщение про бюджет модели |
| F2 (high) | Сообщение ARB приписывает недобор бюджету вывода модели и советует менять модель — при том что материал не при чём | `app_ru.arb:1285` | ложная причина, ложный совет |
| F3 (high) | Нет отдельного статуса/предупреждения «материала хватает примерно на M карточек из N» | `generation_plan.dart:184-219` (`PlanWarningCode`), `plan_warning_message.dart` | требование §2 и §4 не выполнено |
| F4 (medium) | `_syntheticAllocation` (план без разделов: вложения/сканы) берёт «авто»-заказ из `cardsFor(maxTokens)` — то есть из бюджета **одного** ответа; при явном заказе это не применяется, но при «авто» итог зависит от бюджета одного запроса, а не от партий | `generation_chunk_planner.dart:363-367, 1026-1038` | «авто» на скане ограничен одной партией |
| F5 (medium) | Резерв вывода в оценке считается из **суммы** лимитов, зажатой `batchCardsCeiling`, и умножается на число запросов: `tokensFor(min(ceiling, Σlimits)) × requests` | `generation_chunk_planner.dart:1146-1154, 1178` | «Оценка токенов» при большом заказе завышена в разы (например, 500 карточек) |
| F6 (medium) | Нет технического предохранителя на число **партий** для материалового плана (`maxChunks` проверяется только для частей и для prompt-only) | `generation_chunk_planner.dart:324-332, 281-291` | после снятия потолка F1 заказ `int.max` даёт ~4·10¹⁷ партий — зависание/OOM вместо явного `tooManyChunks` |
| F7 (low) | `_topUpChunk` зажимает перераспределённую недостачу в 40 карточек независимо от вместимости партии | `generation_pipeline.dart:1924` | может попросить больше, чем вмещает бюджет ответа |
| F8 (low) | UI предпросмотра не показывает ни фактически созданное количество при исчерпании материала, ни причину недобора (`shortfallCards`/`exhaustedSectionIds` не используются) | `generation_preview_screen.dart:465-513` | требование §5 «показывать фактически созданное и объяснять причину» не выполнено |
| F9 (low) | «Подробнее» не показывает ни общего количества карточек плана, ни максимума в партии, ни распределения по партиям, ни ёмкости материала | `generation_plan_details.dart:105-119` | требование §4 не выполнено |

## 5. Целевая архитектура (три независимых решения)

1. **Input Planner** — только `wholeDocument`/`fragmented`/число частей по
   бюджету входа и резерву `R`. Заказ карточек в интерфейсе отсутствует
   (`input_planner.dart` — `requestedCards` не принимает). Не меняется.
2. **Card Allocator** — распределение **всего** заказа по содержательным
   разделам. Мягкая ёмкость — предпочтение при распределении, а не потолок
   суммы. Отдельно отдаёт оценку ёмкости материала (`estimatedCapacity`) и
   признак `materialLimited`, которые UI показывает **отдельным** статусом.
3. **Output Batch Planner** — `cardsPerBatch = min(batchCardsCeiling,
   cardsFor(maxTokens − reasoningReserve))`, `batchCount =
   ceil(totalPlanned / cardsPerBatch)`. Партии не ограничивают сумму.

## 6. Что нельзя ломать

- `source_exhausted` и однократное перераспределение недостачи (ADR-040 §8).
- `quantity` (заказ) не подменяется: нет тихой обрезки, нет изменения
  пользовательского значения.
- Партии исполняются последовательно; уже полученные карточки не теряются;
  recovery не создаёт дублей.
- Живых API-запросов нет.
