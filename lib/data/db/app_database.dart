// Drift-база приложения CardFlow: 10 таблиц SPEC A5, schemaVersion = 1.
//
// Политика миграций — ADR-005:
//  - onCreate: createAll() создаёт таблицы и объявленные индексы;
//  - beforeOpen: `PRAGMA foreign_keys = ON` (иначе не работает `ON DELETE CASCADE`);
//  - onUpgrade на версии 1 — fail-fast: молча «досоздавать» схему нельзя,
//    миграция появится вместе с schemaVersion = 2 (ADR-005).
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// База данных приложения (SPEC A5).
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
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Открывает БД поверх готового drift-исполнителя.
  AppDatabase(super.e);

  /// Тестовая/локальная БД в памяти (`NativeDatabase.memory()`, ADR-005).
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // ADR-005: до появления migration-шага и dump-файла схемы апгрейд
      // запрещён — fail-fast вместо потери данных.
      throw StateError(
        'Миграция БД с версии $from на $to не реализована (ADR-005): '
        'добавьте шаг миграции, dump схемы и upgrade-тест.',
      );
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
