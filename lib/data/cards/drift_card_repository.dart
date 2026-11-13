// Drift-реализация репозитория карточек (SPEC A5, A6.3, ADR-009).
//
// Чтение: список карточек экрана колоды, снимок для экспорта/сессии.
// Запись: ручное создание/редактирование/удаление; `basic_reversed` — две
// строки с взаимными `sibling_id` в одной транзакции.
//
// Маппинг строк — в `card_row_mapper.dart` (общий с `DriftReviewRepository`).
import 'package:drift/drift.dart';

import 'package:cardflow/data/cards/card_row_mapper.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_repository.dart';

/// Репозиторий карточек поверх drift-БД.
class DriftCardRepository implements CardRepository {
  /// Создаёт репозиторий поверх БД.
  DriftCardRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  @override
  Stream<List<Card>> watchCards(String deckId) {
    final query = database.select(database.cards)
      ..where((table) => table.deckId.equals(deckId))
      ..orderBy(<OrderingTerm Function($CardsTable)>[
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    return query.watch().map(
      (rows) => rows.map(cardFromRow).toList(growable: false),
    );
  }

  @override
  Future<List<Card>> cardsByDeck(String deckId) async {
    final query = database.select(database.cards)
      ..where((table) => table.deckId.equals(deckId))
      ..orderBy(<OrderingTerm Function($CardsTable)>[
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    final rows = await query.get();
    return rows.map(cardFromRow).toList(growable: false);
  }

  @override
  Future<Card?> cardById(String id) async {
    final query = database.select(database.cards)
      ..where((table) => table.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : cardFromRow(row);
  }

  @override
  Future<List<Card>> createCards({
    required String deckId,
    required CardDraft draft,
    required DateTime now,
  }) {
    throw UnimplementedError(
      'DriftCardRepository.createCards: красная фаза итерации 2',
    );
  }

  @override
  Future<Card> updateCard({
    required Card card,
    required CardDraft draft,
    required DateTime now,
  }) {
    throw UnimplementedError(
      'DriftCardRepository.updateCard: красная фаза итерации 2',
    );
  }

  @override
  Future<void> deleteCard(String cardId) {
    throw UnimplementedError(
      'DriftCardRepository.deleteCard: красная фаза итерации 2',
    );
  }

  /// Собирает новую карточку в памяти (id/даты/хеш) — без записи в БД.
  ///
  /// Используется транзакцией `createCards` и тестами.
  Card buildCard({
    required String deckId,
    required CardDraft draft,
    required DateTime now,
  }) {
    throw UnimplementedError(
      'DriftCardRepository.buildCard: красная фаза итерации 2',
    );
  }
}
