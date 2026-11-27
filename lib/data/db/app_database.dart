// Drift-база приложения CardFlow: 10 таблиц SPEC A5 + 5 таблиц прогона
// генерации v3 (TASK «Срез 8», ADR-051), schemaVersion = 2.
//
// Политика миграций — ADR-005:
//  - onCreate: createAll() создаёт таблицы и объявленные индексы;
//  - beforeOpen: `PRAGMA foreign_keys = ON` (иначе не работает `ON DELETE CASCADE`);
//  - onUpgrade: шаговая миграция 1 → 2 (новые таблицы прогона генерации),
//    снимок схемы v1 — `drift_schemas/drift_schema_v1.json`; апгрейд на версию
//    без шага и понижение версии — fail-fast StateError (данные не теряются
//    молча); перед миграцией файл БД копируется в `cardflow.sqlite.bak`
//    (`database_opener.dart`).
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// База данных приложения (SPEC A5 + ADR-051).
@DriftDatabase(
  tables: <Type>[
    Decks,
    Cards,
    ReviewLogs,
    PracticeLogs,
    Media,
    SourceDocs,
    SyncMeta,
    GenerationJobs,
    AppSettings,
    SessionPresets,
    GenerationRuns,
    GenerationUnits,
    GenerationBatches,
    CardDrafts,
    KnowledgeMaps,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Открывает БД поверх готового drift-исполнителя.
  AppDatabase(super.e);

  /// Тестовая/локальная БД в памяти (`NativeDatabase.memory()`, ADR-005).
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  /// Версия схемы: 2 — таблицы прогона генерации v3 (ADR-051).
  static const int currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (to < from) {
        // Понижение версии не поддерживается (ADR-005 §5): открытие «новой» БД
        // старым кодом — ошибка, а не повод пересоздать схему.
        throw StateError(
          'Понижение версии БД с $from на $to не поддерживается (ADR-005): '
          'данные не пересоздаются.',
        );
      }
      if (to > currentSchemaVersion) {
        // ADR-005: шага миграции нет — fail-fast вместо потери данных.
        throw StateError(
          'Миграция БД с версии $from на $to не реализована (ADR-005): '
          'добавьте шаг миграции, dump схемы и upgrade-тест.',
        );
      }
      if (from < 2) {
        // ADR-051: новые таблицы прогона генерации. Порядок — по внешним
        // ключам: generation_runs создаётся первой, затем зависимые таблицы и
        // объявленный уникальный индекс черновиков (ключ идемпотентности
        // импорта: `run_id` + `content_hash`).
        await m.createTable(generationRuns);
        await m.createTable(generationUnits);
        await m.createTable(generationBatches);
        await m.createTable(cardDrafts);
        await m.createIndex(idxCardDraftsRunHash);
        await m.createTable(knowledgeMaps);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
