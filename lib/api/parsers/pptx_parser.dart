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

/// Парсер PPTX: `archive` + `xml`, порядок слайдов из `presentation.xml`.
///
/// Слайды (`ppt/slides/slideN.xml`, текст `a:t`) → разделы в порядке
/// `p:sldIdLst` (связи `presentation.xml.rels`); fallback — числовой порядок.
/// Изображения слайдов (`ppt/media`, привязка `r:embed`) извлекаются с
/// заголовком слайда и номером (fix-gen, Д3); повторы (логотип на каждом
/// слайде) отбрасываются по хешу содержимого.
class PptxParser implements DocumentParser {
  /// Создаёт парсер PPTX.
  const PptxParser();

  static final RegExp _slideEntryPattern = RegExp(
    r'^ppt/slides/slide(\d+)\.xml$',
  );

  @override
  DocumentFormat get format => DocumentFormat.pptx;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final SecureZip zip = SecureZip(bytes);
    final List<String> slides = _orderedSlideEntries(zip)
        .where(zip.contains)
        .toList();
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
    final DocumentImageCollector collector = DocumentImageCollector();
    for (var index = 0; index < slides.length; index++) {
      final String slideEntry = slides[index];
      final XmlDocument slide = zip.readXml(slideEntry);
      final List<String> lines = _slideLines(slide);
      builder.startSection();
      builder.addLines(lines);
      for (final DocumentImage image in _slideImages(
        zip,
        slideEntry,
        slide,
        lines,
        page: index + 1,
        fileName: fileName,
        collector: collector,
      )) {
        builder.addImage(image);
      }
    }
    return builder.build();
  }

  /// Изображения слайда с контекстом (заголовок слайда, подпись).
  List<DocumentImage> _slideImages(
    SecureZip zip,
    String slideEntry,
    XmlDocument slide,
    List<String> lines, {
    required int page,
    required String fileName,
    required DocumentImageCollector collector,
  }) {
    final List<String> relationshipIds = <String>[];
    for (final XmlElement blip in descendantElementsByLocalName(
      slide,
      'blip',
    )) {
      final String? embed = attributeValueByLocalName(blip, 'embed');
      if (embed != null && !relationshipIds.contains(embed)) {
        relationshipIds.add(embed);
      }
    }
    if (relationshipIds.isEmpty) return const <DocumentImage>[];
    final Map<String, String> targets = _slideRelationships(zip, slideEntry);
    String? caption;
    for (final String line in lines) {
      final String cleaned = collapseWhitespace(line);
      if (looksLikeImageCaption(cleaned)) {
        caption = cleaned;
        break;
      }
    }
    final String? context = lines.isEmpty
        ? null
        : collapseWhitespace(lines.take(2).join(' '));
    final List<DocumentImage> images = <DocumentImage>[];
    for (final String relationshipId in relationshipIds) {
      final String? target = targets[relationshipId];
      if (target == null || target.startsWith('http')) continue;
      final String entry = _resolveMediaEntry(slideEntry, target);
      if (!zip.contains(entry)) continue;
      final DocumentImage? image = collector.add(
        entryName: entry,
        bytes: zip.readBytes(entry),
        fileName: fileName,
        sectionIndex: 0,
        caption: caption,
        context: context,
        page: page,
      );
      if (image != null) images.add(image);
    }
    return images;
  }

  /// Связи слайда: `ppt/slides/_rels/slideN.xml.rels`.
  Map<String, String> _slideRelationships(SecureZip zip, String slideEntry) {
    final int slash = slideEntry.lastIndexOf('/');
    final String name = slideEntry.substring(slash + 1);
    final String relsEntry =
        '${slideEntry.substring(0, slash)}/_rels/$name.rels';
    if (!zip.contains(relsEntry)) return const <String, String>{};
    return _relationshipTargets(zip.readXml(relsEntry));
  }

  /// Путь записи архива для `Target` слайда (`../media/x.png` → `ppt/media/x.png`).
  String _resolveMediaEntry(String slideEntry, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final List<String> parts = slideEntry.split('/')..removeLast();
    for (final String segment in target.split('/')) {
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (segment.isNotEmpty && segment != '.') {
        parts.add(segment);
      }
    }
    return parts.join('/');
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
      for (final XmlElement slideId in descendantElementsByLocalName(
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
    for (final XmlElement relationship in descendantElementsByLocalName(
      rels,
      'Relationship',
    )) {
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
    for (final XmlElement paragraph in descendantElementsByLocalName(
      slide,
      'p',
    )) {
      final StringBuffer buffer = StringBuffer();
      for (final XmlElement text in descendantElementsByLocalName(
        paragraph,
        't',
      )) {
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
