import 'package:cardflow/domain/text/document_text_normalization.dart';
import 'package:flutter_test/flutter_test.dart';

/// Красная фаза итерации 3a: единая нормализация текста документов (SPEC A8.3).
void main() {
  group('normalizeDocumentText: переводы строк', () {
    test('CRLF и CR приводятся к LF', () {
      expect(normalizeDocumentText('строка1\r\nстрока2'), 'строка1\nстрока2');
      expect(normalizeDocumentText('строка1\rстрока2'), 'строка1\nстрока2');
      expect(
        normalizeDocumentText('a\r\nb\rc\nd'),
        'a\nb\nc\nd',
        reason: 'Смешанные переводы строк → только \\n',
      );
    });
  });

  group('normalizeDocumentText: невидимые символы', () {
    test(
      'NUL и управляющие символы удаляются, таб и перевод строки сохраняются',
      () {
        expect(
          normalizeDocumentText('a\u0000b\u0007c\td\ne'),
          'abc\td\ne',
          reason: 'NUL/BEL удаляются, таб и \\n сохраняются',
        );
        expect(normalizeDocumentText('a\u0000b'), 'ab');
        expect(normalizeDocumentText('a\u0007b'), 'ab');
        expect(normalizeDocumentText('a\tb'), 'a\tb');
      },
    );

    test('неразрывный пробел становится обычным', () {
      expect(
        normalizeDocumentText('Москва\u00A0— столица'),
        'Москва — столица',
      );
    });
  });

  group('normalizeDocumentText: пробелы и пустые строки', () {
    test('хвостовые пробелы строк убираются', () {
      expect(
        normalizeDocumentText('строка1   \nстрока2\t '),
        'строка1\nстрока2',
      );
    });

    test('три и более пустых строк сжимаются до двух', () {
      expect(normalizeDocumentText('a\n\n\n\nb'), 'a\n\nb');
      expect(normalizeDocumentText('a\n\n\nb'), 'a\n\nb');
      expect(
        normalizeDocumentText('a\n\nb'),
        'a\n\nb',
        reason: 'Ровно одна пустая строка сохраняется',
      );
    });

    test('общие пробелы по краям текста обрезаются', () {
      expect(normalizeDocumentText('  \n\n текст \n\n  '), 'текст');
    });

    test('нормализация идемпотентна', () {
      const String source = '  a  \r\n\r\n\r\n\r\nb\u0000\t \n\nc \n';
      final String once = normalizeDocumentText(source);
      final String twice = normalizeDocumentText(once);
      expect(twice, once);
      expect(once, 'a\n\nb\n\nc');
    });
  });
}
