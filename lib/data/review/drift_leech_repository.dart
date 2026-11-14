// Drift-реализация счётчиков провалов (SPEC A6.7/A7.17, ADR-018).
//
// «Пиявка» — карточка с 8+ провалами (`review_logs.rating = 1`): сам режим
// пиявок остаётся post-MVP (A7.17), но фильтру конструктора нужен счётчик.
// Один GROUP BY-запрос по выбранным колодам; строки без провалов не входят
// в карту (отсутствие = 0).
import 'package:drift/drift.dart';

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
    final List<String> ids = deckIds.toList(growable: false);
    if (ids.isEmpty) return const <String, int>{};
    final String placeholders = List<String>.filled(ids.length, '?').join(', ');
    final List<QueryRow> rows = await database
        .customSelect(
          'SELECT l.card_id AS card_id, COUNT(*) AS failures '
          'FROM review_logs l '
          'INNER JOIN cards c ON c.id = l.card_id '
          'WHERE l.rating = 1 AND c.deck_id IN ($placeholders) '
          'GROUP BY l.card_id',
          variables: <Variable<String>>[
            for (final String id in ids) Variable<String>(id),
          ],
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            database.reviewLogs,
            database.cards,
          },
        )
        .get();
    return <String, int>{
      for (final QueryRow row in rows)
        row.read<String>('card_id'): row.read<int>('failures'),
    };
  }
}
