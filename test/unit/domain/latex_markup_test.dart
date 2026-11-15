import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/latex_markup.dart';

void main() {
  test('inline и display формулы разбираются с сохранением текста', () {
    final markup = LatexMarkup.parse(r'Сумма $a+b$, затем $$c=d$$.');

    expect(markup.hasUnclosedDelimiter, isFalse);
    expect(markup.segments, hasLength(5));
    expect(markup.segments[0].kind, LatexSegmentKind.text);
    expect(markup.segments[0].value, 'Сумма ');
    expect(markup.segments[1].kind, LatexSegmentKind.inlineFormula);
    expect(markup.segments[1].value, 'a+b');
    expect(markup.segments[3].kind, LatexSegmentKind.displayFormula);
    expect(markup.segments[3].value, 'c=d');
    expect(markup.segments[4].value, '.');
  });

  test('две формулы — два независимых шага', () {
    final markup = LatexMarkup.parse(r'$x=1$ и $y=2$');
    expect(
      markup.segments.where((segment) => segment.kind != LatexSegmentKind.text),
      hasLength(2),
    );
  });

  test('незакрытый делимитер помечается для fallback', () {
    final markup = LatexMarkup.parse(r'Ошибка $x+1');
    expect(markup.hasUnclosedDelimiter, isTrue);
    expect(markup.segments.single.kind, LatexSegmentKind.text);
    expect(markup.segments.single.value, r'Ошибка $x+1');
  });

  // fix-gen (Д4): `\(…\)`/`\[…\]` модель иногда пишет вместо `$…$`; разметка
  // нормализует их к поддерживаемым разделителям (SPEC A7.10).
  test(r'\(…\) и \[…\] нормализуются к $…$ и $$…$$', () {
    final inline = LatexMarkup.parse(r'Формула \(x^2\)');
    expect(inline.segments, hasLength(2));
    expect(inline.segments[1].kind, LatexSegmentKind.inlineFormula);
    expect(inline.segments[1].value, 'x^2');

    final display = LatexMarkup.parse(r'Блок \[c=d\]');
    expect(display.segments[1].kind, LatexSegmentKind.displayFormula);
    expect(display.segments[1].value, 'c=d');
  });

  test(r'экранированный \$ — текст, а не делимитер', () {
    final markup = LatexMarkup.parse(r'Цена \$5 и формула $x^2$');
    expect(markup.hasUnclosedDelimiter, isFalse);
    expect(markup.segments.where((segment) => segment.isFormula), hasLength(1));
    expect(markup.segments.first.value, contains(r'$5'));
  });
}
