# Verify — срез 14: ёмкость плана, честный статус, решение о флаге

**Срез:** `TASK.txt` «Срез 14. Ёмкость плана, честный статус, решение о флаге».
Толкования — `journal/QUESTIONS.md` Q26; пересчёт матрицы и вердикт —
`journal/generation-v3/live-s12/matrix-s14.md`; ограничения — L230 (и L227,
L228 из среза 13).

**Факты старта:** ветка `main`, `HEAD = 34fc911` (док среза 13); baseline —
3234 passed + 18 skipped, покрытие 90,9 %, схема БД v3, флаг
`generationPipelineV3` выключен.

## 1. Что сделано (по пунктам TASK)

| Пункт | Сделано | Где | Чем подтверждено |
|---|---|---|---|
| 1.1 Ёмкость слотов | `kMaxCardsPerUnit = 4` (основная + `reverse/cloze/application`); `allocateUnits` больше 4 не раскидывает, остаток — capped-распределением (излишек по убыванию веса); `AllocationPlan` **конструктором** проверяет `cards.length == capacity` и отсутствие двух одинаковых `slotKey` | `lib/domain/generation/allocation.dart` | `allocation_capacity_test` 4/4 (300/47, «в пределах ёмкости не режется», конструктор отвергает повтор слота и карточки сверх ёмкости); property-тест `allocation_test` на 200 прогонах |
| 1.2 Заказ больше ёмкости | `planned == capacity`, `requested` не меняется, `materialLimited` с числом `capacity`; 300/47 → 188 (47 × 4), 112 — `shortfall` | `allocation.dart` (`capacity`, `materialLimited`) | `allocation_capacity_test`: `planned == 188`, `capacity == 188`, `shortfall == 112`, 188 уникальных слотов; `generation_v3_facade_flow_test` («300 при 47 единицах») |
| 1.3 Честный итог | при `materialLimited` и закрытых слотах `complete` → `exhausted_material`; `materialCapacity` = ёмкость (188), вердикт `partial` | `replenish_stage.dart` (`run`, `materialCapacity`), `generation_preview_screen.dart` (строка ARB) | `generation_v3_facade_flow_test`: `jobStatus == partial`, `reason == exhausted_material`, `materialCapacity == 188`, `shortfallReasons[exhaustedMaterial] == 112`; красная фаза — `red-s14.txt` (`Expected: partial, Actual: done`) |
| 1.4 Ноль запросов добора | при исчерпанной ёмкости `debt` пуст, проходов нет | `replenish_stage.dart` | тот же тест: `report.passes == 0`, `port.calls == plan.batches.length` (после первого прохода модель не звали) |
| 2.5 `matchedSubset` | пересечение единиц двух путей, `cleanRate_matched` = чистые/произведённые на базе, «топ-N по salience» (для 150/300 — 80), детерминированный порядок | `matrix_comparison.dart` (`ProducedCardRef`, `MatchedSubset`) | `matrix_comparison_test`: фикстура с известным пересечением (u1/u2 общие, u3 только legacy, u4 только v3), `topUnits: 1` |
| 2.6 `absoluteClean` | число чистых карточек рядом с `cleanRate` в отчёте и метриках | `generation_report.dart`, `metrics_collector.dart` | `generation_report_test`, `metrics_collector_test` (`absoluteClean` и JSON `absolute_clean`) |
| 2.7 Пересчёт | `tool/recompute_matrix_s14.dart` из существующего `matrix.jsonl` → `matrix-s14.md`: absoluteClean, cleanRate_matched, критерий по каждой решающей ячейке | `tool/recompute_matrix_s14.dart`, `live-s12/matrix-s14.md` | запуск инструмента: 6 решающих пар, критерий 6/6, новых платных прогонов 0 |
| 3.8 Критерий | `cleanRate_matched(v3) ≥ 95 %` **и** `absoluteClean(v3) ≥ absoluteClean(legacy)` на всех решающих 80/150/300 — зафиксирован в STATE как окончательный | `matrix_comparison.dart` (`flagCriterion`, `kFlagCleanRateThreshold`), `journal/STATE.md` | `matrix_comparison_test` (met/notMet/notDecisive), `matrix-s14.md` |
| 3.9 Флаг | критерий выполнен → `AppSettings.generationPipelineV3` по умолчанию `true`; legacy — выключением флага в настройках, не удалён | `app_settings.dart`, `app_settings_pipeline_flag_test` | тест: default `true`, JSON без ключа → `true`, `copyWith(false)` сохраняет legacy |
| 3.10 Явный вердикт | «критерий выполнен» с числами, без «продолжаем наблюдать» | `matrix-s14.md` §«Критерий флага», ниже §4 | 6/6 |

## 2. Ёмкость: числа и поведение

`capacity = Σ по единицам min(запрошено на единицу, 4 свободных угла)`.

| Вход | Было (S12) | Стало (S14) |
|---|---|---|
| 47 единиц, заказ 300 | план 300 карточек, 112 повторов слотов | `planned = capacity = 188`, `requested = 300`, `shortfall = 112`, повторов нет |
| 1 единица, заказ 5 | 5 карточек, угол `reverse` повторён | 4 карточки: `null | reverse | cloze | application` |
| 3 единицы, заказ 10 (веса 1 : 0,5 : 0,25) | `[5, 3, 2]` | `[4, 4, 2]` (у единицы не больше 4) |

