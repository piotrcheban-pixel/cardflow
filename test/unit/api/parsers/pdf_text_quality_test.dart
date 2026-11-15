import 'package:cardflow/api/parsers/pdf_text_quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// Итерация 7.10, ADR-024: проверка «нечитаемого» текста из PDF.
///
/// PDFium при битом ToUnicode-словаре отдаёт U+FFFD и одиночные суррогаты;
/// такой текст уходил в API и провайдер отвечал 400 / мусором.
void main() {
  const PdfTextQuality quality = PdfTextQuality();

  group('PdfTextQuality: символы замены', () {
    test('читаемый текст не считается нечитаемым', () {
      expect(
        quality.isUnreadable(
          'Фотосинтез — процесс преобразования световой энергии в химическую.',
        ),
        isFalse,
      );
      expect(quality.isUnreadable('Hello CardFlow PDF'), isFalse);
      expect(quality.isUnreadable(''), isFalse);
    });

    test('единичная замена допустима', () {
      expect(
        quality.isUnreadable('Нормальный текст с одной \uFFFD заменой'),
        isFalse,
      );
    });

    test('много замен подряд → нечитаемый текст', () {
      final String garbled = '\uFFFD' * 10;
      expect(quality.isUnreadable(garbled), isTrue);
    });

    test('порог: 5 замен при доле ≥ 5 %', () {
      final String five = '\uFFFD' * 5;
      expect(
        quality.isUnreadable(five),
        isTrue,
        reason: '5 замен из 5 символов — доля 100 %',
      );
      expect(
        quality.isUnreadable('${'\uFFFD' * 5}${'a' * 95}'),
        isFalse,
        reason: '5 замен из 100 символов — доля 5 %, граница допускается',
      );
      expect(
        quality.isUnreadable('${'\uFFFD' * 4}${'a' * 96}'),
        isFalse,
        reason: '4 замены меньше порога количества',
      );
    });

    test('короткий текст с 5 заменами — нечитаемый', () {
      expect(quality.isUnreadable('\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD'), isTrue);
    });
  });

  group('PdfTextQuality: кодировка UTF-8', () {
    test('одиночные суррогаты нормализуются в замену и считаются', () {
      final String broken = '\uD800' * 10;
      expect(quality.utf8Normalized(broken), '\uFFFD' * 10);
      expect(quality.isUnreadable(broken), isTrue);
    });

    test('валидная пара суррогатов остаётся символом', () {
      expect(quality.utf8Normalized('😀'), '😀');
      expect(quality.isUnreadable('😀 текст'), isFalse);
    });

    test('смешанный текст: замена и валидные символы', () {
      final String text = '${'текст ' * 40}${'\uFFFD' * 6}';
      expect(quality.isUnreadable(text), isFalse, reason: 'доля замен < 5 %');
    });

    test('порог доли: 5 замен из 20 символов — нечитаемый', () {
      expect(quality.isUnreadable('${'a' * 15}${'\uFFFD' * 5}'), isTrue);
    });
  });
}
