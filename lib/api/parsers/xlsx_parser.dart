import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/api/parsers/zip_xml.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:excel_plus/excel_plus.dart';

/// Парсер XLSX через `excel_plus` (SPEC A8.3).
///
/// Листы → разделы (title = имя листа); строки → строки, ячейки через `\t`;
/// формулы — по кэшированному значению `FormulaCellValue.cachedValue`
/// (если кэша нет — исходная формула с `=`, чтобы не терять данные);
/// даты (в т.ч. с временем) — `yyyy-MM-dd`.
///
/// Перед разбором байты проходят те же ZIP-лимиты, что DOCX/PPTX/ODT
/// (`SecureZip`): XLSX — тоже ZIP-контейнер (ADR-010 §4), защита от zip-bomb
/// должна применяться ко всем четырём форматам.
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
    // Проверка структуры и лимитов контейнера до передачи в excel_plus.
    SecureZip(bytes);
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

  /// Текст ячейки: формула — кэш (иначе `=формула`), дата — `yyyy-MM-dd`.
  String _cellText(Data? data) {
    final CellValue? value = data?.value;
    if (value == null) {
      return '';
    }
    if (value is FormulaCellValue) {
      final String? cached = value.cachedValue;
      if (cached != null && cached.isNotEmpty) {
        return cached.trim();
      }
      return '=${value.formula}'.trim();
    }
    if (value is DateCellValue) {
      return _formatDate(value.year, value.month, value.day);
    }
    if (value is DateTimeCellValue) {
      return _formatDate(value.year, value.month, value.day);
    }
    return value.toString().trim();
  }

  String _formatDate(int year, int month, int day) {
    final String paddedMonth = month.toString().padLeft(2, '0');
    final String paddedDay = day.toString().padLeft(2, '0');
    return '${year.toString().padLeft(4, '0')}-$paddedMonth-$paddedDay';
  }
}
