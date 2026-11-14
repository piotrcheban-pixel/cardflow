import 'package:flutter/foundation.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review.dart';
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

  /// Копия с изменёнными полями (оценка сбрасывается только через undo —
  /// отдельным конструктором).
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

  /// Идёт запись в БД.
  final bool busy;

  /// Сколько откатов доступно.
  final int undoCount;

  /// Всего карточек.
  int get total => items.length;

  /// Сколько карточек оценено.
  int get ratedCount =>
      items.where((FeedSessionItem item) => item.rated).length;

  /// Сессия завершена, когда оценены все карточки (ADR-016).
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
/// через [ReviewRepository] (одна транзакция на оценку, SPEC A5).
class FeedSessionEngine extends ChangeNotifier {
  /// Создаёт движок поверх снимка карточек колоды.
  FeedSessionEngine({
    required this.cards,
    required this.scheduler,
    required this.reviewRepository,
    required this.clock,
    this.mode = reviewModeFeed,
  });

  /// Снимок карточек колоды на момент старта сессии.
  final List<Card> cards;

  /// Планировщик интервалов.
  final Scheduler scheduler;

  /// Порт записи повторений.
  final ReviewRepository reviewRepository;

  /// Источник текущего времени.
  final DateTime Function() clock;

  /// Режим, записываемый в `review_logs.mode`.
  final String mode;

  FeedSessionState _state = const FeedSessionState(
    items: <FeedSessionItem>[],
    index: 0,
    busy: false,
    undoCount: 0,
  );

  /// Текущее состояние ленты.
  FeedSessionState get state => _state;

  /// Строит очередь. Вызывается один раз экраном.
  void start() {}

  /// Переходит на страницу [index] без оценки (листание не засчитывается).
  void visit(int index) {}

  /// Раскрывает/скрывает ответ текущей карточки.
  void toggleReveal() {}

  /// Оценивает текущую карточку; `false` — нельзя оценить.
  Future<bool> rate(Rating rating) async => false;

  /// Переходит к следующей неоценённой карточке (авто-продвижение).
  bool advance() => false;

  /// Откатывает последнюю оценку.
  Future<bool> undo() async => false;
}
