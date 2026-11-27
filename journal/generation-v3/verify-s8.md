# Verify — срез 8: Persistence (черновики, миграция, идемпотентный импорт)

**Дата:** 2026-11-28 · **Ветка:** `main` · **Старт:** `HEAD = 44073be` (docs среза 7)
**Контракт:** `TASK.txt` «Срез 8», `docs/generation/ARCH.md` (уточнение среза 8),
ADR-051, `journal/QUESTIONS.md` Q18.

## 1. Что требовалось (TASK.txt)

1. Миграция drift: `generation_runs`, `knowledge_maps`, `generation_units`,
   `generation_batches`, `card_drafts`; `generation_jobs` остаётся совместимым
   представлением для UI, его поля не удаляются.
2. `CardSink`: черновик пишется в БД в момент принятия карточки; падение на 5-м
   батче не теряет первые 4.
3. Импорт в колоду — одной транзакцией, идемпотентно по (`run_id`,
   `content_hash`); повторный импорт не создаёт дублей.
4. Восстановление прогона из БД после перезапуска (состояние, батчи, ledger) и
   продолжение с места остановки, а не с начала.
5. `KnowledgeMapCache` на БД: повторный запуск того же материала не платит за
   understanding.

**Не делать:** не менять `cards`/`review_logs`, не писать ключи в БД, не удалять
старые миграции.

**DoD:** тест миграции с пустой и заполненной БД; тест «упал после 4 батчей →
восстановление продолжает с 5-го»; тест двойного импорта; тест кэша карты
знаний; тесты на in-memory drift.

## 2. Как закрыто

| Требование | Реализация | Тест |
|---|---|---|
| 1. Миграция | `lib/data/db/tables.dart` (5 таблиц), `app_database.dart` (`schemaVersion = 2`, `onUpgrade` 1 → 2, `createTable` + `createIndex`), dump `drift_schemas/drift_schema_v2.json`, `.bak` перед миграцией (`database_opener.dart`) | `schema_migration_v2_test.dart` (4), `test/migrations/migration_test.dart` (5), `schema_test.dart` (27) |
| 2. CardSink | `GenerationRunCardSink` + `DriftGenerationRunStore.saveDraft` (строка на карточку в момент принятия, `insertOrIgnore` по уникальному индексу) | `drift_generation_run_store_test.dart`: «упал после четырёх батчей — первые четыре в БД», «повторное принятие не создаёт второй черновик» |
| 3. Идемпотентный импорт | `DriftGenerationCardStore.importRunCards` — одна транзакция, ключ (`run_id`, `content_hash`) уникальным индексом, отметки в той же транзакции | `drift_run_import_test.dart` (5): двойной импорт, сбой без полуимпорта, второй прогон |
| 4. Восстановление | `GenerationRunSnapshot` (`resumeBatchIndex`, `resumeStage`, `isResumable`) + `planGenerationResume`; `loadRun`, `unitsOfRun`, `latestResumableRunId` | `drift_generation_run_store_test.dart`: «продолжение — с пятой партии», журнал партии после перезапуска, без единиц → `understanding`, завершённый не восстанавливается |
| 5. Кэш карты знаний | `DriftKnowledgeMapCache` (`knowledge_maps`, JSON v1), `knowledge_map_json.dart` | `drift_knowledge_map_cache_test.dart` (12), в т.ч. `UnderstandingService` на DB-кэше: второй прогон `callCount` не растёт |

## 3. Гейты (вывод команд этой сессии)

- `flutter analyze --no-pub lib test` → **No issues found!**
- `dart format --set-exit-if-changed lib test` → **681 files, 0 changed**
- `flutter test --no-pub --exclude-tags golden` → **3109 passed + 17 skipped**,
  `exit 0` (baseline 3073 + 17 skipped; +36 тестов)
- DoD-команды:
  - `flutter test --no-pub test/unit/data/db/migrations/schema_migration_v2_test.dart` → 4 passed;
  - `flutter test --no-pub test/unit/data/generation/drift_generation_run_store_test.dart` → 12 passed;
  - `flutter test --no-pub test/unit/data/generation/drift_run_import_test.dart` → 5 passed;
  - `flutter test --no-pub test/unit/data/generation/drift_knowledge_map_cache_test.dart` → 12 passed.

## 4. Красная фаза (что падало до фикса)

- `SchemaVerifier` на миграции 1 → 2: `Schema does not match`, `comparing
  idx_card_drafts_run_hash: The actual schema does not contain anything with this
  name` — `Migrator.createTable` не создаёт объявленные индексы. Фикс:
  `m.createIndex(idxCardDraftsRunHash)` в шаге миграции.
- `drift_generation_run_store_test`: `Bad state: Too many elements` на
  `snapshot.batches.single` — тест ожидал одну партию при шести бюджетах;
  исправлено ожидание теста (не ослабление: проверяется `batches.first`).
- `test/migrations/migration_test.dart` (legacy, версия dump-файла) покраснел
  после `schemaVersion = 2` — тест обновлён: `versions == [1, 2]`, добавлен
  dump v2 (15 таблиц, 4 индекса), `migrateAndValidate` теперь до v2.

## 5. Найденные и осознанно оставленные ограничения

- Отчёт дедупликации не персистится (`L219`), байты изображений черновиков не
  пишутся (`L220`), кэш карты знаний без TTL/GC (`L221`).
- Новые таблицы не «дорисовывают» старые прогоны: история `generation_jobs`
  читается UI, восстановление — только для прогонов v3.
- Подключение к конвейеру/UI — S9 (протокол §9).

## 6. Чем проверено, кроме тестов

- `drift_schemas/drift_schema_v2.json` сгенерирован `drift_dev schema dump`
  из `AppDatabase` (не руками); снимок v1 не изменялся.
- Миграция **заполненной** БД проверена на настоящей схеме v1
  (`SchemaVerifier.testWithDataIntegrity`): `decks`, `cards`, `review_logs`
  сохранены, новые таблицы пусты.
- Файловая БД версии 1: появляется `cardflow.sqlite.bak` с данными «до»
  (в копии только `decks` и `user_version = 1`), после миграции данные на месте.
