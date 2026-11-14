import 'package:cardflow/domain/scheduling/rating.dart';

/// Минимальное расстояние короткого свайпа-оценки в ленте (SPEC A7.3).
const double feedSwipeMinDistance = 80;

/// Минимальная скорость короткого свайпа-оценки, px/с (SPEC A7.3).
const double feedSwipeMinVelocity = 300;

/// Доля ширины карточки, после которой свайп считается «долгим» (SPEC A7.3).
const double feedLongSwipeFraction = 0.6;

/// Оценка, которую означает горизонтальный свайп в ленте (SPEC A7.3).
///
/// Чистая функция без Flutter: [dx] — смещение пальца/мыши в логических
/// пикселях (вправо > 0), [velocity] — скорость в конце жеста (px/с),
/// [width] — ширина карточки.
///
/// - Вправо: долгий свайп (≥ [feedLongSwipeFraction] ширины) — [Rating.easy],
///   короткий (≥ [feedSwipeMinDistance] и ≥ [feedSwipeMinVelocity]) — [Rating.good].
/// - Влево: долгий — [Rating.hard], короткий — [Rating.again].
/// - Всё остальное (случайный/слишком короткий/слишком медленный жест) —
///   `null`, карточка возвращается пружиной.
///
/// Для «долгого» свайпа скорость не требуется: пользователь осознанно провёл
/// карточку больше половины ширины (ADR-016).
Rating? feedSwipeRating({
  required double dx,
  required double velocity,
  required double width,
}) {
  if (width <= 0) return null;
  final double longThreshold = width * feedLongSwipeFraction;
  if (dx > 0) {
    if (dx >= longThreshold) return Rating.easy;
    if (dx >= feedSwipeMinDistance && velocity >= feedSwipeMinVelocity) {
      return Rating.good;
    }
    return null;
  }
  if (dx < 0) {
    if (-dx >= longThreshold) return Rating.hard;
    if (-dx >= feedSwipeMinDistance && velocity <= -feedSwipeMinVelocity) {
      return Rating.again;
    }
    return null;
  }
  return null;
}
