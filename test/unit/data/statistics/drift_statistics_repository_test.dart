import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/statistics/drift_statistics_repository.dart';
import 'package:cardflow/domain/statistics/statistics.dart';

import '../db/test_support.dart';

void main() {
  late AppDatabase db;
  late DriftStatisticsRepository repository;
  final DateTime now = DateTime(2026, 11, 14, 12);
  final DateTime today = DateTime(2026, 11, 14);

  setUp(() {
    db = AppDatabase.inMemory();
    repository = DriftStatisticsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertReview({
    required String id,
    required String cardId,
    required int rating,
    required DateTime at,
  }) {
    return db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            id: id,
            cardId: cardId,
            rating: rating,
            reviewedAt: toEpochMs(at),
            mode: 'classic',
            recognitionFlag: const Value<int>(0),
          ),
        );
  }

  Future<void> insertGenerationJob({
    required String id,
    required DateTime at,
    int? tokensUsed,
  }) {
    return db
        .into(db.generationJobs)
        .insert(
          GenerationJobsCompanion.insert(
            id: id,
            status: 'done',
            createdAt: toEpochMs(at),
            tokensUsed: Value<int?>(tokensUsed),
          ),
        );
  }

  group('DriftStatisticsRepository — пустая БД', () {
    test('нулевой снимок без исключений', () async {
      final StatisticsSnapshot snapshot = await repository.load(now: now);
      expect(snapshot.isEmpty, isTrue);
      expect(snapshot.retention30, isNull);
      expect(snapshot.heatmap.length, 365);
      expect(snapshot.weakTopics, isEmpty);
      expect(await repository.tokensUsedSince(now), 0);
    });
  });

  group('DriftStatisticsRepository — данные', () {
    setUp(() async {
      await insertDeckRow(
        db,
        id: 'deck-1',
        name: 'Колода',
        createdAt: 0,
        updatedAt: 0,
      );
      await insertCardRow(
        db,
        id: 'card-math',
        deckId: 'deck-1',
        tagsJson: jsonEncode(<String>['математика', 'экзамен']),
        state: 'review',
        due: toEpochMs(DateTime(2026, 11, 16, 9)),
      );
      await insertCardRow(
        db,
        id: 'card-bio',
        deckId: 'deck-1',
        tagsJson: jsonEncode(<String>['биология']),
        state: 'review',
        due: toEpochMs(DateTime(2026, 11, 11, 9)),
      );
      await insertCardRow(db, id: 'card-new', deckId: 'deck-1', state: 'new');
      await insertCardRow(
        db,
        id: 'card-suspended',
        deckId: 'deck-1',
        state: 'review',
        due: toEpochMs(DateTime(2026, 11, 15, 9)),
        suspended: 1,
      );

      // Удержание за 30 дней: 3 из 4 вспомнены.
      await insertReview(id: 'r1', cardId: 'card-math', rating: 3, at: today);
      await insertReview(
        id: 'r2',
        cardId: 'card-math',
        rating: 1,
        at: DateTime(2026, 11, 13, 9),
      );
      await insertReview(
        id: 'r3',
        cardId: 'card-bio',
        rating: 4,
        at: DateTime(2026, 11, 12, 9),
      );
      await insertReview(
        id: 'r4',
        cardId: 'card-bio',
        rating: 2,
        at: DateTime(2026, 11, 10, 9),
      );
      // Старше окна года — не попадает никуда.
      await insertReview(
        id: 'r-old',
        cardId: 'card-math',
        rating: 1,
        at: DateTime(2025, 1, 1, 9),
      );
      // Слабые темы: 5+ повторов и >= 20 % ошибок.
      for (int index = 0; index < 4; index++) {
        await insertReview(
          id: 'r-bio-$index',
          cardId: 'card-bio',
          rating: index < 2 ? 1 : 3,
          at: DateTime(2026, 11, 9 - index, 9),
        );
      }

      await insertGenerationJob(
        id: 'job-1',
        at: now.subtract(const Duration(days: 2)),
        tokensUsed: 1200,
      );
      await insertGenerationJob(
        id: 'job-2',
        at: now.subtract(const Duration(days: 20)),
        tokensUsed: 5000,
      );
    });

    test('удержание, тепловая карта и прогноз', () async {
      final StatisticsSnapshot snapshot = await repository.load(now: now);

      expect(snapshot.totalReviewsYear, 8);
      expect(snapshot.reviews30, 8);
      expect(snapshot.remembered30, 5);
      expect(snapshot.retention30, closeTo(5 / 8, 1e-9));
      expect(snapshot.heatmap.last.count, 1);
      expect(snapshot.heatmap[363].count, 1);
      expect(snapshot.week.last.count, 1);

      expect(snapshot.forecast.length, 7);
      expect(snapshot.forecast[0].due, 1); // card-bio просрочена
      expect(snapshot.forecast[2].due, 1); // card-math today + 2
      expect(snapshot.forecast[1].due, 0); // suspended/new исключены
    });

    test('слабые темы считаются по карточкам и тегам', () async {
      final StatisticsSnapshot snapshot = await repository.load(now: now);
      expect(snapshot.weakTopics, isNotEmpty);
      final WeakTopic bio = snapshot.weakTopics.firstWhere(
        (WeakTopic topic) => topic.tag == 'биология',
      );
      expect(bio.reviews, 6);
      expect(bio.errors, 2);
      expect(bio.errorRate, closeTo(1 / 3, 1e-9));
    });

    test('токены за неделю — только окно since', () async {
      expect(
        await repository.tokensUsedSince(now.subtract(const Duration(days: 7))),
        1200,
      );
    });
  });

  group('DriftStatisticsRepository — устойчивость', () {
    test('битый tags_json не ломает загрузку и не даёт слабых тем', () async {
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
        tagsJson: '{broken',
        state: 'review',
      );
      for (int index = 0; index < 5; index++) {
        await insertReview(
          id: 'review-$index',
          cardId: 'card-1',
          rating: 1,
          at: today,
        );
      }

      final StatisticsSnapshot snapshot = await repository.load(now: now);
      expect(snapshot.totalReviewsYear, 5);
      expect(snapshot.weakTopics, isEmpty);
    });

    test('пустой tags_json и теги-не-строки игнорируются', () async {
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
        tagsJson: '[]',
        state: 'review',
      );
      await insertCardRow(
        db,
        id: 'card-2',
        deckId: 'deck-1',
        tagsJson: '["", 5, null, "ok"]',
        state: 'review',
      );
      for (int index = 0; index < 5; index++) {
        await insertReview(
          id: 'review-1-$index',
          cardId: 'card-1',
          rating: 1,
          at: today,
        );
        await insertReview(
          id: 'review-2-$index',
          cardId: 'card-2',
          rating: 1,
          at: today,
        );
      }

      final StatisticsSnapshot snapshot = await repository.load(now: now);
      expect(
        snapshot.weakTopics.map((WeakTopic topic) => topic.tag).toList(),
        <String>['ok'],
      );
    });
  });
}
