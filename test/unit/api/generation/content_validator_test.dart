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
    String? imageQuery,
  }) => <String, Object?>{
    'front': front,
    'back': back,
    'hint': hint,
    'tags': tags ?? <Object?>['тег'],
    'card_type': cardType,
    'source_excerpt': sourceExcerpt,
    'source_file': sourceFile,
    'image_query': imageQuery,
  };

  List<GeneratedCard> validate(
    List<Map<String, Object?>> cards, {
    String? source,
  }) {
    return validator.validateResponse(<String, Object?>{
      'cards': cards,
    }, sourceText: source ?? sourceText);
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
    expect(issuesOf(card(back: 'b' * 2000)), isEmpty);
    expect(issuesOf(card(back: 'b' * 2001)), <CardIssueCode>[
      CardIssueCode.backTooLong,
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
    expect(issuesOf(card(front: r'Формула $\frac{$')), <CardIssueCode>[
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

  test('image_query: пустой/null → null, длинный обрезается', () {
    expect(validate(<Map<String, Object?>>[card()]).single.imageQuery, isNull);
    expect(
      validate(<Map<String, Object?>>[card(imageQuery: '   ')])
          .single
          .imageQuery,
      isNull,
    );
    final long = 'a' * (CardContentValidator.maxImageQueryLength + 20);
    final parsed = validate(<Map<String, Object?>>[card(imageQuery: long)])
        .single;
    expect(
      parsed.imageQuery,
      hasLength(CardContentValidator.maxImageQueryLength),
    );
  });

  test('неизвестный card_type → invalidResponse', () {
    expect(
      () => validate(<Map<String, Object?>>[card(cardType: 'image')]),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.invalidResponse,
        ),
      ),
    );
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
        <String, Object?>{
          'cards': <Object?>['нет'],
        },
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
    },
  );

  test('несколько пометок сразу идут в стабильном порядке', () {
    expect(issuesOf(card(front: 'a' * 501, back: 'b' * 2001)), <CardIssueCode>[
      CardIssueCode.frontTooLong,
      CardIssueCode.backTooLong,
    ]);
  });
}

bool _alwaysBroken(String text) => false;
