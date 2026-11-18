import 'dart:isolate';
import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/api/parsers/odt_parser.dart';
import 'package:cardflow/api/parsers/pdf_parser.dart';
import 'package:cardflow/api/parsers/pdf_scan_pages.dart';
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
    this.pdfScanPages = const PdfScanPageExtractor(),
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

  /// Разбор скана: страницы + визуальные области (итерация L76).
  final PdfScanPageExtractor pdfScanPages;

  /// Запуск парсинга в изоляте; `null` — использовать `Isolate.run`.
  final IsolateRunner? isolateRunner;

  /// Максимальный размер файла в байтах (SPEC A8.3: 25 МБ).
  final int maxFileBytes;

  /// Разбирает скан: рендер страниц + значимые визуальные области (ADR-037).
  ///
  /// Каждая страница получает полный рендер (контекст для vision-модели), а
  /// найденные схемы/графики — отдельные `DocumentImage` (`croppedRegion`) с
  /// номером страницы. Все ошибки PDFium → `ParserException(scannedPdf)`.
  Future<PdfScanDocument> extractScanPages(
    Uint8List bytes, {
    required String fileName,
    int? maxPages,
  }) async {
    try {
      return await _runInIsolate(
        () =>
            pdfScanPages.extract(bytes, fileName: fileName, maxPages: maxPages),
      );
    } on ParserException {
      rethrow;
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.scannedPdf,
        details: 'Не удалось разобрать страницы PDF: $error',
      );
    }
  }

  /// Разбирает один файл.
  ///
  /// Никогда не бросает исключение: любые ошибки файла превращаются в
  /// [ParsedFileFailure] с кодом из [ParserErrorCode].
  Future<ParsingOutcome> parseFile(FileParsingInput input) async {
    final String fileName = input.fileName;
    try {
      final DocumentFormat? format = documentFormatFromFileName(fileName);
      if (format == null || !format.isSupportedForParsing) {
        return ParsedFileFailure(
          fileName: fileName,
          code: ParserErrorCode.unsupportedFormat,
        );
      }
      if (input.bytes.length > maxFileBytes) {
        return ParsedFileFailure(
          fileName: fileName,
          code: ParserErrorCode.fileTooLarge,
        );
      }
      verifyDocumentSignature(format, input.bytes);
      final DocumentParser? parser = _parserFor(format);
      if (parser == null) {
        return ParsedFileFailure(
          fileName: fileName,
          code: ParserErrorCode.unsupportedFormat,
        );
      }
      final Uint8List bytes = input.bytes;
      final ParsedDocument document = await _runInIsolate(
        () => parser.parse(bytes, fileName: fileName),
      );
      return ParsedFileSuccess(document);
    } on ParserException catch (error) {
      return ParsedFileFailure(fileName: fileName, code: error.code);
    } on Object {
      return ParsedFileFailure(
        fileName: fileName,
        code: ParserErrorCode.unreadableFile,
      );
    }
  }

  /// Разбирает файлы по порядку; ошибка одного файла не прерывает остальные.
  Future<List<ParsingOutcome>> parseAll(List<FileParsingInput> files) async {
    final List<ParsingOutcome> outcomes = <ParsingOutcome>[];
    for (final FileParsingInput file in files) {
      outcomes.add(await parseFile(file));
    }
    return outcomes;
  }

  DocumentParser? _parserFor(DocumentFormat format) {
    for (final DocumentParser parser in _parsers) {
      if (parser.format == format) {
        return parser;
      }
    }
    return null;
  }

  Future<T> _runInIsolate<T>(Future<T> Function() task) {
    final IsolateRunner runner = isolateRunner ?? _isolateRunner;
    return runner(task);
  }
}

/// Production-запуск парсинга в отдельном изоляте (`Isolate.run`).
Future<T> _isolateRunner<T>(Future<T> Function() task) => Isolate.run(task);
