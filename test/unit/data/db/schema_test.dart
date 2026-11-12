// Schema-тест SPEC A5: все 10 таблиц, колонки/типы/NOT NULL/DEFAULT,
// 3 индекса, PRAGMA foreign_keys=ON, каскад, открытие БД (ADR-005).
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
    test('schemaVersion == 1 (ADR-005)', () {
      expect(db.schemaVersion, 1);
    });

    test('созданы ровно 10 таблиц SPEC A5', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get();
      final names = rows.map((row) => row.read<String>('name')).toList();
      expect(names, <String>[
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
  });

  group('SPEC A5: индексы', () {
    test('созданы 3 индекса из A5 с нужными колонками', () async {
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
    test('onUpgrade на версии 1 — fail-fast StateError (ADR-005)', () async {
      await expectLater(
        db.migration.onUpgrade(Migrator(db), 1, 2),
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
  });
}
