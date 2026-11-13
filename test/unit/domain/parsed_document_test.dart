import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Красная фаза итерации 3a: инварианты `ParsedDocument` (SPEC A8.3, A8.5).
void main() {
  ParsedDocument build({
    String text = 'Первый\nВторой',
    List<ParsedSection>? sections,
    ParsedDocumentMetadata metadata = const ParsedDocumentMetadata(),
  }) => ParsedDocument(
    format: DocumentFormat.txt,
    fileName: 'конспект.txt',
    text: text,
    sections: sections ??
        <ParsedSection>[
          ParsedSection(start: 0, end: text.length),
        ],
    metadata: metadata,
  );

  group('ParsedDocument: корректный документ', () {
    test('сохраняет текст, разделы и метаданные', () {
      final ParsedDocument document = build(
        sections: <ParsedSection>[
          const ParsedSection(start: 0, end: 6, title: 'Первый'),
          const ParsedSection(start: 7, end: 13, title: 'Второй'),
        ],
        metadata: const ParsedDocumentMetadata(
          pageCount: 2,
          slideCount: null,
          sheetNames: <String>['Лист1'],
          encoding: 'utf-8',
        ),
      );

      expect(document.format, DocumentFormat.txt);
      expect(document.fileName, 'конспект.txt');
      expect(document.text, 'Первый\nВторой');
      expect(document.sections, hasLength(2));
      expect(document.sections.first.title, 'Первый');
      expect(
        document.text.substring(
          document.sections.last.start,
          document.sections.last.end,
        ),
        'Второй',
      );
      expect(document.metadata.pageCount, 2);
      expect(document.metadata.sheetNames, <String>['Лист1']);
    });

    test('метаданные по умолчанию пустые, раздел может быть без title', () {
      final ParsedDocument document = build();
      expect(document.metadata.pageCount, isNull);
      expect(document.metadata.slideCount, isNull);
      expect(document.metadata.sheetNames, isNull);
      expect(document.metadata.encoding, isNull);
      expect(document.sections.single.title, isNull);
    });
  });

  group('ParsedDocument: нарушение инвариантов → ArgumentError', () {
    test('пустой текст запрещён', () {
      expect(
        () => build(
          text: '',
          sections: <ParsedSection>[const ParsedSection(start: 0, end: 0)],
        ),
        throwsArgumentError,
      );
    });

    test('текст только из пробелов/переводов строк запрещён', () {
      expect(
        () => build(
          text: '   \n\t\n',
          sections: <ParsedSection>[
            const ParsedSection(start: 0, end: 6),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('пустой список разделов запрещён', () {
      expect(() => build(sections: <ParsedSection>[]), throwsArgumentError);
    });

    test('границы раздела должны лежать в тексте', () {
      expect(
        () => build(
          sections: <ParsedSection>[
            const ParsedSection(start: 0, end: 9999),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => build(
          sections: <ParsedSection>[
            const ParsedSection(start: -1, end: 5),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('start должен быть меньше end (непустые разделы)', () {
      expect(
        () => build(
          sections: <ParsedSection>[
            const ParsedSection(start: 3, end: 3),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('разделы должны идти по порядку и не пересекаться', () {
      expect(
        () => build(
          sections: <ParsedSection>[
            const ParsedSection(start: 7, end: 13),
            const ParsedSection(start: 0, end: 6),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => build(
          sections: <ParsedSection>[
            const ParsedSection(start: 0, end: 8),
            const ParsedSection(start: 5, end: 13),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
