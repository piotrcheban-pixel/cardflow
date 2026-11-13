import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/api/parsers/txt_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/document_fixtures.dart';

int _isolateRuns = 0;

/// Тестовый запуск «в изоляте»: считает вызовы и выполняет задачу на месте.
Future<T> _recordingRunner<T>(Future<T> Function() task) {
  _isolateRuns++;
  return task();
}

/// Парсер, который бросает неожиданное исключение (проверка маскировки ошибок).
class _UnexpectedFailureParser implements DocumentParser {
  const _UnexpectedFailureParser();

  @override
  DocumentFormat get format => DocumentFormat.docx;

  @override
  Future<ParsedDocument> parse(Uint8List bytes, {required String fileName}) =>
      throw StateError('сырой внутренний стек: boom');
}

FileParsingInput _input(String fileName, List<int> bytes) =>
    FileParsingInput(fileName: fileName, bytes: Uint8List.fromList(bytes));

/// Красная фаза итерации 3a: сервис парсинга файлов (SPEC A8.3).
void main() {
  setUp(() {
    _isolateRuns = 0;
  });

  group('FileParsingService.parseAll: порядок, успех и ошибки по файлам', () {
    test(
      'порядок файлов сохраняется, успехи и ошибки не блокируют друг друга',
      () async {
        final FileParsingService service = FileParsingService(
          isolateRunner: _recordingRunner,
        );

        final List<ParsingOutcome> outcomes = await service.parseAll(
          <FileParsingInput>[
            _input('первый.txt', utf8Bytes('Первый файл')),
            _input('старый.doc', <int>[0xD0, 0xCF, 0x11, 0xE0]),
            _input('второй.txt', utf8Bytes('Второй файл')),
          ],
        );

        expect(outcomes, hasLength(3));
        expect(outcomes[0], isA<ParsedFileSuccess>());
        expect((outcomes[0] as ParsedFileSuccess).document.text, 'Первый файл');
        expect(outcomes[1], isA<ParsedFileFailure>());
        expect(
          (outcomes[1] as ParsedFileFailure).code,
          ParserErrorCode.unsupportedFormat,
        );
        expect((outcomes[1] as ParsedFileFailure).fileName, 'старый.doc');
        expect(outcomes[2], isA<ParsedFileSuccess>());
        expect(_isolateRuns, 2, reason: 'Парсинг успешных файлов — в изоляте');
      },
    );

    test('пустой список файлов → пустой список результатов', () async {
      final FileParsingService service = FileParsingService(
        isolateRunner: _recordingRunner,
      );
      expect(await service.parseAll(<FileParsingInput>[]), isEmpty);
    });

    test('.xls и неизвестное расширение → unsupportedFormat', () async {
      final FileParsingService service = FileParsingService(
        isolateRunner: _recordingRunner,
      );
      final List<ParsingOutcome> outcomes = await service.parseAll(
        <FileParsingInput>[
          _input('данные.xls', <int>[1, 2, 3]),
          _input('книга.epub', <int>[1, 2, 3]),
        ],
      );
      expect(
        (outcomes[0] as ParsedFileFailure).code,
        ParserErrorCode.unsupportedFormat,
      );
      expect(
        (outcomes[1] as ParsedFileFailure).code,
        ParserErrorCode.unsupportedFormat,
      );
      expect(_isolateRuns, 0, reason: 'Неподдерживаемые файлы не парсятся');
    });
  });

  group('FileParsingService: лимиты и сигнатуры', () {
    test('файл больше лимита → fileTooLarge (до парсинга)', () async {
      final FileParsingService service = FileParsingService(
        isolateRunner: _recordingRunner,
        maxFileBytes: 4,
      );
      final ParsingOutcome outcome = await service.parseFile(
        _input('конспект.txt', utf8Bytes('Пять!')),
      );
      expect(outcome, isA<ParsedFileFailure>());
      expect((outcome as ParsedFileFailure).code, ParserErrorCode.fileTooLarge);
      expect(_isolateRuns, 0);
    });

    test('файл ровно по лимиту парсится', () async {
      final FileParsingService service = FileParsingService(
        isolateRunner: _recordingRunner,
        maxFileBytes: 5,
      );
      final ParsingOutcome outcome = await service.parseFile(
        _input('конспект.txt', utf8Bytes('12345')),
      );
      expect(outcome, isA<ParsedFileSuccess>());
      expect(_isolateRuns, 1);
    });

    test('несоответствие сигнатуры формату → unreadableFile', () async {
      final FileParsingService service = FileParsingService(
        isolateRunner: _recordingRunner,
      );
      final ParsingOutcome outcome = await service.parseFile(
        _input('документ.docx', utf8Bytes('это не zip')),
      );
      expect(
        (outcome as ParsedFileFailure).code,
        ParserErrorCode.unreadableFile,
      );
      expect(_isolateRuns, 0);
    });
  });

  group('FileParsingService: ошибки парсеров и пустой текст', () {
    test('пустой текст документа → emptyText', () async {
      final FileParsingService service = FileParsingService(
        isolateRunner: _recordingRunner,
      );
      final ParsingOutcome outcome = await service.parseFile(
        _input('пустой.txt', utf8Bytes('   ')),
      );
      expect((outcome as ParsedFileFailure).code, ParserErrorCode.emptyText);
    });

    test(
      'неожиданное исключение парсера → unreadableFile без утечки текста',
      () async {
        final FileParsingService service = FileParsingService(
          parsers: <DocumentParser>[const _UnexpectedFailureParser()],
          isolateRunner: _recordingRunner,
        );
        final ParsingOutcome outcome = await service.parseFile(
          _input('документ.docx', buildDocxFromParagraphs(<String>['Текст'])),
        );
        expect(outcome, isA<ParsedFileFailure>());
        final ParsedFileFailure failure = outcome as ParsedFileFailure;
        expect(failure.code, ParserErrorCode.unreadableFile);
        expect(failure.toString(), isNot(contains('boom')));
      },
    );

    test('успешный результат содержит документ с именем файла', () async {
      final FileParsingService service = FileParsingService(
        isolateRunner: _recordingRunner,
      );
      final ParsingOutcome outcome = await service.parseFile(
        _input('лекция.md', utf8Bytes('# Тема\n\nТекст')),
      );
      final ParsedDocument document = (outcome as ParsedFileSuccess).document;
      expect(document.format, DocumentFormat.md);
      expect(document.fileName, 'лекция.md');
      expect(document.text, '# Тема\n\nТекст');
    });
  });

  test('по умолчанию используются все парсеры форматов A8.3', () {
    final FileParsingService service = FileParsingService();
    expect(service.maxFileBytes, 25 * 1024 * 1024);
    expect(service.isolateRunner, isNull);
  });

  test('TxtParser в составе сервиса не влияет на другие форматы', () async {
    final FileParsingService service = FileParsingService(
      parsers: const <DocumentParser>[TxtParser()],
      isolateRunner: _recordingRunner,
    );
    final ParsingOutcome outcome = await service.parseFile(
      _input('заметки.md', utf8Bytes('Текст')),
    );
    expect(
      (outcome as ParsedFileFailure).code,
      ParserErrorCode.unsupportedFormat,
      reason: 'Нет парсера для md — формат не обрабатывается',
    );
  });
}
