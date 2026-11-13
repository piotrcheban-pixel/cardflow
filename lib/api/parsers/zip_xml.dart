import 'dart:typed_data';

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
  SecureZip(List<int> bytes, {SecureZipLimits limits = const SecureZipLimits()}) {
    throw UnimplementedError('SecureZip');
  }

  /// Имена записей архива в порядке следования.
  List<String> get entryNames => throw UnimplementedError('entryNames');

  /// Есть ли в архиве запись с именем [name].
  bool contains(String name) => throw UnimplementedError('contains');

  /// Читает запись [name] как XML-документ.
  ///
  /// Бросает [ParserException] ([ParserErrorCode.unreadableFile]), если записи
  /// нет или XML некорректен.
  XmlDocument readXml(String name) => throw UnimplementedError('readXml');

  /// Читает запись [name] как UTF-8 текст.
  String readUtf8(String name) => throw UnimplementedError('readUtf8');

  /// Читает запись [name] как байты.
  ///
  /// Бросает [ParserException] ([ParserErrorCode.unreadableFile]), если записи
  /// нет.
  Uint8List readBytes(String name) => throw UnimplementedError('readBytes');
}
