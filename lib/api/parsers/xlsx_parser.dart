import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Парсер XLSX через `excel_plus` (SPEC A8.3).
///
/// Листы → разделы (title = имя листа); строки → строки, ячейки через `\t`;
/// формулы — по кэшированному значению (`FormulaCellValue.cachedValue`),
/// даты — `yyyy-MM-dd`.
class XlsxParser implements DocumentParser {
  /// Создаёт парсер XLSX.
  const XlsxParser();

  @override
  DocumentFormat get format => DocumentFormat.xlsx;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) {
    throw UnimplementedError('XlsxParser.parse');
  }
}
