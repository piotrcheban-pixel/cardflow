import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';

/// Репозиторий колод (SPEC A5, A6.2).
///
/// Реализация — drift (`lib/data/decks/`). Интерфейс не зависит от БД, чтобы
/// UI-тесты подменяли его фейком, а `domain/` оставался чистым Dart.
abstract interface class DeckRepository {
  /// Поток сводок колод по запросу [query] (поиск/фильтр/архив).
  ///
  /// Эмитит текущее значение сразу и обновляется при изменениях БД.
  /// Порядок и семантика фильтров — ADR-007.
  Stream<List<DeckSummary>> watchSummaries({
    DeckQuery query = const DeckQuery(),
  });

  /// Поток конкретной колоды (или `null`, если удалена/нет такой).
  Stream<Deck?> watchDeck(String id);

  /// Колода по id без подписки (для экспорта/тестов).
  Future<Deck?> deckById(String id);

  /// Создаёт колоду с обрезанным [name]; возвращает созданную.
  Future<Deck> createDeck({required String name});

  /// Переименовывает колоду; обновляет `updated_at`.
  Future<void> renameDeck({required String id, required String name});

  /// Архивирует колоду (`archived_at = now`); идемпотентно.
  Future<void> archiveDeck(String id);

  /// Восстанавливает колоду из архива (`archived_at = null`); идемпотентно.
  Future<void> unarchiveDeck(String id);

  /// Удаляет колоду; карточки удаляются каскадом (`ON DELETE CASCADE`).
  Future<void> deleteDeck(String id);
}
