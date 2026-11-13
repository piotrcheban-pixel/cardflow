import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

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
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) {
    throw UnimplementedError('PdfParser.parse');
  }
}
