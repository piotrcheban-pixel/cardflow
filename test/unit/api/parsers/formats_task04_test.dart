import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/api/parsers/parser_diagnostics.dart';
import 'package:cardflow/api/parsers/pptx_parser.dart';
import 'package:cardflow/api/parsers/txt_parser.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';

import 'fixtures/document_fixtures.dart';

/// TASK 04, часть 3: поддерживаемые форматы читаются целиком.
///
/// Проверяется кириллица (включая «ё»), таблицы, изображения, кодировки и
/// различение старых бинарных форматов. `.doc`/`.ppt` намеренно не парсятся —
/// в Dart нет надёжного CFB-парсера (ADR-049).
void main() {
  test('DOCX: кириллица, таблица и изображение извлекаются вместе', () async {
    final Uint8List bytes = buildDocxWithImage(
      paragraphs: <String>['Съёшь ещё этих мягких булок', 'Теория упругости'],
      imageBytes: pngFixture(),
      caption: 'Рис. 1. Схема нагружения',
    );
    final Uint8List withTable = zipFixtureBytes(<String, List<int>>{
      'word/document.xml': utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:body>'
        '${docxParagraph('До таблицы')}'
        '${docxTable(<List<String>>[
          <String>['Столица', 'Москва'],
          <String>['Река', 'Волга'],
        ])}'
        '</w:body></w:document>',
      ),
    });

    final ParsedDocument simple = await const DocxParser().parse(
      bytes,
      fileName: 'упругость.docx',
    );
    expect(simple.text, contains('Съёшь ещё этих мягких булок'));
    expect(simple.text, contains('ё'));
    expect(simple.images, hasLength(1));
    final DocumentImage image = simple.images.single;
    expect(image.caption, contains('Рис. 1'));
    expect(image.width, greaterThan(0));

    final ParsedDocument table = await const DocxParser().parse(
      withTable,
      fileName: 'таблица.docx',
    );
    expect(table.text, contains('До таблицы'));
    expect(table.text, contains('Столица\tМосква'));
    expect(table.text, contains('Река\tВолга'));
  });

  test('PPTX: кириллические слайды и картинка слайда', () async {
    final Uint8List bytes = buildPptxWithImage(
      slideTexts: <List<String>>[
        <String>['Фермы и арки', 'Стержни, узлы и опоры'],
        <String>['Вывод: «жёсткость» рамы'],
      ],
      imageBytes: pngFixture(seed: 5),
    );
    final ParsedDocument document = await const PptxParser().parse(
      bytes,
      fileName: 'фермы.pptx',
    );

    expect(document.metadata.slideCount, 2);
    expect(document.sections, hasLength(2));
    expect(document.text, contains('Фермы и арки'));
    expect(document.text, contains('«жёсткость»'));
    expect(document.images, hasLength(1));
    expect(document.images.single.page, 1);
  });

  test('TXT/MD: кириллица в UTF-8 и Windows-1251', () async {
    final ParsedDocument utf8Doc = await const TxtParser().parse(
      Uint8List.fromList(utf8.encode('Привет, ёжик!')),
      fileName: 'заметки.txt',
    );
    expect(utf8Doc.text, 'Привет, ёжик!');
    expect(utf8Doc.metadata.encoding, contains('utf-8'));

    final Uint8List cp1251 = Uint8List.fromList(<int>[
      0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, // Привет
      0x2C,
      0x20,
      0xEC, 0xE8, 0xF0, // мир
    ]);
    final ParsedDocument legacy = await const TxtParser().parse(
      cp1251,
      fileName: 'старое.txt',
    );
    expect(legacy.text, 'Привет, мир');
    expect(legacy.metadata.encoding, contains('1251'));

    final ParsedDocument md = await const TxtParser(format: DocumentFormat.md)
        .parse(
          Uint8List.fromList(utf8.encode('# Заголовок\n\n- пункт «ё»')),
          fileName: 'план.md',
        );
    expect(md.text, contains('# Заголовок'));
    expect(md.text, contains('«ё»'));
  });

  test(
    'диагностика импорта пишет файл/формат/парсер и не включает текст',
    () async {
      final List<String> lines = <String>[];
      final FileParsingService service = FileParsingService(
        isolateRunner: <T>(Future<T> Function() task) => task(),
        diagnostics: ParserDiagnostics(sink: lines.add),
      );
      final ParsingOutcome ok = await service.parseFile(
        FileParsingInput(
          fileName: 'лекция.txt',
          bytes: Uint8List.fromList(utf8.encode('Секретный текст лекции')),
        ),
      );
      final ParsingOutcome bad = await service.parseFile(
        FileParsingInput(
          fileName: 'старый.ppt',
          bytes: Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0]),
        ),
      );

      expect(ok, isA<ParsedFileSuccess>());
      expect(bad, isA<ParsedFileFailure>());
      expect(
        (bad as ParsedFileFailure).code,
        ParserErrorCode.pptFormatNotSupported,
      );
      final String log = lines.join('\n');
      expect(log, contains('"лекция.txt"'));
      expect(log, contains('формат=txt'));
      expect(log, contains('парсер=TxtParser'));
      expect(log, contains('символов=22'));
      expect(
        log,
        isNot(contains('Секретный текст лекции')),
        reason: 'содержимое документа в диагностику не попадает',
      );
      expect(log, contains('ppt'));
      expect(log, contains('pptFormatNotSupported'));
    },
  );

  test('диагностика в release-режиме — no-op', () {
    final List<String> lines = <String>[];
    const ParserDiagnostics disabled = ParserDiagnostics(enabled: false);
    disabled.picked(fileName: 'lecture.pdf', source: 'file');
    disabled.parsed(
      fileName: 'lecture.pdf',
      format: DocumentFormat.pdf,
      pages: 10,
      sections: 3,
      characters: 1000,
      images: 2,
    );
    expect(lines, isEmpty);
  });
}
