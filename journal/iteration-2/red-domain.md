# Итерация 2 — красная фаза: домен и движок сессии (шаг 2)

**Дата:** 2026-11-13 · **Команда:** `fvm flutter test` (полный прогон) + `fvm flutter test test/unit/domain …`
**Итог красной фазы:** **390 passed, 77 failed** — падают только новые тесты итерации 2; существующие тесты итерации 1 зелёные (0 регрессий).
Полный вывод сохранён в `.dart_tool/red_phase_output.txt` (вне git; фрагменты ниже).

## Подготовительные рефакторинги (без изменения поведения, до красного прогона)

- **T1:** единый `CardState` — дубликат enum из `domain/scheduling/scheduling_card.dart` удалён; канон — `domain/cards/card.dart`. `scheduling_card.dart` реэкспортирует `CardState`, поэтому импорты `scheduler.dart` в тестах не изменились. В существующих FSRS/rating-тестах переименовано только значение `newState` → `newCard` (поведение не менялось, тесты зелёные).
- **T6:** общий маппер строк `cards` вынесен в `data/cards/card_row_mapper.dart`; `DriftCardRepository` использует его (карточки в списке/экспорте читаются как раньше). Существующие `card_repository_test` и `deck_zip_roundtrip_test` после этого зелёные.

## Что падает по ожидаемой причине

### CardDraft (валидация/нормализация, SPEC A8.4, ADR-009) — 12 падений

```
00:00 +0 -1: test/unit/domain/card_draft_test.dart:
CardDraft.parseTags разбивает строку, убирает # и пустые, сохраняет порядок [E]
  Expected: ['тег1', 'тег2']
    Actual: ['red-phase']
     Which: at location [0] is 'red-phase' instead of 'тег1'
```

Скелет `parseTags` возвращает маркер `['red-phase']`, `normalized()` — `this`, `validate()` — пустую карту. Красная причина — нейтральная заглушка, тесты уже содержат точные ожидания (500/2000/3/400, trim, ё/решётки, cloze с пустым `back`).

### CardSchedulingMapper (домен ↔ FSRS-снимок) — 6 падений

Ожидания: `toSchedulingCard` для новой карточки → `state new`, `step 0`, `due = now`; для карточки с `fsrs_json` → восстановленный `SchedulingCard`; битый/чужой `fsrs_json` → `FormatException`; `applyOutcome` обновляет `state/fsrs_json/due/updatedAt`, сохраняя содержимое; round-trip `applyOutcome → toSchedulingCard == outcome`. Скелет возвращает новую карточку/исходную — падения assertion-level (`Expected: SchedulingCard(...state: review) Actual: ...newCard` и т.п.).

### ReviewQueue (состав и порядок, ADR-008) — 6 падений

```
00:05 +319 -37: test/unit/domain/review_queue_test.dart:
порядок: просроченные по due, затем новые по createdAt [E]
  Expected: ['due-earlier', 'due-later', 'new-earlier', 'new-later']
    Actual: MappedListIterable<Card, String>:[]
     Which: at location [0] is MappedListIterable<Card, String>:[] which shorter than expected
```

Ожидания: suspended/buried исключены; `due <= now` входят, будущие — нет; граница `due == now`; порядок due→new; тай-брек `id`; исходный список не мутируется.

### Форматирование прогноза (A7.2) — 2 падения

`formatReviewInterval`: `<1 мин` / `N мин` (округление 5m30s → 6) / `N ч` (90m → 2) / `N д` (16 д). Скелет всегда отдаёт `lessThanMinute` → `Expected: ReviewIntervalText(minutes, 6) Actual: ReviewIntervalText(lessThanMinute, 0)`.

### Движок сессии (A6.4/A7.2, ADR-008) — 10 падений

```
00:09 +345 -46: test/unit/ui/review_session_engine_test.dart:
rate пишет оценку и переходит к следующей карточке [E]
  Expected: true
    Actual: <false>
```

Ожидания: `start()` строит очередь и превью (Again 1 мин / Good 10 мин для новой), `reveal()` раскрывает ответ, `rate()` пишет через порт (режим `classic`, `elapsed` от показа, `reviewedAt` из часов), двигает индекс, копит undo-стек, сохраняет busy=false; ошибка записи не двигает сессию; `undo()` вызывает порт и возвращает карточку; пустая очередь — завершённая сессия; прогноз == фактический `due`; suspended не попадает.

### Haptics (A7.2) — 2 теста зелёные сразу

Маппинг `heavy/light/light/selection` был написан вместе со скелетом (тривиальная таблица SPEC); красной фазы по нему нет — зафиксировано осознанно, чтобы не имитировать красное падение.

## Артефакты

- Тесты: `test/unit/domain/{card_draft,card_scheduling,review_queue}_test.dart`, `test/unit/ui/{review_interval_format,review_session_engine,review_haptics}_test.dart`.
- Скелеты API с заглушками, red-фрагмент вывода — этот файл.
