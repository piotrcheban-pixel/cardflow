/// Сборка выборки конструктора (SPEC A6.7/A7.19/A7.20, ADR-018).
///
/// КРАСНАЯ ФАЗА итерации 6: контракт объявлен, фильтры/порядок/разминка/
/// интерливинг/перемешивание/лимит ещё не реализованы (заглушка).
library;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_plan.dart';

/// Чистая сборка очереди конструктора.
abstract final class SessionBuilder {
  /// Сколько карточек поднимает разминка (середина диапазона 3–5 A7.19).
  static const int warmupSize = 4;

  /// Отбирает карточки по фильтрам в базовом порядке (без лимита).
  static List<Card> select({
    required Iterable<Card> cards,
    required SessionConfig config,
    required Map<String, int> failureCounts,
    required DateTime now,
  }) {
    return List<Card>.of(cards);
  }

  /// Собирает очередь: фильтры → разминка → интерливинг → перемешивание → лимит.
  static List<Card> build({
    required Iterable<Card> cards,
    required SessionConfig config,
    required Map<String, int> failureCounts,
    required DateTime now,
    int? seed,
  }) {
    return select(
      cards: cards,
      config: config,
      failureCounts: failureCounts,
      now: now,
    );
  }

  /// План сессии: очередь и бюджет времени из лимита минут.
  static SessionPlan plan({
    required Iterable<Card> cards,
    required SessionConfig config,
    required Map<String, int> failureCounts,
    required DateTime now,
    int? seed,
  }) {
    return SessionPlan(
      cards: build(
        cards: cards,
        config: config,
        failureCounts: failureCounts,
        now: now,
        seed: seed,
      ),
      mode: config.mode,
    );
  }
}
