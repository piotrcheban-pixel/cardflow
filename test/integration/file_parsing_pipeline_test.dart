import 'dart:typed_data';

import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../unit/api/parsers/fixtures/document_fixtures.dart';

/// Интеграционный срез итерации 3a: производственная проводка парсинга файлов.
///
/// `FileParsingService` по умолчанию (все парсеры A8.3 + реальный `Isolate.run`):
/// байты файла → изолят → парсер → `ParsedDocument` → нормализованный текст.
/// Ошибка одного файла не блокирует остальные (SPEC A8.3).
void main() {
  setUpAll(() async {
    await pdfrxInitialize();
  });

  test('production-сервис разбирает все форматы и изолирует ошибки', () async {
    final FileParsingService service = FileParsingService();

    final List<ParsingOutcome> outcomes = await service.parseAll(
      <FileParsingInput>[
        FileParsingInput(
          fileName: 'лекция.docx',
          bytes: buildDocxFromParagraphs(<String>['Вопрос', 'Ответ']),
        ),
        FileParsingInput(
          fileName: 'таблица.xlsx',
          bytes: buildXlsx(<String, String>{
            'Лист1': xlsxRow(1, <String>[xlsxTextCell('A1', 'Значение')]),
          }),
        ),
        FileParsingInput(
          fileName: 'слайды.pptx',
          bytes: buildPptx(
            slideTexts: <List<String>>[
              <String>['Слайд с текстом'],
            ],
          ),
        ),
        FileParsingInput(
          fileName: 'конспект.odt',
          bytes: buildOdt(
            blocks: <({String text, bool heading})>[
              (text: 'Раздел', heading: true),
              (text: 'Текст', heading: false),
            ],
          ),
        ),
        FileParsingInput(
          fileName: 'заметки.md',
          bytes: utf8Bytes('# Тема\n\nТекст'),
        ),
        FileParsingInput(
          fileName: 'заметка.rtf',
          bytes: buildRtf(rtfEscapedCp1251('Простой текст')),
        ),
        FileParsingInput(
          fileName: 'материалы.pdf',
          bytes: buildPdf('Hello CardFlow PDF'),
        ),
        FileParsingInput(
          fileName: 'старый.doc',
          bytes: Uint8List.fromList(<int>[
            0xD0,
            0xCF,
            0x11,
            0xE0,
            0xA1,
            0xB1,
            0x1A,
            0xE1,
          ]),
        ),
        FileParsingInput(fileName: 'битый.docx', bytes: utf8Bytes('не zip')),
      ],
    );

    expect(outcomes, hasLength(9));

    final List<ParsedDocument> documents = outcomes
        .whereType<ParsedFileSuccess>()
        .map((ParsedFileSuccess success) => success.document)
        .toList();
    expect(
      documents,
      hasLength(7),
      reason: '7 поддерживаемых форматов разобраны',
    );

    expect(
      documents.map((ParsedDocument d) => d.format).toSet(),
      <DocumentFormat>{
        DocumentFormat.docx,
        DocumentFormat.xlsx,
        DocumentFormat.pptx,
        DocumentFormat.odt,
        DocumentFormat.md,
        DocumentFormat.rtf,
        DocumentFormat.pdf,
      },
      reason: 'Каждый поддерживаемый формат разобран своим парсером',
    );

    final Map<DocumentFormat, String> texts = <DocumentFormat, String>{
      for (final ParsedDocument document in documents)
        document.format: document.text,
    };
    expect(texts[DocumentFormat.docx], 'Вопрос\nОтвет');
    expect(texts[DocumentFormat.xlsx], 'Значение');
    expect(texts[DocumentFormat.pptx], 'Слайд с текстом');
    expect(texts[DocumentFormat.odt], 'Раздел\nТекст');
    expect(texts[DocumentFormat.md], '# Тема\n\nТекст');
    expect(texts[DocumentFormat.rtf], 'Простой текст');
    expect(texts[DocumentFormat.pdf], 'Hello CardFlow PDF');

    final List<ParsedFileFailure> failures = outcomes
        .whereType<ParsedFileFailure>()
        .toList();
    expect(failures, hasLength(2));
    expect(
      failures.map((ParsedFileFailure f) => f.code).toList(),
      <ParserErrorCode>[
        // TASK 04: `.doc` — отдельный код с советом «Сохраните как .docx»
        // (ADR-049), а не общее «формат не поддерживается».
        ParserErrorCode.docFormatNotSupported,
        ParserErrorCode.unreadableFile,
      ],
      reason: 'Ошибки по файлам, остальные файлы разобраны',
    );
    expect(failures.first.fileName, 'старый.doc');
    expect(failures.last.fileName, 'битый.docx');
  });

  test('форма-фикстуры непустые и проходят сигнатуры', () {
    expect(buildDocxFromParagraphs(<String>['a']).length, greaterThan(0));
    expect(buildXlsx(<String, String>{'Лист1': ''}).length, greaterThan(0));
    expect(buildPdf('x').length, greaterThan(0));
    expect(buildRtf('x').length, greaterThan(0));
  });

  test('код ParserException сохраняется при выбросе внутри реального изолята', () async {
    final FileParsingService service = FileParsingService();
    final List<ParsingOutcome>
    outcomes = await service.parseAll(<FileParsingInput>[
      // ZIP-сигнатура валидна, но это не DOCX: ParserException(unreadableFile)
      // бросается парсером уже внутри Isolate.run.
      FileParsingInput(
        fileName: 'не-docx.docx',
        bytes: zipFixture(<String, String>{'x.txt': 'y'}),
      ),
      // Скан без текстового слоя: ParserException(scannedPdf) из изолята.
      FileParsingInput(fileName: 'скан.pdf', bytes: buildPdfWithoutText()),
    ]);
    expect(
      (outcomes[0] as ParsedFileFailure).code,
      ParserErrorCode.unreadableFile,
    );
    expect(
      (outcomes[1] as ParsedFileFailure).code,
      ParserErrorCode.scannedPdf,
      reason: 'Код ошибки из изолята не должен превращаться в unreadableFile',
    );
  });
}
