# Закрытие L45 — дневные лимиты по календарному дню

**Дата:** 2026-11-14 · **Итерация:** 7 (post-review, долг M3 → L45) · **Режим:** ИТЕРАЦИИ (фикс + MVP-аудит,
без новых фич) · **SPEC:** A6.6, A7.2, A7.3, A5 · **ADR:** ADR-019 (аддендум §8)

## Проблема (L45)

Дневные лимиты новых/повторных из A6.6 применяются к **очереди одной сессии**
(`ReviewQueue.build(..., newLimit:, reviewLimit:)`), а не к календарному дню. Две сессии подряд
получают полный лимит каждая: при лимите 20 новых можно за день пройти 40, 60, … — лимит не работает
как дневной. Разрыв зафиксирован в `journal/KNOWN_LIMITATIONS.md` (L45) и ADR-019 §7.

## Ограничение решения

Схема БД после релиза меняется только владельцем (промпт §5), `schemaVersion` не трогаем: в
`review_logs` нет признака «это первое повторение карточки». Значит расход дня нужно **вывести из
существующей истории** `review_logs`.

## Решение (кратко)

1. **Domain** `lib/domain/review/daily_limits.dart`:
   - `DailyReviewUsage {newCards, repeats}` — расход дня;
   - `DailyLimits.localDayUtc(now)` — полуинтервал `[from, to)` локального календарного дня в UTC
     (корректно переживает DST: границы — локальные полуночи);
   - `DailyLimits.remaining(configured, used)` — `null` (лимита нет, `0` в настройках) / `0` (исчерпан) /
     `n` (осталось).
2. **Порт** `DailyUsageRepository.usageOnDay(now)`; **drift-реализация**
   `DriftDailyUsageRepository` — один `customSelect` по `review_logs` за день:
   - `total` — число оценок в `[from, to)`;
   - `new_cards` — оценки, для карточки которых **нет более ранней** записи (`NOT EXISTS … reviewed_at <`),
     т.е. карточки, впервые оценённые сегодня;
   - `repeats = total − new_cards`.
   Индекс `idx_review_logs_card` (по `card_id`) делает подзапрос дешёвым; читаются только строки дня.
3. **Смысл «новой»** — карточка, у которой сегодня первая по времени запись в `review_logs`. Undo удаляет
   лог, поэтому расход дня самовосстанавливается. Ограничение: карточка с чужим FSRS-состоянием без
   логов (импорт из внешнего формата) при первом повторении в CardFlow считается новой — это ожидаемо,
   т.к. для CardFlow это действительно первое повторение.
4. **Очередь**: `ReviewQueue.build` принимает `int?` — `null` = без лимита, `0` = не брать ничего,
   `n` = не больше `n`. Экран сессии считает остаток: `remaining(настройка, расход дня)`.
5. **Лимиты глобальные** (на все колоды), как и настройка A6.6 «дневные лимиты», которая живёт в общих
   настройках, а не в колоде. Конструктор (A6.7) по-прежнему не ограничивается: у него свой лимит.

## Затрагиваемые файлы

| Файл | Изменение |
|---|---|
| `lib/domain/review/daily_limits.dart` | новый: `DailyReviewUsage`, `DailyLimits` |
| `lib/domain/review/daily_usage_repository.dart` | новый порт |
| `lib/data/review/drift_daily_usage_repository.dart` | новый: SQL-вывод расхода дня |
| `lib/domain/review/review_queue.dart` | `int` → `int?` для лимитов |
| `lib/ui/review/review_session_engine.dart`, `feed_session_engine.dart` | `int?` лимиты |
| `lib/ui/review/review_session_screen.dart`, `feed_session_screen.dart` | чтение расхода → остаток |
| `lib/ui/state/app_providers.dart` | `dailyUsageRepositoryProvider` |
| `test/unit/domain/daily_limits_test.dart` | новый: границы дня, остаток |
| `test/unit/domain/review_queue_limits_test.dart` | `0` = исчерпан, `null` = без лимита |
| `test/unit/data/review/daily_usage_repository_test.dart` | новый: SQL на in-memory drift |
| `test/integration/daily_limits_flow_test.dart` | новый: реальная БД + production-граф, две сессии дня |
| `test/helpers/review_fakes.dart`, `pump_app.dart` | `FakeDailyUsageRepository` в обвязку |
| `docs/decisions/ADR-019-statistics-and-settings.md` | аддендум §8 |
| `journal/KNOWN_LIMITATIONS.md` | L45 снят |

