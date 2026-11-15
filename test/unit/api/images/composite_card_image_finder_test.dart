import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/images/composite_card_image_finder.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';

import '../../../helpers/generation_fakes.dart';

/// Составной поиск иллюстраций: источники по очереди (ADR-027).
void main() {
  test('первый источник дал картинку — второй не вызывается', () async {
    final primary = FakeCardImageFinder(
      byQuery: <String, GeneratedCardImage?>{
        'кремль': makeCardImage(query: 'кремль'),
      },
    );
    final fallback = FakeCardImageFinder(
      byQuery: <String, GeneratedCardImage?>{
        'кремль': makeCardImage(query: 'кремль'),
      },
    );

    final result = await CompositeCardImageFinder(<CardImageFinder>[
      primary,
      fallback,
    ]).findImage('кремль');

    expect(result, isNotNull);
    expect(primary.queries, <String>['кремль']);
    expect(fallback.queries, isEmpty);
  });

  test('первый источник пуст — используется резервный', () async {
    final primary = FakeCardImageFinder(
      byQuery: <String, GeneratedCardImage?>{'кремль': null},
    );
    final fallback = FakeCardImageFinder(
      byQuery: <String, GeneratedCardImage?>{
        'кремль': makeCardImage(query: 'кремль'),
      },
    );

    final result = await CompositeCardImageFinder(<CardImageFinder>[
      primary,
      fallback,
    ]).findImage('кремль');

    expect(result, isNotNull);
    expect(primary.queries, <String>['кремль']);
    expect(fallback.queries, <String>['кремль']);
  });

  test('оба источника пусты — null', () async {
    final finder = CompositeCardImageFinder(<CardImageFinder>[
      FakeCardImageFinder(
        byQuery: <String, GeneratedCardImage?>{'кремль': null},
      ),
      FakeCardImageFinder(
        byQuery: <String, GeneratedCardImage?>{'кремль': null},
      ),
    ]);

    expect(await finder.findImage('кремль'), isNull);
  });

  test('без источников — null', () async {
    expect(
      await const CompositeCardImageFinder(<CardImageFinder>[]).findImage('x'),
      isNull,
    );
  });
}
