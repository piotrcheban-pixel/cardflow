import 'dart:typed_data';

import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/parsers/fixtures/document_fixtures.dart';

/// Красная фаза итерации 3a: детекция формата и сигнатур (SPEC A8.3, ADR-003).
void main() {
  group('documentFormatFromFileName: расширение → DocumentFormat', () {
    test('все поддерживаемые расширения распознаются', () {
      for (final DocumentFormat format in DocumentFormat.values) {
        expect(
          documentFormatFromFileName('конспект.${format.extension}'),
          format,
          reason: 'Расширение .${format.extension} должно распознаваться',
        );
      }
    });

    test('регистр расширения не важен, путь учитывается', () {
      expect(
        documentFormatFromFileName(r'C:\материалы\Лекция 1.DOCX'),
        DocumentFormat.docx,
      );
      expect(documentFormatFromFileName('/tmp/notes.Md'), DocumentFormat.md);
      expect(documentFormatFromFileName('файл.PDF'), DocumentFormat.pdf);
    });

    test('неизвестное расширение или его отсутствие → null', () {
      expect(documentFormatFromFileName('конспект.epub'), isNull);
      expect(documentFormatFromFileName('конспект'), isNull);
      expect(documentFormatFromFileName(''), isNull);
    });
  });

  group('isSupportedForParsing: .doc/.xls — известное ограничение', () {
    test('.doc и .xls не поддерживаются, остальные поддерживаются', () {
      expect(DocumentFormat.doc.isSupportedForParsing, isFalse);
      expect(DocumentFormat.xls.isSupportedForParsing, isFalse);
      for (final DocumentFormat format in <DocumentFormat>[
        DocumentFormat.pdf,
        DocumentFormat.docx,
        DocumentFormat.xlsx,
        DocumentFormat.pptx,
        DocumentFormat.odt,
        DocumentFormat.txt,
        DocumentFormat.md,
        DocumentFormat.rtf,
      ]) {
        expect(
          format.isSupportedForParsing,
          isTrue,
          reason: '${format.extension} должен поддерживаться',
        );
      }
    });
  });

  group('verifyDocumentSignature: сигнатуры контейнеров', () {
    test('валидные контейнеры проходят проверку', () {
      expect(
        () => verifyDocumentSignature(DocumentFormat.docx, buildDocx(bodyXml: '')),
        returnsNormally,
      );
      expect(
        () => verifyDocumentSignature(
          DocumentFormat.xlsx,
          buildXlsx(<String, String>{'Лист1': ''}),
        ),
        returnsNormally,
      );
      expect(
        () => verifyDocumentSignature(
          DocumentFormat.pptx,
          buildPptx(slideTexts: <List<String>>[<String>['Слайд']]),
        ),
        returnsNormally,
      );
      expect(
        () => verifyDocumentSignature(
          DocumentFormat.odt,
          buildOdt(blocks: <({String text, bool heading})>[
            (text: 'Абзац', heading: false),
          ]),
        ),
        returnsNormally,
      );
      expect(
        () => verifyDocumentSignature(DocumentFormat.pdf, buildPdf('Text')),
        returnsNormally,
      );
      expect(
        () => verifyDocumentSignature(
          DocumentFormat.rtf,
          buildRtf('Hello RTF'),
        ),
        returnsNormally,
      );
    });

    test('несоответствие сигнатуры → ParserException(unreadableFile)', () {
      const List<DocumentFormat> zipFormats = <DocumentFormat>[
        DocumentFormat.docx,
        DocumentFormat.xlsx,
        DocumentFormat.pptx,
        DocumentFormat.odt,
      ];
      for (final DocumentFormat format in zipFormats) {
        expect(
          () => verifyDocumentSignature(
            format,
            Uint8List.fromList(<int>[1, 2, 3, 4]),
          ),
          throwsA(
            isA<ParserException>().having(
              (ParserException e) => e.code,
              'code',
              ParserErrorCode.unreadableFile,
            ),
          ),
          reason: '${format.extension}: не ZIP → unreadableFile',
        );
      }
      expect(
        () => verifyDocumentSignature(
          DocumentFormat.pdf,
          Uint8List.fromList(<int>[0x50, 0x4B, 3, 4]),
        ),
        throwsA(isA<ParserException>()),
      );
      expect(
        () => verifyDocumentSignature(
          DocumentFormat.rtf,
          Uint8List.fromList(<int>[0x50, 0x4B, 3, 4]),
        ),
        throwsA(isA<ParserException>()),
      );
    });

    test('TXT/MD проверка сигнатуры не выполняется', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0, 1, 2, 255]);
      expect(
        () => verifyDocumentSignature(DocumentFormat.txt, bytes),
        returnsNormally,
      );
      expect(
        () => verifyDocumentSignature(DocumentFormat.md, bytes),
        returnsNormally,
      );
    });
  });
}


