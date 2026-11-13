import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Минимальный RTF-конвертер (SPEC A8.3, ADR-010).
///
/// Поддержка: `\'hh` с кодовой страницей из `\ansicpg` (для русского — cp1251),
/// `\uN` с пропуском `\ucN`, `\par`/`\line`/`\tab`, экранирование `\\`/`\{`/`\}`,
/// пропуск групп `fonttbl`/`colortbl`/`stylesheet`/`pict`/`info` и `\*`-групп.
class RtfParser implements DocumentParser {
  /// Создаёт парсер RTF.
  const RtfParser();

  @override
  DocumentFormat get format => DocumentFormat.rtf;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) {
    throw UnimplementedError('RtfParser.parse');
  }
}
