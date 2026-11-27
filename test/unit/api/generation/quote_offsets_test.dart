import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/validation/card_validator.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// DoD-команда S5 (BACKLOG): цитата валидна по offsets `ContentModel`.
///
/// `quote_ref` модели — дословная цитата (Q13). Проверка: границы блока из
/// `Document`, равенство `text.substring(start, end)` цитате и **буквальность**.
/// Почти-цитата (нормализация пробелов/тире/регистра) — пометка, а не
/// принятие: offsets такой цитаты не восстанавливают текст.
void main() {
  const CardValidator validator = CardValidator(
    latexChecker: _alwaysValidLatex,
  );

  group('буквальная цитата', () {
    test('offset точный: substring(start, end) == quote_ref', () {
      final Document document = _document(<String>[
        'Энтропия — мера необратимого рассеяния энергии.',
        'Второе начало термодинамики запрещает вечный двигатель.',
      ]);
      const String quote = 'запрещает вечный двигатель';

      final CardCandidate candidate = _validateQuote(
        validator,
        document,
        quote,
      );

      expect(candidate.verdict, CardVerdict.accepted);
      final QuoteMatch match = candidate.quote!;
      expect(match.literal, isTrue);
      expect(match.blockId, 'doc:конспект.md#0#1');
      expect(document.text.substring(match.start, match.end), quote);
      expect(match.length, quote.length);
    });

    test('повтор цитаты в двух блоках — первый блок по порядку документа', () {
      final Document document = _document(<String>[
        'Первое начало: энергия сохраняется.',
        'Второе начало: энергия сохраняется с потерями.',
      ]);

      final CardCandidate candidate = _validateQuote(
        validator,
        document,
        'энергия сохраняется',
      );

      expect(candidate.quote!.blockId, 'doc:конспект.md#0#0');
      expect(
        document.text.substring(candidate.quote!.start, candidate.quote!.end),
        'энергия сохраняется',
      );
    });
  });

  group('почти-цитата и отсутствие', () {
    test('двойной пробел в цитате — quoteNotLiteral, offsets не пишутся', () {
      final Document document = _document(<String>[
        'Энтропия — мера необратимого рассеяния энергии.',
      ]);

      final CardCandidate candidate = _validateQuote(
        validator,
        document,
        'мера необратимого  рассеяния',
      );

      expect(candidate.reasons, contains(CardReasonCode.quoteNotLiteral));
      expect(candidate.quote, isNull);
      expect(candidate.verdict, CardVerdict.warning);
    });

    test('другая буква «ё»/тире в цитате — quoteNotLiteral', () {
      final Document document = _document(<String>[
        'Закон Ома — сила тока пропорциональна напряжению.',
      ]);

      final CardCandidate candidate = _validateQuote(
        validator,
        document,
        'Закон Ома - сила тока',
      );

      expect(candidate.reasons, contains(CardReasonCode.quoteNotLiteral));
    });

    test('цитата через границу блоков не принимается: quoteOutOfRange', () {
      final Document document = _document(<String>[
        'Энтропия — мера рассеяния энергии.',
        'Второе начало запрещает вечный двигатель.',
      ]);

      final CardCandidate candidate = _validateQuote(
        validator,
        document,
        'энергии.\nВторое начало',
      );

      expect(candidate.reasons, contains(CardReasonCode.quoteOutOfRange));
      expect(candidate.quote, isNull);
    });

    test('цитата из мусорного блока (подпись рисунка) не принимается', () {
      const String text = 'Рис. 4 — схема двигателя.\nТекст раздела.';
      final Document document = Document(
        fileName: 'конспект.md',
        format: DocumentFormat.md,
        text: text,
        sections: <Section>[
          Section(
            id: 'doc:конспект.md#0',
            index: 0,
            start: 0,
            end: text.length,
            blockIds: const <String>[
              'doc:конспект.md#0#0',
              'doc:конспект.md#0#1',
            ],
          ),
        ],
        blocks: <Block>[
          const Block(
            id: 'doc:конспект.md#0#0',
            sectionId: 'doc:конспект.md#0',
            start: 0,
            end: 25,
            text: 'Рис. 4 — схема двигателя.',
            noiseKind: NoiseKind.figureCaption,
          ),
          const Block(
            id: 'doc:конспект.md#0#1',
            sectionId: 'doc:конспект.md#0',
            start: 26,
            end: 40,
            text: 'Текст раздела.',
          ),
        ],
      );

      final CardCandidate candidate = _validateQuote(
        validator,
        document,
        'схема двигателя',
      );

      expect(candidate.reasons, contains(CardReasonCode.quoteOutOfRange));
    });

    test('пустой quote_ref — проверка не выполняется', () {
      final Document document = _document(<String>['Текст материала.']);
      final CardCandidate candidate = _validateQuote(validator, document, '');

      expect(candidate.reasons, isEmpty);
      expect(candidate.quote, isNull);
    });
  });
}

bool _alwaysValidLatex(String text) => true;

CardCandidate _validateQuote(
  CardValidator validator,
  Document document,
  String quote,
) {
  final CardValidationReport report = validator.validate(<String, Object?>{
    'cards': <Map<String, Object?>>[
      <String, Object?>{
        'front': 'Что такое энтропия?',
        'back': 'Мера необратимого рассеяния энергии.',
        'hint': null,
        'tags': <Object?>['термодинамика'],
        'card_type': 'basic',
        'unit_id': 'ku:1',
        'angle': 'primary',
        'quote_ref': quote,
      },
    ],
  }, document: document);
  return report.candidates.single;
}

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
