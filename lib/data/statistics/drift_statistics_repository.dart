/// Чтение статистики из drift-БД (SPEC A6.5, ADR-019 §4).
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/domain/statistics/statistics_repository.dart';

/// Репозиторий статистики поверх существующих таблиц (схема не меняется).
class DriftStatisticsRepository implements StatisticsRepository {
  /// Создаёт репозиторий поверх [db].
  DriftStatisticsRepository(this.db);

  /// БД приложения.
  final AppDatabase db;

  @override
  Future<StatisticsSnapshot> load({required DateTime now}) async {
    final DateTime localNow = now.toLocal();
    final DateTime today = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
    );
    final int startMs = toEpochMs(
      DateTime(
        today.year,
        today.month,
        today.day - (StatisticsCalculator.heatmapDays - 1),
      ),
    );
    final int forecastEndMs = toEpochMs(
      DateTime(
        today.year,
        today.month,
        today.day + StatisticsCalculator.forecastDays - 1,
        23,
        59,
        59,
        999,
      ),
    );

    final List<ReviewLogRow> reviewRows = await (db.select(
      db.reviewLogs,
    )..where((table) => table.reviewedAt.isBiggerOrEqualValue(startMs))).get();
    final List<ReviewSample> reviews = <ReviewSample>[
      for (final ReviewLogRow row in reviewRows)
        ReviewSample(
          cardId: row.cardId,
          rating: row.rating,
          reviewedAt: fromEpochMs(row.reviewedAt),
        ),
    ];

    final List<CardRow> tagRows = await (db.select(
      db.cards,
    )..where((table) => table.tagsJson.isNotValue('[]'))).get();
    final Map<String, List<String>> tagsByCard = <String, List<String>>{
      for (final CardRow row in tagRows) row.id: _decodeTags(row.tagsJson),
    };

    final List<TypedResult> dueRows =
        await (db.selectOnly(db.cards)
              ..addColumns(<Expression<Object>>[db.cards.due])
              ..where(
                db.cards.due.isNotNull() &
                    db.cards.suspended.equals(0) &
                    db.cards.state.isNotValue('new') &
                    db.cards.due.isSmallerOrEqualValue(forecastEndMs),
              ))
            .get();
    final List<DateTime> dueDates = <DateTime>[
      for (final TypedResult row in dueRows)
        if (row.read(db.cards.due) case final int due) fromEpochMs(due),
    ];

    final int tokensWeek = await tokensUsedSince(
      DateTime(
        today.year,
        today.month,
        today.day - (StatisticsCalculator.weekDays - 1),
      ),
    );

    return StatisticsCalculator.build(
      reviews: reviews,
      tagsByCard: tagsByCard,
      dueDates: dueDates,
      now: today,
      tokensWeek: tokensWeek,
    );
  }

  @override
  Future<int> tokensUsedSince(DateTime since) async {
    final QueryRow row = await db
        .customSelect(
          'SELECT COALESCE(SUM(tokens_used), 0) AS total '
          'FROM generation_jobs WHERE created_at >= ?',
          variables: <Variable<Object>>[Variable<int>(toEpochMs(since))],
        )
        .getSingle();
    return row.read<int>('total');
  }

  /// Разбирает `cards.tags_json`; битый JSON и не-строки игнорируются.
  static List<String> _decodeTags(String raw) {
    if (raw.isEmpty) return const <String>[];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <String>[];
    }
    if (decoded is! List) return const <String>[];
    final List<String> tags = <String>[];
    for (final Object? value in decoded) {
      if (value is String && value.trim().isNotEmpty) tags.add(value);
    }
    return List<String>.unmodifiable(tags);
  }
}
