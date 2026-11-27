// Тест схемы/миграций по drift-инструментам (ADR-005, ADR-051).
//
// Проверяет, что schema dump-файлы `drift_schemas/drift_schema_v1.json` и
// `drift_schema_v2.json` актуальны и совпадают с тем, что создаёт `AppDatabase`
// в приложении. При изменении схемы без новой версии/dump тест краснеет —
// это и есть fail-fast политики миграций ADR-005.
//
// Тест использует `drift_dev` (`SchemaVerifier`) и работает в обычном
// `flutter test`: sqlite3 native assets проверены спайком S3.
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('версия dump-файла совпадает со schemaVersion приложения', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    expect(GeneratedHelper.versions, <int>[1, db.schemaVersion]);
    expect(db.schemaVersion, 2);
  });

  test('dump v1 создаёт 10 таблиц и 3 индекса SPEC A5', () async {
    final schema = await verifier.schemaAt(1);
    addTearDown(schema.close);

    final rows = schema.rawDatabase.select(
      "SELECT type, name FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
    final tables = <String>[];
    final indexes = <String>[];
    for (final row in rows) {
      switch (row['type']) {
        case 'table':
          tables.add(row['name'] as String);
        case 'index':
          indexes.add(row['name'] as String);
      }
    }

    expect(tables, <String>[
      'app_settings',
      'cards',
      'decks',
      'generation_jobs',
      'media',
      'practice_logs',
      'review_logs',
      'session_presets',
      'source_docs',
      'sync_meta',
    ]);
    expect(indexes, <String>[
      'idx_cards_deck_due',
      'idx_cards_hash',
      'idx_review_logs_card',
    ]);
  });

  test('dump v2 добавляет 5 таблиц прогона генерации и уникальный индекс (ADR-051)', () async {
    final schema = await verifier.schemaAt(2);
    addTearDown(schema.close);

    final rows = schema.rawDatabase.select(
      "SELECT type, name FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
    final tables = <String>[];
    final indexes = <String>[];
    for (final row in rows) {
      switch (row['type']) {
        case 'table':
          tables.add(row['name'] as String);
        case 'index':
          indexes.add(row['name'] as String);
      }
    }

    expect(tables, <String>[
      'app_settings',
      'card_drafts',
      'cards',
      'decks',
      'generation_batches',
      'generation_jobs',
      'generation_runs',
      'generation_units',
      'knowledge_maps',
      'media',
      'practice_logs',
      'review_logs',
      'session_presets',
      'source_docs',
      'sync_meta',
    ]);
    expect(indexes, <String>[
      'idx_card_drafts_run_hash',
      'idx_cards_deck_due',
      'idx_cards_hash',
      'idx_review_logs_card',
    ]);
  });

  test(
    'onCreate приложения совпадает со schema dump v2 (таблицы и индексы)',
    () async {
      // Открываем БД «с нуля», как в приложении: работает onCreate + индексы.
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      await appDb.customSelect('SELECT 1').get();

      // Семантическое сравнение фактической схемы с dump-файлом v2:
      // `migrateAndValidate` собирает reference-схему из dump и сравнивает её
      // с текущей схемой уже открытой БД (различия форматирования SQL игнорируются).
      await verifier.migrateAndValidate(appDb, 2);
    },
  );

  test(
    'migrateAndValidate v1 → v2 проходит (схема открывается drift-классом)',
    () async {
      final connection = await verifier.startAt(1);
      final db = AppDatabase(connection);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);
    },
  );
}
