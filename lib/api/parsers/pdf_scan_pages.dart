/// Страницы PDF-скана: полный рендер + значимые визуальные области (ADR-037).
///
/// Чистый путь сканированного PDF: документ без текстового слоя разбирается не
/// текстовым парсером, а рендером страниц (`PdfScanRenderer`, PDFium). Для
/// каждой страницы сохраняется полный рендер (контекст и OCR-основа для
/// vision-модели) и отдельные значимые области (`PdfPageRegionDetector`) —
/// схемы, графики, диаграммы.
///
/// Изображения регионов попадают в `DocumentImage` и в каталог `<images>`, чтобы
/// модель могла вернуть `image_id`; полный рендер страницы уходит провайдеру
/// как image-part (ADR-023/027) и всегда доступен для повторной обработки.
library;

import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_images.dart';
import 'package:cardflow/api/parsers/pdf_page_regions.dart';
import 'package:cardflow/api/parsers/pdf_scan_renderer.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Одна страница скана: рендер и найденные области.
class PdfScanPage {
  /// Создаёт страницу.
  const PdfScanPage({
    required this.pageNumber,
    required this.pngBytes,
    required this.width,
    required this.height,
    this.regions = const <PdfPageRegion>[],
  });

  /// Номер страницы (с 1).
  final int pageNumber;

  /// Полный рендер страницы (PNG).
  final Uint8List pngBytes;

  /// Ширина рендера в пикселях.
  final int width;

  /// Высота рендера в пикселях.
  final int height;

  /// Значимые визуальные области страницы.
  final List<PdfPageRegion> regions;

  /// Значимые области для модели: страница с одной большой схемой отдаётся
  /// целиком (область == страница), отдельные вырезки не нужны.
  bool get hasSingleVisual => regions.length == 1 && regions.single.isWholePage;
}

/// Разобранный скан: имя файла и страницы в порядке документа.
class PdfScanDocument {
  /// Создаёт документ.
  const PdfScanDocument({required this.fileName, required this.pages});

  /// Имя исходного файла.
  final String fileName;

  /// Страницы в порядке документа.
  final List<PdfScanPage> pages;

  /// Количество отрендеренных страниц.
  int get pageCount => pages.length;

  /// Все страницы одним списком PNG (совместимость с прежним API).
  List<Uint8List> get pagePngs => <Uint8List>[
    for (final PdfScanPage page in pages) page.pngBytes,
  ];

  /// Вложения-страницы для vision-модели (ADR-023: один PDF — один фрагмент).
  List<GenerationAttachment> attachments() => <GenerationAttachment>[
    for (final PdfScanPage page in pages)
      GenerationAttachment(
        fileName: fileName,
        mediaType: AttachmentMediaType.png,
        bytes: page.pngBytes,
        pageNumber: page.pageNumber,
        groupKey: fileName,
      ),
  ];

  /// Изображения регионов для каталога `<images>` и `image_id`.
  ///
  /// Страница с одной большой схемой сохраняется целиком
  /// (`renderedPage`), иначе каждая значимая область — `croppedRegion`.
  /// Повторы по содержимому отбрасываются: одна и та же колонтитульная схема
  /// на нескольких страницах не дублируется.
  List<DocumentImage> documentImages() {
    final List<DocumentImage> images = <DocumentImage>[];
    final Set<String> digests = <String>{};
    for (final PdfScanPage page in pages) {
      if (page.hasSingleVisual) {
        final PdfPageRegion region = page.regions.single;
        final String digest = contentDigest(page.pngBytes);
        if (!digests.add(digest)) continue;
        images.add(
          DocumentImage(
            fileName: fileName,
            bytes: page.pngBytes,
            mediaType: AttachmentMediaType.png,
            page: page.pageNumber,
            width: page.width,
            height: page.height,
            source: DocumentImageSource.renderedPage,
            rect: DocumentImageRect(
              left: region.left,
              top: region.top,
              width: region.width,
              height: region.height,
            ),
            context: 'Полная страница скана',
          ),
        );
        continue;
      }
      for (final PdfPageRegion region in page.regions) {
        final String digest = contentDigest(region.pngBytes);
        if (!digests.add(digest)) continue;
        images.add(
          DocumentImage(
            fileName: fileName,
            bytes: region.pngBytes,
            mediaType: AttachmentMediaType.png,
            page: page.pageNumber,
            width: region.pixelWidth,
            height: region.pixelHeight,
            source: DocumentImageSource.croppedRegion,
            rect: DocumentImageRect(
              left: region.left,
              top: region.top,
              width: region.width,
              height: region.height,
            ),
            order: region.order,
            context: 'Фрагмент скана',
          ),
        );
      }
    }
    return List<DocumentImage>.unmodifiable(images);
  }
}

/// Разбор сканированного PDF: рендер страниц + выделение областей.
class PdfScanPageExtractor {
  /// Создаёт разбор.
  const PdfScanPageExtractor({
    this.renderer = const PdfScanRenderer(),
    this.regions = const PdfPageRegionDetector(),
  });

  /// Рендерер страниц (PDFium).
  final PdfScanRenderer renderer;

  /// Детектор визуальных областей.
  final PdfPageRegionDetector regions;

  /// Рендерит страницы и находит области.
  ///
  /// Ошибки PDFium → `ParserException(scannedPdf)` (как у рендерера); ошибки
  /// областей не фатальны: страница остаётся без вырезок.
  Future<PdfScanDocument> extract(
    Uint8List bytes, {
    required String fileName,
    int? maxPages,
  }) async {
    final List<PdfScanPageRender> rendered = await renderer.renderPages(
      bytes,
      fileName: fileName,
      maxPages: maxPages,
    );
    final List<PdfScanPage> pages = <PdfScanPage>[];
    for (final PdfScanPageRender render in rendered) {
      List<PdfPageRegion> detected = const <PdfPageRegion>[];
      try {
        detected = regions.detect(render.pngBytes, page: render.pageNumber);
      } on Object {
        detected = const <PdfPageRegion>[];
      }
      pages.add(
        PdfScanPage(
          pageNumber: render.pageNumber,
          pngBytes: render.pngBytes,
          width: render.width,
          height: render.height,
          regions: detected,
        ),
      );
    }
    return PdfScanDocument(
      fileName: fileName,
      pages: List<PdfScanPage>.unmodifiable(pages),
    );
  }
}
