# ADR-005 — Открытие SQLite: drift + `NativeDatabase` (native assets), без `drift_flutter`

**Дата:** 2026-11-12 · **Статус:** принято (итерация 1) · **Связано:** SPEC A5, A1 (local-first); `AGENTS.md`; `docs/dependencies.md` §2/§7; ADR-002; `journal/iteration-1/plan.md` §1 (задача 1.3)

## Контекст

SPEC A3/A5 требует SQLite + `drift` как хранилище «local-first». В итерации 0 пакет `drift 2.35.4` уже в `pubspec.yaml`, нативный SQLite — `sqlite3 3.9.1`; `drift_flutter` осознанно **не** добавлялся, потому что тянет EOL-заглушку `sqlite3_flutter_libs 0.6.0+eol` (см. `docs/dependencies.md` §7). Открытие БД и стратегия миграций были отложены на итерацию 1.

Вопросы, которые требовали решения:

1. Чем открывать БД на 5 платформах: `drift_flutter` (официальная рекомендация drift), `sqlite3_flutter_libs` (EOL), или вручную `NativeDatabase` поверх `sqlite3` 3.x (native assets / Dart build hooks).
2. Как тестировать БД в `flutter test` без платформенных плагинов.
3. Какая стратегия версий схемы и миграций на старте.

## Что проверено (факты, итерация 1)

- **Спайк S3 выполнен:** `fvm dart run tool/spike_sqlite.dart` → `sqlite3.version = libVersion 3.54.1` и чтение строки `привет` из `sqlite3.openInMemory()` («СПАЙК OK»). Тот же код внутри `fvm flutter test` → `All tests passed`; при запуске строка «Running build hooks...» подтверждает сборку native assets.
- Вывод: `sqlite3 3.9.1` сам поставляет нативную библиотеку через Dart hooks; `flutter test` (Dart VM) и `dart run` её видят. Плагинные библиотеки (`sqlite3_flutter_libs`) не нужны.
- `drift 2.35.4` предоставляет `package:drift/native.dart` (`NativeDatabase`, `NativeDatabase.memory`, `NativeDatabase.createInBackground`) — совместимо с `sqlite3` 3.x.
- `path_provider 2.1.6` уже в зависимостях (approved, `docs/dependencies.md` §2) — каталог данных приложения доступен без новых пакетов.

## Варианты

1. **`drift_flutter 0.3.1`** — официальный helper: открывает БД в нужном каталоге сам. Минус: тянет EOL-заглушки (`sqlite3_flutter_libs 0.6.0+eol`), которые больше не используются и создают лишний шум в guard/аудите зависимостей; поведение на desktop-платформах всё равно требует проверки. Отклонён.
2. **`drift` + `sqlite3_flutter_libs 0.6.0+eol` вручную** — устаревший способ; пакет помечен «Not used anymore». Отклонён.
3. **`drift` + `NativeDatabase` + `sqlite3 3.9.1` + `path_provider`** — минимум зависимостей, официальный API drift, native assets доказаны спайком. **Принят.**
4. **Отказаться от drift и писать SQL вручную** — противоречит SPEC A3 («SQLite + drift»), теряем типобезопасность/миграции. Отклонён.

## Решение

1. **Открытие БД:** `lib/data/db/database_opener.dart` → `Future<AppDatabase> openAppDatabase()`:
   - `path_provider.getApplicationSupportDirectory()` → подкаталог `cardflow` → файл `cardflow.sqlite`;
   - `NativeDatabase.createInBackground(file)` (I/O в фоновом изоляте, UI не блокируется);
   - `AppDatabase` — drift-класс, `schemaVersion = 1`.
2. **Тесты:** `AppDatabase.inMemory()` (`NativeDatabase.memory()`) в `flutter test`; никаких плагинов в unit-тестах. Это доказано спайком S3 и будет закреплено schema-тестом.
3. **Схема:** в версии 1 создаются **все 10 таблиц и 3 индекса SPEC A5** (`decks, cards, review_logs, practice_logs, media, source_docs, sync_meta, generation_jobs, app_settings, session_presets`; `idx_cards_deck_due`, `idx_cards_hash`, `idx_review_logs_card`). Пустые до своих итераций таблицы создаются заранее — это дешевле, чем миграции «на каждый экран»; `sync_meta` по SPEC A9 создаётся заранее, логика не пишется.
4. **`PRAGMA foreign_keys = ON`** в `beforeOpen`; каскад `cards.deck_id ... ON DELETE CASCADE` работает только при включённых FK, поэтому это обязательный шаг (тест каскада — в `test/unit/data/db/schema_test.dart`).
5. **Политика миграций:**
   - `onUpgrade` на версии 1 — **fail-fast** (`StateError`): молча «досоздавать» схему нельзя, иначе данные потеряются незаметно;
   - при появлении `schemaVersion = 2` обязательны: шаговая миграция (`stepByStep`/ручной `onUpgrade`), **dump-файл схемы** v1 в `drift_schemas/` и upgrade-тест (drift `SchemaVerifier`) на сохранение данных;
   - `schemaVersion` поднимается одним PR/итерацией вместе с миграцией;
   - понижение версии не поддерживается (открытие «старой» БД новой версией — ошибка пользователя, сообщение из ARB);
   - backup: файл БД перед миграцией копируется в `cardflow.sqlite.bak` (требование ввести в итерации, где появится первая миграция; сейчас не пишется — миграций нет).
6. **Тестовые данные:** репозитории принимают `AppDatabase`; тесты используют `AppDatabase.inMemory()` и закрывают БД в `tearDown`.

## Последствия

**Плюсы:** нет EOL-зависимостей; один механизм на всех платформах; БД тестируется в обычном `flutter test` без плагинов; каталог данных стандартный для каждого ОС; drift-миграции остаются типобезопасными.

**Минусы/риски:** (а) native assets — относительно новая механика, в CI-сборках (linux/windows/macos/android/ios) подтвердится только при пуше и прогоне CI — до этого известное ограничение L2/L9; (б) `createInBackground` не используется в тестах (in-memory), что нормально; (в) fail-fast `onUpgrade` означает, что до реализации миграций апгрейд версии схемы физически невозможен — это осознанно (защита от потери данных); (г) файл БД в `getApplicationSupportDirectory` не попадает в пользовательские документы — экспорт/бэкап остаётся через `.zip` (ADR-006).

## Источники

- Спайк S3: код и вывод — `journal/iteration-1/plan.md` §0; воспроизведение — тесты `test/unit/data/db/schema_test.dart`.
- drift docs: https://drift.simonbinder.eu/ · `NativeDatabase` — `package:drift/native.dart`
- `sqlite3` 3.x native assets: https://pub.dev/packages/sqlite3
- `path_provider`: https://pub.dev/packages/path_provider
- SPEC A5 (схема), A9 (`sync_meta` заранее), A1 (local-first)

## Addendum (итерация 1, покрытие)

`tool/coverage_check.dart` исключает из расчёта покрытия `lib/data/db/tables.dart` — декларативный drift-DSL: геттеры колонок в рантайме не исполняются (drift генерирует `$...Table` с полями `GeneratedColumn`, перекрывающими геттеры), поэтому у файла законные 0/89 строк. Порог покрытия не понижается: исполняемый код итерации 1 покрыт на 95,9% (1615/1684, включая UI), а сама схема проверяется отдельно schema-тестом по `PRAGMA`/`sqlite_master` (`test/unit/data/db/schema_test.dart`). Исключение задокументировано в комментарии `tool/coverage_check.dart`.