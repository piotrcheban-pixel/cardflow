import 'package:cardflow/domain/cards/card.dart';

/// Репозиторий карточек (SPEC A5, A6.3).
///
/// В итерации 1 нужен только для чтения (список на экране колоды) и для
/// импорта/экспорта `.zip`; создание/редактирование карточек — итерации 2/5.
abstract interface class CardRepository {
  /// Поток карточек колоды (порядок — `created_at`).
  Stream<List<Card>> watchCards(String deckId);

  /// Снимок карточек колоды (для экспорта/тестов).
  Future<List<Card>> cardsByDeck(String deckId);
}
