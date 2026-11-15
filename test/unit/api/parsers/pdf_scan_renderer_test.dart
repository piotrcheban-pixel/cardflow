import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'package:cardflow/api/parsers/pdf_scan_renderer.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/text/parser_exception.dart';

import 'fixtures/document_fixtures.dart';

/// Итерация 7.9: страницы PDF-скана рендерятся в PNG для Vision-моделей.
void main() {
  const renderer = PdfScanRenderer(maxPages: 2, maxWidth: 800);

  setUpAll(() async {
    await pdfrxInitialize();
  });

  test('первые maxPages страниц → валидные PNG', () async {
    final Uint8List source = buildPdfPages(<String>[
      'Page 1',
      'Page 2',
      'Page 3',
    ]);

    final List<Uint8List> pages = await renderer.render(source, maxPages: 2);

    expect(pages, hasLength(2), reason: 'Рендерим не больше maxPages страниц');
    for (final Uint8List page in pages) {
      expect(
        hasValidAttachmentSignature(AttachmentMediaType.png, page),
        isTrue,
        reason: 'Страница должна быть PNG',
      );
      final img.Image? decoded = img.decodePng(page);
      expect(decoded, isNotNull, reason: 'PNG не декодируется');
      expect(decoded!.width, greaterThan(0));
      expect(decoded.height, greaterThan(0));
    }
  });

  test('ширина страницы ограничена maxWidth', () async {
    final List<Uint8List> pages = await renderer.render(
      buildPdfPages(<String>['Page']),
    );
    final img.Image decoded = img.decodePng(pages.single)!;
    expect(decoded.width, lessThanOrEqualTo(800));
  });

  // Итерация 7.11: скан отправляется максимум тремя страницами (ADR-026).
  test('по умолчанию рендерятся первые 3 страницы', () async {
    const PdfScanRenderer production = PdfScanRenderer();
    expect(production.maxPages, 3);

    final List<Uint8List> pages = await production.render(
      buildPdfPages(<String>['1', '2', '3', '4', '5']),
    );

    expect(pages, hasLength(3));
    for (final Uint8List page in pages) {
      expect(
        hasValidAttachmentSignature(AttachmentMediaType.png, page),
        isTrue,
      );
    }
  });

  test('нечитаемый PDF → ParserException(scannedPdf)', () async {
    await expectLater(
      renderer.render(
        Uint8List.fromList(<int>[...'%PDF-1.4\n'.codeUnits, 0, 1, 2, 3]),
      ),
      throwsA(
        isA<ParserException>().having(
          (ParserException error) => error.code,
          'code',
          ParserErrorCode.scannedPdf,
        ),
      ),
    );
  });

  test('пустые байты → ParserException(scannedPdf)', () async {
    await expectLater(
      renderer.render(Uint8List(0)),
      throwsA(isA<ParserException>()),
    );
  });

  test('рендер работает в отдельном изоляте (production-путь)', () async {
    final Uint8List source = buildPdfPages(<String>['Isolate page']);
    final List<Uint8List> pages = await Isolate.run(() async {
      await pdfrxInitialize();
      return const PdfScanRenderer(maxPages: 1, maxWidth: 400).render(source);
    });

    expect(pages, hasLength(1));
    expect(
      hasValidAttachmentSignature(AttachmentMediaType.png, pages.single),
      isTrue,
    );
  });
}
