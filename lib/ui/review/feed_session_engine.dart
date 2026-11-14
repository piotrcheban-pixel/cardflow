import 'package:flutter/foundation.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_scheduling.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/domain/review/review_repository.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';

/// Карточка ленты с состоянием предъявления (SPEC A7.3, ADR-016).
class FeedSessionItem {
  /// Создаёт элемент ленты.
  const FeedSessionItem({
    required this.card,
    required this.scheduling,
    this.revealed = false,
    this.rated = false,
    this.rating,
  });

  /// Доменная карточка.
  final Card card;

  /// Снимок FSRS-состояния на момент старта сессии.
  final SchedulingCard scheduling;

  /// Показан ли ответ.
  final bool revealed;

  /// Оценена ли карточка в этой сессии.
  final bool rated;

  /// Оценка, если карточка уже оценена.
  final Rating? rating;

  /// Копия с изменёнными полями. Оценка сбрасывается только через undo —
  /// отдельным конструктором (см. [FeedSessionEngine.undo]).
  FeedSessionItem copyWith({bool? revealed, bool? rated, Rating? rating}) {
    return FeedSessionItem(
      card: card,
      scheduling: scheduling,
      revealed: revealed ?? this.revealed,
      rated: rated ?? this.rated,
      rating: rating ?? this.rating,
    );
  }
}

/// Состояние ленты для UI-слоя (SPEC A7.3).
class FeedSessionState {
  /// Создаёт состояние.
  const FeedSessionState({
    required this.items,
    required this.index,
    required this.busy,
    required this.undoCount,
  });

  /// Карточки сессии.
  final List<FeedSessionItem> items;

  /// Индекс текущей страницы.
  final int index;

  /// Идёт запись в БД (жесты заблокированы).
  final bool busy;

  /// Сколько откатов доступно.
  final int undoCount;

  /// Всего карточек.
  int get total => items.length;

  /// Сколько карточек оценено.
  int get ratedCount =>
      items.where((FeedSessionItem item) => item.rated).length;

  /// Сессия завершена, когда оценены все карточки (ADR-016); пустая очередь
  /// тоже завершена — экран показывает отдельное пустое состояние.
  bool get isCompleted => items.every((FeedSessionItem item) => item.rated);

  /// Текущая карточка; `null` после завершения.
  FeedSessionItem? get current =>
      isCompleted || index < 0 || index >= items.length ? null : items[index];

  /// Можно ли оценить текущую карточку.
  bool get canRate => current != null && !current!.rated && !busy;
}

/// Движок режима «Лента» (SPEC A7.3, ADR-016).
///
/// Хранит снимок очереди и состояние карточек; записи повторений и undo идут
/// через [ReviewRepository] (одна транзакция на оценку, SPEC A5). Оценка
/// фиксируется сразу, листание и авто-продвижение — без записи.
class FeedSessionEngine extends ChangeNotifier {
  /// Создаёт движок поверх снимка карточек колоды.
  FeedSessionEngine({
    required this.cards,
    required this.scheduler,
    required this.reviewRepository,
    required this.clock,
    this.mode = reviewModeFeed,
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
  /// по ADR-016 (due/new).
  final bool prebuilt;

  /// Остаток дневного лимита новых карточек на момент старта сессии
  /// (A6.6, ADR-019 §8); `null` — без лимита, `0` — лимит дня исчерпан.
  final int? newLimit;

  /// Остаток дневного лимита повторных карточек; `null` — без лимита.
  final int? reviewLimit;

  final List<ReviewUndo> _undoStack = <ReviewUndo>[];
  List<FeedSessionItem> _items = const <FeedSessionItem>[];
  int _index = 0;
  bool _busy = false;
  bool _initialized = false;
  bool _disposed = false;
  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Текущее состояние ленты.
  FeedSessionState get state => FeedSessionState(
    items: List<FeedSessionItem>.unmodifiable(_items),
    index: _index,
    busy: _busy,
    undoCount: _undoStack.length,
  );

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
    _items = <FeedSessionItem>[
      for (final Card card in queue)
        FeedSessionItem(
          card: card,
          scheduling: CardSchedulingMapper.toSchedulingCard(card, now: now),
        ),
    ];
    _index = 0;
    _shownAt = now;
    _initialized = true;
    _emit();
  }

  /// Переходит на страницу [index] без оценки (листание не засчитывается).
  ///
  /// Во время записи оценки листание игнорируется: иначе завершение записи
  /// пометило бы не ту карточку (гонка `_index`).
  void visit(int index) {
    if (!_initialized ||
        _busy ||
        index == _index ||
        index < 0 ||
        index >= _items.length) {
      return;
    }
    _index = index;
    _shownAt = clock().toUtc();
    _emit();
  }

  /// Раскрывает/скрывает ответ текущей карточки.
  void toggleReveal() {
    if (!_initialized || _busy) return;
    final FeedSessionItem? item = state.current;
    if (item == null || item.rated) return;
    _replaceItem(_index, item.copyWith(revealed: !item.revealed));
    _emit();
  }

  /// Оценивает текущую карточку и переходит к следующей неоценённой.
  ///
  /// Возвращает `false`, если оценивать нельзя (завершено/идёт запись/уже
  /// оценено). Ошибка БД пробрасывается, состояние остаётся прежним.
  Future<bool> rate(Rating rating) async {
    if (!_initialized || _busy) return false;
    final FeedSessionItem? item = state.current;
    if (item == null || item.rated) return false;

    final DateTime reviewedAt = clock().toUtc();
    final int ratedIndex = _index;
    final SchedulingCard outcome = scheduler
        .review(item.scheduling, rating, now: reviewedAt)
        .card;

    _busy = true;
    _emit();
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
      _busy = false;
      _emit();
      rethrow;
    }
    _undoStack.add(undo);
    _replaceItem(ratedIndex, item.copyWith(rated: true, rating: rating));
    final int? next = _nextUnratedIndexFrom(ratedIndex);
    if (next != null) {
      _index = next;
      _shownAt = clock().toUtc();
    }
    _busy = false;
    _emit();
    return true;
  }

