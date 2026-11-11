import 'package:fsrs/fsrs.dart' as fsrs;

import 'rating.dart';
import 'scheduling_card.dart';

export 'scheduling_card.dart' show CardState;

/// Маппинг доменных оценок и состояний на типы пакета `fsrs`.
///
/// Единственное место в проекте, где доменные типы пересекаются с API
/// планировщика: при замене библиотеки меняется только этот файл и адаптер
/// в `scheduler.dart` (ADR-004).
abstract final class FsrsMapper {
  /// Доменная оценка → оценка FSRS (1:1 по значениям).
  static fsrs.Rating toFsrs(Rating rating) => switch (rating) {
    Rating.again => fsrs.Rating.again,
    Rating.hard => fsrs.Rating.hard,
    Rating.good => fsrs.Rating.good,
    Rating.easy => fsrs.Rating.easy,
  };

  /// Оценка FSRS → доменная оценка.
  static Rating fromFsrs(fsrs.Rating rating) => switch (rating) {
    fsrs.Rating.again => Rating.again,
    fsrs.Rating.hard => Rating.hard,
    fsrs.Rating.good => Rating.good,
    fsrs.Rating.easy => Rating.easy,
  };

  /// Доменное состояние → состояние FSRS.
  ///
  /// У FSRS 6 нет отдельного состояния `New`: новая карточка — это `learning`
  /// с шагом 0, поэтому `new` и `learning` отображаются одинаково.
  static fsrs.State toFsrsState(CardState state) => switch (state) {
    CardState.newState || CardState.learning => fsrs.State.learning,
    CardState.review => fsrs.State.review,
    CardState.relearning => fsrs.State.relearning,
  };

  /// Состояние FSRS → доменное состояние (без различения `new`).
  ///
  /// Отличить новую карточку от изучаемой можно по `lastReview == null`:
  /// это делает адаптер планировщика.
  static CardState fromFsrsState(fsrs.State state) => switch (state) {
    fsrs.State.learning => CardState.learning,
    fsrs.State.review => CardState.review,
    fsrs.State.relearning => CardState.relearning,
  };
}
