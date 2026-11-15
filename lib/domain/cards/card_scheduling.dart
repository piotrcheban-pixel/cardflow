import 'dart:convert';

import 'card.dart';
import '../scheduling/scheduling_card.dart';

/// Маппинг доменной карточки `Card` (SPEC A5) на снимок состояния для FSRS
/// и обратно.
///
/// Единственное место, где сходятся `created_at`/`state` строки `cards` и
/// FSRS-состояние из `fsrs_json`: адаптер планировщика работает только со
/// [SchedulingCard] и не знает про остальные поля карточки.
abstract final class CardSchedulingMapper {
  /// Начальное FSRS-состояние новой карточки (итерация 7.11).
  ///
  /// Новая карточка сохраняется с `due = now` и валидным `fsrs_json`: очередь
  /// (`ReviewQueue`) и любой запрос «что учить сейчас» видят её как новую, а не
  /// как строку с `NULL` в `due`. Состояние остаётся `new`, шаг 0, история
  /// повторений пуста — планировщик считает её новой так же, как раньше.
  static SchedulingCard initialScheduling({
    required String cardId,
    required DateTime now,
  }) => SchedulingCard.newCard(cardId: cardId, now: now);

  /// Восстанавливает снимок планировщика из карточки.
  ///
  /// Если у карточки уже есть `fsrs_json` — состояние берётся из него (FSRS —
  /// источник правды по `stability`/`difficulty`/`lastReview`/`step`). Иначе
  /// карточка считается новой: `due = card.due ?? now`, шаг 0.
  ///
  /// Битый или чужой `fsrs_json` — [FormatException]: тихий сброс в «новую»
  /// карточку потерял бы историю повторений.
  static SchedulingCard toSchedulingCard(Card card, {required DateTime now}) {
    final String? raw = card.fsrsJson;
    if (raw == null) {
      return SchedulingCard.newCard(cardId: card.id, now: card.due ?? now);
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('fsrs_json должен быть JSON-объектом: $raw');
    }
    final SchedulingCard scheduling;
    try {
      scheduling = SchedulingCard.fromJson(decoded);
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Битый fsrs_json: $error');
    }
    if (scheduling.cardId != card.id) {
      throw FormatException(
        'fsrs_json принадлежит другой карточке: '
        '${scheduling.cardId} != ${card.id}',
      );
    }
    return scheduling;
  }

  /// Возвращает карточку с применённым результатом оценки: `state`,
  /// `fsrs_json`, `due` и `updatedAt` обновлены (SPEC A5).
  static Card applyOutcome(
    Card card,
    SchedulingCard outcome, {
    required DateTime updatedAt,
  }) {
    return Card(
      id: card.id,
      deckId: card.deckId,
      front: card.front,
      back: card.back,
      hint: card.hint,
      cardType: card.cardType,
      tags: card.tags,
      mediaIds: card.mediaIds,
      latex: card.latex,
      occlusionJson: card.occlusionJson,
      sourceDocId: card.sourceDocId,
      sourceExcerpt: card.sourceExcerpt,
      state: outcome.state,
      fsrsJson: jsonEncode(outcome.toJson()),
      due: outcome.due,
      suspended: card.suspended,
      buriedUntil: card.buriedUntil,
      flagged: card.flagged,
      siblingId: card.siblingId,
      contentHash: card.contentHash,
      createdAt: card.createdAt,
      updatedAt: updatedAt,
    );
  }
}
