import 'package:cardflow/api/generation/content_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контракт нормализации текста для сравнения (этап Ingestion, ADR-050).
///
/// Нормализация живёт **отдельно** от якорей: `Block.text` остаётся текстом
/// источника, а сравнивается `Block.normalizedText`. Тесты фиксируют четыре
/// обещанных преобразования и идемпотентность.
void main() {
  const ContentNormalizer normalizer = ContentNormalizer();

  test('пробелы: повторы, табуляции и NBSP → один пробел, края обрезаны', () {
    expect(
      normalizer.normalizeWhitespace(
        '  Слово\t\tдва   три\u00A0четыре\u2009пять  ',
      ),
      'Слово два три четыре пять',
    );
    expect(normalizer.normalizeWhitespace('a\nb'), 'a b');
    expect(
      normalizer.normalizeWhitespace('нулевой\u200Bширины'),
      'нулевой ширины',
    );
  });

  test('ё → е (в обоих регистрах)', () {
    expect(normalizer.normalizeYo('Ёлка и ещё её'), 'Елка и еще ее');
  });

  test('кавычки: ёлочки, лапки и одинарные → прямые', () {
    expect(
      normalizer.normalizeQuotes('«Привет» „мир“ “тест”'),
      '"Привет" "мир" "тест"',
    );
    expect(normalizer.normalizeQuotes('‘один’ `два´'), "'один' 'два'");
    expect(normalizer.normalizeQuotes('прямые "кавычки"'), 'прямые "кавычки"');
  });

  test('дефисы и тире: все виды → «-», мягкий перенос удаляется', () {
    expect(
      normalizer.normalizeDashes('1—2, 3–4, 5‐6, 7−8'),
      '1-2, 3-4, 5-6, 7-8',
    );
    expect(normalizer.normalizeDashes('сло\u00ADво'), 'слово');
    expect(normalizer.normalizeDashes('обычный-дефис'), 'обычный-дефис');
  });

  test('полная нормализация собирает все правила', () {
    const String raw = '«Ёлка»\u00A0—  это\tдерево';
    expect(normalizer.normalize(raw), '"Елка" - это дерево');
  });

  test('нормализация идемпотентна', () {
    const String raw = ' «Ёлка» —  это\tдерево ';
    final String once = normalizer.normalize(raw);
    expect(normalizer.normalize(once), once);
  });
}
