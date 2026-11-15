import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/deck_name.dart';

/// Имя колоды по умолчанию из темы пожелания (fix-gen, Д1).
void main() {
  test('первые слова темы становятся именем колоды', () {
    expect(
      deckNameFromWishes('Статика: аксиомы, связи, плоские фермы'),
      'Статика: аксиомы, связи, плоские фермы',
    );
    expect(
      deckNameFromWishes('Статика. Сделай 20 карточек, акцент на фермах'),
      'Статика',
    );
  });

  test('длинное пожелание обрезается по словам и символам', () {
    final String name = deckNameFromWishes(
      'Очень длинная тема про теоретическую механику и статику '
      'для подготовки к экзамену',
    );
    expect(name.split(' ').length, lessThanOrEqualTo(kDeckNameMaxWords));
    expect(name.length, lessThanOrEqualTo(kDeckNameMaxLength));
  });

  test('пустое пожелание — пустая строка (вызывающий берёт ARB)', () {
    expect(deckNameFromWishes(null), '');
    expect(deckNameFromWishes('   '), '');
    expect(deckNameFromWishes('...'), '');
  });

  test('кавычки по краям и хвостовая пунктуация убираются', () {
    expect(deckNameFromWishes('«Статика»'), 'Статика');
    expect(deckNameFromWishes('Фермы,'), 'Фермы');
  });
}
