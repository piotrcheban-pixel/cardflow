# Red-фаза итерации 7.18 — тесты планирования (§5.1–5.3)

**Команда:**
```
fvm flutter test --no-pub test/unit/domain/generation/generation_planning_test.dart \
  test/unit/domain/generation/card_allocator_test.dart \
  test/unit/domain/generation/planning_independence_test.dart
```

**Итог:** `00:00 +1 -26: Some tests failed.` — 1 зелёный (пустой список разделов),
26 красных; падения **уровня assertion** (не компиляции): API-скелет стоит,
поведение не реализовано. Полный вывод — `red-raw.log`.

## Почему это красная фаза, а не ошибка компиляции

Новые доменные классы (`Sourced`, `ModelLimits`, `GenerationPlanningConfig`,
`RequestBudget`, `InputPlanner`, `CardAllocator`, `OutputBatchPlanner`) существуют
с контрактом из ADR-040/plan.md и собираются; методы-заглушки возвращают
нереализованные значения. Каждый тест падает на `expect` с ожидаемым и
фактическим значением.

## Представительные падения (ожидалось → получено)

| Тест | Ожидалось | Получено |
|---|---|---|
| T1: total 128000/out 8192, D=40000, 10 карточек | `InputStrategy.wholeDocument` | `InputStrategy.fragmented` |
| T2: 50 карточек | `wholeDocument`, `tokensFor`=8192 | `fragmented` |
| T3: inputOnly, 100 карточек | `wholeDocument` | `fragmented` |
| T4: D=300000 | `partCount` 3, `Dmax` 104416 | 1 часть, 0 |
| T5: 2 картинки по 13 МБ при лимите 20 МБ | 1 `sentToModel`, 1 `omittedPayload`, `payloadLimited` | 0/0, предупреждения нет |
| T6: неизвестное окно | `fragmented`, 4 части, `contextUnconfirmed` | `fragmented`, 1 часть, без предупреждения |
| T7: 64000/32000, D=50000 | `wholeDocument`, input 58300, maxTokens 5700 | `fragmented`, 0, 0 |
| T8: 64000/32000, D=56000 | `fragmented`, 2 части, `Dmax` 42133 | 1 часть, 0 |
| T9: граница total (D=53363) | input 62000, `wholeDocument` | 0, `fragmented` |
| T9: inputOnly без двойного вычитания (D=87500) | input 99550, `wholeDocument` | 0, `fragmented` |
| §5.2 веса 1:3:2:3:1, заказ 50 | `achievable` 50, `[5,15,10,15,5]` | 0, `[0,0,0,0,0]` |
| §5.2 ёмкость первого 3 | `[3,16,10,16,5]` | `[0,0,0,0,0]` |
| §5.2 ёмкости 3/6/5/6/2 | `achievable` 22, `belowRequested` | 0, false |
| §5.2 служебный раздел / маленький | `toc`=0, `small`≥1 | оба 0 |
| §5.2 свойства (заказы 1…100, авто, int.max) | сумма `min(requested, Σcapacity)` | 0 |
| §5.2 невалидный заказ 0/-5 | `ArgumentError` | `CardAllocation(total: 0)` |
| §5.3.1 заказ 10/50/100 | 3 одинаковые части, разные распределение/партии | 1 часть |
| §5.3.2 ответ вмещает 10 | `wholeDocument`, 1 партия | `fragmented` |
| §5.3.2 ответ вмещает 5, заказ 20 | `wholeDocument`, 4 партии по 5 | `fragmented`, 0 партий |
| §5.3.3 prompt-only, заказ 20 | `promptOnly`, 2 партии по 10 | `fragmented`, 0 |

## Фрагменты вывода (дословно)

```
T1: total 128000/out 8192, D=40000, 10 карточек → whole, 47300, 3765 [E]
  Expected: InputStrategy:<InputStrategy.wholeDocument>
    Actual: InputStrategy:<InputStrategy.fragmented>

T9: границы inputOnly: выход не вычитается из лимита входа повторно [E]
  Expected: <99550>
    Actual: <0>

§5.2 распределение веса 1:3:2:3:1, ёмкость ∞, заказ 50 → 5/15/10/15/5 [E]
  Expected: <50>
    Actual: <0>

§5.2 свойства невалидный заказ (0 и отрицательный) → ArgumentError [E]
  Expected: throws <Instance of 'ArgumentError'>
    Actual: <Closure: () => CardAllocation>
     Which: returned CardAllocation:<CardAllocation(total: 0, requested: 0, below: false)>

§5.3.1 заказ 10/50/100 → одинаковые части, разные распределение и партии [E]
  Expected: <3>
    Actual: <1>
```

## Что дальше

Фаза 2: реализовать формулы бюджета и три планировщика (Input → Allocator →
Batches), сохранив контракт тестов неизменным; затем домены-тесты зелёные,
`GenerationChunkPlanner` собирает план через них.
