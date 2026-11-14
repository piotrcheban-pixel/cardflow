/// Конфиг сессии конструктора (SPEC A6.7, ADR-018).
///
/// Неизменяемый снимок параметров экрана «Конструктор сессии»; `toJson` /
/// `fromJson` — контракт `session_presets.config_json` (SPEC A5). Домен без
/// зависимостей от Flutter и БД.
library;

import 'package:collection/collection.dart';

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

  /// Разбирает режим; неизвестный — [FormatException].
  static SessionMode fromWire(String value) {
    for (final SessionMode mode in values) {
      if (mode.wireName == value) return mode;
    }
    throw FormatException('Неизвестный режим сессии: $value');
  }
}

/// Фильтр по состоянию карточки (SPEC A6.7).
enum SessionStateFilter {
  /// Новые карточки (`state = new`).
  newCards('new'),

  /// Изучаемые и переизучаемые (`learning | relearning`).
  inProgress('in_progress'),

  /// В повторении (`state = review`).
  review('review'),

  /// Пиявки: 8+ провалов (A7.17).
  leeches('leeches');

  const SessionStateFilter(this.wireName);

  /// Значение для JSON.
  final String wireName;

  /// Разбирает фильтр; неизвестный — [FormatException].
  static SessionStateFilter fromWire(String value) {
    for (final SessionStateFilter filter in values) {
      if (filter.wireName == value) return filter;
    }
    throw FormatException('Неизвестный фильтр состояния: $value');
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

  /// Разбирает вид лимита; неизвестный — [FormatException].
  static SessionLimitKind fromWire(String value) {
    for (final SessionLimitKind kind in values) {
      if (kind.wireName == value) return kind;
    }
    throw FormatException('Неизвестный вид лимита: $value');
  }
}

/// Лимит сессии: N карточек или N минут (SPEC A6.7).
class SessionLimit {
  /// Лимит по карточкам.
  const SessionLimit.cards(this.value) : kind = SessionLimitKind.cards;

  /// Лимит по минутам.
  const SessionLimit.minutes(this.value) : kind = SessionLimitKind.minutes;

  /// Создаёт лимит с явным видом (контракт JSON).
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
  bool get isMinutes => kind == SessionLimitKind.minutes;

  /// Бюджет времени сессии; `null` для лимита карточек.
  Duration? get timeBudget => isMinutes ? Duration(minutes: value) : null;

  /// Разбирает лимит из JSON `{"kind": …, "value": …}` с проверкой диапазона.
  factory SessionLimit.fromJson(Map<String, Object?> json) {
    final Object? kind = json['kind'];
    final Object? value = json['value'];
    if (kind is! String || value is! int) {
      throw FormatException('Некорректный лимит сессии: $json');
    }
    final SessionLimitKind parsed = SessionLimitKind.fromWire(kind);
    final int max = parsed == SessionLimitKind.cards ? maxCards : maxMinutes;
    if (value < 1 || value > max) {
      throw FormatException(
        'Лимит ${parsed.wireName} вне диапазона 1…$max: $value',
      );
    }
    return SessionLimit(kind: parsed, value: value);
  }

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

  /// Лимит карточек по умолчанию (SPEC молчит — ADR-018).
  static const int defaultCardsLimit = 20;

  /// Выбранные колоды (непустой список для валидного конфига).
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

  /// Перемешивать очередь.
  final bool shuffle;

  /// Интерливинг по колодам.
  final bool interleave;

  /// Разминка (первые карточки — самые лёгкие).
  final bool warmup;

  /// Сериализация для `session_presets.config_json`.
  ///
  /// Множества пишутся в детерминированном порядке: теги — по нижнему
  /// регистру, типы/состояния — в порядке объявления enum.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'deck_ids': <String>[...deckIds],
    'tags': _sortedTags(),
    'card_types': <String>[
      for (final CardType type in _sortedTypes()) type.wireName,
    ],
    'states': <String>[
      for (final SessionStateFilter state in _sortedStates()) state.wireName,
    ],
    'mode': mode.wireName,
    'limit': <String, Object?>{
      'kind': limit.kind.wireName,
      'value': limit.value,
    },
    'shuffle': shuffle,
    'interleave': interleave,
    'warmup': warmup,
  };

