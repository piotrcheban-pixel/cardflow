import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/cloze_markup.dart';

void main() {
  test('текст и несколько пропусков разбираются по порядку', () {
    final markup = ClozeMarkup.parse(
      'Столица {{c1::Париж}}, валюта {{c2::евро}}.',
    );

    expect(markup.hasGaps, isTrue);
    expect(markup.segments, hasLength(5));
    expect(markup.segments[0].text, 'Столица ');
    expect(markup.segments[1].number, 1);
    expect(markup.segments[1].answer, 'Париж');
    expect(markup.segments[2].text, ', валюта ');
    expect(markup.segments[3].number, 2);
    expect(markup.segments[4].text, '.');
  });

  test('одинаковые номера образуют одну группу раскрытия', () {
    final markup = ClozeMarkup.parse('{{c1::А}} + {{c2::Б}} = {{c1::А}}');

    final numbers = markup.segments
        .where((segment) => segment.isGap)
        .map((segment) => segment.number)
        .toList();
    expect(numbers, <int?>[1, 2, 1]);
  });

  test('соседние пропуски не сливаются', () {
    final markup = ClozeMarkup.parse('{{c1::А}}{{c2::Б}}');
    expect(markup.segments.where((segment) => segment.isGap), hasLength(2));
  });

  group('некорректная разметка остаётся обычным текстом', () {
    for (final source in <String>[
      '{{c1::не закрыто',
      '{{c0::ноль}}',
      '{{c-1::минус}}',
      '{{c1::}}',
      '{{c::без номера}}',
      'обычный текст',
    ]) {
      test(source, () {
        final markup = ClozeMarkup.parse(source);
        expect(markup.hasGaps, isFalse);
        expect(markup.segments.single.text, source);
      });
    }
  });
}
