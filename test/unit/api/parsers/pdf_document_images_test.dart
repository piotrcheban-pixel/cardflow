import 'dart:typed_data';

import 'package:cardflow/api/parsers/pdf_parser.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'fixtures/document_fixtures.dart';

/// Итерация L76 (ADR-037): извлечение изображений из обычного PDF.
///
/// `pdfrx` умеет только текст, поэтому изображения читает PDFium через
/// `pdfium_dart` в воркер-изоляте `pdfrx`. Тесты идут на реальном PDFium
/// (CI: pinned `chromium/8125`, L26), без моков FFI.
void main() {
  const PdfParser parser = PdfParser();

  setUpAll(() async {
    await pdfrxInitialize();
  });

  Future<ParsedDocument> parse(Uint8List bytes) =>
      parser.parse(bytes, fileName: 'материалы.pdf');

  test('формат парсера — pdf', () {
    expect(parser.format, DocumentFormat.pdf);
  });

  group('обычный PDF с встроенным изображением', () {
    test(
      'извлекается ровно одно DocumentImage со страницей и координатами',
      () async {
        final ParsedDocument document = await parse(
          buildPdfWithEmbeddedImage(
            imageBytes: diagramJpeg(),
            text: 'Page with a scheme and its description',
          ),
        );

        expect(document.text, contains('Page with a scheme'));
        expect(document.images, hasLength(1));
        final DocumentImage image = document.images.single;
        expect(image.page, 1);
        expect(image.order, 0);
        expect(image.source, DocumentImageSource.embedded);
        expect(image.width, 300);
        expect(image.height, 200);
        expect(image.fileName, 'материалы.pdf');
        expect(image.sectionIndex, 0);
        // Изображение нарисовано 150×100 pt при (80, 380) на странице 612×792.
        final DocumentImageRect rect = image.rect!;
        expect(rect.left, closeTo(80 / 612, 0.01));
        expect(rect.width, closeTo(150 / 612, 0.01));
        expect(rect.height, closeTo(100 / 792, 0.01));
        expect(rect.top, closeTo(1 - 480 / 792, 0.01));
        // PNG читается обратно и совпадает по размерам.
        final img.Image? png = img.decodePng(image.bytes);
        expect(png, isNotNull);
        expect(png!.width, 300);
        expect(png.height, 200);
      },
    );

    test('изображение внутри Form XObject тоже извлекается', () async {
      final ParsedDocument document = await parse(
        buildPdfWithEmbeddedImage(
          imageBytes: diagramJpeg(),
          imageInForm: true,
          text: 'Form object page with a scheme inside',
        ),
      );

      expect(document.images, hasLength(1));
      final DocumentImage image = document.images.single;
      expect(image.page, 1);
      expect(image.bytes.length, greaterThan(0));
      // Координаты вложенного объекта переводятся в систему страницы.
      expect(image.rect!.left, closeTo(80 / 612, 0.01));
      expect(image.rect!.width, closeTo(300 / 612, 0.01));
    });

    test('PDF без изображений — пустой список', () async {
      final ParsedDocument document = await parse(
        buildPdf('Hello CardFlow PDF'),
      );
      expect(document.images, isEmpty);
    });

    test('повторяющееся изображение не дублируется', () async {
      final Uint8List picture = diagramJpeg();
      final ParsedDocument document = await parse(
        buildPdfFromFixturePages(<PdfFixturePage>[
          PdfFixturePage(
            text: 'First page with the same scheme',
            imageJpeg: picture,
            drawRect: (x: 60, y: 480, width: 200, height: 150),
          ),
          PdfFixturePage(
            text: 'Second page with the same scheme',
            imageJpeg: picture,
            drawRect: (x: 60, y: 300, width: 200, height: 150),
          ),
        ]),
      );

      expect(document.images, hasLength(1));
      expect(document.images.single.page, 1);
    });

    test('маленькая иконка отбрасывается фильтром', () async {
      final ParsedDocument document = await parse(
        buildPdfWithEmbeddedImage(
          imageBytes: iconJpeg(),
          imageWidth: 32,
          imageHeight: 32,
          drawRect: (x: 500, y: 700, width: 16, height: 16),
          text: 'Text page with a small interface icon in the corner',
        ),
      );

      expect(document.images, isEmpty);
    });

    test('небольшая формула на странице с подписью сохраняется', () async {
      final ParsedDocument document = await parse(
        buildPdfWithEmbeddedImage(
          imageBytes: formulaJpeg(),
          imageWidth: 120,
          imageHeight: 40,
          drawRect: (x: 200, y: 500, width: 120, height: 40),
          text:
              'Derivation of the moment of force formula.\n'
              'Fig. 3 The moment of force formula in expanded form\n'
              'The rest of the page text explains the notation.',
        ),
      );

      expect(document.images, hasLength(1));
      final DocumentImage image = document.images.single;
      expect(image.caption, contains('Fig. 3'));
      expect(image.width, 120);
    });
  });

  group('классификация страниц и сканы', () {
    test(
      'полностью сканированный PDF → scannedPdf (прежний контракт)',
      () async {
        await expectLater(
          parse(
            buildScannedPdf(
              pageImage: scannedPageRaster(),
              pixelWidth: 1224,
              pixelHeight: 1584,
            ),
          ),
          throwsA(
            isA<ParserException>().having(
              (ParserException error) => error.code,
              'code',
              ParserErrorCode.scannedPdf,
            ),
          ),
        );
      },
    );

    test('смешанный PDF: страница со схемой + страница-скан', () async {
      final ParsedDocument document = await parse(
        buildMixedPdf(
          textPageImage: diagramJpeg(),
          scanPageImage: scannedPageRaster(),
        ),
      );

      expect(document.metadata.pageCount, 2);
      expect(document.sections, hasLength(1));
      // Страница 1 — встроенная схема, страница 2 — полный рендер скана.
      final List<DocumentImage> pageOne = document.images
          .where((DocumentImage image) => image.page == 1)
          .toList();
      final List<DocumentImage> pageTwo = document.images
          .where((DocumentImage image) => image.page == 2)
          .toList();
      expect(pageOne, isNotEmpty, reason: 'схема со страницы 1 не извлечена');
      expect(pageOne.first.source, DocumentImageSource.embedded);
      expect(pageTwo, isNotEmpty, reason: 'страница-скан не обработана');
      expect(
        pageTwo.any(
          (DocumentImage image) =>
              image.source == DocumentImageSource.renderedPage,
        ),
        isTrue,
        reason: 'полный рендер страницы скана не сохранён',
      );
      // Значимая область скана выделена отдельно.
      expect(
        pageTwo.any(
          (DocumentImage image) =>
              image.source == DocumentImageSource.croppedRegion,
        ),
        isTrue,
        reason: 'визуальная область скана не выделена',
      );
      for (final DocumentImage image in document.images) {
        expect(image.sectionIndex, 0);
        expect(image.bytes, isNotEmpty);
      }
    });
  });

  test(
    'битое изображение не отменяет разбор текста (частичный успех)',
    () async {
      final PdfFixtureWriter writer = PdfFixtureWriter();
      final int font = writer.addObject(
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      );
      final int brokenImage = writer.addStream(
        dictionary:
            '/Type /XObject /Subtype /Image /Width 300 /Height 200 '
            '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode',
        data: <int>[0xFF, 0xD8, 0x00, 0x11, 0x22, 0x33, 0x44],
      );
      const String content =
          'BT /F1 14 Tf 72 740 Td (Text survives broken image) Tj ET\n'
          'q 150 0 0 100 80 380 cm /Im1 Do Q\n';
      final int contentStream = writer.addStream(
        dictionary: '/Length ${content.length}',
        data: content.codeUnits,
      );
      final int page = writer.addObject(
        '<< /Type /Page /MediaBox [0 0 612 792] /Contents $contentStream 0 R '
        '/Resources << /Font << /F1 $font 0 R >> '
        '/XObject << /Im1 $brokenImage 0 R >> >> >>',
      );
      final int pages = writer.addObject(
        '<< /Type /Pages /Kids [$page 0 R] /Count 1 >>',
      );
      final int catalog = writer.addObject(
        '<< /Type /Catalog /Pages $pages 0 R >>',
      );

      final ParsedDocument document = await parse(writer.build(root: catalog));

      expect(document.text, 'Text survives broken image');
      expect(document.images, isEmpty);
    },
  );
}
