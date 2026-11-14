// Drift-реализация счётчиков провалов (SPEC A6.7/A7.17, ADR-018).
//
// КРАСНАЯ ФАЗА итерации 6: заглушка контракта; SQL-подсчёт ещё не реализован.
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/session/leech_repository.dart';

/// Счётчики провалов по `review_logs`.
class DriftLeechRepository implements LeechRepository {
  /// Создаёт репозиторий поверх БД.
  DriftLeechRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  @override
  Future<Map<String, int>> failureCounts({
    required Iterable<String> deckIds,
  }) async {
    return const <String, int>{};
  }
}
