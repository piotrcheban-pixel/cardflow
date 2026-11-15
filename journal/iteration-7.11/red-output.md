# Итерация 7.11 — красная фаза (фрагменты вывода)

**Дата:** 2026-11-15 · Прогоны — только `fvm flutter test --no-pub`.

## Шаг 1. Инвариант новой карточки (ADR-026)

До фикса карточка из генерации сохранялась с `due = NULL` и `fsrs_json = NULL`:

```
test/integration/generation_flow_test.dart:
production-граф: карточка с медиа после импорта входит в ReviewQueue [E]
  Expected: not null (due новой карточки — момент импорта)
    Actual: null
```

Счётчик «к повторению» считал новые карточки, если у них появлялся `due`:

```
test/unit/data/decks/deck_repository_test.dart:
новая карточка с due <= now не попадает в счётчик due [E]
  Expected: <0>
    Actual: <1>
```

Порядок конструктора различал новые по `due IS NULL`, а не по `state`:

```
test/unit/domain/session_builder_test.dart:
фильтры пустой набор фильтров — все карточки выбранных колод [E]
  Expected: ['a', 'b']
    Actual: ['b', 'a']
```

## Шаг 2. Честное пустое состояние при дневном лимите (ADR-025)

Воспроизведение owner-note на production-проводке (реальная БД владельца, копия):

```
review_logs за 15.11: 30 записей, actual_days IS NULL у всех
app.settings: daily_new_limit = 20  →  остаток новых = 0
ReviewSessionScreen._load: ReviewQueue.build(cards, newLimit: 0) → []
```

До фикса экран колоды проверял очередь **без** лимитов и пропускал в пустую сессию:

```
test/widget/decks/deck_screen_test.dart:
дневной лимит исчерпан: сообщение о лимите вместо «нет карточек» [E]
  Expected: 'Дневной лимит исчерпан — откройте «Тренировку», чтобы пройти карточки сейчас'
    Actual: 'Нет карточек к повторению'
```

Экран сессии не показывал причину и не предлагал выход:

```
test/widget/review/review_session_screen_test.dart:
дневной лимит исчерпан: причина и переход в тренировку [E]
  Expected: exactly one matching candidate (review-empty-practice)
    Actual: _KeyFinder: Found 0 widgets
```

## Шаг 3. Режим «Тренировка» (ADR-025)

```
test/unit/data/review/practice_repository_test.dart [E]:
recordPractice: строка журнала practice, карточка не меняется
  — класса / порта ещё нет (red до реализации)
```

Расход лимитов считал тренировку новой карточкой:

```
test/unit/data/review/daily_usage_repository_test.dart:
записи mode=practice не расходуют дневной лимит [E]
  Expected: <1>
    Actual: <3>
```

## Шаг 4. Картинки (ADR-027)

Диагностика на хосте (Python, публичные API, без ключей):

```
Openverse: первый GET 200, последующие запросы → "The read operation timed out" (30 с)
Wikimedia Commons «Московский Кремль» → 5 результатов за 1,0 с (JPEG/PNG)
```

Поиск не давал иллюстрацию — генерация уходила без картинок:

```
test/unit/api/images/composite_card_image_finder_test.dart [E]:
первый источник пуст — используется резервный
  — CompositeCardImageFinder ещё нет (red до реализации)

test/unit/api/generation/generation_pipeline_test.dart:
после бюджета поиска картинки не ищутся [E]
  Expected: empty
    Actual: ['eiffel tower']   (лишние 20 с ожидания на карточку)
```

## Шаг 5. PDF-сканы (ADR-023/ADR-027)

```
test/unit/api/parsers/pdf_scan_renderer_test.dart:
по умолчанию рендерятся первые 3 страницы [E]
  Expected: <3>
    Actual: <4>
```

## Фикстуры, которые пришлось привести к новому инварианту

- `test/unit/domain/session_builder_test.dart` — изучаемая карточка получила `due`
  (различие «запланированная/новая» теперь по `state`).
- `test/unit/data/cards/card_crud_test.dart`, `drift_generation_card_store_test.dart` —
  вместо `isNull` проверяется начальное FSRS-состояние (`due = now`, `fsrs_json`
  разбирается `CardSchedulingMapper`).
- `test/integration/feed_session_flow_test.dart` — undo восстанавливает начальное
  состояние, а не `NULL`.
- `test/unit/ui/app_router_test.dart` — 13 маршрутов (добавлен practice).
- `test/widget/generation/generation_screen_test.dart` — скан из 3 страниц.
