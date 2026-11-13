import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/api/parsers/odt_parser.dart';
import 'package:cardflow/api/parsers/pdf_parser.dart';
import 'package:cardflow/api/parsers/pptx_parser.dart';
import 'package:cardflow/api/parsers/rtf_parser.dart';
import 'package:cardflow/api/parsers/txt_parser.dart';
import 'package:cardflow/api/parsers/xlsx_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';

/// Функция запуска парсинга в отдельном изоляте.
///
/// Инжектится в [FileParsingService], чтобы unit-тесты могли проверять факт
/// вызова без реального изолята; production-значение — `Isolate.run`.
typedef IsolateRunner = Future<T> Function<T>(Future<T> Function() task);

/// Входные данные для парсинга: имя файла и его байты.
class FileParsingInput {
  /// Создаёт вход парсинга.
  const FileParsingInput({required this.fileName, required this.bytes});

  /// Имя файла (для `source_file` и определения формата).
  final String fileName;

  /// Содержимое файла.
  final Uint8List bytes;
}

/// Результат парсинга одного файла (успех или ошибка по файлу, SPEC A8.3).
sealed class ParsingOutcome {
  const ParsingOutcome();
}

/// Файл успешно разобран.
final class ParsedFileSuccess extends ParsingOutcome {
  /// Создаёт успешный результат.
  const ParsedFileSuccess(this.document);

  /// Разобранный документ.
  final ParsedDocument document;
}

/// Файл не разобран; [code] маппится в строку ARB.
final class ParsedFileFailure extends ParsingOutcome {
  /// Создаёт ошибочный результат.
  const ParsedFileFailure({required this.fileName, required this.code});

  /// Имя файла, который не удалось разобрать.
  final String fileName;

  /// Код ошибки парсинга.
  final ParserErrorCode code;
}

/// Сервис нативного парсинга набора файлов (SPEC A8.3, A8.5 шаг 3).
///
/// Проверяет лимит размера, определяет формат, выбирает парсер и выполняет
/// разбор в отдельном изоляте. Ошибка одного файла не блокирует остальные:
/// `parseAll` возвращает результат по каждому файлу в порядке входа.
class FileParsingService {
  /// Создаёт сервис.
  ///
  /// [parsers] — реестр парсеров (по умолчанию все форматы A8.3);
  /// [isolateRunner] — запуск в изоляте (по умолчанию `Isolate.run`);
  /// [maxFileBytes] — лимит размера файла (SPEC A8.3: 25 МБ).
  FileParsingService({
    List<DocumentParser>? parsers,
    this.isolateRunner,
    this.maxFileBytes = 25 * 1024 * 1024,
  }) : _parsers = parsers ?? _defaultParsers;

  /// Парсеры по умолчанию: все поддерживаемые форматы A8.3.
  static const List<DocumentParser> _defaultParsers = <DocumentParser>[
    DocxParser(),
    PptxParser(),
    OdtParser(),
    XlsxParser(),
    TxtParser(),
    TxtParser(format: DocumentFormat.md),
    RtfParser(),
    PdfParser(),
  ];

  final List<DocumentParser> _parsers;

  /// Запуск парсинга в изоляте; `null` — использовать `Isolate.run`.
  final IsolateRunner? isolateRunner;

  /// Максимальный размер файла в байтах (SPEC A8.3: 25 МБ).
  final int maxFileBytes;

  /// Разбирает один файл.
  Future<ParsingOutcome> parseFile(FileParsingInput input) {
    throw UnimplementedError(
      'FileParsingService.parseFile (parsers=${_parsers.length}, '
      'isolate=${isolateRunner != null})',
    );
  }

  /// Разбирает файлы по порядку; ошибка одного файла не прерывает остальные.
  Future<List<ParsingOutcome>> parseAll(List<FileParsingInput> files) {
    throw UnimplementedError('FileParsingService.parseAll');
  }
}
