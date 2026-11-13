import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:xml/xml.dart';

/// Лимиты безопасного разбора ZIP-контейнеров (DOCX/PPTX/ODT/XLSX).
///
/// Защищают от zip-bomb и «архивов из миллионов пустых записей»: входной файл
/// уже ограничен 25 МБ (SPEC A8.3), но распакованный объём может быть больше.
class SecureZipLimits {
  /// Создаёт лимиты (по умолчанию — значения из ADR-010).
  const SecureZipLimits({
    this.maxEntries = 10000,
    this.maxEntryBytes = 32 * 1024 * 1024,
    this.maxTotalBytes = 120 * 1024 * 1024,
  });

  /// Максимальное количество записей в архиве.
  final int maxEntries;

  /// Максимальный размер одной записи после распаковки, байт.
  final int maxEntryBytes;

  /// Максимальный суммарный размер распакованных записей, байт.
  final int maxTotalBytes;
}

/// Безопасное чтение ZIP-контейнера документа (DOCX/PPTX/ODT/XLSX).
///
/// Любое нарушение структуры или лимитов — [ParserException] с кодом
/// [ParserErrorCode.unreadableFile]: файл повреждён/не является документом.
class SecureZip {
  /// Разбирает архив [bytes] с ограничениями [limits].
  ///
  /// Бросает [ParserException] ([ParserErrorCode.unreadableFile]), если архив
  /// повреждён или превышает лимиты.
  SecureZip(List<int> bytes, {SecureZipLimits limits = const SecureZipLimits()})
    : _limits = limits {
    arc.Archive archive;
    try {
      archive = arc.ZipDecoder().decodeBytes(
        bytes,
        verify: true,
        throwOnError: true,
      );
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Не удалось разобрать ZIP: $error',
      );
    }
    if (archive.files.length > limits.maxEntries) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Слишком много записей в архиве: ${archive.files.length}',
      );
    }
    int totalBytes = 0;
    final Map<String, arc.ArchiveFile> files = <String, arc.ArchiveFile>{};
    for (final arc.ArchiveFile file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final int size = file.size;
      if (size > limits.maxEntryBytes) {
        throw ParserException(
          ParserErrorCode.unreadableFile,
          details: 'Запись «${file.name}» слишком большая: $size байт',
        );
      }
      totalBytes += size;
      if (totalBytes > limits.maxTotalBytes) {
        throw ParserException(
          ParserErrorCode.unreadableFile,
          details: 'Распакованный объём архива превышает лимит',
        );
      }
      files[file.name] = file;
    }
    _files = files;
  }

  final SecureZipLimits _limits;
  late final Map<String, arc.ArchiveFile> _files;

  /// Имена записей архива в порядке следования.
  List<String> get entryNames => List<String>.unmodifiable(_files.keys);

  /// Есть ли в архиве запись с именем [name].
  bool contains(String name) => _files.containsKey(name);

  /// Читает запись [name] как XML-документ.
  ///
  /// Бросает [ParserException] ([ParserErrorCode.unreadableFile]), если записи
  /// нет или XML некорректен.
  XmlDocument readXml(String name) {
    final String text = readUtf8(name);
    try {
      return XmlDocument.parse(text);
    } on XmlException catch (error) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Некорректный XML в записи «$name»: ${error.message}',
      );
    }
  }

  /// Читает запись [name] как UTF-8 (с поддержкой BOM/UTF-16) текст.
  String readUtf8(String name) => decodeXmlText(readBytes(name));

  /// Читает запись [name] как байты.
  ///
  /// Бросает [ParserException] ([ParserErrorCode.unreadableFile]), если записи
  /// нет.
  Uint8List readBytes(String name) {
    final arc.ArchiveFile? file = _files[name];
    if (file == null) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'В архиве нет обязательной записи «$name»',
      );
    }
    final List<int> content = file.content;
    final Uint8List bytes = Uint8List.fromList(content);
    if (bytes.length > _limits.maxEntryBytes) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Запись «$name» после распаковки больше лимита',
      );
    }
    return bytes;
  }
}

/// Декодирует байты XML-записи: учитывает BOM UTF-8/UTF-16, иначе строгий UTF-8.
///
/// Отдельная функция — чтобы правило было одинаковым для всех OOXML/ODF-парсеров.
String decodeXmlText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return _decodeUtf8(bytes.sublist(3), 'UTF-8 BOM');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  return _decodeUtf8(bytes, 'XML');
}

String _decodeUtf8(List<int> bytes, String source) {
  try {
    return utf8.decode(bytes);
  } on FormatException catch (error) {
    throw ParserException(
      ParserErrorCode.unreadableFile,
      details: 'Некорректная кодировка $source: ${error.message}',
    );
  }
}

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  if (bytes.length.isOdd) {
    throw const ParserException(
      ParserErrorCode.unreadableFile,
      details: 'Нечётная длина UTF-16 XML',
    );
  }
  final List<int> codeUnits = <int>[];
  for (int i = 0; i < bytes.length; i += 2) {
    final int first = bytes[i];
    final int second = bytes[i + 1];
    codeUnits.add(littleEndian ? (second << 8) | first : (first << 8) | second);
  }
  return String.fromCharCodes(codeUnits);
}

