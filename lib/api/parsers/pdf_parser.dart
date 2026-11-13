import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:pdfrx/pdfrx.dart';

/// Парсер PDF: текстовый слой через `pdfrx` (PDFium, MIT) (SPEC A8.3).
///
/// Страницы → разделы; пустой текстовый слой (скан) → `scannedPdf`; битый или
/// запароленный PDF → `unreadableFile`. Вызывается в отдельном изоляте
/// (ADR-010), инициализация PDFium — `pdfrxInitialize()`.
class PdfParser implements DocumentParser {
  /// Создаёт парсер PDF.
  const PdfParser();

  @override
  DocumentFormat get format => DocumentFormat.pdf;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    try {
      await pdfrxInitialize();
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Не удалось инициализировать PDFium: $error',
      );
    }

    PdfDocument document;
    try {
      document = await PdfDocument.openData(
        bytes,
        sourceName: fileName,
        passwordProvider: () => null,
      );
    } on PdfPasswordException catch (error) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'PDF защищён паролем: ${error.message}',
      );
    } on PdfException catch (error) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'PDF повреждён: ${error.message}',
      );
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Не удалось открыть PDF: $error',
      );
    }

    try {
      if (document.pages.isEmpty) {
        throw const ParserException(
          ParserErrorCode.unreadableFile,
          details: 'В PDF нет страниц',
        );
      }
      final List<String> pageTexts = <String>[];
      for (final PdfPage page in document.pages) {
        String text = '';
        try {
          final PdfPageRawText? raw = await page.loadText();
          text = raw?.fullText.trim() ?? '';
        } on Object {
          text = '';
        }
        pageTexts.add(text);
      }
      if (pageTexts.every((String text) => text.isEmpty)) {
        throw const ParserException(
          ParserErrorCode.scannedPdf,
          details: 'Текстовый слой PDF пуст — вероятно, скан',
        );
      }
      final ParsedDocumentBuilder builder = ParsedDocumentBuilder(
        format: format,
        fileName: fileName,
        metadata: ParsedDocumentMetadata(pageCount: pageTexts.length),
      );
      for (final String pageText in pageTexts) {
        if (pageText.isEmpty) {
          continue;
        }
        builder.startSection();
        builder.addLines(pageText.split('\n'));
      }
      return builder.build();
    } finally {
      await document.dispose();
    }
  }
}
