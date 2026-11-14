import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/text/text_sanitizer.dart';

/// Итерация 7.8: единый санитайзер локально извлечённого текста
/// (фикс Word-бага: NUL и другие управляющие символы ломали запрос к API).
void main() {
  const TextSanitizer sanitizer = TextSanitizer();

  group('TextSanitizer: управляющие символы', () {
    test('удаляет NUL, вертикальную табуляцию, BEL и DEL', () {
      expect(sanitizer.sanitize('a\u0000b\u000Bc\u0007d\u007Fe'), 'abcde');
    });

    test('сохраняет табуляцию и перевод строки', () {
      expect(sanitizer.sanitize('a\tb\nc'), 'a\tb\nc');
    });

    test('переводит CRLF и CR в LF', () {
      expect(sanitizer.sanitize('a\r\nb\rc'), 'a\nb\nc');
    });

    test('неразрывный пробел становится обычным', () {
      expect(sanitizer.sanitize('Москва\u00A0— столица'), 'Москва — столица');
    });
  });

  group('TextSanitizer: строки и пробелы', () {
    test('сжимает три и более перевода строки до двух', () {
      expect(sanitizer.sanitize('a\n\n\n\nb'), 'a\n\nb');
      expect(sanitizer.sanitize('a\n\n\nb'), 'a\n\nb');
    });

    test('убирает хвостовые пробелы и обрезает края', () {
      expect(sanitizer.sanitize('  a   \n b\t \n'), 'a\n b');
    });

    test('идемпотентен', () {
      const String source = '  A\u0000\n\n\n  B \t\r\n';
      final String once = sanitizer.sanitize(source);
      expect(sanitizer.sanitize(once), once);
      expect(once, 'A\n\n  B');
    });

    test('пустой и состоящий только из управляющих текст — isEmpty', () {
      expect(sanitizer.isEmpty(''), isTrue);
      expect(sanitizer.isEmpty('   \n\n'), isTrue);
      expect(sanitizer.isEmpty('\u0000\u000B\u0007'), isTrue);
      expect(sanitizer.isEmpty('факт'), isFalse);
    });
  });
}
