import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/domain/scheduling/scheduling_card.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../unit/data/db/test_support.dart';

/// Итерация 7 на production-графе и реальной drift-БД (B6; урок M5).
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
  });

  test('настройки → app_settings → планировщик (шаги обучения)', () async {
    final AppSettings initial = await container.read(
      appSettingsProvider.future,
    );
    expect(initial, AppSettings.defaults);

    final AppSettings custom = initial.copyWith(
      learningSteps: <Duration>[Duration(minutes: 5)],
      desiredRetention: 0.8,
      dailyNewLimit: 2,
    );
    await container.read(appSettingsProvider.notifier).save(custom);

    final AppSettingRow row = await (db.select(
      db.appSettings,
    )..where((table) => table.key.equals('app.settings'))).getSingle();
    expect(jsonDecode(row.valueJson)['desired_retention'], 0.8);

    final Scheduler scheduler = container.read(schedulerProvider);
    final DateTime now = DateTime.utc(2026, 11, 14, 12);
    final SchedulingCard card = SchedulingCard.newCard(
      cardId: 'card-1',
      now: now,
    );
    expect(
      scheduler.previewIntervals(card, now: now)[Rating.again],
      const Duration(minutes: 5),
    );
    expect(container.read(effectiveAppSettingsProvider).dailyNewLimit, 2);
  });

  test(
    'статистика на реальной БД: удержание, слабая тема, прогноз, токены',
    () async {
      final DateTime today = DateTime.now();
      final DateTime day = DateTime(today.year, today.month, today.day);
      await insertDeckRow(
        db,
        id: 'deck-1',
        name: 'Колода',
        createdAt: 0,
        updatedAt: 0,
      );
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        tagsJson: jsonEncode(<String>['алгебра']),
        state: 'review',
        due: toEpochMs(day.add(const Duration(days: 2, hours: 9))),
      );
      for (int index = 0; index < 5; index++) {
        await db
            .into(db.reviewLogs)
            .insert(
              ReviewLogsCompanion.insert(
                id: 'review-$index',
                cardId: 'card-1',
                rating: index < 2 ? 1 : 3,
                reviewedAt: toEpochMs(day.subtract(Duration(days: index))),
                mode: 'classic',
                recognitionFlag: const Value<int>(0),
              ),
            );
      }
      await db
          .into(db.generationJobs)
          .insert(
            GenerationJobsCompanion.insert(
              id: 'job-1',
              status: 'done',
              createdAt: toEpochMs(day),
              tokensUsed: const Value<int?>(777),
            ),
          );

      final StatisticsSnapshot snapshot = await container.read(
        statisticsProvider.future,
      );
      expect(snapshot.reviews30, 5);
      expect(snapshot.remembered30, 3);
      expect(snapshot.retention30, closeTo(3 / 5, 1e-9));
      expect(snapshot.weakTopics.single.tag, 'алгебра');
      expect(snapshot.weakTopics.single.errors, 2);
      expect(snapshot.forecast[2].due, 1);

      expect(await container.read(weeklyTokensProvider.future), 777);
    },
  );
}
