import 'dart:typed_data';

import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/document_fixtures.dart';

/// Красная фаза итерации 3a: DOCX → нормализованный текст (SPEC A8.3).
void main() {
  const DocxParser parser = DocxParser();

  Future<ParsedDocument> parse(Uint8List bytes) =>
      parser.parse(bytes, fileName: 'лекция.docx');

  test('формат парсера — docx', () {
    expect(parser.format, DocumentFormat.docx);
  });

  test('абзацы → строки; runs одного абзаца склеиваются', () async {
    final ParsedDocument document = await parse(
      buildDocx(
        bodyXml:
            docxParagraphRuns(<String>['Первый ', 'абзац']) +
            docxParagraph('Второй абзац'),
      ),
    );

    expect(document.text, 'Первый абзац\nВторой абзац');
    expect(document.format, DocumentFormat.docx);
    expect(document.fileName, 'лекция.docx');
    expect(document.sections, hasLength(1));
    expect(
      document.text.substring(
        document.sections.single.start,
        document.sections.single.end,
      ),
      document.text,
    );
  });

  test('таблица → строки через табуляцию', () async {
    final ParsedDocument document = await parse(
      buildDocx(
        bodyXml:
            docxParagraph('До таблицы') +
            docxTable(<List<String>>[
              <String>['Столица', 'Москва'],
              <String>['Река', 'Волга'],
            ]),
      ),
    );

    expect(document.text, 'До таблицы\nСтолица\tМосква\nРека\tВолга');
  });

  test(
    'заголовки открывают разделы; текст до заголовка — раздел без title',
    () async {
      final ParsedDocument document = await parse(
        buildDocx(
          bodyXml:
              docxParagraph('Вступление без заголовка') +
              docxParagraph('Глава 1', style: 'Heading1') +
              docxParagraph('Текст главы') +
              docxParagraph('Глава 2', style: 'Heading1') +
              docxParagraph('Ещё текст'),
        ),
      );

      expect(document.sections, hasLength(3));
      expect(document.sections[0].title, isNull);
      expect(document.sections[1].title, 'Глава 1');
      expect(document.sections[2].title, 'Глава 2');
      expect(
        document.text.substring(
          document.sections[1].start,
          document.sections[1].end,
        ),
        'Глава 1\nТекст главы',
      );
      expect(
        document.text.substring(
          document.sections[2].start,
          document.sections[2].end,
        ),
        'Глава 2\nЕщё текст',
      );
    },
  );

  test('w:tab и w:br внутри абзаца дают табуляцию и перевод строки', () async {
    final ParsedDocument document = await parse(
      buildDocx(
        bodyXml:
            '<w:p><w:r><w:t>Метка</w:t><w:tab/><w:t>значение</w:t></w:r></w:p>'
            '<w:p><w:r><w:t>Строка</w:t><w:br/><w:t>продолжение</w:t></w:r></w:p>',
      ),
    );

    expect(document.text, 'Метка\tзначение\nСтрока\nпродолжение');
  });

  test('пустой документ (нет текста) → ParserException(emptyText)', () async {
    await expectLater(
      parse(buildDocx(bodyXml: docxParagraph(''))),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.emptyText,
        ),
      ),
    );
  });

  test('битый ZIP → ParserException(unreadableFile)', () async {
    await expectLater(
      parse(Uint8List.fromList(<int>[0x50, 0x4B, 3, 4, 0, 1, 2])),
      throwsA(
        isA<ParserException>().having(
          (ParserException e) => e.code,
          'code',
          ParserErrorCode.unreadableFile,
        ),
      ),
    );
  });

  test('таб-стопы в w:pPr не попадают в текст абзаца', () async {
    final ParsedDocument document = await parse(
      buildDocx(
        bodyXml:
            docxParagraph('Первый') +
            docxParagraphWithTabStops('Второй с табстопом'),
      ),
    );
    expect(document.text, 'Первый\nВторой с табстопом');
  });

  test('текст в w:sdt (content control) и w:customXml не теряется', () async {
    final ParsedDocument document = await parse(
      buildDocx(
        bodyXml:
            docxParagraph('Первый') +
            docxSdt(<String>['Внутри sdt']) +
            docxCustomXml(<String>['Внутри customXml']) +
            docxParagraph('Последний'),
      ),
    );
    expect(document.text, 'Первый\nВнутри sdt\nВнутри customXml\nПоследний');
  });
}
