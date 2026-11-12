import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/text/normalization.dart';

void main() {
  group('normalizeCardText', () {
    test('нижний регистр, ё→е, пунктуация, пробелы', () {
      expect(normalizeCardText('  Ёлка, Зелёная! '), 'елка зеленая');
    });
  });

  group('contentHashOf', () {
    test('детерминирован и не зависит от регистра/ё/пунктуации/пробелов', () {
      final first = contentHashOf(front: 'Что такое FSRS?', back: 'Алгоритм.');
      final second = contentHashOf(
        front: '  что ТАКОЕ fsrs ',
        back: 'алгоритм',
      );
      expect(first, second);
    });

    test('разные front/back дают разные хеши', () {
      expect(
        contentHashOf(front: 'a', back: 'b'),
        isNot(equals(contentHashOf(front: 'b', back: 'a'))),
      );
    });

    test('разделитель не позволяет склеить пары', () {
      expect(
        contentHashOf(front: 'ab', back: 'c'),
        isNot(equals(contentHashOf(front: 'a', back: 'bc'))),
      );
    });

    test('совпадает с sha256 от нормализованных строк через \u0000', () {
      const front = 'Вопрос';
      const back = 'Ответ';
      final expected = sha256
          .convert(
            utf8.encode(
              '${normalizeForComparison(front)}\u0000'
              '${normalizeForComparison(back)}',
            ),
          )
          .toString();
      expect(contentHashOf(front: front, back: back), expected);
    });
  });
}
