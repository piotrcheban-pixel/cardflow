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

  // Итерация 7.10, ADR-024: PDFium отдаёт C1-управляющие (U+0080–U+009F),
  // BOM/zero-width и одиночные суррогаты — API провайдера отклоняет такой текст.
  group('TextSanitizer: Unicode-управляющие и кодировка', () {
    test('удаляет C1-управляющие из PDF', () {
      expect(sanitizer.sanitize('a\u0080b\u0085c\u009Fd'), 'abcd');
      expect(sanitizer.isEmpty('\u0080\u0081\u0082'), isTrue);
    });

    test('удаляет BOM, zero-width и bidi-марки', () {
      expect(
        sanitizer.sanitize('текст\uFEFF\u200B\u200E\u202E\u2066'),
        'текст',
      );
    });

    test('переводит разделители строк U+2028/U+2029 в \\n', () {
      expect(sanitizer.sanitize('a\u2028b\u2029c'), 'a\nb\nc');
    });

    test('удаляет одиночные суррогаты и сохраняет эмодзи', () {
      expect(sanitizer.sanitize('a\uD800b\uDC00c'), 'abc');
      expect(sanitizer.sanitize('смайл \u{1F600} и текст'), 'смайл 😀 и текст');
    });

    test('сохраняет кириллицу, CJK и математические символы', () {
      expect(sanitizer.sanitize('Москва 東京 ∑ x²'), 'Москва 東京 ∑ x²');
    });

    test('идемпотентен для текста с Unicode-мусором', () {
      const String source = '\uFEFF  A\u0085\n\n\n\u2028B\uD800 \u200B';
      final String once = sanitizer.sanitize(source);
      expect(sanitizer.sanitize(once), once);
      expect(once, 'A\n\nB');
    });
  });
}
