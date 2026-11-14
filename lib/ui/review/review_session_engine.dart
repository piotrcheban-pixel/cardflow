import 'package:flutter/foundation.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_scheduling.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/review/review_queue.dart';
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
    this.prebuilt = false,
    this.newLimit,
    this.reviewLimit,
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

  /// `true` — [cards] уже отфильтрованы и упорядочены конструктором (A6.7,
  /// ADR-018) и не пересобираются [ReviewQueue]; `false` — очередь строится
  /// по ADR-008 (due/new).
  final bool prebuilt;

  /// Остаток дневного лимита новых карточек на момент старта сессии
  /// (A6.6, ADR-019 §8); `null` — без лимита, `0` — лимит дня исчерпан.
  final int? newLimit;

  /// Остаток дневного лимита повторных карточек; `null` — без лимита.
  final int? reviewLimit;

  ReviewSessionState _state = const ReviewSessionState(
    items: <ReviewSessionItem>[],
    index: 0,
    revealed: false,
    busy: false,
    undoCount: 0,
  );

  final List<ReviewUndo> _undoStack = <ReviewUndo>[];
  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  bool _initialized = false;
  bool _disposed = false;

  /// Текущее состояние сессии.
  ReviewSessionState get state => _state;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Строит очередь и готовит первую карточку. Вызывается один раз экраном.
  void start() {
    if (_initialized) return;
    final DateTime now = clock().toUtc();
    // План конструктора (A6.7, ADR-018) приходит уже отфильтрованным и
    // упорядоченным: пересборка `ReviewQueue` отбросила бы будущие `due`.
    final List<Card> queue = prebuilt
        ? List<Card>.unmodifiable(cards)
        : ReviewQueue.build(
            cards,
            now: now,
            newLimit: newLimit,
            reviewLimit: reviewLimit,
          );
    final List<ReviewSessionItem> items = <ReviewSessionItem>[
      for (final Card card in queue)
        ReviewSessionItem(
          card: card,
          scheduling: CardSchedulingMapper.toSchedulingCard(card, now: now),
        ),
    ];
    _shownAt = now;
    _initialized = true;
    _emit(items: items, index: 0, revealed: false, busy: false);
  }

  /// Раскрывает ответ текущей карточки (тап/пробел).
  void reveal() {
    if (!_initialized || _state.isCompleted || _state.revealed) return;
    _emit(index: _state.index, revealed: true, busy: _state.busy);
  }

  /// Оценивает текущую карточку и переходит к следующей.
  ///
  /// Возвращает `false`, если сессия завершена или идёт запись.
  Future<bool> rate(Rating rating) async {
    if (!_initialized || _state.busy || _state.isCompleted) return false;
    final ReviewSessionItem item = _state.current!;
    final DateTime reviewedAt = clock().toUtc();
    final SchedulingCard outcome = scheduler
        .review(item.scheduling, rating, now: reviewedAt)
        .card;

    _emit(index: _state.index, revealed: _state.revealed, busy: true);
    final ReviewUndo undo;
    try {
      undo = await reviewRepository.recordReview(
        cardId: item.card.id,
        rating: rating,
        reviewedAt: reviewedAt,
        outcome: outcome,
        mode: mode,
        elapsed: reviewedAt.difference(_shownAt),
      );
    } catch (_) {
      _emit(index: _state.index, revealed: _state.revealed, busy: false);
      rethrow;
    }
    _undoStack.add(undo);
    _shownAt = clock().toUtc();
    _emit(index: _state.index + 1, revealed: false, busy: false);
    return true;
  }

  /// Откатывает последнюю оценку; `false` — откатывать нечего/идёт запись.
  Future<bool> undo() async {
    if (!_initialized || _state.busy || _undoStack.isEmpty) return false;
    _emit(index: _state.index, revealed: _state.revealed, busy: true);
    try {
      await reviewRepository.undoReview(_undoStack.last);
    } catch (_) {
      _emit(index: _state.index, revealed: _state.revealed, busy: false);
      rethrow;
    }
    _undoStack.removeLast();
    _shownAt = clock().toUtc();
    _emit(index: _state.index - 1, revealed: true, busy: false);
    return true;
  }

  void _emit({
    List<ReviewSessionItem>? items,
    required int index,
    required bool revealed,
    required bool busy,
  }) {
    // Асинхронная запись может завершиться уже после закрытия экрана: не
    // дёргаем notifyListeners у освобождённого ChangeNotifier.
    if (_disposed) return;
    final List<ReviewSessionItem> queue = items ?? _state.items;
    final ReviewSessionItem? current = index < queue.length
        ? queue[index]
        : null;
    _state = ReviewSessionState(
      items: queue,
      index: index,
      revealed: revealed,
      busy: busy,
      undoCount: _undoStack.length,
      preview: current == null
          ? null
          : scheduler.previewIntervals(current.scheduling, now: clock()),
    );
    notifyListeners();
  }

  @override
  String toString() =>
      'ReviewSessionEngine(mode: $mode, cards: ${cards.length}, '
      'rated: ${_state.index})';
}
