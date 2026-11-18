import 'dart:typed_data';

import 'package:cardflow/api/parsers/pdf_scan_pages.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'fixtures/document_fixtures.dart';

/// Сканированные PDF: рендер страниц и значимые области (итерация L76,
/// ADR-037). Тест идёт реальным путём скана — PDFium растеризует страницу,
/// детектор выделяет области; обычное извлечение Image XObject здесь не
/// участвует.
void main() {
  const PdfScanPageExtractor extractor = PdfScanPageExtractor();

  setUpAll(() async {
    await pdfrxInitialize();
  });

  test('скан: страница рендерится, схема выделяется как область', () async {
    final Uint8List pdf = buildScannedPdf(
      pageImage: scannedPageRaster(),
      pixelWidth: 1224,
      pixelHeight: 1584,
    );

    final PdfScanDocument scan = await extractor.extract(
      pdf,
      fileName: 'скан.pdf',
    );

    expect(scan.pageCount, 1);
    final PdfScanPage page = scan.pages.single;
    expect(page.pageNumber, 1);
    expect(page.pngBytes, isNotEmpty);
    final img.Image? rendered = img.decodePng(page.pngBytes);
    expect(rendered, isNotNull);
    expect(page.width, rendered!.width);
    expect(page.height, rendered.height);
    expect(page.regions, isNotEmpty, reason: 'Визуальная область не найдена');
    expect(page.hasSingleVisual, isFalse);

    final List<DocumentImage> images = scan.documentImages();
    expect(images, hasLength(page.regions.length));
    final DocumentImage region = images.first;
    expect(region.page, 1);
    expect(region.source, DocumentImageSource.croppedRegion);
    expect(region.fileName, 'скан.pdf');
    expect(region.mediaType, AttachmentMediaType.png);
    expect(region.rect, isNotNull);
    expect(region.rect!.top, greaterThan(0.3));
    expect(img.decodePng(region.bytes), isNotNull);
  });

  test('страница с одной большой схемой сохраняется целиком', () async {
    final PdfScanDocument scan = await extractor.extract(
      buildScannedPdf(
        pageImage: scannedWholeDiagramRaster(),
        pixelWidth: 900,
        pixelHeight: 1200,
      ),
      fileName: 'схема.pdf',
    );

    final PdfScanPage page = scan.pages.single;
    expect(page.hasSingleVisual, isTrue);
    final List<DocumentImage> images = scan.documentImages();
    expect(images, hasLength(1));
    expect(images.single.source, DocumentImageSource.renderedPage);
    expect(images.single.width, page.width);
    expect(images.single.height, page.height);
  });

  test('вложения скана: номер страницы и группа одного PDF', () async {
    final PdfScanDocument scan = await extractor.extract(
      buildScannedPdf(
        pageImage: scannedPageRaster(),
        pixelWidth: 1224,
        pixelHeight: 1584,
      ),
      fileName: 'лекция-скан.pdf',
    );

    final List<GenerationAttachment> attachments = scan.attachments();
    expect(attachments, hasLength(1));
    expect(attachments.single.pageNumber, 1);
    expect(attachments.single.groupKey, 'лекция-скан.pdf');
    expect(
      hasValidAttachmentSignature(
        AttachmentMediaType.png,
        attachments.single.bytes,
      ),
      isTrue,
    );
  });

  test('пустая страница скана: страница есть, областей нет', () async {
    final img.Image blank = img.Image(width: 900, height: 1200);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    final PdfScanDocument scan = await extractor.extract(
      buildScannedPdf(
        pageImage: Uint8List.fromList(img.encodeJpg(blank)),
        pixelWidth: 900,
        pixelHeight: 1200,
      ),
      fileName: 'пусто.pdf',
    );

    expect(scan.pageCount, 1);
    expect(scan.pages.single.regions, isEmpty);
    expect(scan.documentImages(), isEmpty);
  });

  test('нечитаемый PDF → ParserException(scannedPdf)', () async {
    await expectLater(
      extractor.extract(
        Uint8List.fromList(<int>[...'%PDF-1.4\n'.codeUnits, 1, 2, 3]),
        fileName: 'битый.pdf',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
