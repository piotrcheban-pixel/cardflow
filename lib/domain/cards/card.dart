import 'package:collection/collection.dart';

/// Тип карточки (SPEC A5): `basic | basic_reversed | cloze`.
enum CardType {
  /// Вопрос-ответ.
  basic('basic'),

  /// Двусторонняя карточка (две строки `cards` со взаимными `sibling_id`).
  basicReversed('basic_reversed'),

  /// Пропуск `{{c1::…}}` (SPEC A7.9).
  cloze('cloze');

  const CardType(this.wireName);

  /// Имя в БД/JSON (`cards.card_type`).
  final String wireName;

  /// Разбирает тип из строки БД/JSON.
  static CardType fromWire(String value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    throw FormatException('Неизвестный тип карточки: $value');
  }
}

/// Состояние карточки уровня приложения (SPEC A5: `state`).
enum CardState {
  /// Новая карточка, ещё не изучалась.
  newCard('new'),

  /// Изучается (шаги обучения).
  learning('learning'),

  /// В повторении.
  review('review'),

  /// Переизучается после провала.
  relearning('relearning');

  const CardState(this.wireName);

  /// Имя в БД/JSON (`cards.state`).
  final String wireName;

  /// Разбирает состояние из строки БД/JSON.
  static CardState fromWire(String value) {
    for (final state in values) {
      if (state.wireName == value) return state;
    }
    throw FormatException('Неизвестное состояние карточки: $value');
  }
}

/// Карточка (SPEC A5) — единица знания: `front/back` + тип + теги.
///
/// Доменная модель без зависимостей от Flutter/БД. `occlusionJson` и
/// `fsrsJson` хранятся как сырые JSON-строки: их разбор — задача итераций 2/5.
class Card {
  /// Создаёт карточку.
  const Card({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.cardType,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.hint,
    this.tags = const <String>[],
    this.questionMediaIds = const <String>[],
    this.answerMediaIds = const <String>[],
    this.latex,
    this.occlusionJson,
    this.sourceDocId,
    this.sourceExcerpt,
    this.fsrsJson,
    this.due,
    this.suspended = false,
    this.buriedUntil,
    this.flagged = false,
    this.siblingId,
    this.contentHash,
  });

  /// Уникальный идентификатор (`TEXT PRIMARY KEY`).
  final String id;

  /// Колода-владелец (`cards.deck_id`).
  final String deckId;

  /// Лицевая сторона (вопрос).
  final String front;

  /// Обратная сторона (ответ).
  final String back;

  /// Подсказка без раскрытия ответа.
  final String? hint;

  /// Тип карточки.
  final CardType cardType;

  /// Теги (SPEC: до 3, без `#`).
  final List<String> tags;

  /// Идентификаторы изображений лицевой стороны (`media_json` v2).
  ///
  /// С 7.19 стороны независимы (ADR-042): на лицевой стороне показываются
  /// только эти изображения. Legacy-карточки (плоский `media_json`) читаются
  /// как изображения вопроса — до 7.19 единственная иллюстрация показывалась на
  /// лицевой стороне. У occlusion-карточки первое изображение вопроса — холст
  /// под маски.
  final List<String> questionMediaIds;

  /// Идентификаторы изображений обратной стороны (`media_json` v2).
  ///
  /// Показываются только после переворота: изображение-ответ не должно
  /// раскрывать ответ до него (ADR-042).
  final List<String> answerMediaIds;

  /// Все id карточки: вопрос, затем ответ (для GC, экспорта, чтения медиа).
  List<String> get mediaIds => <String>[...questionMediaIds, ...answerMediaIds];

  /// LaTeX-разметка карточки, если есть.
  final String? latex;

  /// JSON масок Image Occlusion (SPEC A7.8), если есть.
  final String? occlusionJson;

  /// Идентификатор исходного документа (`source_docs.id`), если есть.
  final String? sourceDocId;

  /// Цитата для кнопки «Почему?» (SPEC A6.4).
  final String? sourceExcerpt;

  /// Состояние карточки уровня приложения (SPEC A5: `state`).
  final CardState state;

  /// Состояние FSRS (сырой JSON адаптера), если карточка уже планировалась.
  final String? fsrsJson;

  /// Денормализованный `due` (SPEC A5).
  final DateTime? due;

  /// Приостановлена (исключена из сессий).
  final bool suspended;

  /// Отложена до момента (buried).
  final DateTime? buriedUntil;

  /// Флаг пользователя (пиявка — post-MVP, флаг в MVP).
  final bool flagged;

  /// Парная карточка для `basic_reversed`.
  final String? siblingId;

  /// Хеш дедупликации `front + "\u0000" + back` (SPEC A5/A8.5).
  final String? contentHash;

  /// Момент создания.
  final DateTime createdAt;

  /// Момент последнего изменения.
  final DateTime updatedAt;

  /// Первое изображение карточки: вопроса, иначе ответа; `null` — медиа нет.
  String? get primaryMediaId => questionMediaIds.isNotEmpty
      ? questionMediaIds.first
      : (answerMediaIds.isEmpty ? null : answerMediaIds.first);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    const deep = DeepCollectionEquality();
    return other is Card &&
        other.id == id &&
        other.deckId == deckId &&
        other.front == front &&
        other.back == back &&
        other.hint == hint &&
        other.cardType == cardType &&
        deep.equals(other.tags, tags) &&
        deep.equals(other.questionMediaIds, questionMediaIds) &&
        deep.equals(other.answerMediaIds, answerMediaIds) &&
        other.latex == latex &&
        other.occlusionJson == occlusionJson &&
        other.sourceDocId == sourceDocId &&
        other.sourceExcerpt == sourceExcerpt &&
        other.state == state &&
        other.fsrsJson == fsrsJson &&
        other.due == due &&
        other.suspended == suspended &&
        other.buriedUntil == buriedUntil &&
        other.flagged == flagged &&
        other.siblingId == siblingId &&
        other.contentHash == contentHash &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    const deep = DeepCollectionEquality();
    return Object.hashAll(<Object?>[
      id,
      deckId,
      front,
      back,
      hint,
      cardType,
      deep.hash(tags),
      deep.hash(questionMediaIds),
      deep.hash(answerMediaIds),
      latex,
      occlusionJson,
      sourceDocId,
      sourceExcerpt,
      state,
      fsrsJson,
      due,
      suspended,
      buriedUntil,
      flagged,
      siblingId,
      contentHash,
      createdAt,
      updatedAt,
    ]);
  }

  @override
  String toString() =>
      'Card(id: $id, deckId: $deckId, type: ${cardType.wireName}, '
      'state: ${state.wireName})';
}
