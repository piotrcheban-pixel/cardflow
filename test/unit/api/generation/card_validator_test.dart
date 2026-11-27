import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/validation/card_validator.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контракт этапа Validation (TASK «Срез 6», ADR-050): структурные проверки
/// A8.4 и семантические эвристики с кодом причины, цитата — буквально по
/// offsets `ContentModel`.
///
/// Карточка не исчезает: принятая и помеченная — в `candidates`, отброшенная —
/// в `rejected` вместе с исходной записью («показать отброшенные»).
void main() {
  const CardValidator validator = CardValidator(
    latexChecker: _latexIsValidForTest,
  );

  test('корректная карточка принята: ни одной причины, цитата по offsets', () {
    final Document document = _document(<String>[
      'Энтропия — мера необратимого рассеяния энергии.',
      'Второе начало термодинамики запрещает вечный двигатель.',
    ]);
    const String quote = 'мера необратимого рассеяния энергии';

    final CardValidationReport report = validator.validate(
      _response(<Map<String, Object?>>[_card(quoteRef: quote)]),
      document: document,
      knownUnitIds: const <String>{'ku:1'},
      knownSectionIds: const <String>{'doc:конспект.md#0'},
    );

    expect(report.rejected, isEmpty);
    final CardCandidate candidate = report.candidates.single;
    expect(candidate.verdict, CardVerdict.accepted);
    expect(candidate.reasons, isEmpty);
    expect(candidate.card.front, 'Что такое энтропия?');
    expect(candidate.card.cardType, CardType.basic);
    expect(candidate.card.unitId, 'ku:1');
    expect(candidate.card.quoteRef, quote);
    final QuoteMatch? quoteMatch = candidate.quote;
    expect(quoteMatch, isNotNull);
    expect(quoteMatch!.literal, isTrue);
    expect(quoteMatch.blockId, 'doc:конспект.md#0#0');
    expect(document.text.substring(quoteMatch.start, quoteMatch.end), quote);
  });

  group('структурные проверки A8.4', () {
    test('нет front — отброшено с причиной, запись сохранена', () {
      final CardValidationReport report = validator.validate(
        _response(<Object?>[
          <String, Object?>{'front': 42, 'back': 'Ответ', 'card_type': 'basic'},
        ]),
      );

      expect(report.cards, isEmpty);
      final RejectedCard rejected = report.rejected.single;
      expect(rejected.code, CardReasonCode.missingRequiredField);
      expect(rejected.front, isNull);
      expect(rejected.rawMap, isNotNull);
      expect(rejected.rawMap!['back'], 'Ответ');
    });

    test('нет back — отброшено с причиной', () {
      final CardValidationReport report = validator.validate(
        _response(<Object?>[
          <String, Object?>{
            'front': 'Вопрос?',
            'back': 7,
            'card_type': 'basic',
          },
        ]),
      );

      expect(report.rejected.single.code, CardReasonCode.missingRequiredField);
    });

    test('неизвестный card_type отброшен, occlusion отображён в basic', () {
      final CardValidationReport unknown = validator.validate(
        _response(<Map<String, Object?>>[_card(cardType: 'multiple_choice')]),
      );
      expect(unknown.rejected.single.code, CardReasonCode.unknownCardType);

      final CardValidationReport occlusion = validator.validate(
        _response(<Map<String, Object?>>[_card(cardType: 'occlusion')]),
      );
      final GeneratedCard card = occlusion.cards.single;
      expect(occlusion.candidates.single.verdict, CardVerdict.accepted);
      expect(card.isOcclusion, isTrue);
      expect(card.cardType, CardType.basic);
    });

    test('пустой front отброшен с причиной emptyFront', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[_card(front: '   ')]),
      );

      expect(report.rejected.single.code, CardReasonCode.emptyFront);
      expect(report.cards, isEmpty);
    });

    test(
      'длины front/back: граница 500/2000 без пометки, больше — пометка',
      () {
        final CardValidationReport atLimit = validator.validate(
          _response(<Map<String, Object?>>[
            _card(front: 'Вопрос? ' * 62, back: 'Ответ ' * 333),
          ]),
        );
        expect(
          atLimit.candidates.single.reasons,
          isNot(contains(CardReasonCode.frontTooLong)),
        );
        expect(
          atLimit.candidates.single.reasons,
          isNot(contains(CardReasonCode.backTooLong)),
        );

        final CardValidationReport overLimit = validator.validate(
          _response(<Map<String, Object?>>[
            _card(front: 'Вопрос? ' * 63, back: 'Ответ ' * 334),
          ]),
        );
        expect(
          overLimit.candidates.single.reasons,
          containsAll(<CardReasonCode>[
            CardReasonCode.frontTooLong,
            CardReasonCode.backTooLong,
          ]),
        );
      },
    );

    test('cloze без пропуска — пометка clozeMissing', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[
          _card(front: 'Столица Франции — Париж.', cardType: 'cloze', back: ''),
        ]),
      );

      expect(report.candidates.single.verdict, CardVerdict.warning);
      expect(
        report.candidates.single.reasons,
        contains(CardReasonCode.clozeMissing),
      );
    });

    test('осмысленный cloze проходит без пометок', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[
          _card(
            front: 'Столица Франции — {{c1::Париж}}.',
            cardType: 'cloze',
            back: '',
          ),
        ]),
      );

      expect(report.candidates.single.verdict, CardVerdict.accepted);
      expect(report.candidates.single.reasons, isEmpty);
    });

    test('теги: 4 тега или «#» — tagsAdjusted, нормальный список — без', () {
      final CardValidationReport adjusted = validator.validate(
        _response(<Map<String, Object?>>[
          _card(tags: <Object?>['#т1', 'т2', '', 'т3', 'т4']),
        ]),
      );
      expect(
        adjusted.candidates.single.reasons,
        contains(CardReasonCode.tagsAdjusted),
      );
      expect(adjusted.cards.single.tags, <String>['т1', 'т2', 'т3']);

      final CardValidationReport clean = validator.validate(
        _response(<Map<String, Object?>>[
          _card(tags: <Object?>['т1', 'т2']),
        ]),
      );
      expect(clean.candidates.single.reasons, isEmpty);
    });

    test('LaTeX: непарсящаяся формула — latexBroken, корректная — без', () {
      final CardValidationReport broken = validator.validate(
        _response(<Map<String, Object?>>[
          _card(front: 'Чему равно \$\\broken{1}\$?'),
        ]),
      );
      expect(
        broken.candidates.single.reasons,
        contains(CardReasonCode.latexBroken),
      );

      final CardValidationReport ok = validator.validate(
        _response(<Map<String, Object?>>[
          _card(front: 'Чему равно \$x^2\$ при \$x = 2\$?', back: '4'),
        ]),
      );
      expect(ok.candidates.single.reasons, isEmpty);
    });

    test('корень ответа не объект с cards — GenerationException', () {
      expect(
        () => validator.validate(<Object?>[1, 2, 3]),
        throwsA(
          isA<GenerationException>().having(
            (GenerationException e) => e.code,
            'code',
            GenerationErrorCode.invalidResponse,
          ),
        ),
      );
      expect(
        () => validator.validate(<String, Object?>{'cards': 'нет'}),
        throwsA(isA<GenerationException>()),
      );
    });
  });

  group('семантические эвристики', () {
    test('ответ внутри вопроса — answerInQuestion', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[
          _card(
            front: 'Что такое энтропия — мера необратимого рассеяния энергии?',
            back: 'Мера необратимого рассеяния энергии.',
            quoteRef: null,
          ),
        ]),
      );

      expect(
        report.candidates.single.reasons,
        contains(CardReasonCode.answerInQuestion),
      );
    });

    test('ответ не в вопросе у корректной карточки — нет пометки', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[_card(quoteRef: null)]),
      );

      expect(
        report.candidates.single.reasons,
        isNot(contains(CardReasonCode.answerInQuestion)),
      );
    });

    test('вопрос несамостоятелен: «этот», «выше», «см. рис.» — пометка', () {
      const List<String> dangling = <String>[
        'Какой процесс описан выше?',
        'См. рис. 4: какова сила тока в цепи?',
        'Почему этот процесс идёт самопроизвольно?',
        'Что будет, если повысить температуру, как сказано выше?',
      ];
      for (final String front in dangling) {
        final CardValidationReport report = validator.validate(
          _response(<Map<String, Object?>>[
            _card(front: front, quoteRef: null),
          ]),
        );
        expect(
          report.candidates.single.reasons,
          contains(CardReasonCode.questionNotSelfContained),
          reason: 'не пойман несамостоятельный вопрос: $front',
        );
      }
    });

    test('самостоятельный вопрос без ложных срабатываний', () {
      const List<String> selfContained = <String>[
        'Что такое энтропия?',
        'Чему равно давление на глубине 10 метров?',
        'Как изменяется давление с высотой в атмосфере?',
        'Какие силы действуют на тело в жидкости?',
      ];
      for (final String front in selfContained) {
        final CardValidationReport report = validator.validate(
          _response(<Map<String, Object?>>[
            _card(front: front, quoteRef: null),
          ]),
        );
        expect(
          report.candidates.single.reasons,
          isNot(contains(CardReasonCode.questionNotSelfContained)),
          reason: 'ложная пометка на корректном вопросе: $front',
        );
      }
    });

    test(
      'атомарность: перечисление больше трёх — notAtomic, ровно три — без',
      () {
        final CardValidationReport many = validator.validate(
          _response(<Map<String, Object?>>[
            _card(
              front:
                  'Назовите виды теплопередачи: 1) теплопроводность '
                  '2) конвекция 3) излучение 4) испарение?',
              quoteRef: null,
            ),
          ]),
        );
        expect(
          many.candidates.single.reasons,
          contains(CardReasonCode.notAtomic),
        );

        final CardValidationReport three = validator.validate(
          _response(<Map<String, Object?>>[
            _card(
              front:
                  'Назовите виды теплопередачи: 1) теплопроводность '
                  '2) конвекция 3) излучение?',
              quoteRef: null,
            ),
          ]),
        );
        expect(
          three.candidates.single.reasons,
          isNot(contains(CardReasonCode.notAtomic)),
        );
      },
    );

    test('cloze осмысленный: пропуск не на весь вопрос и номера с c1', () {
      const List<String> meaningless = <String>[
        '{{c1::Энтропия}}',
        '{{c1::Энтропия}} — {{c2::Энтропия}}',
        'Энтропия — {{c2::мера рассеяния энергии}}',
      ];
      for (final String front in meaningless) {
        final CardValidationReport report = validator.validate(
          _response(<Map<String, Object?>>[
            _card(front: front, cardType: 'cloze', back: '', quoteRef: null),
          ]),
        );
        expect(
          report.candidates.single.reasons,
          contains(CardReasonCode.clozeMeaningless),
          reason: 'не пойман бессмысленный cloze: $front',
        );
      }

      final CardValidationReport meaningful = validator.validate(
        _response(<Map<String, Object?>>[
          _card(
            front: 'Энтропия — {{c1::мера}} необратимого {{c2::рассеяния}} энергии.',
            cardType: 'cloze',
            back: '',
            quoteRef: null,
          ),
        ]),
      );
      expect(
        meaningful.candidates.single.reasons,
        isNot(contains(CardReasonCode.clozeMeaningless)),
      );
    });

    test('язык ru: латиница без кириллицы — languageNotRussian', () {
      final CardValidationReport english = validator.validate(
        _response(<Map<String, Object?>>[
          _card(
            front: 'What is entropy?',
            back: 'A measure of energy dispersal in a closed system.',
            quoteRef: null,
          ),
        ]),
      );
      expect(
        english.candidates.single.reasons,
        contains(CardReasonCode.languageNotRussian),
      );

      final CardValidationReport russianWithLatin = validator.validate(
        _response(<Map<String, Object?>>[
          _card(
            front: 'Как FSRS планирует повторения?',
            back: 'По стабильности и сложности карточки.',
            quoteRef: null,
          ),
        ]),
      );
      expect(
        russianWithLatin.candidates.single.reasons,
        isNot(contains(CardReasonCode.languageNotRussian)),
      );
    });

    test('unit_id и section_id вне партии — unitUnknown/sectionUnknown', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[
          _card(unitId: 'ku:нет', sectionId: 'doc:нет#0', quoteRef: null),
        ]),
        knownUnitIds: const <String>{'ku:1'},
        knownSectionIds: const <String>{'doc:конспект.md#0'},
      );

      expect(
        report.candidates.single.reasons,
        containsAll(<CardReasonCode>[
          CardReasonCode.unitUnknown,
          CardReasonCode.sectionUnknown,
        ]),
      );

      final CardValidationReport unknownMaterial = validator.validate(
        _response(<Map<String, Object?>>[
          _card(unitId: 'ku:нет', sectionId: 'doc:нет#0', quoteRef: null),
        ]),
      );
      expect(
        unknownMaterial.candidates.single.reasons,
        isEmpty,
        reason: 'без известных id сверять не с чем — пометок нет',
      );
    });
  });

  group('цитата по offsets', () {
    late Document document;

    setUp(() {
      document = _document(<String>[
        'Энтропия — мера необратимого рассеяния энергии.',
        'Второе начало термодинамики запрещает вечный двигатель.',
      ]);
    });

    test('цитата, отличающаяся пробелами/тире/регистром, — не буквальная', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[_card(quoteRef: 'энтропия - мера')]),
        document: document,
      );

      final CardCandidate candidate = report.candidates.single;
      expect(candidate.reasons, contains(CardReasonCode.quoteNotLiteral));
      expect(candidate.quote, isNull);
    });

    test('цитаты нет в материале — quoteOutOfRange, карточка остаётся', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[
          _card(quoteRef: 'квантовая запутанность фотонов'),
        ]),
        document: document,
      );

      final CardCandidate candidate = report.candidates.single;
      expect(candidate.verdict, CardVerdict.warning);
      expect(candidate.reasons, contains(CardReasonCode.quoteOutOfRange));
      expect(candidate.quote, isNull);
      expect(report.cards, hasLength(1), reason: 'карточка не исчезает');
    });

    test('без документа цитата не проверяется и не помечается', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[_card(quoteRef: 'чего угодно')]),
      );

      expect(report.candidates.single.reasons, isEmpty);
      expect(report.candidates.single.quote, isNull);
    });
  });

  group('отчёт', () {
    test('принятые, помеченные и отброшенные не смешиваются', () {
      final CardValidationReport report = validator.validate(
        _response(<Object?>[
          _card(quoteRef: null),
          _card(
            front: 'Что такое энтропия — мера рассеяния энергии?',
            back: 'Мера рассеяния энергии.',
            quoteRef: null,
          ),
          <String, Object?>{'front': 'нет обратной стороны'},
        ]),
      );

      expect(report.acceptedCount, 1);
      expect(report.warningCount, 1);
      expect(report.rejectedCount, 1);
      expect(report.cards, hasLength(2));
      expect(report.warnings.single.verdict, CardVerdict.warning);
      expect(report.warningCounts[CardReasonCode.answerInQuestion], 1);
      expect(report.hasRejects, isTrue);
      expect(report.rejected.single.rawMap!['front'], 'нет обратной стороны');
    });

    test('угол карточки: primary → null, reverse сохраняется', () {
      final CardValidationReport report = validator.validate(
        _response(<Map<String, Object?>>[
          _card(quoteRef: null),
          _card(quoteRef: null, angle: 'reverse'),
        ]),
      );

      expect(report.cards.first.angle, isNull);
      expect(report.cards.last.angle, 'reverse');
    });
  });
}

