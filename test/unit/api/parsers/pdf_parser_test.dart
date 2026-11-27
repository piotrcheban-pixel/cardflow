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

  test(
    'текстовый слой извлекается, страница → раздел, pageCount в метаданных',
    () async {
      final ParsedDocument document = await parse(
        buildPdf('Hello CardFlow PDF'),
      );

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
    },
  );

  test(
    'PDF без текстового слоя (скан) → ParserException(scannedPdf)',
    () async {
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
    },
  );

  test('битый PDF → ParserException(corruptFile)', () async {
    await expectLater(
      parse(
        Uint8List.fromList(<int>[
          ...'%PDF-1.4\n'.codeUnits,
          ...'это не pdf-структура'.codeUnits,
        ]),
      ),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.corruptFile,
        ),
      ),
    );
  });

  test(
    'многостраничный PDF: страницы → разделы, пустая страница пропускается',
    () async {
      final ParsedDocument document = await parse(
        buildPdfPages(<String>['First page', '', 'Third page']),
      );
      expect(document.metadata.pageCount, 3);
      expect(document.sections, hasLength(2));
      expect(document.text, 'First page\n\nThird page');
    },
  );

  test('запароленный PDF → ParserException(passwordProtected)', () async {
    await expectLater(
      parse(
        buildEncryptedPdf(
          userPassword: 'secret-user',
          ownerPassword: 'secret-owner',
        ),
      ),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.passwordProtected,
        ),
      ),
    );
  });

  // Итерация 7.10, ADR-024: битый ToUnicode-словарь → U+FFFD → понятная ошибка
  // вместо мусорного текста в запросе к API.
  test('PDF с символами замены → ParserException(garbledText)', () async {
    await expectLater(
      parse(buildGarbledPdf()),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.garbledText,
        ),
      ),
    );
  });

  test('PDF с C1-управляющими: они удаляются, текст остаётся', () async {
    final ParsedDocument document = await parse(
      buildPdf('Hello\u0080\u0085\u009F CardFlow'),
    );

    expect(document.text, 'Hello CardFlow');
    for (final int code in document.text.codeUnits) {
      expect(
        code < 0x80 || code > 0x9F,
        isTrue,
        reason: 'C1-управляющий U+${code.toRadixString(16)} остался в тексте',
      );
    }
  });

  test('PDF с одиночными суррогатами: они вычищаются из текста', () async {
    final ParsedDocument document = await parse(
      buildType0UnicodePdf(<String>['0041', 'D800', 'D800', '0042']),
    );

    expect(document.text, 'AB');
  });

  // TASK 04, часть 2: обычный PDF с кириллицей — не ошибка и не мусор.
  test('PDF с кириллицей: текст извлекается без замен', () async {
    final ParsedDocument document = await parse(
      buildType0UnicodePdf(<String>[
        '041F',
        '0440',
        '0438',
        '0432',
        '0435',
        '0442',
        '0020',
        '043C',
        '0438',
        '0440',
      ]),
    );

    expect(document.text, 'Привет мир');
    expect(document.text, isNot(contains('\uFFFD')));
  });

  // TASK 04, часть 2: большой документ разбирается целиком.
  test('большой PDF (120 страниц): все страницы → разделы', () async {
    final ParsedDocument document = await parse(
      buildPdfPages(<String>[
        for (int page = 1; page <= 120; page++) 'Page $page content',
      ]),
    );

    expect(document.metadata.pageCount, 120);
    expect(document.sections, hasLength(120));
    expect(document.text, contains('Page 1 content'));
    expect(document.text, contains('Page 120 content'));
  });

  // TASK 04, часть 2: пустой (0 байт) PDF не считается успехом.
  test('пустой PDF → corruptFile, а не пустой документ', () async {
    await expectLater(
      parse(Uint8List(0)),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.corruptFile,
        ),
      ),
    );
  });
}
