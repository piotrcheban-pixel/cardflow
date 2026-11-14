# Итерация 4 — красная фаза (шаг 2)

**Дата:** 2026-11-14 · **HEAD на старте:** `e5f64c4` · **Тесты:** `feed_swipe`, `feed_session_engine`,
`feed_session_screen`, `feed_entry`, `feed_session_flow`, обновлён `app_router_test`.
**Скелеты:** сигнатуры `feedSwipeRating`, `FeedSessionEngine`/`FeedSessionItem`/`FeedSessionState`,
`FeedCardView`, `FeedProgressBar`, `FeedSessionScreen`; ARB-ключи именами `feed*`; `reviewModeFeed`;
`AppRoutes.feed/feedPath`; маршрут `/decks/:id/feed` — только в тестовом helper (production-роутер
добавляется в зелёной фазе, поэтому тест роутера красный).

## Команды и результат

| Команда | Результат |
|---|---|
| `fvm flutter test test/unit/ui/feed_swipe_test.dart --reporter expanded` | **7 passed / 5 failed** — все падения assertion-level (`Expected: Rating.good, Actual: null`) |
| `fvm flutter test test/unit/ui/feed_session_engine_test.dart --reporter expanded` | **2 passed / 18 failed** — `Total: <0>` вместо 3, `ratedCount: 0`, `advance: false` |
| `fvm flutter test test/widget/review/feed_session_screen_test.dart --reporter expanded` | **0 passed / 20 failed** — `Found 0 widgets with type "FeedProgressBar"` и далее по контракту |
| `fvm flutter test test/widget/review/feed_entry_test.dart test/unit/ui/app_router_test.dart test/integration/feed_session_flow_test.dart` | **2 passed / 4 failed** — лист режимов без «Ленты», production-роут 404, маршрутов 8 вместо 9, движок не пишет лог |

## Фрагменты ожидаемого поведения (assertion-level)

`feed_swipe_test`:

```
Expected: Rating:<Rating.good>
  Actual: <null>
  test\unit\ui\feed_swipe_test.dart 12:7
...
Expected: Rating:<Rating.easy>
  Actual: <null>
  test\unit\ui\feed_swipe_test.dart 53:7
```

`feed_session_engine_test`:

```
Expected: an object with length of <3>
  Actual: []
   Which: has length of <0>
  test\unit\ui\feed_session_engine_test.dart 267:5
...
Expected: true
  Actual: <false>
  test\unit\ui\feed_session_engine_test.dart 252:5
...
Expected: completes to a value that true
  Actual: <Instance of 'Future<bool>'>
   Which: emitted <false>
  test\unit\ui\feed_session_engine_test.dart 334:11
```

`feed_session_screen_test`:

```
Expected: exactly one matching candidate
  Actual: _TypeWidgetFinder:<Found 0 widgets with type "FeedProgressBar": []>
   Which: means none were found but one was expected
  test\widget\review\feed_session_screen_test.dart line 110
```

`feed_entry_test`:

```
Expected: exactly one matching candidate
  Actual: _TypeWidgetFinder:<Found 0 widgets with type "FeedSessionScreen": []>
  test\widget\review\feed_entry_test.dart line 100
```

`app_router_test`:

```
Expected: <9>
  Actual: <8>
  test\unit\ui\app_router_test.dart
```

## Наблюдения красной фазы

- Все падения — по ожидаемому поведению, а не по компиляции: сигнатуры и ARB-ключи объявлены заранее.
- Скелет `FeedSessionState` с пустым списком даёт `isCompleted = true`; это ожидаемо для пустой очереди,
  но тесты `start` падают на `total`/`current` — то, что должны доказать.
- `app_router_test` падает только на количестве/наличии `/decks/:deckId/feed`; `AppRoutes.feedPath`
  уже объявлен как контракт (путь проверен отдельным тестом и прошёл).
- `prefer_final_fields` в скелете движка исчезнет в зелёной фазе (поле начнёт присваиваться).
