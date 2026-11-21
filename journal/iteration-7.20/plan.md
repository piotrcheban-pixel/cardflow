# План 7.20 — произвольный заказ карточек и партии вывода

**Дата:** 2026-11-21 · **Ветка:** `main` · **Старт:** `HEAD = 0d3c35b`.
Аудит — `journal/iteration-7.20/audit.md`. Живых API-запросов нет.

## Инварианты итерации

1. Заказ пользователя (`requestedCards`) — **не потолок** и не оценка: он
   сохраняется целиком до тех пор, пока план технически выполним.
2. Выходной бюджет модели ограничивает **одну партию**, не сумму.
3. Мягкая ёмкость материала (эвристика `words/40 × density`) — **отдельный**
   статус «материала хватает примерно на M карточек из N»; она не режет заказ и
   не выдаётся за бюджет модели.
4. Партии исполняются последовательно; уже созданные карточки не теряются;
   `source_exhausted` останавливает ненужные запросы; недостача один раз
   перераспределяется.
5. Никакой тихой обрезки и изменения значения поля.

## Шаги (каждый — отдельный коммит)

| # | Шаг | Состав |
|---|---|---|
| 1 | audit | `journal/iteration-7.20/{audit,plan}.md` |
| 2 | red | assertion-level тесты: allocator, batch planner, план (materials), pipeline, UI |
| 3 | green: Card Allocator | мягкая ёмкость → предпочтение; `estimatedCapacity`, `materialLimited`; сумма = заказ |
| 4 | green: Output Batch Planner | `batchCount`/`batchSizes` (жадно: полные партии + остаток), guard `maxBatches`, точный резерв оценки |
| 5 | green: план/предупреждения | `PlanWarningCode.materialCapacityBelowRequested`; `requestedAbovePlan` — только «нет содержательных разделов»; новые геттеры плана |
| 6 | green: pipeline | `_topUpChunk` ≤ вместимости партии; сохранение/перераспределение без изменений |
| 7 | green: UI | «Запрошено: N карточек», «Подробнее» (всего/максимум в партии/распределение/стратегия/ёмкость), предпросмотр: фактически создано + причина недобора |
| 8 | review | независимое ревью снимка (L35), findings — fix-коммит с тестами |
| 9 | verify | `gen-l10n`, `dart format`, `analyze`, полный набор, `--coverage` ≥ 80 %, `build windows --release`, Windows smoke |
| 10 | remember | `journal/iteration-7.20/{summary,verify,review}.md`, ADR-043, `docs/generation-planning.md`, `KNOWN_LIMITATIONS` L194–L196, `STATE.md` |
| 11 | push + CI | один прогон после всех коммитов, результат 9/9 в журнале |

## Контракты (целевые)

### `CardAllocator`

```
allocate(sections, requestedCards):
  null (авто) → planned[s] = effectiveCapacity(s); achievable = Σ; capacity = Σ
  explicit    → planned = water-filling(min(requested, Σcapacity))  // как было
                + остаток (requested − Σplanned) по весам (точная целочисленная
                  раздача наибольших остатков), сумма = requested
  estimatedCapacity = Σ soft capacity (null, если есть раздел без предела)
  materialLimited   = requested != null && estimatedCapacity != null &&
                      requested > estimatedCapacity
  belowRequested    = planned sum < requested  (теперь только «нет содержательных
                      разделов»)
```

### `OutputBatchPlanner`

```
cardsPerBatch = min(batchCardsCeiling, cardsFor(maxTokens − reasoningReserve),
                    maxCardsPerRequest)  ≥ 1
batchCount(total) = total ~/ perBatch + (total % perBatch == 0 ? 0 : 1)
batchSizes(total) = [perBatch × (count − 1), total − perBatch × (count − 1)]
```

Сумма партий = total; ни одна партия не превышает `cardsPerBatch`; лишний
запрос не создаётся. В fragmented партии строятся внутри частей, но их число не
выводится из числа частей.

### Предупреждения

| Код | Когда | Текст |
|---|---|---|
| `materialCapacityBelowRequested` | заказ больше мягкой ёмкости материала | «Материала хватает примерно на {capacity} карточек из {requested}. Заказ сохранён: если материал закончится, оставшиеся партии будут остановлены, а не выдуманы.» |
| `requestedAbovePlan` | заказ невыполним (нет содержательных разделов) | «Запрошено {requested} карточек, план может выдать {achievable}: в материалах нет содержательных разделов…» |

## Тесты (обязательные, red до реализации)

Параметры: заказы 1, 5, 10, 20, 40, 50, 100, 200, 500, максимально допустимый
(`maxChunks × cardsPerBatch`); вместимости 3, 4, 7, 12, 16, 20, 22, 40.

1–6: 40/16 → 3 партии [16,16,8]; 100/12 → 9 партий (12×8+4); 200/20 → 10;
1/16 → 1; 16/16 → 1; 17/16 → 2.
7–9: изменение `maxOutputTokens`/`reasoningReserveTokens`/`batchCardsCeiling`
меняет число партий, но не сумму.
10: изменение `requestedCards` меняет партии и распределение, части входа — те же.
11–13: whole и fragmented обслуживают несколько партий; сумма = заказ; число
партий не выводится из числа частей.
14: предпросмотр и production дают одинаковое число партий.
15: карточки предыдущих партий не теряются.
16: recovery не создаёт дублей партий/карточек.
17: `source_exhausted` останавливает последующие запросы.
18: нехватка материала — отдельный статус, не «бюджет модели».
Плюс UI: «Запрошено: 40 карточек», «Подробнее» с распределением, отсутствие
ложного сообщения о бюджете модели.
