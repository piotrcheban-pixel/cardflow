# ADR-051 — Схема БД v2: журнал прогона генерации v3, черновики принятого, кэш карты знаний

**Дата:** 2026-11-28 · **Статус:** принято (срез 8 генерации v3) · **Связано:** SPEC A5, ADR-005 (открытие БД и миграции), ADR-050 (архитектура генерации v3), `docs/generation/ARCH.md` §2 этап 8, §3.5, `docs/generation/BACKLOG.md` S8, `journal/STATE.md` (срез 8), `journal/QUESTIONS.md` Q18

## Контекст

TASK «Срез 8. Persistence» требует:

1. миграцию drift: `generation_runs`, `knowledge_maps`, `generation_units`, `generation_batches`, `card_drafts`, причём `generation_jobs` остаётся совместимым представлением для UI, его поля не удаляются;
2. `CardSink`: черновик пишется в БД в момент принятия карточки (падение на 5-м батче не теряет первые 4);
3. импорт в колоду одной транзакцией, идемпотентный по (`run_id`, `content_hash`);
4. восстановление прогона из БД после перезапуска (состояние, батчи, ledger) и продолжение с места остановки;
5. `KnowledgeMapCache` на БД: повторный запуск того же материала не платит за understanding.

`docs/generation/BACKLOG.md` S8 предполагал более дешёвый вариант — хранить журнал JSON-ом в `generation_jobs` «без изменения схемы БД, staging-таблица — только отдельным ADR». TASK.txt приоритетнее плана (протокол, `journal/STATE.md` срезов 2/3/4/7): он прямо называет пять таблиц и миграцию, а AGENTS.md требует, чтобы изменение схемы шло **вместе с ADR**. Этот ADR — то самое решение; расхождение с BACKLOG зафиксировано в `journal/QUESTIONS.md` Q18.

Ограничения, которые нельзя нарушать (TASK «Не делать» + AGENTS.md):

- не менять существующие таблицы `cards` и `review_logs` (и остальные таблицы SPEC A5);
- не писать ключи API в БД;
- не удалять старые миграции (единственная существующая — создание схемы v1);
- тексты материалов и промпты с материалами не логируются и не дублируются в БД: в новых таблицах хранятся структура прогона, утверждения карты знаний (они уже часть материала, но нужны для восстановления) и цитаты — без ключей, без тел ответов провайдера.

## Варианты

1. **Журнал в JSON-поле `generation_jobs`** (BACKLOG S8). Плюс: схема не меняется. Минусы: нет идемпотентности импорта на уровне БД (ключ `(run_id, content_hash)` пришлось бы проверять в коде под гонку), нет индексируемого восстановления «какие партии выполнены», журнал и черновики пишутся перезаписью одного большого JSON — при падении посреди записи теряется последняя порция принятого, а именно этого требует инвариант ARCH §3.5. Отклонён TASK.txt.
2. **Пять отдельных таблиц + миграция `schemaVersion` 1 → 2** (принят). Плюс: черновик — своя строка в момент принятия (сбой не теряет предыдущие), ключ идемпотентности `(run_id, content_hash)` — уникальный индекс SQLite, восстановление читает партии индексом PK `(run_id, batch_index)`, кэш карты — отдельная таблица с ключом `(document_id, content_hash)`. Минус: нужна миграция и dump схемы (ADR-005 §5).
3. **Не хранить понимание, а пересчитывать всегда** — противоречит п. 5 TASK; отклонён.
4. **Хранить байты изображений в черновиках** — раздувает БД и дублирует файловое хранилище медиа; отклонён: в `card_drafts.card_json` остаются только структура карточки и id каталога `<images>`, изображения разрешаются при импорте.

## Решение

### 1. Схема v2 (`lib/data/db/tables.dart`)

`schemaVersion` = **2**. Добавляются пять таблиц; таблицы SPEC A5 не меняются.

| Таблица | Ключ | Назначение |
|---|---|---|
| `generation_runs` | `id` (= `generation_jobs.id`) | этап стейт-машины (`stage`), статус задания (`status`), провайдер/модель, `deck_id`, версии промптов (`prompt_versions_json`), `created_at`/`updated_at` |
| `generation_units` | `(run_id, unit_id)` | единицы карты знаний прогона: раздел, тема, вид, утверждение, `salience`, `splittable`, якоря (`anchors_json`), `order_index` — без них восстановленная партия не совпадёт с исходной |
| `generation_batches` | `(run_id, batch_index)` | журнал партии: `status` (`pending/running/done/failed`), `requested`, `generated`, `invalid`, `duplicates`, `attempts`, `cause` |
| `card_drafts` | `id`, уникальный `(run_id, content_hash)` | принятая карточка в момент принятия: `card_json` (структура без байтов), `unit_id`, `angle`, `imported_card_id`, `imported_at` |
| `knowledge_maps` | `(document_id, content_hash)` | кэш карты знаний: `map_json` (формат v1), `created_at` |

Внешние ключи `run_id → generation_runs.id` — `ON DELETE CASCADE` (удаление прогона убирает его партии, черновики и единицы; `generation_jobs` не трогается: это представление для истории UI).

### 2. Миграция (`lib/data/db/app_database.dart`)

`onCreate` — `createAll()` (свежая БД сразу v2). `onUpgrade`:

- `to > currentSchemaVersion` — fail-fast `StateError` (ADR-005: без шага миграции данные не «досоздаются»);
- `to < from` — `StateError` (понижение версии не поддерживается, ADR-005 §5);
- `from < 2` — создаются пять таблиц и уникальный индекс `idx_card_drafts_run_hash` (`Migrator.createTable` не создаёт объявленные индексы — индекс создаётся явно; это поймал `SchemaVerifier`, а не ревью).

