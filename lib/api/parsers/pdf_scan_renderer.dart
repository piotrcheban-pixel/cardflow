/// Рендер страниц PDF-скана в PNG для моделей с Vision (итерация 7.9, ADR-023).
///
/// Скан без текстового слоя нельзя отправить текстовой моделью; PDFium
/// (`pdfrx`) растеризует первые страницы, а `package:image` кодирует их в PNG.
/// Класс не зависит от Flutter и выполняется в изоляте (A8.3).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart';

import 'package:cardflow/domain/text/parser_exception.dart';

/// Рендерер страниц PDF-скана.
class PdfScanRenderer {
  /// Создаёт рендерер.
  ///
  /// [maxPages] — максимум страниц (первые страницы документа); по умолчанию
  /// 3 страницы (итерация 7.11): этого хватает модели для первых карточек, а
  /// размер запроса с PNG-страницами остаётся разумным;
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
      final List<Uint8List> pages = <Uint8List>[];
      for (var index = 0; index < count; index++) {
        final PdfPage page = document.pages[index];
        final double pageWidth = page.width;
        final double pageHeight = page.height;
        if (pageWidth <= 0 || pageHeight <= 0) continue;
        // 2× от 72 dpi (144 dpi), но не шире maxWidth.
        final double targetWidth = math.min(maxWidth.toDouble(), pageWidth * 2);
        final double targetHeight = targetWidth * (pageHeight / pageWidth);
        PdfImage? rendered;
        try {
          rendered = await page.render(
            fullWidth: targetWidth,
            fullHeight: targetHeight,
          );
          if (rendered == null) continue;
          final image.Image raster = rendered.createImageNF(
            pixelSizeThreshold: maxWidth,
          );
          pages.add(image.encodePng(raster));
        } on Object {
          // Пропускаем страницу: если не отрендерилась ни одна, ниже ошибка.
          continue;
        } finally {
          rendered?.dispose();
        }
      }
      if (pages.isEmpty) {
        throw const ParserException(
          ParserErrorCode.scannedPdf,
          details: 'Не удалось отрендерить ни одной страницы PDF',
        );
      }
      return List<Uint8List>.unmodifiable(pages);
    } finally {
      await document.dispose();
    }
  }
}
