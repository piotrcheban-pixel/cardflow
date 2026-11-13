import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';

/// Красная фаза итерации 2: haptics оценок по таблице SPEC A7.2.
void main() {
  test('haptic-токены оценок: heavy / light / light / selection', () {
    expect(reviewHapticFor(Rating.again), ReviewHaptic.heavy);
    expect(reviewHapticFor(Rating.hard), ReviewHaptic.light);
    expect(reviewHapticFor(Rating.good), ReviewHaptic.light);
    expect(reviewHapticFor(Rating.easy), ReviewHaptic.selection);
  });

  test('каждая оценка имеет haptic (нет забытых значений)', () {
    for (final rating in Rating.values) {
      expect(reviewHapticFor(rating), isNotNull);
    }
  });
}
