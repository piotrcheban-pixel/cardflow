import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/api/parsers/xml_local_names.dart';
import 'package:cardflow/api/parsers/zip_xml.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:xml/xml.dart';

/// Парсер DOCX: `archive` + `xml`, `word/document.xml` (SPEC A8.3).
///
/// Абзацы (`w:p`/`w:t`) → строки; таблицы (`w:tbl`/`w:tr`/`w:tc`) → строки через
/// табуляцию; заголовки (`w:pStyle` = `Heading*`/`Title`) открывают раздел.
class DocxParser implements DocumentParser {
  /// Создаёт парсер DOCX.
  const DocxParser();

  /// Стили абзаца, которые считаются заголовками разделов.
  static const List<String> _headingStylePrefixes = <String>[
    'heading',
    'title',
  ];

  @override
  DocumentFormat get format => DocumentFormat.docx;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final SecureZip zip = SecureZip(bytes);
    if (!zip.contains('word/document.xml')) {
      throw const ParserException(
        ParserErrorCode.unreadableFile,
        details: 'В DOCX нет word/document.xml',
      );
    }
    final XmlDocument document = zip.readXml('word/document.xml');
    final XmlElement? body = firstDescendantByLocalName(document, 'body');
    if (body == null) {
      throw const ParserException(
        ParserErrorCode.unreadableFile,
        details: 'В DOCX нет w:body',
      );
    }

    final ParsedDocumentBuilder builder = ParsedDocumentBuilder(
      format: format,
      fileName: fileName,
    );
    for (final XmlElement block in body.childElements) {
      switch (block.name.local) {
        case 'p':
          final String? heading = _headingTitle(block);
          final String text = _paragraphText(block);
          if (heading != null) {
            builder.startSection(title: heading);
          }
          builder.addLine(text);
        case 'tbl':
          for (final String row in _tableRows(block)) {
            builder.addLine(row);
          }
        default:
          continue;
      }
    }
    return builder.build();
  }

  /// Заголовок абзаца, если стиль `w:pStyle` — Heading*/Title.
  String? _headingTitle(XmlElement paragraph) {
    for (final XmlElement properties in paragraph.childElements) {
      if (properties.name.local != 'pPr') {
        continue;
      }
      for (final XmlElement style in properties.childElements) {
        if (style.name.local != 'pStyle') {
          continue;
        }
        final String? value = attributeValueByLocalName(style, 'val');
        if (value == null) {
          continue;
        }
        final String normalized = value.toLowerCase();
        final bool isHeading = _headingStylePrefixes.any(
          (String prefix) => normalized.startsWith(prefix),
        );
        if (isHeading) {
          final String text = collapseWhitespace(_paragraphText(paragraph));
          return text.isEmpty ? null : text;
        }
      }
    }
    return null;
  }

  /// Текст абзаца: `w:t` со всеми прогонами, `w:tab` → `\t`, `w:br`/`w:cr` → `\n`.
  String _paragraphText(XmlElement paragraph) {
    final StringBuffer buffer = StringBuffer();
    for (final XmlElement element in paragraph.descendantElements) {
      switch (element.name.local) {
        case 't':
          buffer.write(element.innerText);
        case 'tab':
          buffer.write('\t');
        case 'br':
        case 'cr':
          buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  /// Строки таблицы: ячейки через `\t`, пустые хвостовые ячейки убираются.
  Iterable<String> _tableRows(XmlElement table) sync* {
    for (final XmlElement row in table.descendantElements) {
      if (row.name.local != 'tr' || _nearestTable(row) != table) {
        continue;
      }
      final List<String> cells = <String>[];
      for (final XmlElement cell in row.childElements) {
        if (cell.name.local != 'tc') {
          continue;
        }
        cells.add(_cellText(cell));
      }
      while (cells.isNotEmpty && cells.last.isEmpty) {
        cells.removeLast();
      }
      yield cells.join('\t');
    }
  }

  /// Ближайшая таблица-предок элемента [element].
  XmlElement? _nearestTable(XmlElement element) {
    for (final XmlElement ancestor in element.ancestorElements) {
      if (ancestor.name.local == 'tbl') {
        return ancestor;
      }
    }
    return null;
  }

  /// Текст ячейки: абзацы через пробел (структура вложенных таблиц теряется).
  String _cellText(XmlElement cell) {
    final List<String> paragraphs = <String>[];
    for (final XmlElement paragraph in cell.descendantElements) {
      if (paragraph.name.local != 'p') {
        continue;
      }
      final String text = collapseWhitespace(_paragraphText(paragraph));
      if (text.isNotEmpty) {
        paragraphs.add(text);
      }
    }
    return paragraphs.join(' ');
  }
}
