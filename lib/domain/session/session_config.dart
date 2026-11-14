/// Конфиг сессии конструктора (SPEC A6.7, ADR-018).
///
/// КРАСНАЯ ФАЗА итерации 6: объявлен контракт, поведение сериализации ещё не
/// реализовано (заглушка) — тесты падают по ожиданиям, а не по компиляции.
library;

import 'package:cardflow/domain/cards/card.dart';

/// Режим собранной сессии (совпадает с `review_logs.mode`).
enum SessionMode {
  /// Классический режим (SPEC A7.2, ADR-008).
  classic('classic'),

  /// Лента (SPEC A7.3, ADR-016).
  feed('feed');

  const SessionMode(this.wireName);

  /// Значение для JSON/`review_logs.mode`.
  final String wireName;

  /// Разбирает режим; неизвестный — [FormatException] (в заглушке — classic).
  static SessionMode fromWire(String value) {
    for (final SessionMode mode in values) {
      if (mode.wireName == value) return mode;
    }
    return classic;
  }
}

/// Фильтр по состоянию карточки (SPEC A6.7).
enum SessionStateFilter {
  /// Новые карточки.
  newCards('new'),

  /// Изучаемые и переизучаемые.
  inProgress('in_progress'),

  /// В повторении.
  review('review'),

  /// Пиявки: 8+ провалов (A7.17).
  leeches('leeches');

  const SessionStateFilter(this.wireName);

  /// Значение для JSON.
  final String wireName;

  /// Разбирает фильтр.
  static SessionStateFilter fromWire(String value) {
    for (final SessionStateFilter filter in values) {
      if (filter.wireName == value) return filter;
    }
    return newCards;
  }
}

/// Вид лимита сессии.
enum SessionLimitKind {
  /// N карточек.
  cards('cards'),

  /// N минут.
  minutes('minutes');

  const SessionLimitKind(this.wireName);

  /// Значение для JSON.
  final String wireName;

  /// Разбирает вид лимита.
  static SessionLimitKind fromWire(String value) {
    for (final SessionLimitKind kind in values) {
      if (kind.wireName == value) return kind;
    }
    return cards;
  }
}

/// Лимит сессии: N карточек или N минут (SPEC A6.7).
class SessionLimit {
  /// Лимит по карточкам.
  const SessionLimit.cards(int value)
    : kind = SessionLimitKind.cards,
      value = value;

  /// Лимит по минутам.
  const SessionLimit.minutes(int value)
    : kind = SessionLimitKind.minutes,
      value = value;

  /// Создаёт лимит с явным видом.
  const SessionLimit({required this.kind, required this.value});

  /// Максимум карточек в лимите.
  static const int maxCards = 500;

  /// Максимум минут в лимите.
  static const int maxMinutes = 180;

  /// Вид лимита.
  final SessionLimitKind kind;

  /// Значение лимита.
  final int value;

  /// Лимит по минутам.
  bool get isMinutes => false;

  /// Бюджет времени сессии; `null` для лимита карточек (заглушка).
  Duration? get timeBudget => null;

  @override
  bool operator ==(Object other) =>
      other is SessionLimit && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'SessionLimit(${kind.wireName}: $value)';
}

/// Параметры сессии конструктора (SPEC A6.7, ADR-018).
class SessionConfig {
  /// Создаёт конфиг.
  const SessionConfig({
    required this.deckIds,
    this.tags = const <String>{},
    this.cardTypes = const <CardType>{},
    this.states = const <SessionStateFilter>{},
    this.mode = SessionMode.classic,
    this.limit = const SessionLimit.cards(20),
    this.shuffle = false,
    this.interleave = false,
    this.warmup = false,
  });

  /// Версия контракта `session_presets.config_json`.
  static const int version = 1;

  /// Выбранные колоды.
  final List<String> deckIds;

  /// Фильтр тегов (OR); пусто — без фильтра.
  final Set<String> tags;

  /// Фильтр типов карточек (OR); пусто — без фильтра.
  final Set<CardType> cardTypes;

  /// Фильтр состояний (OR); пусто — без фильтра.
  final Set<SessionStateFilter> states;

  /// Режим сессии.
  final SessionMode mode;

  /// Лимит карточек/минут.
  final SessionLimit limit;

  /// Перемешивать.
  final bool shuffle;

  /// Интерливинг по колодам.
  final bool interleave;

  /// Разминка.
  final bool warmup;

  /// Сериализация для `session_presets.config_json` (заглушка).
  Map<String, Object?> toJson() => <String, Object?>{};

  /// Разбор JSON пресета (заглушка).
  factory SessionConfig.fromJson(Map<String, Object?> json) {
    return const SessionConfig(deckIds: <String>[]);
  }

  /// Копия с заменой полей.
  SessionConfig copyWith({
    List<String>? deckIds,
    Set<String>? tags,
    Set<CardType>? cardTypes,
    Set<SessionStateFilter>? states,
    SessionMode? mode,
    SessionLimit? limit,
    bool? shuffle,
    bool? interleave,
    bool? warmup,
  }) {
    return SessionConfig(
      deckIds: deckIds ?? this.deckIds,
      tags: tags ?? this.tags,
      cardTypes: cardTypes ?? this.cardTypes,
      states: states ?? this.states,
      mode: mode ?? this.mode,
      limit: limit ?? this.limit,
      shuffle: shuffle ?? this.shuffle,
      interleave: interleave ?? this.interleave,
      warmup: warmup ?? this.warmup,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionConfig &&
      other.deckIds.length == deckIds.length &&
      other.tags.length == tags.length &&
      other.cardTypes.length == cardTypes.length &&
      other.states.length == states.length &&
      other.mode == mode &&
      other.limit == limit &&
      other.shuffle == shuffle &&
      other.interleave == interleave &&
      other.warmup == warmup;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(deckIds),
    Object.hashAll(tags),
    Object.hashAll(cardTypes),
    Object.hashAll(states),
    mode,
    limit,
    shuffle,
    interleave,
    warmup,
  );

  @override
  String toString() =>
      'SessionConfig(decks: ${deckIds.length}, mode: ${mode.wireName}, '
      'limit: $limit)';
}
