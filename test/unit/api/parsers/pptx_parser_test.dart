import 'dart:typed_data';

import 'package:cardflow/api/parsers/pptx_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/document_fixtures.dart';

/// Красная фаза итерации 3a: PPTX → нормализованный текст (SPEC A8.3).
void main() {
  const PptxParser parser = PptxParser();

  Future<ParsedDocument> parse(Uint8List bytes) =>
      parser.parse(bytes, fileName: 'презентация.pptx');

  test('формат парсера — pptx', () {
    expect(parser.format, DocumentFormat.pptx);
  });

  test('слайды → разделы в порядке presentation.xml', () async {
    final ParsedDocument document = await parse(
      buildPptx(
        slideTexts: <List<String>>[
          <String>['Слайд 1', 'Первый текст'],
          <String>['Слайд 2'],
          <String>['Слайд 3'],
        ],
        presentationOrder: <int>[3, 1, 2],
      ),
    );

    expect(document.metadata.slideCount, 3);
    expect(document.sections, hasLength(3));
    expect(
      document.text.substring(
        document.sections[0].start,
        document.sections[0].end,
      ),
      'Слайд 3',
    );
    expect(
      document.text.substring(
        document.sections[1].start,
        document.sections[1].end,
      ),
      'Слайд 1\nПервый текст',
    );
    expect(
      document.text.substring(
        document.sections[2].start,
        document.sections[2].end,
      ),
      'Слайд 2',
    );
    expect(document.text, 'Слайд 3\n\nСлайд 1\nПервый текст\n\nСлайд 2');
  });

  test('без presentation.xml — числовой порядок slideN.xml', () async {
    final ParsedDocument document = await parse(
      buildPptx(
        slideTexts: <List<String>>[
          <String>['Раз'],
          <String>['Два'],
          <String>['Три'],
        ],
        presentationOrder: <int>[],
      ),
    );

    expect(
      document.text,
      'Раз\n\nДва\n\nТри',
      reason: 'fallback: слайды по возрастанию номера файла',
    );
    expect(document.sections, hasLength(3));
  });

  test('пустая презентация → ParserException(emptyText)', () async {
    await expectLater(
      parse(
        buildPptx(
          slideTexts: <List<String>>[
            <String>[''],
          ],
        ),
      ),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.emptyText,
        ),
      ),
    );
  });

  test('битый ZIP → ParserException(unreadableFile)', () async {
    await expectLater(
      parse(Uint8List.fromList(<int>[0x50, 0x4B, 3, 4, 9, 9])),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.unreadableFile,
        ),
      ),
    );
  });
}
