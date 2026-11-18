import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/document_text_normalization.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';

/// Собирает [ParsedDocument] из логических разделов парсера.
///
/// Единственное место сборки текста и границ: каждый раздел нормализуется
/// `normalizeDocumentText`, пустые разделы отбрасываются, разделы разделяются
/// пустой строкой (`\n\n`). Смещения `start`/`end` считаются уже по итоговому
/// тексту, поэтому валидны для чанкинга A8.5.
class ParsedDocumentBuilder {
  /// Создаёт сборщик для формата [format] и имени файла [fileName].
  ParsedDocumentBuilder({
    required this.format,
    required this.fileName,
    this.metadata = const ParsedDocumentMetadata(),
  });

  /// Формат источника.
  final DocumentFormat format;

  /// Имя исходного файла.
  final String fileName;

  /// Метаданные формата.
  final ParsedDocumentMetadata metadata;

  final List<_SectionDraft> _drafts = <_SectionDraft>[];
  final Map<int, List<DocumentImage>> _sectionImages =
      <int, List<DocumentImage>>{};
  List<String> _lines = <String>[];
  List<DocumentImage> _images = <DocumentImage>[];
  String? _title;
  bool _hasCurrent = false;

  /// Начинает новый раздел с заголовком [title] (может быть `null`).
  void startSection({String? title}) {
    _flushCurrent();
    _hasCurrent = true;
    _title = title;
    _lines = <String>[];
    _images = <DocumentImage>[];
  }

  /// Добавляет изображение в текущий раздел (fix-gen, Д3).
  void addImage(DocumentImage image) {
    _ensureCurrent();
    _images.add(image);
  }

  /// Добавляет изображение к разделу по индексу (0-based) — для изображений
  /// страниц PDF, у которых нет собственного текстового раздела (ADR-037).
  ///
  /// Если раздела с таким индексом в итоговом документе нет, изображение
  /// отбрасывается: привязка к несуществующему разделу невозможна.
  void addImageToSection(int sectionIndex, DocumentImage image) {
    if (sectionIndex < 0) return;
    (_sectionImages[sectionIndex] ??= <DocumentImage>[]).add(image);
  }

  /// Добавляет строку в текущий раздел (раздел начнётся автоматически).
  void addLine(String line) {
    _ensureCurrent();
    _lines.add(line);
  }

  /// Добавляет строки в текущий раздел.
  void addLines(Iterable<String> lines) {
    for (final String line in lines) {
      addLine(line);
    }
  }

  /// Собирает нормализованный документ.
  ///
  /// Бросает [ParserException] с кодом [ParserErrorCode.emptyText], если после
  /// нормализации не осталось текста.
  ParsedDocument build() {
    _flushCurrent();
    final StringBuffer buffer = StringBuffer();
    final List<ParsedSection> sections = <ParsedSection>[];
    final List<DocumentImage> images = <DocumentImage>[];
    for (final _SectionDraft draft in _drafts) {
      final String sectionText = normalizeDocumentText(draft.lines.join('\n'));
      if (sectionText.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.write('\n\n');
      }
      final int start = buffer.length;
      buffer.write(sectionText);
      sections.add(
        ParsedSection(start: start, end: buffer.length, title: draft.title),
      );
      final int sectionIndex = sections.length - 1;
      for (final DocumentImage image in draft.images) {
        images.add(image.withSectionIndex(sectionIndex));
      }
      for (final DocumentImage image
          in _sectionImages[sectionIndex] ?? const <DocumentImage>[]) {
        images.add(image.withSectionIndex(sectionIndex));
      }
    }
    final String text = buffer.toString();
    if (text.isEmpty) {
      throw const ParserException(
        ParserErrorCode.emptyText,
        details: 'После извлечения и нормализации текст пуст',
      );
    }
    return ParsedDocument(
      format: format,
      fileName: fileName,
      text: text,
      sections: sections,
      metadata: metadata,
      images: images,
    );
  }

  void _ensureCurrent() {
    if (_hasCurrent) {
      return;
    }
    _hasCurrent = true;
    _title = null;
    _lines = <String>[];
    _images = <DocumentImage>[];
  }

  void _flushCurrent() {
    if (_hasCurrent && _lines.isNotEmpty) {
      _drafts.add(
        _SectionDraft(
          title: _title,
          lines: List<String>.unmodifiable(_lines),
          images: List<DocumentImage>.unmodifiable(_images),
        ),
      );
    }
    _lines = <String>[];
    _images = <DocumentImage>[];
  }
}

/// Накопленный раздел до нормализации.
class _SectionDraft {
  const _SectionDraft({
    required this.title,
    required this.lines,
    required this.images,
  });

  final String? title;
  final List<String> lines;
  final List<DocumentImage> images;
}
