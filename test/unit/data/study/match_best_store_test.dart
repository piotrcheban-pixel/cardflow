import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/study/drift_match_best_store.dart';

/// Лучшее время «Подбора пар» в app_settings (7.16).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('сохраняет и читает лучшее время по колоде', () async {
    final store = DriftMatchBestStore(db);
    expect(await store.bestMs('deck-1'), isNull);

    await store.saveIfBetter('deck-1', 12000);
    expect(await store.bestMs('deck-1'), 12000);

    await store.saveIfBetter('deck-2', 9000);
    expect(await store.bestMs('deck-1'), 12000);
    expect(await store.bestMs('deck-2'), 9000);
  });

  test('лучший результат не ухудшается', () async {
    final store = DriftMatchBestStore(db);
    await store.saveIfBetter('deck-1', 9000);
    await store.saveIfBetter('deck-1', 15000);
    expect(await store.bestMs('deck-1'), 9000);
    await store.saveIfBetter('deck-1', 7000);
    expect(await store.bestMs('deck-1'), 7000);
  });

  test('битый JSON и неизвестная версия → пусто', () async {
    final store = DriftMatchBestStore(db);
    for (final String value in <String>[
      'битый',
      '{"version":99,"decks":{"deck-1":1000}}',
      '{"version":1,"decks":"oops"}',
    ]) {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: DriftMatchBestStore.settingsKey,
              valueJson: value,
            ),
          );
      expect(await store.bestMs('deck-1'), isNull, reason: value);
    }
  });

  test('нулевой/отрицательный результат не записывается', () async {
    final store = DriftMatchBestStore(db);
    await store.saveIfBetter('deck-1', 0);
    await store.saveIfBetter('deck-1', -5);
    expect(await store.bestMs('deck-1'), isNull);
  });
}
