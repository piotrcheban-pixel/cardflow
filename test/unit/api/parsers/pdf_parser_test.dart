import 'dart:typed_data';

import 'package:cardflow/api/parsers/pdf_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixtures/document_fixtures.dart';

/// Красная фаза итерации 3a: PDF через pdfrx (SPEC A8.3, ADR-010).
///
/// PDFium инициализируется один раз на процесс теста: PDF-парсер использует
/// Dart-инициализацию pdfrx (без Flutter-виджетов и плагинов).
void main() {
  const PdfParser parser = PdfParser();

  setUpAll(() async {
    await pdfrxInitialize();
  });

  Future<ParsedDocument> parse(Uint8List bytes) =>
      parser.parse(bytes, fileName: 'материалы.pdf');

  test('формат парсера — pdf', () {
    expect(parser.format, DocumentFormat.pdf);
  });

  test('текстовый слой извлекается, страница → раздел, pageCount в метаданных', () async {
    final ParsedDocument document = await parse(buildPdf('Hello CardFlow PDF'));

    expect(document.text, 'Hello CardFlow PDF');
    expect(document.metadata.pageCount, 1);
    expect(document.sections, hasLength(1));
    expect(
      document.text.substring(
        document.sections.single.start,
        document.sections.single.end,
      ),
      'Hello CardFlow PDF',
    );
  });

  test('PDF без текстового слоя (скан) → ParserException(scannedPdf)', () async {
    await expectLater(
      parse(buildPdfWithoutText()),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.scannedPdf,
        ),
      ),
    );
  });

  test('битый PDF → ParserException(unreadableFile)', () async {
    await expectLater(
      parse(
        Uint8List.fromList(
          <int>[...'%PDF-1.4\n'.codeUnits, ...'это не pdf-структура'.codeUnits],
        ),
      ),
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
