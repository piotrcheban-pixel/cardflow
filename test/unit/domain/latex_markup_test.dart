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
      markup.segments
          .where((segment) => segment.kind != LatexSegmentKind.text),
      hasLength(2),
    );
  });

  test('незакрытый делимитер помечается для fallback', () {
    final markup = LatexMarkup.parse(r'Ошибка $x+1');
    expect(markup.hasUnclosedDelimiter, isTrue);
    expect(markup.segments.single.kind, LatexSegmentKind.text);
    expect(markup.segments.single.value, r'Ошибка $x+1');
  });

  test(r'\(…\) не поддерживается и остаётся текстом', () {
    const source = r'Формула \(x^2\)';
    final markup = LatexMarkup.parse(source);
    expect(markup.segments.single.kind, LatexSegmentKind.text);
    expect(markup.segments.single.value, source);
  });
}
