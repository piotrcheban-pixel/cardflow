import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';

/// Репозиторий карточек (SPEC A5, A6.3).
///
/// Чтение — список экрана колоды, выборка для сессии и экспорт; запись —
/// ручное создание/редактирование (итерация 2), импорт (итерация 1).
abstract interface class CardRepository {
  /// Поток карточек колоды (порядок — `created_at`).
  Stream<List<Card>> watchCards(String deckId);

  /// Снимок карточек колоды (для экспорта/тестов/сессии).
  Future<List<Card>> cardsByDeck(String deckId);

  /// Карточка по id; `null` — не найдена.
  Future<Card?> cardById(String id);

  /// Создаёт карточку (для `basic_reversed` — две строки с взаимными
  /// `sibling_id`, SPEC A5) и возвращает созданные карточки.
  Future<List<Card>> createCards({
    required String deckId,
    required CardDraft draft,
    required DateTime now,
  });

  /// Обновляет содержимое карточки (тип не меняется, ADR-009).
  Future<Card> updateCard({
    required Card card,
    required CardDraft draft,
    required DateTime now,
  });

  /// Удаляет карточку; у парной `basic_reversed` обнуляет `sibling_id`.
  Future<void> deleteCard(String cardId);
}
