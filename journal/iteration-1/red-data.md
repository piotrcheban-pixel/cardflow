# Красная фаза и итог: data-drift — drift-схема, миграции, репозитории колод и карточек

**Дата:** 2026-11-12 · **Исполнитель:** data-drift · **Задача:** task-1 (plan §1, п. 1.3)
**TDD-порядок:** тесты → красный → минимальная реализация → зелёный. Ниже — фактические прогоны.

## 0. Как шла красная фаза (честная хронология)

1. **Тесты написаны до реализации** — до появления `lib/data/db/tables.dart`, drift-кодогенерации
   и реальных репозиториев:
   - `test/unit/data/db/schema_test.dart` — 10 таблиц/колонки/типы/NOT NULL/DEFAULT, 3 индекса,
     `PRAGMA foreign_keys=ON`, каскад, `schemaVersion==1`, повторное открытие, файловый opener;
   - `test/unit/data/decks/deck_repository_test.dart` — CRUD, trim/ArgumentError, архив с
     идемпотентностью, поиск (регистр, ё/е, подстрока), 4 фильтра, `includeArchived`, порядок,
     счётчики, watch-обновления, каскад;
   - `test/unit/data/cards/card_repository_test.dart` — маппинг всех полей (nullable, bool,
     JSON-списки, epoch ms UTC), порядок `created_at ASC, id`, watch, снимок.
2. **Прогон №1 — красный на компиляции** (ожидаемо: реализация ещё заглушка без drift-API).
3. **Прогон №2 — assertion-level красный:** таблицы/БД/opener реализованы, `build_runner`
   прогнан, репозитории намеренно оставлены скелетами (чтение → пустые/null, запись → no-op),
   чтобы тесты компилировались и падали именно на проверках поведения, а не на
   `UnimplementedError`/компиляции.
4. **Прогон №3 — зелёный:** реальные `DriftDeckRepository`/`DriftCardRepository`.

## 1. Прогон №1: красный на компиляции

```
$ fvm flutter test test/unit/data
test/unit/data/db/test_support.dart:23:9: Error: Undefined name 'DecksCompanion'.
test/unit/data/db/test_support.dart:21:16: Error: The getter 'decks' isn't defined for the type 'AppDatabase'.
test/unit/data/db/test_support.dart:21:8: Error: The method 'into' isn't defined for the type 'AppDatabase'.
test/unit/data/db/test_support.dart:61:16: Error: The getter 'cards' isn't defined for the type 'AppDatabase'.
...
00:00 +0 -3: Some tests failed.
Failing tests:
  test/unit/data/cards/card_repository_test.dart: loading ...
  test/unit/data/db/schema_test.dart: loading ...
  test/unit/data/decks/deck_repository_test.dart: loading ...
```

Причина ожидаемая: тесты написаны раньше drift-схемы; на этой фазе assertion-level вывода быть
не может. Schema-тест покрывает декларативную часть (таблицы/индексы/FK) — её TDD-red выражен
именно compile-фазой; после реализации схемы он сразу зелёный (§4, шаг 1).

## 2. Прогон №2: assertion-level красный (скелеты репозиториев)

```
$ fvm flutter test test/unit/data/db test/unit/data/decks test/unit/data/cards
00:00 +25 -30: Some tests failed.
```

Фрагменты (ожидалось: X, получено: Y) — из вывода прогона:

```
decks/deck_repository_test.dart: createDeck создаёт колоду: UUID v4, trim имени, UTC-таймстемпы, пустые настройки
  Expected: true
  Actual: <false>                       # UUID-регэксп: получен пустой id

decks/deck_repository_test.dart: createDeck пустое или пробельное имя — ArgumentError
  Expected: throws <Instance of 'ArgumentError'>
  Actual: <Instance of 'Future<Deck>'>
   Which: emitted Deck:<Deck(id: , name: , archived: false)>

decks/deck_repository_test.dart: renameDeck меняет имя, trim, обновляет updated_at, не трогает created_at
  Expected: not null
  Actual: <null>                        # deckById(...) скелета всегда null

decks/deck_repository_test.dart: watchDeck: начальное значение и обновление после rename
  Expected: Deck:<Deck(id: , name: Стрим, archived: false)>
  Actual: <null>

decks/deck_repository_test.dart: watchSummaries: поиск без поиска — все активные колоды
  Expected: ['deck-yo', 'deck-es', 'deck-fr']
  Actual: MappedListIterable<DeckSummary, String>:[]

decks/deck_repository_test.dart: watchSummaries: фильтры и архив due: колоды с просроченными карточками
  Expected: ['deck-progress']
  Actual: MappedListIterable<DeckSummary, String>:[]

decks/deck_repository_test.dart: watchSummaries: порядок updatedAt DESC, при равенстве — имя по возрастанию
  Expected: ['Гамма', 'Альфа', 'Бета']
  Actual: []

cards/card_repository_test.dart: маппинг всех полей полная карточка: все поля, включая nullable/bool/JSON/даты
  Expected: an object with length of <1>
  Actual: []
   Which: has length of <0>

cards/card_repository_test.dart: cardsByDeck возвращает только карточки указанной колоды
  Expected: ['card-1']
  Actual: MappedListIterable<Card, String>:[]

cards/card_repository_test.dart: watchCards порядок created_at ASC, при равенстве — id ASC
  Expected: ['card-a', 'card-b', 'card-c']
  Actual: MappedListIterable<Card, String>:[]
```

