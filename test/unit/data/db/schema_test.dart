// Schema-тест SPEC A5: 10 таблиц A5 + 5 таблиц прогона генерации (ADR-051),
// колонки/типы/NOT NULL/DEFAULT, индексы, PRAGMA foreign_keys=ON, каскад,
// открытие БД (ADR-005).
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_opener.dart';

import 'test_support.dart';

/// Описание колонки в человекочитаемом виде для сравнения с SPEC A5.
String _describeColumn(QueryRow row) {
  final name = row.read<String>('name');
  final type = row.read<String>('type');
  final notNull = row.read<int>('notnull') != 0;
  final pk = row.read<int>('pk') != 0;
  final defaultValue = row.readNullable<String>('dflt_value');
  final parts = <String>[name, type];
  if (notNull) parts.add('NOT NULL');
  if (pk) parts.add('PK');
  if (defaultValue != null) parts.add('DEFAULT $defaultValue');
  return parts.join(' ');
}

Future<List<String>> _columnsOf(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map(_describeColumn).toList();
}

void main() {
  late AppDatabase db;

  setUpAll(() {
    // Schema-тесты намеренно открывают несколько независимых БД одновременно
    // (in-memory + файловая из openAppDatabase): предупреждение drift о
    // «multiple databases» здесь ложное — исполнители друг другу не мешают.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('SPEC A5: таблицы и колонки', () {
    test('schemaVersion == 2 (ADR-051: таблицы прогона генерации)', () {
      expect(db.schemaVersion, 2);
    });

    test('созданы 10 таблиц SPEC A5 и 5 таблиц прогона генерации', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get();
      final names = rows.map((row) => row.read<String>('name')).toList();
      expect(names, <String>[
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
    });

    test('decks: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'decks'), <String>[
        'id TEXT NOT NULL PK',
        'name TEXT NOT NULL',
        "settings_json TEXT NOT NULL DEFAULT '{}'",
        'archived_at INTEGER',
        'created_at INTEGER NOT NULL',
        'updated_at INTEGER NOT NULL',
      ]);
    });

    test('cards: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'cards'), <String>[
        'id TEXT NOT NULL PK',
        'deck_id TEXT NOT NULL',
        'front TEXT NOT NULL',
        'back TEXT NOT NULL',
        'hint TEXT',
        'card_type TEXT NOT NULL',
        "tags_json TEXT NOT NULL DEFAULT '[]'",
        "media_json TEXT NOT NULL DEFAULT '[]'",
        'latex TEXT',
        'occlusion_json TEXT',
        'source_doc_id TEXT',
        'source_excerpt TEXT',
        'state TEXT NOT NULL',
        'fsrs_json TEXT',
        'due INTEGER',
        'suspended INTEGER NOT NULL DEFAULT 0',
        'buried_until INTEGER',
        'flagged INTEGER NOT NULL DEFAULT 0',
        'sibling_id TEXT',
        'content_hash TEXT',
        'created_at INTEGER NOT NULL',
        'updated_at INTEGER NOT NULL',
      ]);
    });

    test('review_logs: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'review_logs'), <String>[
        'id TEXT NOT NULL PK',
        'card_id TEXT NOT NULL',
        'rating INTEGER NOT NULL',
        'reviewed_at INTEGER NOT NULL',
        'mode TEXT NOT NULL',
        'recognition_flag INTEGER NOT NULL DEFAULT 0',
        'scheduled_days REAL',
        'actual_days REAL',
        'elapsed_ms INTEGER',
      ]);
    });

    test('practice_logs: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'practice_logs'), <String>[
        'id TEXT NOT NULL PK',
        'card_id TEXT NOT NULL',
        'mode TEXT NOT NULL',
        'reviewed_at INTEGER NOT NULL',
      ]);
    });

    test('media: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'media'), <String>[
        'id TEXT NOT NULL PK',
        'card_id TEXT NOT NULL',
        'path TEXT NOT NULL',
        'mime_type TEXT NOT NULL',
        'size INTEGER NOT NULL',
      ]);
    });

    test('source_docs: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'source_docs'), <String>[
        'id TEXT NOT NULL PK',
        'deck_id TEXT NOT NULL',
        'path TEXT NOT NULL',
        'title TEXT NOT NULL',
      ]);
    });

    test('sync_meta: колонки соответствуют A5 (без PK, post-MVP)', () async {
      expect(await _columnsOf(db, 'sync_meta'), <String>[
        'device_id TEXT',
        'last_sync_hlc TEXT',
      ]);
    });

    test('generation_jobs: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'generation_jobs'), <String>[
        'id TEXT NOT NULL PK',
        'status TEXT NOT NULL',
        'created_at INTEGER NOT NULL',
        'provider TEXT',
        'model TEXT',
        'tokens_used INTEGER',
        'prompt_version TEXT',
        'error_code TEXT',
        'cards_count INTEGER',
        'chunk_count INTEGER',
        'files_json TEXT',
        'result_deck_id TEXT',
      ]);
    });

    test('app_settings: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'app_settings'), <String>[
        'key TEXT NOT NULL PK',
        'value_json TEXT NOT NULL',
      ]);
    });

    test('session_presets: колонки соответствуют A5', () async {
      expect(await _columnsOf(db, 'session_presets'), <String>[
        'id TEXT NOT NULL PK',
        'name TEXT NOT NULL',
        'config_json TEXT NOT NULL',
        'created_at INTEGER NOT NULL',
      ]);
    });

    test('generation_runs: колонки соответствуют ADR-051', () async {
      expect(await _columnsOf(db, 'generation_runs'), <String>[
        'id TEXT NOT NULL PK',
        'stage TEXT NOT NULL',
        'status TEXT NOT NULL',
        'created_at INTEGER NOT NULL',
        'updated_at INTEGER NOT NULL',
        'provider TEXT',
        'model TEXT',
        'deck_id TEXT',
        'prompt_versions_json TEXT',
      ]);
    });

    test('generation_units: колонки соответствуют ADR-051', () async {
      expect(await _columnsOf(db, 'generation_units'), <String>[
        'run_id TEXT NOT NULL PK',
        'unit_id TEXT NOT NULL PK',
        'section_id TEXT NOT NULL',
        'topic TEXT NOT NULL',
        'kind TEXT NOT NULL',
        'statement TEXT NOT NULL',
        'salience REAL NOT NULL',
        'splittable INTEGER NOT NULL',
        'anchors_json TEXT NOT NULL',
        'order_index INTEGER NOT NULL',
      ]);
    });

    test('generation_batches: колонки соответствуют ADR-051', () async {
      expect(await _columnsOf(db, 'generation_batches'), <String>[
        'run_id TEXT NOT NULL PK',
        'batch_index INTEGER NOT NULL PK',
        'status TEXT NOT NULL',
        'requested INTEGER NOT NULL',
        'generated INTEGER NOT NULL DEFAULT 0',
        'invalid INTEGER NOT NULL DEFAULT 0',
        'duplicates INTEGER NOT NULL DEFAULT 0',
        'attempts INTEGER NOT NULL DEFAULT 0',
        'cause TEXT',
      ]);
    });

    test('card_drafts: колонки соответствуют ADR-051', () async {
      expect(await _columnsOf(db, 'card_drafts'), <String>[
        'id TEXT NOT NULL PK',
        'run_id TEXT NOT NULL',
        'batch_index INTEGER NOT NULL',
        'content_hash TEXT NOT NULL',
        'unit_id TEXT',
        'angle TEXT',
        'card_json TEXT NOT NULL',
        'created_at INTEGER NOT NULL',
        'imported_card_id TEXT',
        'imported_at INTEGER',
      ]);
    });

    test('knowledge_maps: колонки соответствуют ADR-051', () async {
      expect(await _columnsOf(db, 'knowledge_maps'), <String>[
        'document_id TEXT NOT NULL PK',
        'content_hash TEXT NOT NULL PK',
        'map_json TEXT NOT NULL',
        'created_at INTEGER NOT NULL',
      ]);
    });
  });

  group('SPEC A5: индексы', () {
    test('созданы индексы A5 и уникальный индекс черновиков ADR-051', () async {
      final rows = await db
          .customSelect(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type = 'index' AND name NOT LIKE 'sqlite_autoindex_%' "
            "ORDER BY name",
          )
          .get();
      final byName = <String, String>{
        for (final row in rows)
          row.read<String>('name'): row.read<String>('tbl_name'),
      };
      expect(byName, <String, String>{
        'idx_card_drafts_run_hash': 'card_drafts',
        'idx_cards_deck_due': 'cards',
        'idx_cards_hash': 'cards',
        'idx_review_logs_card': 'review_logs',
      });

      Future<List<String>> indexColumns(String index) async {
        final info = await db.customSelect('PRAGMA index_info($index)').get();
        return info.map((row) => row.read<String>('name')).toList();
      }

      expect(await indexColumns('idx_cards_deck_due'), <String>[
        'deck_id',
        'due',
      ]);
      expect(await indexColumns('idx_cards_hash'), <String>[
        'deck_id',
        'content_hash',
      ]);
      expect(await indexColumns('idx_review_logs_card'), <String>['card_id']);
      expect(await indexColumns('idx_card_drafts_run_hash'), <String>[
        'run_id',
        'content_hash',
      ]);
    });
  });

  group('SPEC A5: внешние ключи и каскад', () {
    test('PRAGMA foreign_keys включён (ADR-005)', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });

    test('cards.deck_id ссылается на decks.id с ON DELETE CASCADE', () async {
      final rows = await db
          .customSelect('PRAGMA foreign_key_list(cards)')
          .get();
      expect(rows, hasLength(1));
      final fk = rows.single;
      expect(fk.read<String>('table'), 'decks');
      expect(fk.read<String>('from'), 'deck_id');
      expect(fk.read<String>('to'), 'id');
      expect(fk.read<String>('on_delete'), 'CASCADE');
    });

    test('карточка с несуществующей колодой отклоняется FK', () async {
      await expectLater(
        insertCardRow(db, id: 'card-x', deckId: 'нет-такой-колоды'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('удаление колоды каскадно удаляет её карточки', () async {
      await insertDeckRow(
        db,
        id: 'deck-1',
        name: 'Колода',
        createdAt: 1,
        updatedAt: 1,
      );
      await insertCardRow(db, id: 'card-1', deckId: 'deck-1');
      await insertCardRow(db, id: 'card-2', deckId: 'deck-1');

      await (db.delete(db.decks)..where((t) => t.id.equals('deck-1'))).go();

      expect(await db.select(db.decks).get(), isEmpty);
      expect(await db.select(db.cards).get(), isEmpty);
    });
  });

  group('открытие БД (ADR-005)', () {
    test('onUpgrade на неизвестную версию — fail-fast StateError', () async {
      // Миграция 1 → 2 реализована (ADR-051); fail-fast остаётся для версий
      // без шага миграции: данные не «досоздаются» молча.
      await expectLater(
        db.migration.onUpgrade(Migrator(db), 2, 3),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('ADR-005'),
          ),
        ),
      );
    });

    test(
      'AppDatabase.inMemory() создаёт схему и повторно открывается',
      () async {
        final first = AppDatabase.inMemory();
        await insertDeckRow(
          first,
          id: 'deck-1',
          name: 'Первая',
          createdAt: 1,
          updatedAt: 1,
        );
        await first.close();

        final second = AppDatabase.inMemory();
        addTearDown(second.close);
        expect(await second.select(second.decks).get(), isEmpty);
        await insertDeckRow(
          second,
          id: 'deck-2',
          name: 'Вторая',
          createdAt: 2,
          updatedAt: 2,
        );
        final decks = await second.select(second.decks).get();
        expect(decks.map((row) => row.name), <String>['Вторая']);
      },
    );

    test('openAppDatabase() создаёт файл в подкаталоге cardflow и переоткрывает данные', () async {
      final tempDir = await Directory.systemTemp.createTemp('cardflow-db-test');
      addTearDown(() async {
        await tempDir.delete(recursive: true);
      });

      final first = await openAppDatabase(baseDirectory: tempDir);
      await insertDeckRow(
        first,
        id: 'deck-1',
        name: 'Испанский',
        createdAt: 1,
        updatedAt: 1,
      );
      await first.close();

      final expectedFile = File(
        '${tempDir.path}${Platform.pathSeparator}cardflow'
        '${Platform.pathSeparator}cardflow.sqlite',
      );
      expect(expectedFile.existsSync(), isTrue);

      final reopened = await openAppDatabase(baseDirectory: tempDir);
      addTearDown(reopened.close);
      final decks = await reopened.select(reopened.decks).get();
      expect(decks.map((row) => row.name), <String>['Испанский']);
    });

    test(
      'файл БД версии 1 копируется в .bak и мигрирует с данными (ADR-005 §5)',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('cardflow-db-v1');
        addTearDown(() async {
          await tempDir.delete(recursive: true);
        });
        final Directory dataDirectory = Directory(
          '${tempDir.path}${Platform.pathSeparator}cardflow',
        )..createSync(recursive: true);
        final File dbFile = File(
          '${dataDirectory.path}${Platform.pathSeparator}cardflow.sqlite',
        );

        // Файл «старой» версии: таблица колод периода schemaVersion = 1.
        final Database v1 = sqlite3.open(dbFile.path);
        v1.execute('''
        CREATE TABLE decks (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          settings_json TEXT NOT NULL DEFAULT '{}',
          archived_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
        v1.execute('''
        INSERT INTO decks (id, name, created_at, updated_at)
        VALUES ('deck-old', 'Колода версии 1', 1, 1)
      ''');
        v1.execute('PRAGMA user_version = 1');
        v1.close();

        final AppDatabase db = await openAppDatabase(baseDirectory: tempDir);
        addTearDown(db.close);

        final File backup = File('${dbFile.path}$appDatabaseBackupSuffix');
        expect(backup.existsSync(), isTrue, reason: 'копия до миграции');

        // Копия — именно состояние «до»: в ней нет новых таблиц.
        final Database snapshot = sqlite3.open(backup.path);
        addTearDown(snapshot.close);
        final List<String> backupTables = snapshot
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toList();
        expect(backupTables, <String>['decks']);
        expect(snapshot.select('PRAGMA user_version').first.columnAt(0), 1);

        // Данные на месте, миграция выполнена.
        final List<DeckRow> decks = await db.select(db.decks).get();
        expect(decks.map((row) => row.name), <String>['Колода версии 1']);
        final List<QueryRow> tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'generation_runs'",
            )
            .get();
        expect(tables, hasLength(1));
      },
    );

    test('актуальная БД не копируется повторно при каждом старте', () async {
      final tempDir = await Directory.systemTemp.createTemp('cardflow-db-v2');
      addTearDown(() async {
        await tempDir.delete(recursive: true);
      });
      final AppDatabase first = await openAppDatabase(baseDirectory: tempDir);
      await first.close();

      final File dbFile = File(
        '${tempDir.path}${Platform.pathSeparator}cardflow'
        '${Platform.pathSeparator}cardflow.sqlite',
      );
      final File backup = File('${dbFile.path}$appDatabaseBackupSuffix');
      expect(backup.existsSync(), isFalse);

      final AppDatabase second = await openAppDatabase(baseDirectory: tempDir);
      addTearDown(second.close);
      expect(backup.existsSync(), isFalse);
    });
  });
}
