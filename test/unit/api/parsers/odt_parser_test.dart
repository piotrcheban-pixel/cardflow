import 'dart:typed_data';

import 'package:cardflow/api/parsers/odt_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/document_fixtures.dart';

/// Красная фаза итерации 3a: ODT → нормализованный текст (SPEC A8.3).
void main() {
  const OdtParser parser = OdtParser();

  Future<ParsedDocument> parse(Uint8List bytes) =>
      parser.parse(bytes, fileName: 'конспект.odt');

  test('формат парсера — odt', () {
    expect(parser.format, DocumentFormat.odt);
  });

  test('заголовки → разделы с title, абзацы → строки', () async {
    final ParsedDocument document = await parse(
      buildOdt(
        blocks: <({String text, bool heading})>[
          (text: 'Вступление', heading: false),
          (text: 'Раздел 1', heading: true),
          (text: 'Текст раздела 1', heading: false),
          (text: 'Раздел 2', heading: true),
          (text: 'Текст раздела 2', heading: false),
        ],
      ),
    );

    expect(
      document.text,
      'Вступление\n\nРаздел 1\nТекст раздела 1\n\nРаздел 2\nТекст раздела 2',
    );
    expect(document.sections, hasLength(3));
    expect(document.sections[0].title, isNull);
    expect(document.sections[1].title, 'Раздел 1');
    expect(document.sections[2].title, 'Раздел 2');
    expect(
      document.text.substring(
        document.sections[1].start,
        document.sections[1].end,
      ),
      'Раздел 1\nТекст раздела 1',
    );
  });

  test('пустой ODT → ParserException(emptyText)', () async {
    await expectLater(
      parse(
        buildOdt(
          blocks: <({String text, bool heading})>[(text: '', heading: false)],
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
      parse(Uint8List.fromList(<int>[0x50, 0x4B, 3, 4, 0, 0])),
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