  /// Переходит к следующей неоценённой карточке (авто-продвижение).
  ///
  /// Оценку не ставит: это навигация, а не ответ (SPEC A7.3, ADR-016).
  /// Идёт только вперёд: на последней странице авто-продвижение
  /// останавливается, а не прыгает в начало.
  bool advance() {
    if (!_initialized || _busy || state.isCompleted) return false;
    final int? next = _nextUnratedAfter(_index);
    if (next == null) return false;
    _index = next;
    _shownAt = clock().toUtc();
    _emit();
    return true;
  }

  /// Откатывает последнюю оценку; `false` — откатывать нечего/идёт запись.
  Future<bool> undo() async {
    if (!_initialized || _busy || _undoStack.isEmpty) return false;
    final ReviewUndo undo = _undoStack.last;
    _busy = true;
    _emit();
    try {
      await reviewRepository.undoReview(undo);
    } catch (_) {
      _busy = false;
      _emit();
      rethrow;
    }
    _undoStack.removeLast();
    final int index = _items.indexWhere(
      (FeedSessionItem item) => item.card.id == undo.previousCard.id,
    );
    if (index >= 0) {
      _items = List<FeedSessionItem>.of(_items);
      _items[index] = FeedSessionItem(
        card: _items[index].card,
        scheduling: _items[index].scheduling,
        revealed: true,
      );
      _index = index;
    }
    _shownAt = clock().toUtc();
    _busy = false;
    _emit();
    return true;
  }

  /// Следующая неоценённая карточка после [from]; если после нет — первая
  /// неоценённая с начала (чтобы оценка на последней странице не оставила
  /// сессию незавершённой).
  int? _nextUnratedIndexFrom(int from) {
    final int? after = _nextUnratedAfter(from);
    if (after != null) return after;
    for (int i = 0; i < _items.length; i++) {
      if (!_items[i].rated) return i;
    }
    return null;
  }

  /// Следующая неоценённая карточка строго после [index] (без перехода назад).
  int? _nextUnratedAfter(int index) {
    for (int i = index + 1; i < _items.length; i++) {
      if (!_items[i].rated) return i;
    }
    return null;
  }

  void _replaceItem(int index, FeedSessionItem item) {
    _items = List<FeedSessionItem>.of(_items);
    _items[index] = item;
  }

  void _emit() {
    // Асинхронная запись может завершиться уже после закрытия экрана: не
    // дёргаем notifyListeners у освобождённого ChangeNotifier.
    if (_disposed) return;
    notifyListeners();
  }

  @override
  String toString() =>
      'FeedSessionEngine(mode: $mode, cards: ${cards.length}, '
      'rated: ${state.ratedCount}, index: $_index)';
}
