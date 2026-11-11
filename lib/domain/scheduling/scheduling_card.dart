/// Состояние карточки на уровне приложения (SPEC A5):
/// `new | learning | review | relearning`.
///
/// В пакете `fsrs` 2.0.1 отдельного состояния `New` нет — новые карточки живут
/// в `learning` с шагом 0 и без последнего повторения; маппинг выполняет
/// [FsrsMapper].
enum CardState {
  /// Новая карточка, ещё не выученная.
  newState('new'),

  /// Изучается (шаги обучения).
  learning('learning'),

  /// В долгосрочном повторении.
  review('review'),

  /// Переучивается после забывания.
  relearning('relearning');

  const CardState(this.wireName);

  /// Строка для хранения в БД (SPEC A5).
  final String wireName;

  /// Восстанавливает состояние по строке из БД.
  static CardState fromWireName(String value) => switch (value) {
    'new' => CardState.newState,
    'learning' => CardState.learning,
    'review' => CardState.review,
    'relearning' => CardState.relearning,
    _ => throw ArgumentError('Неизвестное состояние карточки: $value'),
  };
}

/// Иммутабельный снимок состояния карточки для планировщика и хранения
/// в `cards.fsrs_json` (SPEC A5).
///
/// Домен не зависит от Flutter и от пакета `fsrs`: преобразование выполняет
/// адаптер в `scheduler.dart`.
class SchedulingCard {
  /// Создаёт снимок состояния.
  ///
  /// [due] и [lastReview] должны быть в UTC — FSRS-пакет принимает только UTC.
  SchedulingCard({
    required this.cardId,
    required this.state,
    required this.due,
    this.step,
    this.stability,
    this.difficulty,
    this.lastReview,
  }) : assert(due.isUtc, 'due должен быть в UTC'),
       assert(
         lastReview == null || lastReview.isUtc,
         'lastReview должен быть в UTC',
       );

  /// Создаёт новую карточку: состояние `new`, шаг 0, без истории повторений.
  factory SchedulingCard.newCard({
    required String cardId,
    required DateTime now,
  }) {
    final utcNow = now.toUtc();
    return SchedulingCard(
      cardId: cardId,
      state: CardState.newState,
      due: utcNow,
      step: 0,
    );
  }

  /// Идентификатор карточки (TEXT PRIMARY KEY в БД).
  final String cardId;

  /// Состояние на уровне приложения.
  final CardState state;

  /// Шаг обучения/переобучения; `null` в состоянии `review`.
  final int? step;

  /// Стабильность FSRS.
  final double? stability;

  /// Сложность FSRS.
  final double? difficulty;

  /// Дата следующего повторения (UTC).
  final DateTime due;

  /// Дата последнего повторения (UTC); `null` для новой карточки.
  final DateTime? lastReview;

  /// Сериализация для `cards.fsrs_json`.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'cardId': cardId,
    'state': state.wireName,
    'step': step,
    'stability': stability,
    'difficulty': difficulty,
    'due': due.toUtc().toIso8601String(),
    'lastReview': lastReview?.toUtc().toIso8601String(),
  };

  /// Восстанавливает снимок из `cards.fsrs_json`.
  factory SchedulingCard.fromJson(Map<String, dynamic> json) {
    final due = DateTime.parse(json['due'] as String).toUtc();
    final lastReviewRaw = json['lastReview'] as String?;
    return SchedulingCard(
      cardId: json['cardId'] as String,
      state: CardState.fromWireName(json['state'] as String),
      step: json['step'] as int?,
      stability: (json['stability'] as num?)?.toDouble(),
      difficulty: (json['difficulty'] as num?)?.toDouble(),
      due: due,
      lastReview: lastReviewRaw == null
          ? null
          : DateTime.parse(lastReviewRaw).toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SchedulingCard &&
          other.cardId == cardId &&
          other.state == state &&
          other.step == step &&
          other.stability == stability &&
          other.difficulty == difficulty &&
          other.due == due &&
          other.lastReview == lastReview;

  @override
  int get hashCode =>
      Object.hash(cardId, state, step, stability, difficulty, due, lastReview);

  @override
  String toString() =>
      'SchedulingCard(cardId: $cardId, state: ${state.wireName}, step: $step, '
      'stability: $stability, difficulty: $difficulty, due: $due, '
      'lastReview: $lastReview)';
}
