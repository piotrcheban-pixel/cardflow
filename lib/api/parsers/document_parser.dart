import 'dart:typed_data';

import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Нативный локальный парсер одного формата документов (SPEC A8.3).
///
/// Реализации — `lib/api/parsers/`, чистый Dart (кроме PDF, где используется
/// `pdfrx`). Парсер обязан вернуть непустой нормализованный `ParsedDocument`
/// или бросить `ParserException`; сырые исключения наружу не выпускаются.
abstract interface class DocumentParser {
  /// Формат, который обрабатывает парсер.
  DocumentFormat get format;

  /// Разбирает байты файла [bytes] с именем [fileName].
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName});
}
