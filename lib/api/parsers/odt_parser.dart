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

/// Парсер ODT: `archive` + `xml`, `content.xml` (SPEC A8.3).
///
/// `text:h` — заголовки разделов (title), `text:p` — абзацы → строки.
/// Служебные поддеревья (оглавление `text:index-body`/`text:table-of-content`,
/// примечания `office:annotation`, отслеживаемые изменения) пропускаются,
/// иначе оглавление дублирует текст, а комментарии рецензентов попадают
/// в материал для генерации карточек. Изображения (`draw:image` →
/// `Pictures/`) извлекаются с окружающим текстом (fix-gen, Д3).
class OdtParser implements DocumentParser {
  /// Создаёт парсер ODT.
  const OdtParser();

  /// Служебные элементы, чьё поддерево не является текстом документа.
  static const Set<String> _serviceElements = <String>{
    'index-body',
    'table-of-content',
    'annotation',
    'tracked-changes',
  };

  @override
  DocumentFormat get format => DocumentFormat.odt;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
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
    final DocumentImageCollector collector = DocumentImageCollector();
    String previousText = '';
    String? currentHeading;
    final List<XmlElement> paragraphs = content.descendantElements
        .where((XmlElement element) {
          final String localName = element.name.local;
          if (localName != 'h' && localName != 'p') return false;
          return !_insideServiceElement(element);
        })
        .toList(growable: false);
    for (var index = 0; index < paragraphs.length; index++) {
      final XmlElement element = paragraphs[index];
      final String text = collapseWhitespace(element.innerText);
      if (element.name.local == 'h') {
        currentHeading = text.isEmpty ? null : text;
        builder.startSection(title: text.isEmpty ? null : text);
      }
      builder.addLine(text);
      for (final String href in _imageHrefs(element)) {
        final String entry = href.startsWith('/') ? href.substring(1) : href;
        if (!zip.contains(entry)) continue;
        final String caption = looksLikeImageCaption(text)
            ? text
            : _followingCaption(paragraphs, index) ?? '';
        final String? context = text.isNotEmpty
            ? text
            : previousText.isNotEmpty
            ? previousText
            : currentHeading;
        final DocumentImage? image = collector.add(
          entryName: entry,
          bytes: zip.readBytes(entry),
          fileName: fileName,
          sectionIndex: 0,
          caption: caption.isEmpty ? null : caption,
          context: context,
        );
        if (image != null) {
          builder.addImage(image);
        }
      }
      if (text.isNotEmpty) previousText = text;
    }
    return builder.build();
  }

  /// Ссылки изображений в абзаце (`draw:image xlink:href`).
  List<String> _imageHrefs(XmlElement paragraph) {
    final List<String> hrefs = <String>[];
    for (final XmlElement element in paragraph.descendantElements) {
      if (element.name.local != 'image') continue;
      final String? href = attributeValueByPrefix(element, 'href', 'xlink');
      if (href != null && !hrefs.contains(href)) hrefs.add(href);
    }
    return hrefs;
  }

  /// Подпись рисунка в пределах следующих двух абзацев.
  String? _followingCaption(List<XmlElement> paragraphs, int index) {
    for (
      var next = index + 1;
      next < paragraphs.length && next <= index + 2;
      next++
    ) {
      final String text = collapseWhitespace(paragraphs[next].innerText);
      if (looksLikeImageCaption(text)) return text;
    }
    return null;
  }

  /// Лежит ли [element] внутри служебного поддерева (оглавление/примечание).
  bool _insideServiceElement(XmlElement element) {
    for (final XmlElement ancestor in element.ancestorElements) {
      if (_serviceElements.contains(ancestor.name.local)) {
        return true;
      }
    }
    return false;
  }
}
