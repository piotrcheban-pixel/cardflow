import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Парсер ODT: `archive` + `xml`, `content.xml` (SPEC A8.3).
///
/// `text:h` — заголовки разделов (title), `text:p` — абзацы → строки.
class OdtParser implements DocumentParser {
  /// Создаёт парсер ODT.
  const OdtParser();

  @override
  DocumentFormat get format => DocumentFormat.odt;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) {
    throw UnimplementedError('OdtParser.parse');
  }
}