  /// Разбирает JSON пресета.
  ///
  /// Неизвестные ключи игнорируются (совместимость вперёд); неверная версия,
  /// пустой список колод и неизвестные значения фильтров — [FormatException].
  factory SessionConfig.fromJson(Map<String, Object?> json) {
    final Object? version = json['version'];
    if (version != SessionConfig.version) {
      throw FormatException('Неизвестная версия конфига сессии: $version');
    }
    final Object? rawDecks = json['deck_ids'];
    if (rawDecks is! List || rawDecks.isEmpty) {
      throw const FormatException('Конфиг сессии без колод невалиден');
    }
    final List<String> deckIds = <String>[];
    for (final Object? deckId in rawDecks) {
      if (deckId is! String || deckId.isEmpty) {
        throw FormatException('Некорректный id колоды: $deckId');
      }
      deckIds.add(deckId);
    }

    final Set<String> tags = <String>{};
    for (final String tag in _stringList(json['tags'], 'tags')) {
      tags.add(tag);
    }

    final Set<CardType> cardTypes = <CardType>{};
    for (final String type in _stringList(json['card_types'], 'card_types')) {
      cardTypes.add(CardType.fromWire(type));
    }

    final Set<SessionStateFilter> states = <SessionStateFilter>{};
    for (final String state in _stringList(json['states'], 'states')) {
      states.add(SessionStateFilter.fromWire(state));
    }

    final Object? rawMode = json['mode'];
    final SessionMode mode = rawMode == null
        ? SessionMode.classic
        : SessionMode.fromWire(
            rawMode is String
                ? rawMode
                : throw FormatException('Некорректный режим: $rawMode'),
          );

    final Object? rawLimit = json['limit'];
    final SessionLimit limit = rawLimit == null
        ? const SessionLimit.cards(defaultCardsLimit)
        : SessionLimit.fromJson(
            rawLimit is Map<String, Object?>
                ? rawLimit
                : throw FormatException('Некорректный лимит: $rawLimit'),
          );

    return SessionConfig(
      deckIds: List<String>.unmodifiable(deckIds),
      tags: Set<String>.unmodifiable(tags),
      cardTypes: Set<CardType>.unmodifiable(cardTypes),
      states: Set<SessionStateFilter>.unmodifiable(states),
      mode: mode,
      limit: limit,
      shuffle: _boolOrDefault(json['shuffle']),
      interleave: _boolOrDefault(json['interleave']),
      warmup: _boolOrDefault(json['warmup']),
    );
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

  List<String> _sortedTags() {
    final List<String> result = tags.toList(growable: false);
    result.sort((String a, String b) {
      final int byLower = a.toLowerCase().compareTo(b.toLowerCase());
      return byLower != 0 ? byLower : a.compareTo(b);
    });
    return result;
  }

  List<CardType> _sortedTypes() {
    final List<CardType> result = cardTypes.toList(growable: false);
    result.sort((CardType a, CardType b) => a.index.compareTo(b.index));
    return result;
  }

  List<SessionStateFilter> _sortedStates() {
    final List<SessionStateFilter> result = states.toList(growable: false);
    result.sort(
      (SessionStateFilter a, SessionStateFilter b) =>
          a.index.compareTo(b.index),
    );
    return result;
  }

  static List<String> _stringList(Object? value, String key) {
    if (value == null) return const <String>[];
    if (value is! List) {
      throw FormatException('Поле $key должно быть списком: $value');
    }
    final List<String> result = <String>[];
    for (final Object? item in value) {
      if (item is! String) {
        throw FormatException('Поле $key содержит не строку: $item');
      }
      result.add(item);
    }
    return result;
  }

  static bool _boolOrDefault(Object? value) {
    if (value == null) return false;
    if (value is! bool) throw FormatException('Ожидался bool: $value');
    return value;
  }

  static const ListEquality<String> _listEquality = ListEquality<String>();
  static const SetEquality<String> _tagEquality = SetEquality<String>();
  static const SetEquality<CardType> _typeEquality = SetEquality<CardType>();
  static const SetEquality<SessionStateFilter> _stateEquality =
      SetEquality<SessionStateFilter>();

  @override
  bool operator ==(Object other) =>
      other is SessionConfig &&
      _listEquality.equals(other.deckIds, deckIds) &&
      _tagEquality.equals(other.tags, tags) &&
      _typeEquality.equals(other.cardTypes, cardTypes) &&
      _stateEquality.equals(other.states, states) &&
      other.mode == mode &&
      other.limit == limit &&
      other.shuffle == shuffle &&
      other.interleave == interleave &&
      other.warmup == warmup;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(deckIds),
    Object.hashAllUnordered(tags),
    Object.hashAllUnordered(cardTypes),
    Object.hashAllUnordered(states),
    mode,
    limit,
    shuffle,
    interleave,
    warmup,
  );

  @override
  String toString() =>
      'SessionConfig(decks: ${deckIds.length}, tags: ${tags.length}, '
      'types: ${cardTypes.length}, states: ${states.length}, '
      'mode: ${mode.wireName}, limit: $limit, shuffle: $shuffle, '
      'interleave: $interleave, warmup: $warmup)';
}
