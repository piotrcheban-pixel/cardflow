import 'package:cardflow/ui/decks/deck_archive_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

/// Красная фаза: безопасное имя файла для экспорта колоды в ZIP (SPEC A6.9).
void main() {
  const String fallback = 'Колода';

  group('deckArchiveFileName: имя файла экспорта', () {
    test('добавляет расширение .zip', () {
      expect(
        deckArchiveFileName('Испанский', fallbackName: fallback),
        'Испанский.zip',
      );
    });

    test('обрезает внешние пробелы и схлопывает внутренние', () {
      expect(
        deckArchiveFileName('  Моя   колода  ', fallbackName: fallback),
        'Моя колода.zip',
      );
    });

    test('убирает недопустимые для файловой системы символы', () {
      final String name = deckArchiveFileName(
        r'Моя/колода\для:тест*?"<>|',
        fallbackName: fallback,
      );
      expect(name, endsWith('.zip'));
      for (final String invalid in <String>[
        '/',
        r'\',
        ':',
        '*',
        '?',
        '"',
        '<',
        '>',
        '|',
      ]) {
        expect(
          name,
          isNot(contains(invalid)),
          reason: 'В имени файла остался недопустимый символ "$invalid"',
        );
      }
      expect(name, 'Моя колода для тест.zip');
    });

    test('пустое/пробельное имя заменяется запасным из ARB', () {
      expect(deckArchiveFileName('   ', fallbackName: fallback), 'Колода.zip');
      expect(deckArchiveFileName('', fallbackName: fallback), 'Колода.zip');
    });

    test('непригодное запасное имя заменяется брендовым fallback', () {
      expect(deckArchiveFileName('   ', fallbackName: '   '), 'cardflow.zip');
    });

    test('имя только из недопустимых символов заменяется запасным', () {
      expect(
        deckArchiveFileName('///:::', fallbackName: fallback),
        'Колода.zip',
      );
    });

    test('слишком длинное имя обрезается до безопасной длины', () {
      final String name = deckArchiveFileName(
        'Очень длинное название колоды ${'а' * 200}',
        fallbackName: fallback,
      );
      expect(name, endsWith('.zip'));
      expect(name.length, lessThanOrEqualTo(84));
    });

    test('кириллица, цифры и дефисы сохраняются', () {
      expect(
        deckArchiveFileName('Колода-2 (часть 1)', fallbackName: fallback),
        'Колода-2 (часть 1).zip',
      );
    });
  });
}
