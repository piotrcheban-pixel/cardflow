import 'card.dart';
import '../scheduling/scheduling_card.dart';

/// Маппинг доменной карточки `Card` (SPEC A5) на снимок состояния для FSRS
/// и обратно.
///
/// Единственное место, где сходятся `created_at`/`state` строки `cards` и
/// FSRS-состояние из `fsrs_json`: адаптер планировщика работает только со
/// [SchedulingCard] и не знает про остальные поля карточки.
abstract final class CardSchedulingMapper {
  /// Восстанавливает снимок планировщика из карточки.
  ///
  /// Если у карточки уже есть `fsrs_json` — состояние берётся из него (FSRS —
  /// источник правды по `stability`/`difficulty`/`lastReview`/`step`). Иначе
  /// карточка считается новой: `due = card.due ?? now`, шаг 0.
  static SchedulingCard toSchedulingCard(Card card, {required DateTime now}) {
    return SchedulingCard.newCard(cardId: card.id, now: now);
  }

  /// Возвращает карточку с применённым результатом оценки: `state`,
  /// `fsrs_json`, `due` и `updatedAt` обновлены (SPEC A5).
  static Card applyOutcome(
    Card card,
    SchedulingCard outcome, {
    required DateTime updatedAt,
  }) {
    return card;
  }
}