Инвариант держит **конструктор**: `AllocationPlan(requested: 2, units: [budget(2)], cards: [primary, primary])` бросает `AssertionError` (тот же слот), а `cards: [primary]` при ёмкости 4 — тоже (карточек меньше ёмкости). Красная фаза до реализации: `expected 188, actual 300` и конструктор возвращал план с повтором слота (`red-s14.txt`).

Итог прогона 300/47 (фасад, фейковый `LlmPort`):

| Поле | Значение |
|---|---|
| `plan.requested` / `plan.plannedCards` / `plan.capacity` | 300 / 188 / 188 |
| `report.accepted` | 188 |
| `report.reason` | `exhausted_material` |
| `report.materialCapacity` | 188 |
| `report.shortfallReasons[exhaustedMaterial]` | 112 |
| `CompletionVerdict.fromReport(...).jobStatus` | `partial` |
| `report.passes`, `port.calls` | 0, `plan.batches.length` (добор не звал модель) |

## 3. Сопоставимая база и `absoluteClean`

- `MatchedSubset.of(legacy, v3)` оставляет только единицы, где **оба** пути
  произвели хотя бы одну карточку; `legacyCleanRate`/`v3CleanRate` считаются
  на этом подмножестве. `topUnits` отбирает верх материала по максимальной
  значимости единицы (при равенстве — по id), поэтому результат детерминирован.
- `absoluteClean` = `accepted − acceptedWithWarnings` числом: доля без объёма
  вводит в заблуждение (учебный 300: legacy 73 чистых против v3 292).
- В существующей матрице пер-юнитных карточек нет, но `coverage = 100 %` у
  обоих путей во всех решающих ячейках: единиц без карточки нет, значит
  сопоставимая база совпадает с произведённым (`matched = произведено`).
  При `coverage < 1` пересчёт даёт `—`, а не догадку (L230); «топ-80 по
  salience» на реальных ячейках применить нельзя по той же причине — правило
  реализовано и покрыто фикстурой.

## 4. Критерий флага — окончательный

Критерий (зафиксирован в `journal/STATE.md`, не пересматривается):
`cleanRate_matched(v3) ≥ 95 %` **и** `absoluteClean(v3) ≥
absoluteClean(legacy)` на всех решающих ячейках 80/150/300.

| Материал | Заказ | legacy absoluteClean | v3 absoluteClean | v3 cleanRate_matched | ≥ 95 % | объём | Вердикт |
|---|---:|---:|---:|---:|---|---|---|
| учебный текст | 80 | 50 | 80 | 100,0 % | да | да | выполнен |
| учебный текст | 150 | 53 | 150 | 100,0 % | да | да | выполнен |
| учебный текст | 300 | 73 | 292 | 97,3 % | да | да | выполнен |
| статья | 80 | 16 | 80 | 100,0 % | да | да | выполнен |
| статья | 150 | 15 | 150 | 100,0 % | да | да | выполнен |
| статья | 300 | 15 | 185 | 97,9 % | да | да | выполнен |

**Критерий выполнен на 6 из 6 решающих пар.** `generationPipelineV3`
включён по умолчанию (`AppSettings`, JSON без ключа → `true`); legacy доступен
выключением флага в настройках и не удалён. Источник чисел —
`matrix-s14.md`, пересчёт из `matrix.jsonl` без новых платных прогонов.

## 5. Красная и зелёная фазы, гейты

Красная фаза — `journal/generation-v3/red-s14.txt`: assertion-level падения до
реализации (`Expected: <188> Actual: <300>`; `Expected: throws AssertionError
Actual: AllocationPlan(...)`; `Expected: partial Actual: done`).

**Гейты (2026-11-28; после `dart format lib test tool`):**
- `flutter analyze --no-pub lib test tool` → **No issues found!**;
- `dart format --set-exit-if-changed lib test tool` → **0 changed**
  (727 files, 13 отформатированы до гейта);
- `flutter test --no-pub --coverage --exclude-tags golden` → **3244 passed + 18 skipped, exit 0** (+10 к baseline 3234)
  (`green-s14-full.txt`);
- покрытие рукописного кода — **90,9 % (27103/29824)** при пороге 80 %
  (`coverage-s14.txt`);
- guards (`ru_strings`, `architecture`, `no_webview`, `no_secrets`, `contrast`,
  `ci_pdfium`) — зелёные в полном прогоне.

## 6. Остаточные ограничения (осознанные)

1. `SchemaCompatProfile` не персистится между запусками (L227).
2. Dedup сверяет только стороны текста (L228).
3. Пер-юнитных карточек в `matrix.jsonl` нет: `matchedSubset` на реальных
   ячейках выведен из `coverage == 100 %`, «топ-80 по salience» не применён —
   это L230, а не подмена.
4. Живая матрица не перемерялась (TASK: новых платных прогонов не делать); все
   живые числа — про `deepseek / deepseek-flash` (L222).
5. Мультифайл и `source_file` по-прежнему не в матрице (S11, Q23).
6. Legacy не удалён: его тесты (`generation_flow_test` и др.) явно выключают
   флаг (`legacyGenerationSettings` + override `effectiveAppSettingsProvider`),
   потому что первый синхронный `read` настроек видит `defaults`.
