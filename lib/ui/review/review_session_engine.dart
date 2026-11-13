import 'package:flutter/foundation.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/review/review_repository.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';

/// Haptic-токен оценки по таблице SPEC A7.2.
enum ReviewHaptic {
  /// «Не знаю» — `heavyImpact`.
  heavy,

  /// «Сложно» / «Знаю» — `lightImpact`.
  light,

  /// «Легко» — `selectionClick`.
  selection,
}

/// Haptic для оценки (SPEC A7.2).
ReviewHaptic reviewHapticFor(Rating rating) => switch (rating) {
  Rating.again => ReviewHaptic.heavy,
  Rating.hard || Rating.good => ReviewHaptic.light,
  Rating.easy => ReviewHaptic.selection,
};

/// Элемент очереди: карточка и её снимок для планировщика.
class ReviewSessionItem {
  /// Создаёт элемент.
  const ReviewSessionItem({required this.card, required this.scheduling});

  /// Доменная карточка.
  final Card card;

  /// Снимок FSRS-состояния на момент старта сессии.
  final SchedulingCard scheduling;
}

/// Состояние классической сессии (SPEC A6.4, A7.2).
class ReviewSessionState {
  /// Создаёт состояние.
  const ReviewSessionState({
    required this.items,
    required this.index,
    required this.revealed,
    required this.busy,
    required this.undoCount,
    this.preview,
  });

  /// Очередь сессии (фиксированная, ADR-008).
  final List<ReviewSessionItem> items;

  /// Индекс текущей карточки; `items.length` — сессия завершена.
  final int index;

  /// Показан ли ответ текущей карточки.
  final bool revealed;

  /// Идёт запись в БД (кнопки/undo заблокированы).
  final bool busy;

  /// Сколько откатов доступно (стек undo).
  final int undoCount;

  /// Прогноз интервалов текущей карточки над кнопками (SPEC A7.2).
  final Map<Rating, Duration>? preview;

  /// Всего карточек в сессии.
  int get total => items.length;

  /// Сколько карточек уже оценено.
  int get ratedCount => index;

  /// Сессия завершена.
  bool get isCompleted => index >= items.length;

  /// Текущая карточка; `null` после завершения.
  ReviewSessionItem? get current => isCompleted ? null : items[index];
}

/// Движок классической сессии: очередь, раскрытие ответа, оценки, undo.
///
/// Держит только состояние экрана; все записи — через [ReviewRepository]
/// (транзакционно, SPEC A5). Ошибки БД пробрасываются вызывающему коду:
/// экран показывает сообщение из ARB, карточка остаётся текущей.
class ReviewSessionEngine extends ChangeNotifier {
  /// Создаёт движок поверх снимка карточек колоды.
  ReviewSessionEngine({
    required this.cards,
    required this.scheduler,
    required this.reviewRepository,
    required this.clock,
    this.mode = reviewModeClassic,
  });

  /// Снимок карточек колоды на момент старта сессии.
  final List<Card> cards;

  /// Планировщик интервалов.
  final Scheduler scheduler;

  /// Порт записи повторений (транзакция на оценку).
  final ReviewRepository reviewRepository;

  /// Источник текущего времени (в тестах — управляемый).
  final DateTime Function() clock;

  /// Режим, записываемый в `review_logs.mode`.
  final String mode;

  final ReviewSessionState _state = const ReviewSessionState(
    items: <ReviewSessionItem>[],
    index: 0,
    revealed: false,
    busy: false,
    undoCount: 0,
  );

  /// Текущее состояние сессии.
  ReviewSessionState get state => _state;

  /// Строит очередь и готовит первую карточку. Вызывается один раз экраном.
  void start() {
    // Красная фаза: движок ещё не строит очередь.
  }

  /// Раскрывает ответ текущей карточки (тап/пробел).
  void reveal() {
    // Красная фаза: раскрытие ещё не реализовано.
  }

  /// Оценивает текущую карточку и переходит к следующей.
  ///
  /// Возвращает `false`, если сессия завершена или идёт запись.
  Future<bool> rate(Rating rating) async => false;

  /// Откатывает последнюю оценку; `false` — откатывать нечего/идёт запись.
  Future<bool> undo() async => false;

  @override
  String toString() =>
      'ReviewSessionEngine(mode: $mode, cards: ${cards.length}, '
      'rated: ${_state.index})';
}
