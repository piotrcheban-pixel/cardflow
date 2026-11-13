import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Парсер PPTX: `archive` + `xml`, порядок слайдов из `presentation.xml`.
///
/// Слайды (`ppt/slides/slideN.xml`, текст `a:t`) → разделы в порядке
/// `p:sldIdLst` (связи `presentation.xml.rels`); fallback — числовой порядок.
class PptxParser implements DocumentParser {
  /// Создаёт парсер PPTX.
  const PptxParser();

  @override
  DocumentFormat get format => DocumentFormat.pptx;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) {
    throw UnimplementedError('PptxParser.parse');
  }
}
