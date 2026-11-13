import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/api/parsers/xml_local_names.dart';
import 'package:cardflow/api/parsers/zip_xml.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:xml/xml.dart';

/// Парсер PPTX: `archive` + `xml`, порядок слайдов из `presentation.xml`.
///
/// Слайды (`ppt/slides/slideN.xml`, текст `a:t`) → разделы в порядке
/// `p:sldIdLst` (связи `presentation.xml.rels`); fallback — числовой порядок.
class PptxParser implements DocumentParser {
  /// Создаёт парсер PPTX.
  const PptxParser();

  static final RegExp _slideEntryPattern = RegExp(
    r'^ppt/slides/slide(\d+)\.xml$',
  );

  @override
  DocumentFormat get format => DocumentFormat.pptx;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) async {
    final SecureZip zip = SecureZip(bytes);
    final List<String> slides = _orderedSlideEntries(zip);
    if (slides.isEmpty) {
      throw const ParserException(
        ParserErrorCode.unreadableFile,
        details: 'В PPTX нет слайдов',
      );
    }

    final ParsedDocumentBuilder builder = ParsedDocumentBuilder(
      format: format,
      fileName: fileName,
      metadata: ParsedDocumentMetadata(slideCount: slides.length),
    );
    for (final String slideEntry in slides) {
      if (!zip.contains(slideEntry)) {
        continue;
      }
      final List<String> lines = _slideLines(zip.readXml(slideEntry));
      builder.startSection();
      builder.addLines(lines);
    }
    return builder.build();
  }

  /// Порядок файлов слайдов: `presentation.xml` → rels, fallback — номера.
  List<String> _orderedSlideEntries(SecureZip zip) {
    const String presentationEntry = 'ppt/presentation.xml';
    const String relsEntry = 'ppt/_rels/presentation.xml.rels';
    if (zip.contains(presentationEntry) && zip.contains(relsEntry)) {
      final Map<String, String> targets = _relationshipTargets(
        zip.readXml(relsEntry),
      );
      final List<String> order = <String>[];
      for (final XmlElement slideId
          in descendantElementsByLocalName(
            zip.readXml(presentationEntry),
            'sldId',
          )) {
        final String? relationshipId = attributeValueByPrefix(
          slideId,
          'id',
          'r',
        );
        if (relationshipId == null) {
          continue;
        }
        final String? target = targets[relationshipId];
        if (target == null) {
          continue;
        }
        final String normalized = target.startsWith('/')
            ? target.substring(1)
            : 'ppt/$target';
        order.add(normalized.replaceAll('\\', '/'));
      }
      if (order.isNotEmpty) {
        return order;
      }
    }
    final List<String> fallback = zip.entryNames
        .where(_slideEntryPattern.hasMatch)
        .toList();
    fallback.sort(
      (String a, String b) => _slideNumber(a).compareTo(_slideNumber(b)),
    );
    return fallback;
  }

  int _slideNumber(String entry) {
    final RegExpMatch? match = _slideEntryPattern.firstMatch(entry);
    return int.parse(match?.group(1) ?? '0');
  }

  /// Карта `Relationship Id → Target` из XML-файла связей.
  Map<String, String> _relationshipTargets(XmlDocument rels) {
    final Map<String, String> targets = <String, String>{};
    for (final XmlElement relationship
        in descendantElementsByLocalName(rels, 'Relationship')) {
      final String? id = attributeValueByLocalName(relationship, 'Id');
      final String? target = attributeValueByLocalName(relationship, 'Target');
      if (id != null && target != null) {
        targets[id] = target;
      }
    }
    return targets;
  }

  /// Строки слайда: абзацы `a:p`, текст `a:t`.
  List<String> _slideLines(XmlDocument slide) {
    final List<String> lines = <String>[];
    for (final XmlElement paragraph
        in descendantElementsByLocalName(slide, 'p')) {
      final StringBuffer buffer = StringBuffer();
      for (final XmlElement text in descendantElementsByLocalName(paragraph, 't')) {
        buffer.write(text.innerText);
      }
      final String line = collapseWhitespace(buffer.toString());
      if (line.isNotEmpty) {
        lines.add(line);
      }
    }
    return lines;
  }
}

