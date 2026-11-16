import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/review/drift_practice_repository.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/scheduling/rating.dart';

import '../db/test_support.dart';

/// Запись тренировки (ADR-025, итерация 7.11): `review_logs.mode = 'practice'`,
/// расписание FSRS не меняется, undo удаляет запись.
void main() {
  late AppDatabase db;
  late DriftPracticeRepository repository;
  final DateTime now = DateTime.utc(2026, 11, 15, 19, 30);

  setUp(() async {
    db = AppDatabase.inMemory();
    repository = DriftPracticeRepository(db);
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Колода',
      createdAt: 1,
      updatedAt: 1,
    );
    await insertCardRow(
      db,
      id: 'card-1',
      deckId: 'deck-1',
      state: 'new',
      due: toEpochMs(now),
      fsrsJson:
          '{"cardId":"card-1","state":"new","step":0,"stability":null,'
          '"difficulty":null,"due":"2026-11-15T19:30:00.000Z",'
          '"lastReview":null}',
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'recordPractice: строка журнала practice, карточка не меняется',
    () async {
      final CardRow before = (await db.select(db.cards).get()).single;

      final String logId = await repository.recordPractice(
        cardId: 'card-1',
        rating: Rating.good,
        reviewedAt: now,
        elapsed: const Duration(seconds: 7),
      );

      final ReviewLogRow log = (await db.select(db.reviewLogs).get()).single;
      expect(log.id, logId);
      expect(log.cardId, 'card-1');
      expect(log.rating, Rating.good.value);
      expect(log.mode, reviewModePractice);
      expect(log.scheduledDays, isNull);
      expect(log.actualDays, isNull);
      expect(log.elapsedMs, 7000);
      expect(log.reviewedAt, toEpochMs(now));

      final CardRow after = (await db.select(db.cards).get()).single;
      expect(after.state, before.state, reason: 'state не меняется');
      expect(after.fsrsJson, before.fsrsJson, reason: 'fsrs_json не меняется');
      expect(after.due, before.due, reason: 'due не меняется');
      expect(
        after.updatedAt,
        before.updatedAt,
        reason: 'updated_at не меняется',
      );
    },
  );

  test(
    'recordPractice неизвестной карточки — StateError, без строки',
    () async {
      await expectLater(
        repository.recordPractice(
          cardId: 'missing',
          rating: Rating.again,
          reviewedAt: now,
        ),
        throwsStateError,
      );
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    },
  );

  test('undoPractice удаляет только запись тренировки', () async {
    final String logId = await repository.recordPractice(
      cardId: 'card-1',
      rating: Rating.easy,
      reviewedAt: now,
    );
    // Обычная оценка не должна удаляться тренировочным undo.
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            id: 'classic-log',
            cardId: 'card-1',
            rating: 3,
            reviewedAt: toEpochMs(now),
            mode: reviewModeClassic,
          ),
        );

    await repository.undoPractice(logId);

    final List<ReviewLogRow> logs = await db.select(db.reviewLogs).get();
    expect(logs.map((ReviewLogRow row) => row.id), <String>['classic-log']);
  });

  test(
    'undoPractice с mode режима удаляет только свою запись (7.15)',
    () async {
      final repository = DriftPracticeRepository(db);
      final String testLog = await repository.recordPractice(
        cardId: 'card-1',
        rating: Rating.good,
        reviewedAt: now,
        mode: 'test',
      );
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              id: 'classic-log-2',
              cardId: 'card-1',
              rating: 3,
              reviewedAt: toEpochMs(now),
              mode: reviewModeClassic,
            ),
          );

      await repository.undoPractice(testLog, mode: 'test');

      final List<ReviewLogRow> logs = await db.select(db.reviewLogs).get();
      expect(logs.map((ReviewLogRow row) => row.id), contains('classic-log-2'));
      expect(logs.map((ReviewLogRow row) => row.id), isNot(contains(testLog)));
      expect(
        logs.firstWhere((ReviewLogRow row) => row.id == 'classic-log-2').mode,
        reviewModeClassic,
      );
    },
  );

  test('undoPractice: обычный лог не удаляется', () async {
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            id: 'classic-log',
            cardId: 'card-1',
            rating: 3,
            reviewedAt: toEpochMs(now),
            mode: reviewModeClassic,
          ),
        );

    await expectLater(repository.undoPractice('classic-log'), throwsStateError);
    expect(await db.select(db.reviewLogs).get(), hasLength(1));
  });
}