## Красная фаза (что должно упасть до реализации)

1. `DailyLimits.localDayUtc` — границы дня (в т.ч. переход месяца) и `remaining` (null/0/n).
2. `ReviewQueue.build(newLimit: 0)` — сегодня `0` значит «без лимита», нужен «не брать ничего»;
   `DailyReviewUsage` — расход дня.
3. `DriftDailyUsageRepository.usageOnDay` — новый класс, компиляции нет.
4. Интеграционный сценарий: 5 новых карточек, лимит 2/сессию → вторая сессия того же дня должна получить
   **0** карточек (сегодня получит 2), а на следующий день — снова 2.

### Факт красной фазы (вывод команд, `.red-phase-l45.log`)

Поведенческий уровень (существующий `ReviewQueue`):

```
00:00 +3 -1: ReviewQueue — дневные лимиты (A6.6, ADR-019 §2) 0 — дневной лимит исчерпан …
  Expected: empty
    Actual: [Card(id: due-0 … state: review), …, Card(id: new-3 … state: new)]   // 7 карточек
  остаток дня 0 — очередь пуста, а не «без ограничения»
00:00 +3 -2: … остаток дня обрезает каждую часть отдельно (L45)
  Expected: ['due-0', 'due-1']
    Actual: ['due-0', 'due-1', 'new-0', 'new-1', 'new-2', 'new-3']
```

Уровень нового API (компиляция):

```
test/unit/domain/daily_limits_test.dart:3:8: Error: Error when reading 'lib/domain/review/daily_limits.dart': Не удается найти указанный файл
test/unit/domain/daily_limits_test.dart:13:53: Error: Undefined name 'DailyLimits'.
```

## Зелёная фаза

- `fvm flutter test <4 файла>` → **31 passed** (`All tests passed!`).
- Полный прогон: `fvm flutter test --coverage --exclude-tags golden` → **1203 passed + 1 skipped**
  (до фикса было 1175 + 1; +28 тестов).
- Покрытие `fvm dart run tool/coverage_check.dart --min=80` → **92.6 % (8368/9038)**, порог пройден.
- `fvm flutter analyze` → `No issues found!`; `fvm dart format --set-exit-if-changed lib test` → 305 files,
  **0 changed**.

### Уточнение семантики по ходу зелёной фазы

Первая реализация считала «новой» карточку с **первой в истории** записью в журнале. Интеграционный тест
на лимите повторных упал: засеянная due-карточка (есть `fsrs_json` и `last_review`, но логов в этой БД
нет — ровно как после импорта колоды) посчиталась новой, и лимит повторных не израсходовался
(`Expected: <0>, Actual: <1>`). Исправлено на признак **`actual_days IS NULL`** — «до этой оценки
карточка не планировалась»: он верно отличает импортированные карточки от вводимых впервые и не требует
коррелированного подзапроса. Тест «карточка с чужим состоянием (импорт) — повторная, а не новая»
закрепляет поведение.

## Критерии приёмки

- [x] `ReviewQueue.build` различает «без лимита» (`null`) и «исчерпан» (`0`).
- [x] Расход дня считается по локальному календарному дню из `review_logs`, без миграций.
- [x] Повторное открытие сессии в тот же день уважает остаток (интеграционный тест на реальной БД).
- [x] Undo уменьшает расход дня (лог удалён) — тест.
- [x] Ночной переход: вчерашние оценки не расходуют сегодняшний лимит — тест.
- [x] `analyze` 0, `dart format` 0 changed, полный прогон **1203 passed + 1 skipped**, покрытие **92.6 %**.
- [x] ADR-019 §8 + L45 снят в `KNOWN_LIMITATIONS.md`.
