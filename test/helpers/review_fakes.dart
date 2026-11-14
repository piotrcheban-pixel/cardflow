import 'dart:async';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/review/daily_usage_repository.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/review/review_repository.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/scheduling/scheduling_card.dart';

/// In-memory дневной расход лимитов для тестов без drift (ADR-019 §8).
class FakeDailyUsageRepository implements DailyUsageRepository {
  /// Создаёт фейк с расходом [usage] (по умолчанию — начало дня).
  FakeDailyUsageRepository({this.usage = DailyReviewUsage.empty});

  /// Расход дня, который вернёт [usageOnDay].
  DailyReviewUsage usage;

  /// Если задано — [usageOnDay] бросает это исключение.
  Object? error;

  /// Моменты, с которыми запрашивали расход дня.
  final List<DateTime> requestedAt = <DateTime>[];

  @override
  Future<DailyReviewUsage> usageOnDay(DateTime now) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    requestedAt.add(now);
    return usage;
  }
}

/// Фейковый порт записи повторений для unit-тестов движка сессии.
///
/// In-memory журнал вызовов; токен undo строится из снимка карточки,
/// переданного в [previousCard] (тест задаёт его перед вызовом).
class FakeReviewRepository implements ReviewRepository {
  /// Снимок карточки, который вернётся в токене undo.
  Card? previousCard;

  /// Ошибка, бросаемая `recordReview`.
  Object? recordError;

  /// Если задано — `recordReview` ждёт завершения (проверка busy-состояния).
  Completer<void>? recordGate;

  /// Ошибка, бросаемая `undoReview`.
  Object? undoError;

  /// Оценки в порядке вызовов.
  final List<Rating> ratings = <Rating>[];

  /// Id карточек в порядке вызовов.
  final List<String> cardIds = <String>[];

  /// Моменты повторений в порядке вызовов.
  final List<DateTime> reviewedAts = <DateTime>[];

  /// Новые состояния планировщика в порядке вызовов.
  final List<SchedulingCard> outcomes = <SchedulingCard>[];

  /// Режимы в порядке вызовов.
  final List<String> modes = <String>[];

  /// Замеры времени в порядке вызовов.
  final List<Duration?> elapsedTimes = <Duration?>[];

  /// Токены, переданные в undo.
  final List<ReviewUndo> undone = <ReviewUndo>[];

  int _logCounter = 0;

  @override
  Future<ReviewUndo> recordReview({
    required String cardId,
    required Rating rating,
    required DateTime reviewedAt,
    required SchedulingCard outcome,
    required String mode,
    Duration? elapsed,
  }) async {
    if (recordError != null) throw recordError!;
    final Completer<void>? gate = recordGate;
    if (gate != null) await gate.future;
    ratings.add(rating);
    cardIds.add(cardId);
    reviewedAts.add(reviewedAt);
    outcomes.add(outcome);
    modes.add(mode);
    elapsedTimes.add(elapsed);
    final Card? snapshot = previousCard;
    if (snapshot == null) {
      throw StateError('FakeReviewRepository.previousCard не задан');
    }
    return ReviewUndo(logId: 'log-${++_logCounter}', previousCard: snapshot);
  }

  @override
  Future<void> undoReview(ReviewUndo undo) async {
    if (undoError != null) throw undoError!;
    undone.add(undo);
  }
}
