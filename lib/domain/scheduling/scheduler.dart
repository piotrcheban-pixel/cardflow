import 'package:fsrs/fsrs.dart' as fsrs;

import 'fsrs_mapper.dart';
import 'rating.dart';
import 'scheduling_card.dart';

export 'rating.dart' show Rating;
export 'scheduling_card.dart' show CardState, SchedulingCard;

/// Результат применения оценки: обновлённая карточка и время повторения.
class ReviewOutcome {
  /// Создаёт результат повторения.
  const ReviewOutcome({required this.card, required this.reviewedAt});

  /// Новое состояние карточки (исходная не мутируется).
  final SchedulingCard card;

  /// Момент повторения (UTC).
  final DateTime reviewedAt;
}

/// Порт планировщика интервального повторения (SPEC A7.1, A7.2).
///
/// Домен зависит от этого интерфейса, а не от конкретной библиотеки FSRS.
abstract interface class Scheduler {
  /// Прогноз следующего интервала для каждой оценки — значения над кнопками
  /// «Не знаю / Сложно / Знаю / Легко» (SPEC A7.2). Ключи — в порядке [Rating.values].
  Map<Rating, Duration> previewIntervals(SchedulingCard card, {DateTime? now});

  /// Применяет оценку и возвращает новое состояние карточки.
  ReviewOutcome review(SchedulingCard card, Rating rating, {DateTime? now});
}

/// Адаптер FSRS-6 (пакет `fsrs` 2.0.1) к доменному порту [Scheduler].
///
/// Конфигурация по умолчанию (ADR-004): desiredRetention 0.9, шаги обучения
/// 1 мин / 10 мин, fuzzing выключен — прогноз интервалов детерминирован
/// и совпадает с фактическим планированием.
class FsrsScheduler implements Scheduler {
  /// Создаёт планировщик с весами FSRS-6 по умолчанию.
  FsrsScheduler({
    double desiredRetention = 0.9,
    List<Duration> learningSteps = const <Duration>[
      Duration(minutes: 1),
      Duration(minutes: 10),
    ],
    List<Duration> relearningSteps = const <Duration>[Duration(minutes: 10)],
    List<double> parameters = fsrs.defaultParameters,
    int maximumInterval = 36500,
    bool enableFuzzing = false,
  }) : _scheduler = fsrs.Scheduler(
         parameters: parameters,
         desiredRetention: desiredRetention,
         learningSteps: learningSteps,
         relearningSteps: relearningSteps,
         maximumInterval: maximumInterval,
         enableFuzzing: enableFuzzing,
       );

  final fsrs.Scheduler _scheduler;

  @override
  Map<Rating, Duration> previewIntervals(SchedulingCard card, {DateTime? now}) {
    final at = _resolveNow(now);
    final fsrsCard = _toFsrsCard(card);
    final result = <Rating, Duration>{};
    for (final rating in Rating.values) {
      final reviewed = _scheduler.reviewCard(
        fsrsCard,
        FsrsMapper.toFsrs(rating),
        reviewDateTime: at,
      );
      result[rating] = reviewed.card.due.difference(at);
    }
    return result;
  }

  @override
  ReviewOutcome review(SchedulingCard card, Rating rating, {DateTime? now}) {
    final at = _resolveNow(now);
    final reviewed = _scheduler.reviewCard(
      _toFsrsCard(card),
      FsrsMapper.toFsrs(rating),
      reviewDateTime: at,
    );
    return ReviewOutcome(
      card: _fromFsrsCard(reviewed.card, originalCardId: card.cardId),
      reviewedAt: at,
    );
  }

  static DateTime _resolveNow(DateTime? now) => (now ?? DateTime.now()).toUtc();

  /// FSRS требует int-идентификатор карточки; в БД у нас TEXT (UUID).
  /// В расчётах интервалов id не участвует, поэтому берём детерминированный хэш.
  static int _intId(String cardId) {
    var hash = 0x811c9dc5; // FNV-1a, 32 бита
    for (final unit in cardId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static fsrs.Card _toFsrsCard(SchedulingCard card) => fsrs.Card(
    cardId: _intId(card.cardId),
    state: FsrsMapper.toFsrsState(card.state),
    step: card.state == CardState.newState ? 0 : card.step,
    stability: card.stability,
    difficulty: card.difficulty,
    due: card.due.toUtc(),
    lastReview: card.lastReview?.toUtc(),
  );

  static SchedulingCard _fromFsrsCard(
    fsrs.Card reviewed, {
    required String originalCardId,
  }) => SchedulingCard(
    cardId: originalCardId,
    // После reviewCard() lastReview всегда установлен, поэтому состояния
    // FSRS learning/review/relearning маппятся 1:1; «new» существует только
    // до первого повторения (см. SchedulingCard.newCard).
    state: FsrsMapper.fromFsrsState(reviewed.state),
    step: reviewed.step,
    stability: reviewed.stability,
    difficulty: reviewed.difficulty,
    due: reviewed.due.toUtc(),
    lastReview: reviewed.lastReview?.toUtc(),
  );
}