Снимки схемы — `drift_schemas/drift_schema_v1.json` (существовал) и `drift_schemas/drift_schema_v2.json` (добавлен); по ним сгенерированы `test/unit/data/db/migrations/generated/*` (`schema_v1.dart`, `schema_v2.dart`, `schema_versions.dart`), проверка — `test/unit/data/db/migrations/schema_migration_v2_test.dart` (`SchemaVerifier`, миграция пустой и заполненной БД).

Перед миграцией файловой БД `openAppDatabase` копирует файл в `cardflow.sqlite.bak` (`backupBeforeMigration`, ADR-005 §5: «требование ввести в итерации, где появится первая миграция»). Копия делается только если `PRAGMA user_version` файла старее текущей схемы.

### 3. Слой данных (`lib/data/generation/`)

- `drift_generation_run_store.dart` — `DriftGenerationRunStore`: `openRun` (идемпотентно по `runId`, не сбрасывает принятое), `saveStage`, `saveBatch`, `saveDraft` (`InsertMode.insertOrIgnore` + уникальный индекс), `saveDeckId`, `loadRun` (снимок), `unitsOfRun`, `latestResumableRunId`; `GenerationRunCardSink` — реализация порта `CardSink` с `runId` и часами. Одновременно ведётся `generation_jobs` (строка создаётся вместе с прогоном, `status`/`result_deck_id` синхронизируются) — это и есть «совместимое представление для UI».
- `drift_knowledge_map_cache.dart` — `DriftKnowledgeMapCache implements KnowledgeMapCache<KnowledgeMap>`; повреждённая запись считается промахом (кэш ускоряет, а не мешает).
- `drift_generation_card_store.dart` — `importRunCards`: импорт черновиков прогона **одной транзакцией**, отметки `imported_card_id`/`imported_at` пишутся в той же транзакции, второй рубеж — дедупликация по хешу колоды. `importGeneratedCards` и `importRunCards` делят `_resolveDeck`, `_insertCard`, `_insertMedia`, `_writeImage`.

### 4. Домен (`lib/domain/generation/`)

- `generation_run_snapshot.dart` — `GenerationBatchStatus`, `GenerationBatchRecord`, `RunCardDraft`, `GenerationRunSnapshot` (журнал, `resumeBatchIndex`, `resumeStage`, `isResumable`);
- `run_resume.dart` — `GenerationResumePlan` и `planGenerationResume`: выполненные партии не попадают в план, снимок без единиц карты продолжается с `understanding`, все партии выполнены → `replenishing`;
- `knowledge_map_json.dart`, `generated_card_json.dart` — форматы хранения v1 (строгий разбор, `FormatException` вместо «примерно такой» карты/карточки).

## Последствия

**Плюсы.** Инвариант ARCH §3.5 («сбой не теряет принятое») держится на уровне БД: каждая принятая карточка — своя строка; восстановление читает журнал, а не память; повторный импорт невозможен на уровне схемы (уникальный индекс), а не только «по договорённости»; понимание материала не оплачивается дважды после перезапуска.

**Минусы/ограничения.**

- **Отчёт дедупликации не персистится**: `DedupReport` (пары и уровни) считается заново из карточек и колоды; в БД живёт счётчик `generation_batches.duplicates`. Для вердикта Completion (S9) этого достаточно: он читает числа журнала.
- **Байты изображений не в БД**: черновик хранит структуру и id каталога `<images>`; иллюстрации, разрешённые в байты, доживают до импорта в памяти процесса. После перезапуска картинка разрешается заново (поиск остаётся best effort, ADR-028).
- **`salience` в `generation_units` — REAL без диапазона в CHECK**: диапазон 0..1 проверяет домен при записи/чтении (`KnowledgeUnit`, `knowledge_map_json`), а не SQL.
- Прогоны, созданные до v2, в новых таблицах отсутствуют: история `generation_jobs` остаётся читаемой (старый экран), восстановление доступно только для прогонов v3; старые строки не «дорисовываются».
- Кэш карты знаний растёт: TTL/GC не вводятся в этом срезе (ограничение зафиксировано в `journal/KNOWN_LIMITATIONS.md`).

## Проверка (команды и тесты)

- `.fvm\versions\3.47.9\bin\flutter.bat test --no-pub test/unit/data/db/migrations/schema_migration_v2_test.dart` — миграция пустой и заполненной БД, политика версий (4 теста);
- `... test/unit/data/db/schema_test.dart` — 27 тестов схемы: 15 таблиц, колонки новых таблиц, индекс, backup `cardflow.sqlite.bak`;
- `... test/unit/data/generation/drift_generation_run_store_test.dart` — 12 тестов: черновик в момент принятия, «упал после четырёх батчей → восстановление с пятого», журнал партии, `latestResumableRunId`, совместимость `generation_jobs`;
- `... test/unit/data/generation/drift_run_import_test.dart` — 5 тестов: один транзакционный импорт, двойной импорт, сбой без полуимпорта;
- `... test/unit/data/generation/drift_knowledge_map_cache_test.dart` — 12 тестов: кэш на БД + сквозной `UnderstandingService` (второй прогон не вызывает модель).

## Источники

- TASK.txt «Срез 8. Persistence: черновики, миграция, идемпотентный импорт»;
- `docs/generation/ARCH.md` §2 (этап 8), §3.5; `docs/generation/BACKLOG.md` S8;
- ADR-005 (открытие БД, политика миграций, `.bak`), ADR-050 (генерация v3);
- drift `SchemaVerifier` — https://drift.simonbinder.eu/docs/migrations/tests/
