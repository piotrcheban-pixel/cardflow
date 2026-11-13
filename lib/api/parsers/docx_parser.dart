import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Парсер DOCX: `archive` + `xml`, `word/document.xml` (SPEC A8.3).
///
/// Абзацы (`w:p`/`w:t`) → строки; таблицы (`w:tbl`/`w:tr`/`w:tc`) → строки через
/// табуляцию; заголовки (`w:pStyle` = `Heading*`/`Title`) открывают раздел.
class DocxParser implements DocumentParser {
  /// Создаёт парсер DOCX.
  const DocxParser();

  @override
  DocumentFormat get format => DocumentFormat.docx;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) {
    throw UnimplementedError('DocxParser.parse');
  }
}
