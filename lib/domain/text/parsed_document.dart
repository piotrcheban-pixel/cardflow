import 'package:cardflow/domain/text/document_format.dart';

/// Нормализованный документ, полученный нативным парсером (SPEC A8.3).
///
/// [text] — канонический текст: переводы строк унифицированы, управляющие
/// символы удалены, хвостовые пробелы и лишние пустые строки убраны
/// (`normalizeDocumentText`). Границы разделов (A8.5) заданы смещениями
/// `start`/`end` в [text] и используются чанкингом генерации.
class ParsedDocument {
  /// Создаёт документ и проверяет инварианты.
  ParsedDocument({
    required this.format,
    required this.fileName,
    required this.text,
    required this.sections,
    this.metadata = const ParsedDocumentMetadata(),
  });

  /// Формат источника.
  final DocumentFormat format;

  /// Имя исходного файла (для `source_file` карточек и UI).
  final String fileName;

  /// Нормализованный текст документа.
  final String text;

  /// Разделы документа в порядке следования; непустые и не пересекаются.
  final List<ParsedSection> sections;

  /// Метаданные формата (страницы/слайды/листы/кодировка).
  final ParsedDocumentMetadata metadata;
}

/// Границы раздела внутри [ParsedDocument.text].
class ParsedSection {
  /// Создаёт границы раздела.
  const ParsedSection({required this.start, required this.end, this.title});

  /// Смещение начала раздела в тексте (включительно).
  final int start;

  /// Смещение конца раздела в тексте (исключительно).
  final int end;

  /// Заголовок раздела, если он выводится из документа.
  final String? title;
}

/// Метаданные документа, зависящие от формата.
class ParsedDocumentMetadata {
  /// Создаёт метаданные; все поля опциональны.
  const ParsedDocumentMetadata({
    this.pageCount,
    this.slideCount,
    this.sheetNames,
    this.encoding,
  });

  /// Количество страниц (PDF).
  final int? pageCount;

  /// Количество слайдов (PPTX).
  final int? slideCount;

  /// Имена листов (XLSX), в порядке файла.
  final List<String>? sheetNames;

  /// Определённая кодировка текста (TXT/MD): `utf-8`, `utf-8-bom`, ...
  final String? encoding;
}
