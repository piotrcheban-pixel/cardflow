import 'package:cardflow/domain/scheduling/rating.dart';

/// Минимальное расстояние короткого свайпа-оценки в ленте (SPEC A7.3).
const double feedSwipeMinDistance = 80;

/// Минимальная скорость короткого свайпа-оценки, px/с (SPEC A7.3).
const double feedSwipeMinVelocity = 300;

/// Доля ширины карточки, после которой свайп считается «долгим» (SPEC A7.3).
const double feedLongSwipeFraction = 0.6;

/// Оценка, которую означает горизонтальный свайп в ленте (SPEC A7.3).
///
/// Красная фаза итерации 4: сигнатура зафиксирована тестами, поведение ещё не
/// реализовано.
Rating? feedSwipeRating({
  required double dx,
  required double velocity,
  required double width,
}) {
  return null;
}
