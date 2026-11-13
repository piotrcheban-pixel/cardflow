import 'dart:typed_data';

import 'package:cardflow/api/parsers/xlsx_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/document_fixtures.dart';

/// Красная фаза итерации 3a: XLSX → нормализованный текст (SPEC A8.3).
void main() {
  const XlsxParser parser = XlsxParser();

  Future<ParsedDocument> parse(Uint8List bytes) =>
      parser.parse(bytes, fileName: 'таблица.xlsx');

  test('формат парсера — xlsx', () {
    expect(parser.format, DocumentFormat.xlsx);
  });

  test('листы → разделы с title, строки → строки, ячейки через табуляцию', () async {
    final ParsedDocument document = await parse(
      buildXlsx(<String, String>{
        'Столицы': xlsxRow(1, <String>[
          xlsxTextCell('A1', 'Страна'),
          xlsxTextCell('B1', 'Столица'),
        ]) +
            xlsxRow(2, <String>[
              xlsxTextCell('A2', 'Россия'),
              xlsxTextCell('B2', 'Москва'),
            ]),
        'Реки': xlsxRow(1, <String>[xlsxTextCell('A1', 'Волга')]),
      }),
    );

    expect(document.metadata.sheetNames, <String>['Столицы', 'Реки']);
    expect(document.sections, hasLength(2));
    expect(document.sections[0].title, 'Столицы');
    expect(document.sections[1].title, 'Реки');
    expect(
      document.text.substring(
        document.sections[0].start,
        document.sections[0].end,
      ),
      'Страна\tСтолица\nРоссия\tМосква',
    );
    expect(
      document.text.substring(
        document.sections[1].start,
        document.sections[1].end,
      ),
      'Волга',
    );
  });

  test('формула берётся по кэшированному значению, а не как формула', () async {
    final ParsedDocument document = await parse(
      buildXlsx(<String, String>{
        'Лист1': xlsxRow(1, <String>[
          xlsxNumberCell('A1', 41),
          xlsxFormulaCell('B1', 'A1+1', '42'),
        ]),
      }),
    );

    expect(document.text, contains('42'));
    expect(
      document.text,
      isNot(contains('A1+1')),
      reason: 'SPEC A8.3: формулы — по кэшированному значению',
    );
  });

  test('дата приводится к yyyy-MM-dd, хвостовые пустые ячейки убираются', () async {
    final ParsedDocument document = await parse(
      buildXlsx(<String, String>{
        'Лист1': xlsxRow(1, <String>[
          xlsxDateCell('A1', '2024-05-17'),
          xlsxTextCell('B1', 'Москва'),
        ]) +
            xlsxRow(2, <String>[xlsxTextCell('A2', 'Без ячеек справа')]),
      }),
    );

    expect(document.text, '2024-05-17\tМосква\nБез ячеек справа');
  });

  test('пустая таблица → ParserException(emptyText)', () async {
    await expectLater(
      parse(buildXlsx(<String, String>{'Лист1': ''})),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.emptyText,
        ),
      ),
    );
  });

  test('битые байты → ParserException(unreadableFile)', () async {
    await expectLater(
      parse(Uint8List.fromList(<int>[0x50, 0x4B, 3, 4, 0, 0, 0])),
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
