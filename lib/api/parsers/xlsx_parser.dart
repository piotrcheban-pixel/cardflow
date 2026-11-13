import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:excel_plus/excel_plus.dart';

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
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Не удалось разобрать XLSX: $error',
      );
    }
    final Map<String, Sheet> tables = workbook.tables;
    if (tables.isEmpty) {
      throw const ParserException(
        ParserErrorCode.unreadableFile,
        details: 'В XLSX нет листов',
      );
    }

    final ParsedDocumentBuilder builder = ParsedDocumentBuilder(
      format: format,
      fileName: fileName,
      metadata: ParsedDocumentMetadata(
        sheetNames: List<String>.unmodifiable(tables.keys),
      ),
    );
    for (final MapEntry<String, Sheet> table in tables.entries) {
      builder.startSection(title: table.key);
      for (final List<Data?> row in table.value.rows) {
        final List<String> cells = row.map(_cellText).toList();
        while (cells.isNotEmpty && cells.last.isEmpty) {
          cells.removeLast();
        }
        if (cells.any((String cell) => cell.isNotEmpty)) {
          builder.addLine(cells.join('\t'));
        }
      }
    }
    return builder.build();
  }

  /// Текст ячейки: формула — кэш, дата — `yyyy-MM-dd`, иначе `toString`.
  String _cellText(Data? data) {
    final CellValue? value = data?.value;
    if (value == null) {
      return '';
    }
    if (value is FormulaCellValue) {
      return (value.cachedValue ?? '').trim();
    }
    if (value is DateCellValue) {
      final String month = value.month.toString().padLeft(2, '0');
      final String day = value.day.toString().padLeft(2, '0');
      return '${value.year.toString().padLeft(4, '0')}-$month-$day';
    }
    return value.toString().trim();
  }
}
