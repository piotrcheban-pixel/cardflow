import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_card_limit.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';

/// Распределение общего числа карточек из пожеланий (fix-gen, A8.1).
void main() {
  test('requestedCardCount: «20 карточек», «сделай 15 карточек»', () {
    expect(requestedCardCount('Статика: аксиомы и фермы. 20 карточек'), 20);
    expect(requestedCardCount('Сделайте 15 карточек по теме'), 15);
    expect(requestedCardCount('Нужно 8 карточек'), 8);
    expect(requestedCardCount('20 cards about statics'), 20);
  });

  test('requestedCardCount: число без слова «карточка» не считается', () {
    expect(requestedCardCount('Глава 3, акцент на датах'), isNull);
    expect(requestedCardCount('Статика'), isNull);
    expect(requestedCardCount(null), isNull);
    expect(requestedCardCount('   '), isNull);
  });

  test('requestedCardCount: абсурдно большое число ограничивается', () {
    expect(requestedCardCount('1000 карточек'), kMaxRequestedCards);
  });

  test(
    'distributeCardLimits: сумма равна запрошенному, пропорции по объёму',
    () {
      final limits = distributeCardLimits(
        volumes: <int>[100, 300, 100],
        total: 20,
      );
      expect(limits.fold<int>(0, (int sum, int value) => sum + value), 20);
      expect(limits[1], greaterThan(limits[0]));
      expect(limits[2], greaterThanOrEqualTo(limits[0] - 1));
    },
  );

  test('distributeCardLimits: один фрагмент получает всё', () {
    expect(distributeCardLimits(volumes: <int>[500], total: 12), <int>[12]);
  });

  test('distributeCardLimits: не больше kMaxCardsPerChunk на фрагмент', () {
    final limits = distributeCardLimits(
      volumes: <int>[100, 100, 100],
      total: 200,
    );
    for (final int limit in limits) {
      expect(limit, lessThanOrEqualTo(kMaxCardsPerChunk));
    }
  });

  test('distributeCardLimits: каждый непустой фрагмент получает хотя бы 1', () {
    final limits = distributeCardLimits(volumes: <int>[1000, 1, 1], total: 3);
    expect(limits.every((int limit) => limit >= 1), isTrue);
  });

  test('distributeCardLimits: пустой объём и нулевой итог', () {
    expect(distributeCardLimits(volumes: <int>[], total: 10), isEmpty);
    expect(distributeCardLimits(volumes: <int>[10, 20], total: 0), <int>[0, 0]);
  });
}
