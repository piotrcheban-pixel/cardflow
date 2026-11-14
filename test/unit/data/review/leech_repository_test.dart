import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/review/drift_leech_repository.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/session/leech_repository.dart';

import '../db/test_support.dart';

/// Красная фаза итерации 6: счётчики провалов для фильтра «Пиявки»
/// (SPEC A6.7/A7.17, ADR-018) — только `Again`, только свои колоды.
void main() {
  late AppDatabase db;
  late DriftLeechRepository repository;
  final DateTime now = DateTime.utc(2026, 11, 14, 12);

  setUp(() async {
    db = AppDatabase.inMemory();
    repository = DriftLeechRepository(db);
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Первая',
      createdAt: 0,
      updatedAt: 0,
    );
    await insertDeckRow(
      db,
      id: 'deck-2',
      name: 'Вторая',
      createdAt: 0,
      updatedAt: 0,
    );
    for (final String id in <String>['a', 'b', 'c', 'd']) {
      await insertCardRow(
        db,
        id: id,
        deckId: id == 'd' ? 'deck-2' : 'deck-1',
        front: 'Вопрос $id',
      );
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addLog(String cardId, int rating, {required int index}) async {
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            id: 'log-$cardId-$index',
            cardId: cardId,
            rating: rating,
            reviewedAt: toEpochMs(now),
            mode: 'classic',
          ),
        );
  }

  test('считает только Again и только по своим колодам', () async {
    for (int index = 0; index < 8; index++) {
      await addLog('a', 1, index: index);
    }
    for (int index = 0; index < 7; index++) {
      await addLog('b', 1, index: index);
    }
    for (int index = 0; index < 3; index++) {
      await addLog('c', 3, index: index);
    }
    for (int index = 0; index < 10; index++) {
      await addLog('d', 1, index: index);
    }

    final Map<String, int> counts = await repository.failureCounts(
      deckIds: <String>['deck-1'],
    );

    expect(counts, <String, int>{'a': 8, 'b': 7});
    expect(counts.containsKey('c'), isFalse, reason: 'Good — не провал');
    expect(counts.containsKey('d'), isFalse, reason: 'другая колода');
  });

  test('несколько колод — счётчики всех', () async {
    await addLog('a', 1, index: 0);
    await addLog('d', 1, index: 0);
    await addLog('d', 1, index: 1);

    final Map<String, int> counts = await repository.failureCounts(
      deckIds: <String>['deck-1', 'deck-2'],
    );

    expect(counts, <String, int>{'a': 1, 'd': 2});
  });

  test('пустой список колод — пустая карта', () async {
    await addLog('a', 1, index: 0);

    expect(await repository.failureCounts(deckIds: <String>[]), isEmpty);
  });

  test('порог пиявок — 8 провалов (A7.17)', () {
    expect(leechFailureThreshold, 8);
  });
}
