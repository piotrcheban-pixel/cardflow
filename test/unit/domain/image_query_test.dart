import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/image_query.dart';

/// ADR-028 (итерация 7.12): производный запрос картинки из текста карточки и
/// распознавание запрета картинок в пожеланиях.
void main() {
  group('derivedImageQuery', () {
    test('«Что такое X?» → X', () {
      expect(
        derivedImageQuery(
          front: 'Что такое спайность минерала?',
          back: 'Способность раскалываться по плоскостям.',
          cardType: CardType.basic,
        ),
        'спайность минерала',
      );
    });

    test('«Что называют X?» и «Что понимают под X?» → X', () {
      expect(
        derivedImageQuery(
          front: 'Что называют шкалой Мооса?',
          back: 'Шкалу твёрдости.',
          cardType: CardType.basic,
        ),
        'шкалой Мооса',
      );
      expect(
        derivedImageQuery(
          front: 'Что понимают под плотностью минерала?',
          back: 'Массу единицы объёма.',
          cardType: CardType.basic,
        ),
        'плотностью минерала',
      );
    });

    test('«X — это …» → X', () {
      expect(
        derivedImageQuery(
          front: 'Спайность — это способность минерала раскалываться.',
          back: 'Определение.',
          cardType: CardType.basic,
        ),
        'Спайность',
      );
    });

    test('английская форма «What is X?»', () {
      expect(
        derivedImageQuery(
          front: 'What is a galaxy?',
          back: 'A gravitationally bound system.',
          cardType: CardType.basic,
        ),
        'a galaxy',
      );
    });

    test('обычный вопрос без определения — null', () {
      expect(
        derivedImageQuery(
          front: 'Какое животное считается самым крупным?',
          back: 'Слон.',
          cardType: CardType.basic,
        ),
        isNull,
      );
    });

    test('cloze и basic_reversed не дают производный запрос', () {
      expect(
        derivedImageQuery(
          front: 'Столица — {{c1::Париж}}',
          back: '',
          cardType: CardType.cloze,
        ),
        isNull,
      );
      expect(
        derivedImageQuery(
          front: 'Что такое термин?',
          back: 'Определение.',
          cardType: CardType.basicReversed,
        ),
        isNull,
      );
    });

    test('чисто числовой/служебный front не становится запросом', () {
      expect(
        derivedImageQuery(front: '1', back: '11', cardType: CardType.basic),
        isNull,
      );
      expect(
        derivedImageQuery(
          front: 'Что такое 12345?',
          back: 'Число.',
          cardType: CardType.basic,
        ),
        isNull,
      );
    });

    test('длинный предмет обрезается до лимита слов и символов', () {
      final String long = List<String>.filled(30, 'слово').join(' ');
      final String? query = derivedImageQuery(
        front: 'Что такое $long?',
        back: 'Ответ.',
        cardType: CardType.basic,
      );
      expect(query, isNotNull);
      expect(query!.split(' ').length, derivedImageQueryMaxWords);
      expect(query.length, lessThanOrEqualTo(derivedImageQueryMaxLength));
    });
  });

  group('wishesForbidImages', () {
    test('русские формулировки запрета', () {
      expect(wishesForbidImages('Без картинок, только текст'), isTrue);
      expect(wishesForbidImages('не добавляй картинки'), isTrue);
      expect(wishesForbidImages('Не ищи изображения'), isTrue);
      expect(wishesForbidImages('без иллюстраций'), isTrue);
    });

    test('английские формулировки запрета', () {
      expect(wishesForbidImages('no images please'), isTrue);
      expect(wishesForbidImages("don't add any pictures"), isTrue);
    });

    test('обычные пожелания не запрещают картинки', () {
      expect(wishesForbidImages('Покороче, 10 карточек'), isFalse);
      expect(wishesForbidImages('Добавь картинки где уместно'), isFalse);
      expect(wishesForbidImages(null), isFalse);
      expect(wishesForbidImages('   '), isFalse);
    });
  });
}
