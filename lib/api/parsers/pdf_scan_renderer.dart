/// Рендер страниц PDF-скана в PNG для моделей с Vision (итерация 7.9, ADR-023).
///
/// Скан без текстового слоя нельзя отправить текстовой моделью; PDFium
/// (`pdfrx`) растеризует страницы, а `package:image` кодирует их в PNG.
/// Класс не зависит от Flutter и выполняется в изоляте (A8.3).
///
/// Итерация L76 (ADR-037): рендер возвращает номер страницы, чтобы изображения
/// скана не теряли связь с исходной страницей; общий помощник
/// [pdfScanPageToPng] используется и парсером (у него документ уже открыт).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart';

import 'package:cardflow/domain/text/parser_exception.dart';

/// Отрендеренная страница PDF с номером (с 1).
class PdfScanPageRender {
  /// Создаёт рендер страницы.
  const PdfScanPageRender({
    required this.pageNumber,
    required this.pngBytes,
    required this.width,
    required this.height,
  });

  /// Номер страницы (с 1).
  final int pageNumber;

  /// PNG-содержимое страницы.
  final Uint8List pngBytes;

  /// Ширина PNG в пикселях.
  final int width;

  /// Высота PNG в пикселях.
  final int height;
}

/// Рендерит одну страницу PDFium в PNG (144 dpi, но не шире [maxWidth]).
///
/// Возвращает `null`, если страницу отрисовать не удалось (битая страница не
/// отменяет остальные — частичный успех, ADR-037).
Future<PdfScanPageRender?> pdfScanPageToPng(
  PdfPage page, {
  required int pageNumber,
  int maxWidth = 1600,
}) async {
  final double pageWidth = page.width;
  final double pageHeight = page.height;
  if (pageWidth <= 0 || pageHeight <= 0) return null;
  final double targetWidth = math.min(maxWidth.toDouble(), pageWidth * 2);
  final double targetHeight = targetWidth * (pageHeight / pageWidth);
  PdfImage? rendered;
  try {
    rendered = await page.render(
      fullWidth: targetWidth,
      fullHeight: targetHeight,
    );
    if (rendered == null) return null;
    final image.Image raster = rendered.createImageNF(
      pixelSizeThreshold: maxWidth,
    );
    final Uint8List png = Uint8List.fromList(image.encodePng(raster));
    return PdfScanPageRender(
      pageNumber: pageNumber,
      pngBytes: png,
      width: raster.width,
      height: raster.height,
    );
  } on Object {
    return null;
  } finally {
    rendered?.dispose();
  }
}

/// Рендерер страниц PDF-скана.
class PdfScanRenderer {
  /// Создаёт рендерер.
  ///
  /// [maxPages] — максимум страниц (первые страницы документа); по умолчанию
  /// 3 страницы (итерация 7.11, ADR-027): этого хватает модели для первых
  /// карточек, а размер запроса с PNG-страницами остаётся разумным;
  /// [maxWidth] — максимальная ширина PNG в пикселях.
  const PdfScanRenderer({this.maxPages = 3, this.maxWidth = 1600});

  /// Максимум рендерируемых страниц.
  final int maxPages;

  /// Максимальная ширина страницы в пикселях.
  final int maxWidth;

  /// Рендерит первые страницы [bytes] в PNG.
  ///
  /// Любая ошибка PDFium/PDF → `ParserException(scannedPdf)`: вызывающий экран
  /// показывает понятную строку ARB и не выпускает сырое исключение.
  Future<List<Uint8List>> render(
    Uint8List bytes, {
    String? fileName,
    int? maxPages,
  }) async {
    final List<PdfScanPageRender> pages = await renderPages(
      bytes,
      fileName: fileName,
      maxPages: maxPages,
    );
    return List<Uint8List>.unmodifiable(<Uint8List>[
      for (final PdfScanPageRender page in pages) page.pngBytes,
    ]);
  }

  /// Рендерит первые страницы [bytes] с номерами страниц.
  Future<List<PdfScanPageRender>> renderPages(
    Uint8List bytes, {
    String? fileName,
    int? maxPages,
  }) async {
    if (bytes.isEmpty) {
      throw const ParserException(
        ParserErrorCode.scannedPdf,
        details: 'Пустой PDF-файл',
      );
    }
    try {
      await pdfrxInitialize();
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.scannedPdf,
        details: 'Не удалось инициализировать PDFium: $error',
      );
    }

    PdfDocument document;
    try {
      document = await PdfDocument.openData(
        bytes,
        sourceName: fileName ?? 'scan.pdf',
        passwordProvider: () => null,
      );
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.scannedPdf,
        details: 'Не удалось открыть PDF для рендера: $error',
      );
    }

    final int limit = math.max(1, maxPages ?? this.maxPages);
    try {
      if (document.pages.isEmpty) {
        throw const ParserException(
          ParserErrorCode.scannedPdf,
          details: 'В PDF нет страниц',
        );
      }
      final int count = math.min(document.pages.length, limit);
      final List<PdfScanPageRender> pages = <PdfScanPageRender>[];
      for (var index = 0; index < count; index++) {
        final PdfScanPageRender? page = await pdfScanPageToPng(
          document.pages[index],
          pageNumber: index + 1,
          maxWidth: maxWidth,
        );
        if (page != null) pages.add(page);
      }
      if (pages.isEmpty) {
        throw const ParserException(
          ParserErrorCode.scannedPdf,
          details: 'Не удалось отрендерить ни одной страницы PDF',
        );
      }
      return List<PdfScanPageRender>.unmodifiable(pages);
    } finally {
      await document.dispose();
    }
  }
}
