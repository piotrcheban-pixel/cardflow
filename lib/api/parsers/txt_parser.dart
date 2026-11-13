import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Парсер TXT/MD: чтение байтов с явным определением кодировки (SPEC A8.3).
///
/// Порядок: BOM UTF-8 → BOM UTF-16 → строгий UTF-8 → cp1251/KOI8-R по доле
/// кириллицы (ADR-010). Формат (`txt` или `md`) задаётся в конструкторе.
class TxtParser implements DocumentParser {
  /// Создаёт парсер текста; [format] — [DocumentFormat.txt] или `.md`.
  const TxtParser({this.format = DocumentFormat.txt});

  @override
  final DocumentFormat format;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) {
    throw UnimplementedError('TxtParser.parse');
  }
}