Schema-тесты на этом прогоне уже зелёные (19 из 25 passed; ещё 6 — репозиторные тесты на
пустые/негативные сценарии, которые скелет случайно удовлетворял). Красная фаза для
бизнес-логики репозиториев — 30 падений выше.

## 3. Реализация (зелёная фаза), поставленные файлы

- `lib/data/db/tables.dart` — 10 drift-таблиц A5 (`DeckRow`, `CardRow`, `ReviewLogRow`,
  `PracticeLogRow`, `MediaRow`, `SourceDocRow`, `SyncMetaRow`, `GenerationJobRow`,
  `AppSettingRow`, `SessionPresetRow`), snake_case-колонки, DEFAULT `'{}'`/`'[]'`/0, FK каскада,
  3 индекса через `@TableIndex` (`idx_cards_deck_due`, `idx_cards_hash`, `idx_review_logs_card`).
- `lib/data/db/app_database.dart` — `@DriftDatabase`, `schemaVersion = 1`, `MigrationStrategy`:
  `onCreate → createAll` (создаёт и декларативные индексы), `onUpgrade → StateError` (fail-fast
  ADR-005), `beforeOpen → PRAGMA foreign_keys = ON`; фабрика `AppDatabase.inMemory()`
  (`NativeDatabase.memory()`, спайк S3).
- `lib/data/db/database_opener.dart` — `openAppDatabase({Directory? baseDirectory})`:
  `getApplicationSupportDirectory()/cardflow/cardflow.sqlite`, `NativeDatabase.createInBackground`.
- `lib/data/db/epoch.dart` — INTEGER epoch **ms** UTC ↔ `DateTime` (формат SPEC A5).
- `lib/data/decks/drift_deck_repository.dart` — `watchSummaries` (SQL с LEFT JOIN + SUM CASE:
  total/new/inProgress/due; поиск по `normalizeForComparison`, фильтры `DeckFilter`, архив,
  порядок `updated_at DESC`/имя; `readsFrom: {decks, cards}`), `watchDeck`, `deckById`,
  `createDeck` (uuid v4, trim, ArgumentError), `renameDeck`, `archiveDeck`/`unarchiveDeck`
  (идемпотентно), `deleteDeck` (каскад FK).
- `lib/data/cards/drift_card_repository.dart` — маппинг всех полей `Card ↔ CardRow`
  (JSON-списки tags/media, 0/1 ↔ bool, epoch ms ↔ DateTime UTC, fsrs/occlusion — сырые строки),
  `watchCards`/`cardsByDeck` (порядок `created_at ASC, id ASC`).
- `test/migrations/migration_test.dart` + `test/migrations/generated/**` +
  `drift_schemas/drift_schema_v1.json` — snake dump/`SchemaVerifier`: версия dump ==
  `schemaVersion`, dump v1 создаёт 10 таблиц + 3 индекса, `onCreate` приложения семантически
  совпадает с dump v1 (`migrateAndValidate`), открытие drift-класса поверх v1-схемы проходит.
- Тесты: `test/unit/data/db/schema_test.dart`, `test/unit/data/decks/deck_repository_test.dart`,
  `test/unit/data/cards/card_repository_test.dart`, `test/unit/data/db/test_support.dart`.

## 4. Зелёные прогоны

