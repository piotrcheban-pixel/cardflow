import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';

/// Красная фаза итерации 3b: контентные правила A8.4 (пометки, а не удаление).
void main() {
  const validator = CardContentValidator();
  const sourceText =
      'Это исходный текст. FSRS — алгоритм интервального повторения. '
      'Он планирует повторения карточек.';

  Map<String, Object?> card({
    String front = 'Вопрос',
    String back = 'Ответ',
    String? hint,
    List<Object?>? tags,
    String cardType = 'basic',
    String? sourceExcerpt,
    String? sourceFile,
    String? imageId,
    String? imageQuery,
    Map<String, Object?>? image,
    List<String> questionImageIds = const <String>[],
    List<String> answerImageIds = const <String>[],
  }) => <String, Object?>{
    'front': front,
    'back': back,
    'hint': hint,
    'tags': tags ?? <Object?>['тег'],
    'card_type': cardType,
    'source_excerpt': sourceExcerpt,
    'source_file': sourceFile,
    'image_id': imageId,
    if (image != null) 'image': image else 'image_query': imageQuery,
    'question_image_ids': <String>[...questionImageIds, ?imageId],
    'answer_image_ids': answerImageIds,
    'image': image,
  };

  Map<String, Object?> imageSpec({
    String query = 'truss bridge structure engineering',
    String fallbackQuery = 'truss bridge',
    String kind = 'photo',
  }) => <String, Object?>{
    'query': query,
    'fallback_query': fallbackQuery,
    'kind': kind,
  };

  List<GeneratedCard> validate(
    List<Map<String, Object?>> cards, {
    String? source,
    Set<String> imageIds = const <String>{},
  }) {
    return validator.validateResponse(
      <String, Object?>{'cards': cards},
      sourceText: source ?? sourceText,
      imageIds: imageIds,
    );
  }

  List<CardIssueCode> issuesOf(Map<String, Object?> raw) =>
      validate(<Map<String, Object?>>[raw]).single.issues;

  test('валидная карточка проходит без пометок', () {
    final cards = validate(<Map<String, Object?>>[
      card(
        tags: <Object?>['fsrs', 'память'],
        sourceExcerpt: 'FSRS — алгоритм интервального повторения.',
        sourceFile: 'лекция.docx',
      ),
    ]);
    expect(cards, hasLength(1));
    final parsed = cards.single;
    expect(parsed.front, 'Вопрос');
    expect(parsed.back, 'Ответ');
    expect(parsed.cardType, CardType.basic);
    expect(parsed.tags, <String>['fsrs', 'память']);
    expect(parsed.sourceExcerpt, 'FSRS — алгоритм интервального повторения.');
    expect(parsed.sourceFile, 'лекция.docx');
    expect(parsed.issues, isEmpty);
    expect(parsed.hasIssues, isFalse);
  });

  test('front пустой — пометка emptyFront, карточка остаётся', () {
    expect(issuesOf(card(front: '   ')), <CardIssueCode>[
      CardIssueCode.emptyFront,
    ]);
  });

  test('длины: front > 500 и back > 2000 — пометки, границы включительно', () {
    expect(issuesOf(card(front: 'a' * 500)), isEmpty);
    expect(issuesOf(card(front: 'a' * 501)), <CardIssueCode>[
      CardIssueCode.frontTooLong,
    ]);
    // 2000 символов — граница A8.4, но мягкий предел A8.1 (~200) уже превышен.
    expect(issuesOf(card(back: 'b' * 2000)), <CardIssueCode>[
      CardIssueCode.backTooVerbose,
    ]);
    expect(issuesOf(card(back: 'b' * 2001)), <CardIssueCode>[
      CardIssueCode.backTooLong,
      CardIssueCode.backTooVerbose,
    ]);
  });

  test('cloze: хотя бы один {{cN::…}}, иначе clozeMissing', () {
    expect(
      issuesOf(card(cardType: 'cloze', front: 'Пропуск {{c1::текст}} тут')),
      isEmpty,
    );
    expect(
      issuesOf(card(cardType: 'cloze', front: 'Без маски')),
      <CardIssueCode>[CardIssueCode.clozeMissing],
    );
  });

  test('теги: обрезаются до 3, пустые и # удаляются, пометка tagsAdjusted', () {
    final parsed = validate(<Map<String, Object?>>[
      card(tags: <Object?>['#тег', '', ' a ', 'b', 'c']),
    ]).single;
    expect(parsed.tags, <String>['тег', 'a', 'b']);
    expect(parsed.issues, contains(CardIssueCode.tagsAdjusted));
  });

  test('теги без изменений не помечаются', () {
    expect(issuesOf(card(tags: <Object?>['раз', 'два', 'три'])), isEmpty);
  });

  test('сломанный LaTeX — пометка latexBroken, карточка не отбрасывается', () {
    expect(issuesOf(card(front: r'Чему равна $\frac{$')), <CardIssueCode>[
      CardIssueCode.latexBroken,
    ]);
    expect(issuesOf(card(back: r'Ответ $x^2$')), isEmpty);
  });

  test('проверку LaTeX можно подменить (инъекция)', () {
    const injected = CardContentValidator(latexChecker: _alwaysBroken);
    final cards = injected.validateResponse(<String, Object?>{
      'cards': <Object?>[card()],
    }, sourceText: sourceText);
    expect(cards.single.issues, contains(CardIssueCode.latexBroken));
  });

  test('пустые materials (prompt-only): source_excerpt обнуляется, '
      'карточка остаётся (fix-gen Д1)', () {
    final parsed = validate(<Map<String, Object?>>[
      card(sourceExcerpt: 'Цитата, которой нет в пустом тексте'),
    ], source: '').single;
    expect(parsed.sourceExcerpt, isNull);
    expect(parsed.issues, isNot(contains(CardIssueCode.excerptMismatch)));
    expect(parsed.front, isNotEmpty);
  });

  test('source_excerpt: пробелы нормализуются и проверяется вхождение', () {
    final found = validate(<Map<String, Object?>>[
      card(sourceExcerpt: 'FSRS  —   алгоритм\nинтервального повторения.'),
    ]).single;
    expect(
      found.sourceExcerpt,
      'FSRS — алгоритм интервального повторения.',
      reason: 'Цитату храним с нормализованными пробелами',
    );
    expect(found.issues, isEmpty);

    final notFound = validate(<Map<String, Object?>>[
      card(sourceExcerpt: 'Этой цитаты нет в тексте'),
    ]).single;
    expect(notFound.sourceExcerpt, isNull);
    expect(notFound.issues, <CardIssueCode>[CardIssueCode.excerptMismatch]);
  });

  test('source_excerpt null — без пометок', () {
    expect(issuesOf(card()), isEmpty);
  });

  test('basic_reversed и cloze разбираются в CardType', () {
    final cards = validate(<Map<String, Object?>>[
      card(cardType: 'basic_reversed', sourceExcerpt: null),
      card(
        cardType: 'cloze',
        front: 'Текст {{c1::пропуск}}',
        sourceExcerpt: null,
      ),
    ]);
    expect(cards[0].cardType, CardType.basicReversed);
    expect(cards[1].cardType, CardType.cloze);
  });

  test(
    'occlusion — wire-формат: basic + isOcclusion (SPEC A5, итерация 7.9)',
    () {
      final parsed = validate(<Map<String, Object?>>[
        card(
          cardType: 'occlusion',
          imageQuery: '  photosynthesis diagram  ',
          sourceExcerpt: null,
        ),
      ]).single;

      expect(parsed.cardType, CardType.basic);
      expect(parsed.isOcclusion, isTrue);
      expect(parsed.imageQuery, 'photosynthesis diagram');
      expect(parsed.occlusionJson, isNull, reason: 'маску ставит пайплайн');
    },
  );

  test('image (v6): объект разбирается, kind и fallback сохраняются', () {
    final parsed = validate(<Map<String, Object?>>[
      card(image: imageSpec(kind: 'diagram')),
    ]).single;
    expect(parsed.imageQuery, 'truss bridge structure engineering');
    expect(parsed.imageFallbackQuery, 'truss bridge');
    expect(parsed.imageKind, GeneratedCardImageKind.diagram);
    expect(parsed.issues, isNot(contains(CardIssueCode.imageQueryAdjusted)));
  });

  test('image_query (v5) остаётся совместимым: запрос берётся как есть', () {
    final parsed = validate(<Map<String, Object?>>[
      card(imageQuery: '  photosynthesis diagram  '),
    ]).single;
    expect(parsed.imageQuery, 'photosynthesis diagram');
    expect(parsed.imageKind, GeneratedCardImageKind.diagram);
  });

  test('нормализация: > 7 слов режется, кириллица/мусор вычищаются', () {
    final tooMany = validate(<Map<String, Object?>>[
      card(imageQuery: 'one two three four five six seven eight nine'),
    ]).single;
    expect(tooMany.imageQuery, 'one two three four five six seven');
    expect(tooMany.issues, contains(CardIssueCode.imageQueryAdjusted));

    final mixed = validate(<Map<String, Object?>>[
      card(imageQuery: 'photo of mitochondria cell 3.jpg'),
    ]).single;
    expect(mixed.imageQuery, 'mitochondria cell');
    expect(mixed.imageKind, GeneratedCardImageKind.photo);

    final cyrillic = validate(<Map<String, Object?>>[
      card(imageQuery: 'схема фермы'),
    ]).single;
    expect(cyrillic.imageQuery, isNull);
    expect(cyrillic.issues, contains(CardIssueCode.imageQueryAdjusted));

    expect(
      validate(<Map<String, Object?>>[card(imageQuery: '   ')])
          .single
          .imageQuery,
      isNull,
    );
  });

  test('абстрактному понятию запрос больше не обнуляется (7.14)', () {
    final parsed = validate(<Map<String, Object?>>[
      card(
        front: 'При каком условии две силы уравновешивают друг друга?',
        back: 'Аксиома о равновесии двух сил',
        imageQuery: 'balance scale equilibrium',
      ),
    ]).single;
    expect(parsed.imageQuery, 'balance scale equilibrium');
    expect(parsed.imageKind, GeneratedCardImageKind.illustration);
    expect(parsed.issues, isNot(contains(CardIssueCode.abstractImageQuery)));
  });

  test(
    'image_id из каталога: неизвестный обнуляется, image остаётся запасным',
    () {
      final known = validate(
        <Map<String, Object?>>[
          card(questionImageIds: <String>['img1'], image: imageSpec()),
        ],
        imageIds: <String>{'img1'},
      ).single;
      expect(known.questionImageIds, <String>['img1']);
      expect(known.imageQuery, 'truss bridge structure engineering');
      expect(known.issues, isNot(contains(CardIssueCode.imageQueryAdjusted)));

      final unknown = validate(<Map<String, Object?>>[card(imageId: 'img9')])
          .single;
      expect(unknown.questionImageIds, isEmpty);
      expect(unknown.issues, contains(CardIssueCode.imageIdUnknown));
    },
  );

  test('неизвестный card_type отбрасывается сам, остальные карточки живы', () {
    final outcome = validator.validateResponseWithRejects(<String, Object?>{
      'cards': <Object?>[
        card(cardType: 'image'),
        card(front: 'Что такое FSRS?', back: 'Алгоритм.'),
      ],
    }, sourceText: sourceText);
    expect(outcome.rejectedCards, 1);
    expect(outcome.cards, hasLength(1));
    expect(outcome.cards.single.front, 'Что такое FSRS?');
  });

  test('пустой массив карточек — пустой результат', () {
    expect(validate(<Map<String, Object?>>[]), isEmpty);
  });

  test(
    'некорректная структура ответа — GenerationException(invalidResponse)',
    () {
      for (final response in <Object?>[
        null,
        <String, Object?>{},
        <String, Object?>{'cards': 'нет'},
      ]) {
        expect(
          () => validator.validateResponse(response, sourceText: sourceText),
          throwsA(
            isA<GenerationException>().having(
              (exception) => exception.code,
              'code',
              GenerationErrorCode.invalidResponse,
            ),
          ),
          reason: 'response=$response',
        );
      }
      final outcome = validator.validateResponseWithRejects(<String, Object?>{
        'cards': <Object?>['нет'],
      }, sourceText: sourceText);
      expect(outcome.cards, isEmpty);
      expect(outcome.rejectedCards, 1);
    },
  );

  test('несколько пометок сразу идут в стабильном порядке', () {
    expect(issuesOf(card(front: 'a' * 501, back: 'b' * 2001)), <CardIssueCode>[
      CardIssueCode.frontTooLong,
      CardIssueCode.backTooLong,
      CardIssueCode.backTooVerbose,
    ]);
  });
}

bool _alwaysBroken(String text) => false;
