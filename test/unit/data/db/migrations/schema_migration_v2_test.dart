// Тест миграции схемы БД 1 → 2 (TASK «Срез 8», ADR-005 §5, ADR-051).
//
// Проверяется то, что требует DoD среза: миграция **пустой** БД и миграция
// **заполненной** БД. Схема версии 1 берётся не из головы, а из снимка
// `drift_schemas/drift_schema_v1.json` (сгенерированные `schema_v1.dart`/
// `schema_v2.dart`): поэтому тест падает, если шаг миграции разошёлся с dump-ом
// схемы, а не только с ожиданиями автора теста.
//
// Вторая часть — политика ADR-005: понижение версии не поддерживается, а
// апгрейд на версию без шага остаётся fail-fast (данные не теряются молча).
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

/// Строка `decks` версии 1: колода, которая обязана пережить миграцию.
const Map<String, Object?> _deck = <String, Object?>{
  'id': 'deck-1',
  'name': 'Колода до миграции',
  'settings_json': '{"newPerDay":7}',
  'archived_at': null,
  'created_at': 1000,
  'updated_at': 2000,
};

/// Строка `cards` версии 1: карточка с расписанием и хешем.
const Map<String, Object?> _card = <String, Object?>{
  'id': 'card-1',
  'deck_id': 'deck-1',
  'front': 'Вопрос до миграции',
  'back': 'Ответ до миграции',
  'hint': null,
  'card_type': 'basic',
  'tags_json': '["миграция"]',
  'media_json': '[]',
  'latex': null,
  'occlusion_json': null,
  'source_doc_id': null,
  'source_excerpt': 'цитата',
  'state': 'review',
  'fsrs_json': '{"stability":1.0}',
  'due': 5000,
  'suspended': 0,
  'buried_until': null,
  'flagged': 1,
  'sibling_id': null,
  'content_hash': 'hash-1',
  'created_at': 1000,
  'updated_at': 2000,
};

/// Строка `review_logs` версии 1: журнал повторений не должен исчезнуть.
const Map<String, Object?> _reviewLog = <String, Object?>{
  'id': 'log-1',
  'card_id': 'card-1',
  'rating': 3,
  'reviewed_at': 3000,
  'mode': 'classic',
  'recognition_flag': 0,
  'scheduled_days': 2.0,
  'actual_days': 1.0,
  'elapsed_ms': 4200,
};

RawValuesInsertable _raw(Map<String, Object?> values) =>
    RawValuesInsertable(<String, Expression<Object>>{
      for (final MapEntry<String, Object?> entry in values.entries)
        entry.key: Variable<Object>(entry.value),
    });

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('миграция 1 → 2', () {
    test(
      'пустая БД версии 1: схема доходит до 2 и содержит новые таблицы',
      () async {
        final DatabaseConnection connection = await verifier.startAt(1);
        final AppDatabase db = AppDatabase(connection);
        addTearDown(db.close);

        await verifier.migrateAndValidate(db, 2);

        // Новые таблицы прогона генерации реально созданы в БД (а не только в
        // сгенерированном коде).
        for (final String table in <String>[
          'generation_runs',
          'generation_units',
          'generation_batches',
          'card_drafts',
          'knowledge_maps',
        ]) {
          final List<QueryRow> rows = await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
                variables: <Variable<Object>>[Variable<String>(table)],
              )
              .get();
          expect(
            rows,
            hasLength(1),
            reason: 'нет таблицы $table после миграции',
          );
        }
      },
    );

    test('заполненная БД версии 1: данные не потеряны, новые таблицы пусты', () async {
      await verifier.testWithDataIntegrity<v1.DatabaseAtV1, v2.DatabaseAtV2>(
        oldVersion: 1,
        newVersion: 2,
        createOld: v1.DatabaseAtV1.new,
        createNew: v2.DatabaseAtV2.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (Batch batch, v1.DatabaseAtV1 oldDb) {
          batch.insert(oldDb.decks, _raw(_deck));
          batch.insert(oldDb.cards, _raw(_card));
          batch.insert(oldDb.reviewLogs, _raw(_reviewLog));
        },
        validateItems: (v2.DatabaseAtV2 newDb) async {
          // Чтение через `customSelect`: тест сверяет данные, а не формы
          // сгенерированных классов, поэтому формат строк не важен.
          final List<QueryRow> decks = await newDb
              .customSelect('SELECT * FROM decks')
              .get();
          expect(decks, hasLength(1));
          final QueryRow deck = decks.single;
          expect(deck.read<String>('id'), 'deck-1');
          expect(deck.read<String>('name'), 'Колода до миграции');
          expect(deck.read<String>('settings_json'), '{"newPerDay":7}');
          expect(deck.read<int>('created_at'), 1000);
          expect(deck.read<int>('updated_at'), 2000);

          final List<QueryRow> cards = await newDb
              .customSelect('SELECT * FROM cards')
              .get();
          expect(cards, hasLength(1));
          final QueryRow card = cards.single;
          expect(card.read<String>('front'), 'Вопрос до миграции');
          expect(card.read<String>('back'), 'Ответ до миграции');
          expect(card.read<String>('content_hash'), 'hash-1');
          expect(card.read<int>('due'), 5000);
          expect(card.read<int>('flagged'), 1);

          final List<QueryRow> logs = await newDb
              .customSelect('SELECT * FROM review_logs')
              .get();
          expect(logs, hasLength(1));
          expect(logs.single.read<String>('card_id'), 'card-1');
          expect(logs.single.read<int>('rating'), 3);

          // Новые таблицы заполненной БД пусты: миграция ничего не выдумывает.
          for (final String table in <String>[
            'generation_runs',
            'generation_units',
            'generation_batches',
            'card_drafts',
            'knowledge_maps',
          ]) {
            final List<QueryRow> rows = await newDb
                .customSelect('SELECT * FROM $table')
                .get();
            expect(rows, isEmpty, reason: 'таблица $table не пуста');
          }
        },
      );
    });
  });

  group('политика миграций ADR-005', () {
    test('понижение версии — StateError, данные не пересоздаются', () async {
      final AppDatabase db = AppDatabase.inMemory();
      addTearDown(db.close);
      // Открываем БД, чтобы создать схему v2.
      await db.customSelect('SELECT 1').get();

      await expectLater(
        db.migration.onUpgrade(Migrator(db), 2, 1),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Понижение версии'),
          ),
        ),
      );
    });

    test('апгрейд на неизвестную версию — fail-fast StateError', () async {
      final AppDatabase db = AppDatabase.inMemory();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      await expectLater(
        db.migration.onUpgrade(Migrator(db), 2, 3),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('ADR-005'),
          ),
        ),
      );
    });
  });
}
