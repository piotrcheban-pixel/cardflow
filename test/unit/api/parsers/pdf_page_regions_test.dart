import 'dart:typed_data';

import 'package:cardflow/api/parsers/pdf_page_regions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'fixtures/document_fixtures.dart';

/// Выделение значимых визуальных областей на растре страницы скана
/// (итерация L76, ADR-037). Детектор чистый: PNG-растр без PDFium.
void main() {
  const PdfPageRegionDetector detector = PdfPageRegionDetector();

  test('схема в центре скана выделяется, строки текста — нет', () {
    final Uint8List page = scannedPageRaster();
    final List<PdfPageRegion> regions = detector.detect(page, page: 2);

    expect(regions, isNotEmpty, reason: 'Схема на странице не найдена');
    final PdfPageRegion region = regions.first;
    // Схема нарисована в (200..1000)×(640..1040) при 1224×1584.
    expect(region.page, 2);
    expect(region.width, greaterThan(0.5));
    expect(region.height, greaterThan(0.15));
    expect(
      region.top,
      greaterThan(0.3),
      reason: 'Область не должна захватывать текст сверху',
    );
    expect(region.isWholePage, isFalse);
    // Вырезка — валидный PNG из полного рендера (без масштабирования).
    final img.Image? crop = img.decodePng(region.pngBytes);
    expect(crop, isNotNull);
    expect(region.pixelWidth, crop!.width);
    expect(region.pixelHeight, crop.height);
  });

  test('одна большая схема — область «вся страница»', () {
    final List<PdfPageRegion> regions = detector.detect(
      scannedWholeDiagramRaster(),
      page: 1,
    );

    expect(regions, hasLength(1));
    expect(regions.single.isWholePage, isTrue);
    expect(regions.single.areaFraction, greaterThan(0.5));
  });

  test('пустая страница — нет областей', () {
    final img.Image blank = img.Image(width: 600, height: 800);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    final List<PdfPageRegion> regions = detector.detect(
      Uint8List.fromList(img.encodePng(blank)),
      page: 1,
    );
    expect(regions, isEmpty);
  });

  test('страница только с текстом — визуальных областей нет', () {
    final img.Image page = img.Image(width: 900, height: 1200);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    for (var line = 0; line < 12; line++) {
      img.drawString(
        page,
        'Just a line of plain text number ${line + 1}',
        font: img.arial24,
        x: 80,
        y: 80 + line * 40,
        color: img.ColorRgb8(10, 10, 10),
      );
    }
    final List<PdfPageRegion> regions = detector.detect(
      Uint8List.fromList(img.encodePng(page)),
      page: 1,
    );
    expect(regions, isEmpty);
  });

  test('не PNG — пустой список, без исключения', () {
    final List<PdfPageRegion> regions = detector.detect(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      page: 1,
    );
    expect(regions, isEmpty);
  });

  test('области идут в читальном порядке и с номерами', () {
    final List<PdfPageRegion> regions = detector.detect(
      scannedPageRaster(),
      page: 5,
    );
    for (var index = 0; index < regions.length; index++) {
      expect(regions[index].order, index);
      expect(regions[index].page, 5);
      expect(regions[index].left, inInclusiveRange(0, 1));
      expect(regions[index].top, inInclusiveRange(0, 1));
    }
  });
}