```
$ fvm dart run build_runner build --delete-conflicting-outputs
  Built with build_runner/aot; wrote 113 outputs.        # app_database.g.dart

$ fvm flutter test test/unit/data/db test/unit/data/decks test/unit/data/cards
00:01 +55: All tests passed!                            # schema 20 + decks 29 + cards 7
                                                       # (на момент красной фазы schema было 19;
                                                       #  позже добавлен тест onUpgrade fail-fast)

$ fvm flutter test test/migrations
00:00 +4: All tests passed!                             # dump + SchemaVerifier

$ fvm flutter test test/unit/data test/migrations
00:01 +172: All tests passed!                           # включая чужие transfer-тесты archive-zip

$ fvm dart format --output=none --set-exit-if-changed lib/data/db lib/data/decks lib/data/cards test/unit/data test/migrations
Formatted 17 files (0 changed); exit code 0

$ fvm dart analyze lib/data/db lib/data/decks lib/data/cards test/unit/data test/migrations
No issues found!

$ fvm flutter test --coverage test/unit/data/db test/unit/data/decks test/unit/data/cards test/migrations
00:02 +60: All tests passed!
```

Покрытие рукописного data-кода (по `coverage/lcov.info`, сгенерированные `*.g.dart` исключены):

| файл | покрытие |
|---|---|
| `lib/data/db/app_database.dart` | 11/11 = 100% |
| `lib/data/db/epoch.dart` | 3/3 = 100% |
| `lib/data/decks/drift_deck_repository.dart` | 112/113 = 99,1% |
| `lib/data/cards/drift_card_repository.dart` | 46/48 = 95,8% |
| `lib/data/db/database_opener.dart` | 5/6 = 83,3% (непокрыта ветка `baseDirectory == null` → `path_provider`, в тестах плагина нет) |
| `lib/data/db/tables.dart` | 0/89 — **декларативный кодогенерационный DSL** |

Итого по исполняемому data-коду: **177/181 = 97,8%**. `tables.dart` даёт 0% законно: drift-геттеры
колонок исполняются только кодогенератором и в рантайме бросают `UnsupportedError` — сгенерированные
`$...Table` классы переопределяют их (так устроен drift 2.35.4, `lib/src/dsl/dsl.dart::_isGenerated`).
**Запрос к Lead:** добавить `lib/data/db/tables.dart` в список декларативных исключений
`tool/coverage_check.dart` (рядом с `*.g.dart`), иначе файл занижает общий порог ≥80% на ~89 строк.

## 5. Что не проверено / ограничения (на момент отчёта)

1. **Полный `fvm flutter analyze`** на момент отчёта: 3 issues — все в чужом файле
   `lib/data/transfer/file_picker_gateway.dart` (archive-zip в работе: в контракте
   `FileGateway` появился `saveZipFile`, реализация ещё не дописана). В файлах data-drift —
   0 issues (см. команду выше). Чужие файлы не правились.
   Следствие: комбинированный прогон `fvm flutter test test/unit/data test/migrations` в момент
   отчёта падает не на assertions, а на компиляции чужого файла (`FilePickerGateway` без
   `saveZipFile`) — это временное состояние параллельной работы; собственный набор
   (`db+decks+cards+migrations`) — 60/60 зелёный.
2. **Upgrade-миграция v1→v2** не проверена: миграций в v1 нет; `onUpgrade` — fail-fast
   (ADR-005). По ADR-005 при появлении `schemaVersion = 2` обязательны шаг миграции,
   dump v2 и upgrade-тест `SchemaVerifier`.
3. **`due`-счётчики `watchSummaries`** вычисляются от момента подписки на стрим: drift
   переизлучает поток только при изменении `decks`/`cards`, а не от течения времени.
   Для UI экрана «Колоды» это значит, что при долгом простое список не сам обновится
   (нужен перезапрос/рефреш при возврате на экран) — отметить в ADR-007/итерации UI.
4. **Семантика счётчиков (уточнить в ADR-007):** `newCards` = карточки `state='new'`,
   `inProgressCards` = `learning`/`relearning` (как в контракте `DeckSummary`), обе считаются
   **без** исключения `suspended` (в контракте исключения оговорены только для `due`:
   `due <= now`, `suspended=0`, `buried_until` не в будущем). `totalCards` — все карточки.
5. **Поиск** реализован в Dart после SQL-выборки (нормализация `ё→е`, пунктуация — SQLite
   не умеет по-русски штатно); для больших библиотек это O(колод), не O(карточек) — приемлемо.
6. **`settings_json`** обязан быть JSON-объектом: иное — `FormatException` (данные пишет только
   приложение); аналогично `tags_json`/`media_json` — JSON-массивы строк.
7. **CI-сборки 5 платформ** не проверены до пуша (native assets; известное ограничение L2/L9).
