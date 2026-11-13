import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/api/parsers/xml_local_names.dart';
import 'package:cardflow/api/parsers/zip_xml.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:xml/xml.dart';

/// Парсер ODT: `archive` + `xml`, `content.xml` (SPEC A8.3).
///
/// `text:h` — заголовки разделов (title), `text:p` — абзацы → строки.
class OdtParser implements DocumentParser {
  /// Создаёт парсер ODT.
  const OdtParser();

  @override
  DocumentFormat get format => DocumentFormat.odt;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) async {
    final SecureZip zip = SecureZip(bytes);
    if (!zip.contains('content.xml')) {
      throw const ParserException(
        ParserErrorCode.unreadableFile,
        details: 'В ODT нет content.xml',
      );
    }
    final XmlDocument content = zip.readXml('content.xml');

    final ParsedDocumentBuilder builder = ParsedDocumentBuilder(
      format: format,
      fileName: fileName,
    );
    for (final XmlElement element in content.descendantElements) {
      final String localName = element.name.local;
      if (localName != 'h' && localName != 'p') {
        continue;
      }
      final String text = collapseWhitespace(element.innerText);
      if (localName == 'h') {
        builder.startSection(title: text.isEmpty ? null : text);
      }
      builder.addLine(text);
    }
    return builder.build();
  }
}