/// Проверка LaTeX в тестах: «\broken» считается ошибкой разметки.
bool _latexIsValidForTest(String text) => !text.contains(r'\broken');

Map<String, Object?> _response(List<Object?> cards) => <String, Object?>{
  'cards': cards,
};

Map<String, Object?> _card({
  Object? front = 'Что такое энтропия?',
  Object? back = 'Мера необратимого рассеяния энергии в замкнутой системе.',
  Object? cardType = 'basic',
  Object? unitId = 'ku:1',
  Object? angle = 'primary',
  Object? quoteRef = 'Энтропия',
  List<Object?>? tags,
  String? sectionId,
}) => <String, Object?>{
  'front': front,
  'back': back,
  'hint': null,
  'tags': tags ?? <Object?>['термодинамика'],
  'card_type': cardType,
  'source_excerpt': null,
  'source_file': null,
  'unit_id': unitId,
  'angle': angle,
  'quote_ref': quoteRef,
  'section_id': ?sectionId,
};

/// Документ из строк: блок = строка, раздел — весь текст.
Document _document(List<String> lines) {
  final StringBuffer buffer = StringBuffer();
  final List<Block> blocks = <Block>[];
  const String sectionId = 'doc:конспект.md#0';
  var offset = 0;
  for (var index = 0; index < lines.length; index++) {
    if (index > 0) {
      buffer.write('\n');
      offset += 1;
    }
    final String line = lines[index];
    blocks.add(
      Block(
        id: '$sectionId#$index',
        sectionId: sectionId,
        start: offset,
        end: offset + line.length,
        text: line,
      ),
    );
    buffer.write(line);
    offset += line.length;
  }
  final String text = buffer.toString();
  return Document(
    fileName: 'конспект.md',
    format: DocumentFormat.md,
    text: text,
    sections: <Section>[
      Section(
        id: sectionId,
        index: 0,
        start: 0,
        end: text.length,
        blockIds: <String>[for (final Block block in blocks) block.id],
      ),
    ],
    blocks: blocks,
  );
}
