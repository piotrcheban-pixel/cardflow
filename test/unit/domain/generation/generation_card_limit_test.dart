import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_card_limit.dart';

/// Разбор заказа карточек из пожеланий без искусственного потолка 200 (L-24).
///
/// Распределение заказа по фрагментам живёт в планировщике (D.5/D.7) и
/// проверяется `generation_chunk_planner_test`, а не отдельной утилитой.
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

  test('заказ больше 200 не режется: 201, 500, 1000 сохраняются', () {
    expect(requestedCardCount('201 карточка'), 201);
    expect(requestedCardCount('500 карточек'), 500);
    expect(requestedCardCount('1000 карточек'), 1000);
    expect(requestedCardCount('10000 cards'), 10000);
  });

  test('переполнение int: заказ ограничен представлением, а не 200', () {
    expect(
      requestedCardCount('999999999999999999999 карточек'),
      kMaxRepresentableRequestedCards,
    );
  });
}
