import 'dart:isolate';
import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/api/parsers/odt_parser.dart';
import 'package:cardflow/api/parsers/parser_diagnostics.dart';
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

/// Поставщик каталога временных файлов приложения (main-изолят).
///
/// Production — `path_provider` → `getTemporaryDirectory()`; в тестах —
/// фиксированная строка. Вызывается **до** `Isolate.run`: платформенный канал
/// в фоновом изоляте недоступен, а PDFium нужен явный каталог кэша
/// (`PdfiumBootstrap`, TASK 04).
typedef PdfCacheDirectoryProvider = Future<String?> Function();

/// Входные данные для парсинга: имя файла и его байты.
class FileParsingInput {
  /// Создаёт вход парсинга.
  const FileParsingInput({
    required this.fileName,
    required this.bytes,
    this.mimeType,
  });

  /// Имя файла (для `source_file` и определения формата).
  final String fileName;

  /// Содержимое файла.
  final Uint8List bytes;

  /// MIME-тип от провайдера/платформы (только для диагностики).
  final String? mimeType;
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
  /// [maxFileBytes] — лимит размера файла (SPEC A8.3: 25 МБ);
  /// [pdfCacheDirectory] — каталог кэша PDFium из main-изолята (TASK 04);
  /// [diagnostics] — debug-диагностика импорта (TASK 04, часть 8).
  FileParsingService({
    List<DocumentParser>? parsers,
    this.isolateRunner,
    this.maxFileBytes = 25 * 1024 * 1024,
    this.pdfScanPages = const PdfScanPageExtractor(),
    this.pdfCacheDirectory,
    this.diagnostics = const ParserDiagnostics(),
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

  /// Каталог кэша PDFium, полученный в main-изоляте (`path_provider`).
  ///
  /// `null` — PDFium использует `Directory.systemTemp` (никогда не `HOME`:
  /// на Android переменная не задана, из-за чего PDF не читался вообще,
  /// TASK 04).
  final PdfCacheDirectoryProvider? pdfCacheDirectory;

  /// Debug-диагностика импорта: имя, формат, парсер, страницы, изображения.
  final ParserDiagnostics diagnostics;

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
    final String? cacheDirectory = await _pdfCacheDirectory();
    try {
      return await _runInIsolate(
        () => pdfScanPages.extract(
          bytes,
          fileName: fileName,
          maxPages: maxPages,
          cacheDirectory: cacheDirectory,
        ),
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
    DocumentFormat? format;
    try {
      format = documentFormatFromFileName(fileName);
      if (format == null) {
        diagnostics.failed(
          fileName: fileName,
          format: null,
          code: ParserErrorCode.unsupportedFormat.name,
          details: 'расширение файла не входит в набор A8.3',
        );
        return ParsedFileFailure(
          fileName: fileName,
          code: ParserErrorCode.unsupportedFormat,
        );
      }
      if (!format.isSupportedForParsing) {
        // Старые бинарные форматы: понятный следующий шаг вместо общего
        // «формат не поддерживается» (TASK 04, часть 3, ADR-049).
        final ParserErrorCode code = switch (format) {
          DocumentFormat.doc => ParserErrorCode.docFormatNotSupported,
          DocumentFormat.ppt => ParserErrorCode.pptFormatNotSupported,
          _ => ParserErrorCode.unsupportedFormat,
        };
        diagnostics.failed(
          fileName: fileName,
          format: format,
          code: code.name,
          details: 'CFB-парсера нет, формат только для сообщения пользователю',
        );
        return ParsedFileFailure(fileName: fileName, code: code);
      }
      if (input.bytes.length > maxFileBytes) {
        diagnostics.failed(
          fileName: fileName,
          format: format,
          code: ParserErrorCode.fileTooLarge.name,
          details: '${input.bytes.length} Б > $maxFileBytes Б',
        );
        return ParsedFileFailure(
          fileName: fileName,
          code: ParserErrorCode.fileTooLarge,
        );
      }
      verifyDocumentSignature(format, input.bytes);
      final String? cacheDirectory = format == DocumentFormat.pdf
          ? await _pdfCacheDirectory()
          : null;
      final DocumentParser? parser = _parserFor(
        format,
        pdfCacheDirectory: cacheDirectory,
      );
      if (parser == null) {
        diagnostics.failed(
          fileName: fileName,
          format: format,
          code: ParserErrorCode.unsupportedFormat.name,
          details: 'парсер формата не зарегистрирован',
        );
        return ParsedFileFailure(
          fileName: fileName,
          code: ParserErrorCode.unsupportedFormat,
        );
      }
      diagnostics.dispatched(
        fileName: fileName,
        format: format,
        parser: parser.runtimeType.toString(),
        bytes: input.bytes.length,
        cacheDirectory: cacheDirectory,
      );
      final Uint8List bytes = input.bytes;
      final ParsedDocument document = await _runInIsolate(
        () => parser.parse(bytes, fileName: fileName),
      );
      diagnostics.parsed(
        fileName: fileName,
        format: format,
        pages: document.metadata.pageCount ?? 0,
        sections: document.sections.length,
        characters: document.text.length,
        images: document.images.length,
      );
      return ParsedFileSuccess(document);
    } on ParserException catch (error) {
      diagnostics.failed(
        fileName: fileName,
        format: format,
        code: error.code.name,
        details: error.details,
      );
      return ParsedFileFailure(fileName: fileName, code: error.code);
    } on Object catch (error) {
      diagnostics.failed(
        fileName: fileName,
        format: format,
        code: ParserErrorCode.unreadableFile.name,
        details: '${error.runtimeType}',
      );
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

  /// Каталог кэша PDFium: ошибка провайдера не должна ломать PDF.
  Future<String?> _pdfCacheDirectory() async {
    final PdfCacheDirectoryProvider? provider = pdfCacheDirectory;
    if (provider == null) return null;
    try {
      return await provider();
    } on Object {
      return null;
    }
  }

  DocumentParser? _parserFor(
    DocumentFormat format, {
    String? pdfCacheDirectory,
  }) {
    for (final DocumentParser parser in _parsers) {
      if (parser.format == format) {
        // PDF-парсеры получают явный каталог кэша PDFium: статика изолята
        // своя, значение из main-изолята передаётся строкой (TASK 04).
        if (parser is PdfParser) {
          return parser.withCacheDirectory(pdfCacheDirectory);
        }
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
