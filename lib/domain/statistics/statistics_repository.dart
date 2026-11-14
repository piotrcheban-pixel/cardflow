/// Контракт чтения статистики (SPEC A6.5, ADR-019 §4).
library;

import 'package:cardflow/domain/statistics/statistics.dart';

/// Порт статистики: только чтение существующих таблиц.
abstract interface class StatisticsRepository {
  /// Загружает снимок на момент [now].
  Future<StatisticsSnapshot> load({required DateTime now});

  /// Сумма `generation_jobs.tokens_used` с момента [since].
  Future<int> tokensUsedSince(DateTime since);
}
