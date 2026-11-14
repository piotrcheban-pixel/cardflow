import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/review/drift_daily_usage_repository.dart';
import 'package:cardflow/domain/review/daily_limits.dart';

/// Расход дневных лимитов из `review_logs` (ADR-019 §8, закрытие L45).
///
/// Реальная drift-БД в памяти: проверяется SQL вывода «новые vs повторные» по
/// истории журнала — без нового столбца и без миграции. «Новая» — запись без
/// предыдущего планирования (`actual_days IS NULL`), «повторная» — все прочие.
void main() {
  late AppDatabase db;
  late DriftDailyUsageRepository repository;
  final DateTime now = DateTime(2026, 11, 14, 12);
  late ({DateTime from, DateTime to}) day;

  setUp(() {
    db = AppDatabase.inMemory();
    repository = DriftDailyUsageRepository(db);
    day = DailyLimits.localDayUtc(now);
  });

  tearDown(() async {
    await db.close();
  });

  /// [actualDays] — `null` для ввода новой карточки, число для повторной
  /// (ровно так пишет `DriftReviewRepository.recordReview`).
  Future<void> seedLog({
    required String id,
    required String cardId,
    required DateTime at,
    double? actualDays,
    int rating = 3,
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
            actualDays: Value<double?>(actualDays),
          ),
        );
  }

  Future<DailyReviewUsage> usageToday() => repository.usageOnDay(now);

  test('пустой журнал — нулевой расход', () async {
    expect(await usageToday(), DailyReviewUsage.empty);
  });

  test(
    'новые — записи без предыдущего планирования, остальные повторные',
    () async {
      // card-a: повторения (уже планировалась вчера и сегодня).
      await seedLog(
        id: 'l1',
        cardId: 'card-a',
        at: day.from.subtract(const Duration(hours: 3)),
        actualDays: 10,
      );
      await seedLog(
        id: 'l2',
        cardId: 'card-a',
        at: day.from.add(const Duration(hours: 1)),
        actualDays: 1,
      );
      // card-b: введена сегодня (actual_days = null), затем ещё повторение.
      await seedLog(
        id: 'l3',
        cardId: 'card-b',
        at: day.from.add(const Duration(hours: 2)),
      );
      await seedLog(
        id: 'l4',
        cardId: 'card-b',
        at: day.from.add(const Duration(hours: 4)),
        actualDays: 0.01,
      );
      // card-c: введена сегодня один раз.
      await seedLog(
        id: 'l5',
        cardId: 'card-c',
        at: day.from.add(const Duration(hours: 5)),
      );

      final DailyReviewUsage usage = await usageToday();
      expect(usage.newCards, 2, reason: 'card-b и card-c введены сегодня');
      expect(usage.repeats, 2, reason: 'card-a и второе повторение card-b');
      expect(usage.total, 4, reason: 'всего 4 оценки в журнале за день');
    },
  );

  test('карточка с чужим состоянием (импорт) — повторная, а не новая', () async {
    // Импортированные карточки приходят с `fsrs_json` и `last_review`, поэтому
    // `recordReview` пишет им actual_days; лимит новых они не расходуют.
    await seedLog(
      id: 'l1',
      cardId: 'imported-card',
      at: day.from.add(const Duration(hours: 1)),
      actualDays: 42,
    );

    final DailyReviewUsage usage = await usageToday();
    expect(usage.newCards, 0);
    expect(usage.repeats, 1);
  });

  test('вчерашние оценки не расходуют сегодняшний лимит', () async {
    await seedLog(
      id: 'l1',
      cardId: 'card-a',
      at: day.from.subtract(const Duration(hours: 1)),
    );
    await seedLog(
      id: 'l2',
      cardId: 'card-b',
      at: day.from.subtract(const Duration(days: 30)),
    );

    expect(await usageToday(), DailyReviewUsage.empty);
  });

  test('границы дня: from включён, to исключён', () async {
    await seedLog(id: 'start', cardId: 'card-a', at: day.from);
    await seedLog(id: 'end', cardId: 'card-b', at: day.to);

    final DailyReviewUsage usage = await usageToday();
    expect(
      usage.total,
      1,
      reason: 'оценка ровно в to относится к следующему дню',
    );
    expect(usage.newCards, 1);
  });

  test('колода не важна: лимиты общие на приложение', () async {
    // В журнале нет deck_id; расход дня считается по всем карточкам.
    await seedLog(
      id: 'l1',
      cardId: 'deck-1-card',
      at: day.from.add(const Duration(hours: 1)),
    );
    await seedLog(
      id: 'l2',
      cardId: 'deck-2-card',
      at: day.from.add(const Duration(hours: 2)),
    );

    final DailyReviewUsage usage = await usageToday();
    expect(usage.newCards, 2);
    expect(usage.repeats, 0);
  });

  test('удаление лога (undo) уменьшает расход дня', () async {
    await seedLog(
      id: 'l1',
      cardId: 'card-a',
      at: day.from.add(const Duration(hours: 1)),
    );
    expect((await usageToday()).newCards, 1);

    await (db.delete(db.reviewLogs)..where((t) => t.id.equals('l1'))).go();
    expect(await usageToday(), DailyReviewUsage.empty);
  });
}
