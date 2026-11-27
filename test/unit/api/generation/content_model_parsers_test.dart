import 'dart:typed_data';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/api/parsers/pdf_parser.dart';
import 'package:cardflow/api/parsers/pptx_parser.dart';
import 'package:cardflow/api/parsers/txt_parser.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../parsers/fixtures/document_fixtures.dart';

/// DoD среза 1: пять фикстур — PDF, DOCX, PPTX, MD и скан без текстового слоя.
///
/// Для каждой: offsets блоков точные (`text.substring(start, end) == text`),
/// блок восстанавливается по id, раздел не рвёт абзац (блок целиком в одном
/// разделе), мусор помечен флагом, а не удалён. Скан даёт **пустую** модель без
/// исключения. Парсеры не менялись: адаптер работает на их `ParsedDocument`.
void main() {
  const ContentModelBuilder builder = ContentModelBuilder();

  /// Общие инварианты модели для любой фикстуры.
  void expectModelInvariants(Document model) {
    expect(model.blocks, isNotEmpty);
    for (final Block block in model.blocks) {
      expect(
        model.text.substring(block.start, block.end),
        block.text,
        reason: 'offsets блока ${block.id}',
      );
      expect(model.block(block.id), same(block));
      final Section section = model.section(block.sectionId)!;
      expect(
        block.start >= section.start && block.end <= section.end,
        isTrue,
        reason: 'блок ${block.id} не входит в раздел ${section.id}',
      );
    }
    // Блоки не пересекаются и идут по порядку.
    for (var index = 1; index < model.blocks.length; index++) {
      expect(model.blocks[index].start >= model.blocks[index - 1].end, isTrue);
    }
    // Разделы идут по порядку и покрывают свои блоки.
    for (var index = 1; index < model.sections.length; index++) {
      expect(
        model.sections[index].start >= model.sections[index - 1].end,
        isTrue,
      );
    }
  }

  test('PDF: страница — раздел, колонтитул и номера страниц помечены', () async {
    final Uint8List bytes = buildPdfFromFixturePages(<PdfFixturePage>[
      const PdfFixturePage(
        text: 'CardFlow header\nFirst lesson paragraph.\n12',
      ),
      const PdfFixturePage(
        text:
            'CardFlow header\nSecond lesson paragraph.\nFig. 2. Two nodes\n13',
      ),
    ]);
    final ParsedDocument parsed = await const PdfParser().parse(
      bytes,
      fileName: 'lesson.pdf',
    );
    final Document model = builder.build(parsed);

    expectModelInvariants(model);
    expect(model.sections, hasLength(2));
    expect(model.contentBlocks.map((Block block) => block.text), <String>[
      'First lesson paragraph.',
      'Second lesson paragraph.',
    ]);
    final Map<String, NoiseKind> expectedNoise = <String, NoiseKind>{
      '12': NoiseKind.pageNumber,
      '13': NoiseKind.pageNumber,
      'Fig. 2. Two nodes': NoiseKind.figureCaption,
    };
    for (final MapEntry<String, NoiseKind> entry in expectedNoise.entries) {
      final Block block = model.blocks.firstWhere(
        (Block candidate) => candidate.text == entry.key,
      );
      expect(block.noiseKind, entry.value, reason: entry.key);
    }
    // Колонтитул повторяется в двух разделах — оба вхождения помечены.
    final List<Block> headers = model.blocks
        .where((Block block) => block.text == 'CardFlow header')
        .toList();
    expect(headers, hasLength(2));
    for (final Block header in headers) {
      expect(header.noiseKind, NoiseKind.runningHeaderFooter);
    }
    expect(
      model.blocks
          .where((Block block) => block.text == 'CardFlow header')
          .map((Block block) => block.sectionId),
      <String>['doc:lesson.pdf#0', 'doc:lesson.pdf#1'],
    );
  });

  test('DOCX: разделы по заголовкам, служебные строки помечены', () async {
    final Uint8List bytes = buildDocx(
      bodyXml:
          docxParagraph('Первый раздел без заголовка') +
          docxParagraph('Колонтитул курса') +
          docxParagraph('Глава 1', style: 'Heading1') +
          docxParagraph('Первый абзац главы.') +
          docxParagraph('7') +
          docxParagraph('Колонтитул курса') +
          docxParagraph('Глава 2', style: 'Heading1') +
          docxParagraph('Второй абзац главы.') +
          docxParagraph('Рис. 2. Схема цепи') +
          docxParagraph('Колонтитул курса'),
    );
    final ParsedDocument parsed = await const DocxParser().parse(
      bytes,
      fileName: 'конспект.docx',
    );
    final Document model = builder.build(parsed);

    expectModelInvariants(model);
    expect(model.sections, hasLength(3));
    expect(model.sections.map((Section section) => section.title), <String?>[
      null,
      'Глава 1',
      'Глава 2',
    ]);
    expect(model.contentBlocks.map((Block block) => block.text), <String>[
      'Первый раздел без заголовка',
      'Глава 1',
      'Первый абзац главы.',
      'Глава 2',
      'Второй абзац главы.',
    ]);
    final List<Block> footers = model.noiseBlocks
        .where((Block block) => block.text == 'Колонтитул курса')
        .toList();
    expect(footers, hasLength(3));
    for (final Block footer in footers) {
      expect(footer.noiseKind, NoiseKind.runningHeaderFooter);
    }
    final Block pageNumber = model.noiseBlocks.firstWhere(
      (Block block) => block.text == '7',
    );
    expect(pageNumber.noiseKind, NoiseKind.pageNumber);
    final Block caption = model.noiseBlocks.firstWhere(
      (Block block) => block.text == 'Рис. 2. Схема цепи',
    );
    expect(caption.noiseKind, NoiseKind.figureCaption);
  });

  test('PPTX: слайд — раздел, строки слайда — блоки', () async {
    final Uint8List bytes = buildPptx(
      slideTexts: <List<String>>[
        <String>['Урок 1', 'Первая строка слайда'],
        <String>['Урок 2', 'Вторая строка слайда'],
      ],
    );
    final ParsedDocument parsed = await const PptxParser().parse(
      bytes,
      fileName: 'слайды.pptx',
    );
    final Document model = builder.build(parsed);

    expectModelInvariants(model);
    expect(model.sections, hasLength(2));
    expect(model.sections.map((Section section) => section.title), <String?>[
      null,
      null,
    ]);
    expect(model.contentBlocks.map((Block block) => block.text), <String>[
      'Урок 1',
      'Первая строка слайда',
      'Урок 2',
      'Вторая строка слайда',
    ]);
    expect(model.noiseBlocks, isEmpty);
    expect(model.sections[0].blockIds, hasLength(2));
    expect(model.sections[1].blockIds, hasLength(2));
  });

  test(
    'MD: один раздел, строка — блок, нормализация не трогает текст',
    () async {
      const String markdown =
          '# Кинематика\n'
          '\n'
          'Скорость — это путь за время.\n'
          '\n'
          '- Первое свойство\n'
          '- Второе свойство';
      final ParsedDocument parsed = await const TxtParser(
        format: DocumentFormat.md,
      ).parse(utf8Bytes(markdown), fileName: 'тема.md');
      final Document model = builder.build(parsed);

      expectModelInvariants(model);
      expect(model.format, DocumentFormat.md);
      expect(model.sections, hasLength(1));
      expect(model.contentBlocks.map((Block block) => block.text), <String>[
        '# Кинематика',
        'Скорость — это путь за время.',
        '- Первое свойство',
        '- Второе свойство',
      ]);
      expect(model.noiseBlocks, isEmpty);
      // Исходный текст с «ё/тире» сохранён, сравнение идёт по нормализованной форме.
      final Block dash = model.contentBlocks.firstWhere(
        (Block block) => block.text.contains('—'),
      );
      expect(dash.text, 'Скорость — это путь за время.');
      expect(dash.normalizedText, 'Скорость - это путь за время.');
      final Section section = model.sections.single;
      expect(model.text.substring(section.start, section.end), markdown);
    },
  );

  test('скан без текстового слоя: пустая модель, без исключения', () async {
    final FileParsingService service = FileParsingService(
      isolateRunner: <T>(Future<T> Function() task) => task(),
    );
    final ParsingOutcome outcome = await service.parseFile(
      FileParsingInput(
        fileName: 'скан.pdf',
        bytes: buildScannedPdf(pageImage: scannedPageRaster()),
      ),
    );

    expect(outcome, isA<ParsedFileFailure>());
    expect((outcome as ParsedFileFailure).code, ParserErrorCode.scannedPdf);

    final Document model = builder.buildFromOutcome(outcome);

    expect(model.isEmpty, isTrue);
    expect(model.text, isEmpty);
    expect(model.blocks, isEmpty);
    expect(model.sections, isEmpty);
    expect(model.fileName, 'скан.pdf');
    expect(model.format, DocumentFormat.pdf);
    expect(model.blockAt(0), isNull);
  });
}
