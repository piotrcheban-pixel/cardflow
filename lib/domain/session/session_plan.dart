/// Готовый план сессии конструктора (SPEC A6.7/A7.20, ADR-018).
library;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/session/session_config.dart';

/// Очередь, собранная конструктором, и бюджет времени сессии.
///
/// Передаётся экранам классики и ленты через `GoRouter.extra`; движки с
/// `prebuilt = true` не пересобирают эту очередь (ADR-018).
class SessionPlan {
  /// Создаёт план.
  const SessionPlan({
    required this.cards,
    this.timeBudget,
    this.mode = SessionMode.classic,
  });

  /// Порядок карточек, собранный конструктором.
  final List<Card> cards;

  /// Бюджет времени (лимит минут); `null` — без ограничения.
  final Duration? timeBudget;

  /// Режим сессии (`classic` или `feed`).
  final SessionMode mode;

  @override
  String toString() =>
      'SessionPlan(cards: ${cards.length}, mode: ${mode.wireName}, '
      'budget: $timeBudget)';
}
