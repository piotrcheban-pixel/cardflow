import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/domain/cards/card.dart';
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
  }) => <String, Object?>{
    'front': front,
    'back': back,
    'hint': hint,
    'tags': tags ?? <Object?>['тег'],
    'card_type': cardType,
    'source_excerpt': sourceExcerpt,
    'source_file': sourceFile,
    'image_id': imageId,
    'image_query': imageQuery,
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

  test(
    'image_query: пустой/null → null, не латиница/длиннее 7 слов → null',
    () {
      expect(
        validate(<Map<String, Object?>>[card()]).single.imageQuery,
        isNull,
      );
      expect(
        validate(<Map<String, Object?>>[card(imageQuery: '   ')])
            .single
            .imageQuery,
        isNull,
      );
      // Слишком длинный запрос (fix-gen): не обрезается, а обнуляется.
      final long = 'a' * (CardContentValidator.maxImageQueryLength + 20);
      final parsed = validate(<Map<String, Object?>>[card(imageQuery: long)])
          .single;
      expect(parsed.imageQuery, isNull);
      expect(parsed.issues, contains(CardIssueCode.imageQueryAdjusted));
      // Кириллица в запросе: только латиница.
      final cyrillic = validate(<Map<String, Object?>>[
        card(imageQuery: 'схема фермы'),
      ]).single;
      expect(cyrillic.imageQuery, isNull);
      // Больше 7 слов.
      final tooManyWords = validate(<Map<String, Object?>>[
        card(imageQuery: 'one two three four five six seven eight'),
      ]).single;
      expect(tooManyWords.imageQuery, isNull);
    },
  );

  test('image_query для абстрактного понятия обнуляется (Д2)', () {
    final parsed = validate(<Map<String, Object?>>[
      card(
        front: 'При каком условии две силы уравновешивают друг друга?',
        back: 'Аксиома о равновесии двух сил',
        imageQuery: 'ball physics',
      ),
    ]).single;
    expect(parsed.imageQuery, isNull);
    expect(parsed.issues, contains(CardIssueCode.abstractImageQuery));
  });

  test('image_id из каталога: неизвестный обнуляется, при известном '
      'image_query игнорируется (Д3)', () {
    final known = validate(
      <Map<String, Object?>>[card(imageId: 'img1', imageQuery: 'truss bridge')],
      imageIds: <String>{'img1'},
    ).single;
    expect(known.imageId, 'img1');
    expect(known.imageQuery, isNull);
    expect(known.issues, contains(CardIssueCode.imageQueryAdjusted));

    final unknown = validate(<Map<String, Object?>>[card(imageId: 'img9')])
        .single;
    expect(unknown.imageId, isNull);
    expect(unknown.issues, contains(CardIssueCode.imageIdUnknown));
  });

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
