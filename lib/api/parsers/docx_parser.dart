import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_images.dart';
import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/api/parsers/xml_local_names.dart';
import 'package:cardflow/api/parsers/zip_xml.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:xml/xml.dart';

/// Парсер DOCX: `archive` + `xml`, `word/document.xml` (SPEC A8.3).
///
/// Абзацы (`w:p`/`w:t`) → строки; таблицы (`w:tbl`/`w:tr`/`w:tc`) → строки через
/// табуляцию; заголовки (`w:pStyle` = `Heading*`/`Title`) открывают раздел.
/// Изображения (`word/media` + привязка `r:embed` к абзацу) извлекаются с
/// подписью и окружающим текстом (fix-gen, Д3).
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
    final List<_DocxBlock> blocks = <_DocxBlock>[
      for (final XmlElement element in _blocks(body)) _blockOf(element),
    ];
    final Map<String, String> relationships = _documentRelationships(zip);
    final DocumentImageCollector collector = DocumentImageCollector();

    String? currentHeading;
    String previousText = '';
    for (var index = 0; index < blocks.length; index++) {
      final _DocxBlock block = blocks[index];
      if (block.heading != null) {
        currentHeading = block.heading;
        builder.startSection(title: block.heading);
      }
      if (block.rows.isNotEmpty) {
        for (final String row in block.rows) {
          builder.addLine(row);
        }
      } else {
        builder.addLine(block.text);
      }
      for (final String relationshipId in block.imageIds) {
        final DocumentImage? image = _imageFrom(
          zip,
          relationships,
          relationshipId,
          fileName: fileName,
          caption: _captionFor(blocks, index),
          context: block.text.isNotEmpty
              ? block.text
              : previousText.isNotEmpty
              ? previousText
              : currentHeading,
          collector: collector,
        );
        if (image != null) builder.addImage(image);
      }
      if (block.text.isNotEmpty) previousText = block.text;
    }
    return builder.build();
  }

  /// Блок документа: абзац/таблица, заголовок и привязанные изображения.
  _DocxBlock _blockOf(XmlElement element) {
    if (element.name.local == 'tbl') {
      return _DocxBlock(
        text: '',
        rows: _tableRows(element).toList(growable: false),
        imageIds: const <String>[],
      );
    }
    return _DocxBlock(
      text: _paragraphText(element),
      heading: _headingTitle(element),
      imageIds: _imageRelationshipIds(element),
    );
  }

  /// Идентификаторы связей изображений в абзаце (`r:embed`, `r:id`).
  List<String> _imageRelationshipIds(XmlElement paragraph) {
    final List<String> ids = <String>[];
    for (final XmlElement element in paragraph.descendantElements) {
      if (element.name.local == 'blip') {
        final String? embed = attributeValueByLocalName(element, 'embed');
        if (embed != null && !ids.contains(embed)) ids.add(embed);
      } else if (element.name.local == 'imagedata') {
        final String? id = attributeValueByPrefix(element, 'id', 'r');
        if (id != null && !ids.contains(id)) ids.add(id);
      }
    }
    return ids;
  }

  /// Подпись ближайшего рисунка: сам абзац или следующий за ним.
  String? _captionFor(List<_DocxBlock> blocks, int index) {
    final String own = collapseWhitespace(blocks[index].text);
    if (looksLikeImageCaption(own)) return own;
    for (
      var next = index + 1;
      next < blocks.length && next <= index + 2;
      next++
    ) {
      final String candidate = collapseWhitespace(blocks[next].text);
      if (looksLikeImageCaption(candidate)) return candidate;
    }
    return null;
  }

  /// Карта `Relationship Id → Target` из `word/_rels/document.xml.rels`.
  Map<String, String> _documentRelationships(SecureZip zip) {
    const String relsEntry = 'word/_rels/document.xml.rels';
    if (!zip.contains(relsEntry)) return const <String, String>{};
    final Map<String, String> targets = <String, String>{};
    for (final XmlElement relationship in descendantElementsByLocalName(
      zip.readXml(relsEntry),
      'Relationship',
    )) {
      final String? id = attributeValueByLocalName(relationship, 'Id');
      final String? target = attributeValueByLocalName(relationship, 'Target');
      if (id != null && target != null) targets[id] = target;
    }
    return targets;
  }

  /// Читает изображение связи; `null` — внешняя ссылка/нет записи/мусор.
  DocumentImage? _imageFrom(
    SecureZip zip,
    Map<String, String> relationships,
    String relationshipId, {
    required String fileName,
    required String? caption,
    required String? context,
    required DocumentImageCollector collector,
  }) {
    final String? target = relationships[relationshipId];
    if (target == null || target.startsWith('http')) return null;
    final String entry = target.startsWith('/')
        ? target.substring(1)
        : 'word/$target';
    final String normalized = entry.replaceAll('\\', '/');
    if (!zip.contains(normalized)) return null;
    late final Uint8List bytes;
    try {
      bytes = zip.readBytes(normalized);
    } on ParserException {
      return null;
    }
    return collector.add(
      entryName: normalized,
      bytes: bytes,
      fileName: fileName,
      sectionIndex: 0,
      caption: caption,
      context: context,
    );
  }

  /// Блочные элементы тела документа в порядке следования.
  ///
  /// Помимо прямых `w:p`/`w:tbl` разворачивает контейнеры content controls
  /// (`w:sdt` → `w:sdtContent`) и `w:customXml`, иначе текст из них теряется.
  Iterable<XmlElement> _blocks(XmlElement container) sync* {
    for (final XmlElement child in container.childElements) {
      switch (child.name.local) {
        case 'p':
        case 'tbl':
          yield child;
        case 'sdt':
        case 'sdtContent':
        case 'customXml':
          yield* _blocks(child);
        default:
          continue;
      }
    }
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
  ///
  /// Узлы поддерева `w:pPr` (таб-стопы `w:tabs/w:tab`, рамки и т.п.) — разметка,
  /// а не текст абзаца, поэтому пропускаются.
  String _paragraphText(XmlElement paragraph) {
    final StringBuffer buffer = StringBuffer();
    for (final XmlElement element in paragraph.descendantElements) {
      if (_insideParagraphProperties(element, paragraph)) {
        continue;
      }
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

  /// Лежит ли [element] внутри `w:pPr` абзаца [paragraph].
  bool _insideParagraphProperties(XmlElement element, XmlElement paragraph) {
    XmlNode? node = element.parent;
    while (node != null && node != paragraph) {
      if (node is XmlElement && node.name.local == 'pPr') {
        return true;
      }
      node = node.parent;
    }
    return false;
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

/// Блок DOCX для первого прохода: текст, заголовок, строки таблицы, картинки.
class _DocxBlock {
  const _DocxBlock({
    required this.text,
    required this.imageIds,
    this.heading,
    this.rows = const <String>[],
  });

  final String text;
  final String? heading;
  final List<String> rows;
  final List<String> imageIds;
}
