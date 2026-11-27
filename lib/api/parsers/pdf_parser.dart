import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_images.dart';
import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/api/parsers/pdf_image_extractor.dart';
import 'package:cardflow/api/parsers/pdf_page_classifier.dart';
import 'package:cardflow/api/parsers/pdf_page_regions.dart';
import 'package:cardflow/api/parsers/pdf_scan_renderer.dart';
import 'package:cardflow/api/parsers/pdf_text_quality.dart';
import 'package:cardflow/api/parsers/pdfium_bootstrap.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:cardflow/domain/text/text_sanitizer.dart';
import 'package:pdfrx/pdfrx.dart';

/// Парсер PDF: текстовый слой через `pdfrx` (PDFium, MIT) (SPEC A8.3).
///
/// Страницы → разделы; пустой текстовый слой (скан) → `scannedPdf`; битый или
/// запароленный PDF → `unreadableFile`; нечитаемый текстовый слой (символы
/// замены/битая кодировка) → `garbledText` (итерация 7.10, ADR-024).
/// Вызывается в отдельном изоляте (ADR-010), инициализация PDFium —
/// `pdfrxInitialize()`.
///
/// Итерация L76 «PDF Visual Intelligence» (ADR-037): парсер извлекает
/// **визуальное содержимое** PDF — встроенные Image XObject (включая Form
/// XObject) с номером страницы, порядком и координатами, а для страниц без
/// текста — полный рендер и отдельные значимые области (рентген скана).
/// Классификация — постранично: один PDF может сочетать текстовые страницы и
/// сканы. Полностью сканированный PDF по-прежнему отдаёт `scannedPdf`: его
/// страницы уходят провайдеру как image-part (ADR-023/027) отдельным путём
/// (`PdfScanPageExtractor` в экране генерации).
class PdfParser implements DocumentParser {
  /// Создаёт парсер PDF.
  const PdfParser({
    this.sanitizer = const TextSanitizer(),
    this.quality = const PdfTextQuality(),
    this.imageExtractor = const PdfImageExtractor(),
    this.regionDetector = const PdfPageRegionDetector(),
    this.imageFilter = const PdfImageFilter(),
    this.maxScanPages = 3,
    this.maxImages = 24,
    this.cacheDirectory,
  });

  /// Каталог кэша PDFium, вычисленный в main-изоляте (`path_provider`).
  ///
  /// Передаётся строкой, потому что из фонового изолята платформенный канал
  /// недоступен. `null` — `Directory.systemTemp` (никогда не `HOME`: на
  /// Android его нет, TASK 04).
  final String? cacheDirectory;

  /// Копия парсера с явным каталогом кэша PDFium.
  PdfParser withCacheDirectory(String? value) => PdfParser(
    sanitizer: sanitizer,
    quality: quality,
    imageExtractor: imageExtractor,
    regionDetector: regionDetector,
    imageFilter: imageFilter,
    maxScanPages: maxScanPages,
    maxImages: maxImages,
    cacheDirectory: value,
  );

  /// Санитайзер извлечённого текста (C1/суррогаты/BOM).
  final TextSanitizer sanitizer;

  /// Проверка «нечитаемого» текста.
  final PdfTextQuality quality;

  /// Извлечение встроенных изображений (PDFium).
  final PdfImageExtractor imageExtractor;

  /// Выделение визуальных областей на страницах без текста.
  final PdfPageRegionDetector regionDetector;

  /// Фильтр мусорных изображений.
  final PdfImageFilter imageFilter;

  /// Максимум страниц, которые рендерятся для поиска областей (векторные
  /// схемы/сканы без Image XObject).
  final int maxScanPages;

  /// Максимум изображений из одного PDF (приоритет — порядок документа).
  final int maxImages;

  @override
  DocumentFormat get format => DocumentFormat.pdf;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    try {
      // TASK 04: явный каталог кэша — иначе на Android pdfrx уходит в ветку
      // `Platform.environment['HOME']!` и падает до открытия документа.
      await ensurePdfiumInitialized(cacheDirectory: cacheDirectory);
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Не удалось инициализировать PDFium: $error',
      );
    }

    PdfDocument document;
    try {
      document = await PdfDocument.openData(
        bytes,
        sourceName: fileName,
        passwordProvider: () => null,
      );
    } on PdfPasswordException catch (error) {
      throw ParserException(
        ParserErrorCode.passwordProtected,
        details: 'PDF защищён паролем: ${error.message}',
      );
    } on PdfException catch (error) {
      throw ParserException(
        ParserErrorCode.corruptFile,
        details: 'PDF повреждён: ${error.message}',
      );
    } on Object catch (error) {
      throw ParserException(
        ParserErrorCode.corruptFile,
        details: 'Не удалось открыть PDF: $error',
      );
    }

    try {
      if (document.pages.isEmpty) {
        throw const ParserException(
          ParserErrorCode.unreadableFile,
          details: 'В PDF нет страниц',
        );
      }
      final List<String> pageTexts = <String>[];
      int pageErrors = 0;
      for (final PdfPage page in document.pages) {
        String text = '';
        try {
          final PdfPageRawText? raw = await page.loadText();
          text = raw?.fullText ?? '';
        } on Object {
          pageErrors++;
          text = '';
        }
        pageTexts.add(text);
      }
      // Нечитаемый текстовый слой (битый ToUnicode/кодировка) — раньше это
      // уходило в API и провайдер отвечал 400/мусором (ADR-024).
      for (final String pageText in pageTexts) {
        if (quality.isUnreadable(pageText)) {
          throw const ParserException(
            ParserErrorCode.garbledText,
            details: 'Текстовый слой PDF содержит символы замены',
          );
        }
      }
      final List<String> cleanedTexts = <String>[
        for (final String pageText in pageTexts) sanitizer.sanitize(pageText),
      ];
      if (cleanedTexts.every((String text) => text.isEmpty)) {
        if (pageErrors > 0) {
          throw const ParserException(
            ParserErrorCode.unreadableFile,
            details: 'Не удалось извлечь текст ни одной страницы PDF',
          );
        }
        throw const ParserException(
          ParserErrorCode.scannedPdf,
          details: 'Текстовый слой PDF пуст — вероятно, скан',
        );
      }

      final ParsedDocumentBuilder builder = ParsedDocumentBuilder(
        format: format,
        fileName: fileName,
        metadata: ParsedDocumentMetadata(pageCount: pageTexts.length),
      );
      // Разделы — по страницам с текстом; сканы привязываются к ближайшему
      // текстовому разделу (связь со страницей сохраняется в `page`).
      final List<int> sectionOfPage = <int>[];
      var sectionCount = 0;
      for (final String pageText in cleanedTexts) {
        if (pageText.isEmpty) {
          sectionOfPage.add(-1);
          continue;
        }
        builder.startSection();
        builder.addLines(pageText.split('\n'));
        sectionOfPage.add(sectionCount++);
      }

      final List<_StagedImage> images = await _collectImages(
        document: document,
        fileName: fileName,
        pageTexts: cleanedTexts,
        imageExtraction: await imageExtractor
            .withCacheDirectory(cacheDirectory)
            .extract(bytes),
      );
      for (final _StagedImage staged in images) {
        builder.addImageToSection(
          _sectionForPage(sectionOfPage, staged.image.page),
          staged.image,
        );
      }
      return builder.build();
    } finally {
      await document.dispose();
    }
  }

  /// Раздел для страницы: ближайший предшествующий текстовый, иначе первый.
  int _sectionForPage(List<int> sectionOfPage, int? page) {
    if (sectionOfPage.isEmpty) return 0;
    final int index = (page ?? 1) - 1;
    for (var current = index; current >= 0; current--) {
      if (current < sectionOfPage.length && sectionOfPage[current] >= 0) {
        return sectionOfPage[current];
      }
    }
    for (final int section in sectionOfPage) {
      if (section >= 0) return section;
    }
    return 0;
  }

  /// Собирает изображения всех страниц: встроенные, рендеры и области.
  Future<List<_StagedImage>> _collectImages({
    required PdfDocument document,
    required String fileName,
    required List<String> pageTexts,
    required PdfImageExtractionResult? imageExtraction,
  }) async {
    final Map<int, List<PdfEmbeddedImage>> imagesByPage =
        <int, List<PdfEmbeddedImage>>{};
    for (final PdfEmbeddedImage image
        in imageExtraction?.images ?? const <PdfEmbeddedImage>[]) {
      (imagesByPage[image.page] ??= <PdfEmbeddedImage>[]).add(image);
    }
    final List<_StagedImage> staged = <_StagedImage>[];
    final Set<String> digests = <String>{};
    var renderedPages = 0;
    for (var index = 0; index < pageTexts.length; index++) {
      final int pageNumber = index + 1;
      final String pageText = pageTexts[index];
      final List<PdfEmbeddedImage> pageImages =
          imagesByPage[pageNumber] ?? const <PdfEmbeddedImage>[];
      final PdfPageClassification classification = classifyPdfPage(
        page: pageNumber,
        text: pageText,
        imageCount: pageImages.length,
      );
      final bool figureContext = pageHasFigureContext(pageText);
      final String? caption = pdfPageCaption(pageText);
      final String? context = pdfPageContextText(pageText);
      PdfEmbeddedImage? pageRaster;
      for (final PdfEmbeddedImage image in pageImages) {
        if (image.coversPage()) {
          pageRaster = image;
          break;
        }
      }
      if (pageRaster != null) {
        // Страница целиком — скан/полноразмерная иллюстрация: сохраняем
        // рендер страницы и значимые области внутри неё.
        _stage(
          staged: staged,
          digests: digests,
          fileName: fileName,
          bytes: pageRaster.pngBytes,
          width: pageRaster.pixelWidth,
          height: pageRaster.pixelHeight,
          page: pageNumber,
          order: pageRaster.order,
          source: DocumentImageSource.renderedPage,
          rect: _normalizedRect(
            left: pageRaster.left,
            bottom: pageRaster.bottom,
            right: pageRaster.right,
            top: pageRaster.top,
            pageWidth: pageRaster.pageWidth,
            pageHeight: pageRaster.pageHeight,
          ),
          caption: caption,
          context: context,
        );
        _stageRegions(
          staged: staged,
          digests: digests,
          fileName: fileName,
          page: pageNumber,
          regions: _detectRegions(pageRaster.pngBytes, page: pageNumber),
          caption: caption,
          context: context,
        );
        continue;
      }
      for (final PdfEmbeddedImage image in pageImages) {
        if (!imageFilter.isSignificant(
          width: image.pixelWidth,
          height: image.pixelHeight,
          byteLength: image.pngBytes.length,
          hasFigureContext: figureContext,
        )) {
          continue;
        }
        _stage(
          staged: staged,
          digests: digests,
          fileName: fileName,
          bytes: image.pngBytes,
          width: image.pixelWidth,
          height: image.pixelHeight,
          page: pageNumber,
          order: image.order,
          source: DocumentImageSource.embedded,
          rect: _normalizedRect(
            left: image.left,
            bottom: image.bottom,
            right: image.right,
            top: image.top,
            pageWidth: image.pageWidth,
            pageHeight: image.pageHeight,
          ),
          caption: caption,
          context: context,
        );
      }
      // Страница без текста и без встроенных изображений: содержание может быть
      // векторным (схемы). Рендерим и ищем области — не больше maxScanPages.
      final bool needsRendering =
          pageImages.isEmpty && !classification.hasTextLayer;
      if (needsRendering && renderedPages < maxScanPages) {
        renderedPages++;
        final PdfScanPageRender? render = await pdfScanPageToPng(
          document.pages[index],
          pageNumber: pageNumber,
        );
        if (render != null) {
          final List<PdfPageRegion> regions = _detectRegions(
            render.pngBytes,
            page: pageNumber,
          );
          // Страница только с текстом рендерится в «пустоту»: областей нет —
          // не сохраняем бесполезный рендер.
          if (regions.isNotEmpty) {
            _stage(
              staged: staged,
              digests: digests,
              fileName: fileName,
              bytes: render.pngBytes,
              width: render.width,
              height: render.height,
              page: pageNumber,
              order: 0,
              source: DocumentImageSource.renderedPage,
              rect: null,
              caption: caption,
              context: context,
            );
            _stageRegions(
              staged: staged,
              digests: digests,
              fileName: fileName,
              page: pageNumber,
              regions: regions,
              caption: caption,
              context: context,
            );
          }
        }
      }
    }
    if (staged.length > maxImages) {
      return List<_StagedImage>.unmodifiable(staged.sublist(0, maxImages));
    }
    return List<_StagedImage>.unmodifiable(staged);
  }

  /// Значимые области рендера страницы; ошибки детектора не фатальны.
  List<PdfPageRegion> _detectRegions(Uint8List pngBytes, {required int page}) {
    try {
      return regionDetector.detect(pngBytes, page: page);
    } on Object {
      return const <PdfPageRegion>[];
    }
  }

  /// Добавляет значимые области рендера страницы (без области «вся страница»).
  void _stageRegions({
    required List<_StagedImage> staged,
    required Set<String> digests,
    required String fileName,
    required int page,
    required List<PdfPageRegion> regions,
    required String? caption,
    required String? context,
  }) {
    for (final PdfPageRegion region in regions) {
      if (region.isWholePage) {
        // Одна большая схема уже сохранена полной страницей.
        continue;
      }
      _stage(
        staged: staged,
        digests: digests,
        fileName: fileName,
        bytes: region.pngBytes,
        width: region.pixelWidth,
        height: region.pixelHeight,
        page: page,
        order: region.order,
        source: DocumentImageSource.croppedRegion,
        rect: DocumentImageRect(
          left: region.left,
          top: region.top,
          width: region.width,
          height: region.height,
        ),
        caption: caption,
        context: context,
      );
    }
  }

  /// Кладёт изображение в список, отбрасывая полные повторы по содержимому.
  void _stage({
    required List<_StagedImage> staged,
    required Set<String> digests,
    required String fileName,
    required Uint8List bytes,
    required int width,
    required int height,
    required int page,
    required int order,
    required DocumentImageSource source,
    required DocumentImageRect? rect,
    String? caption,
    String? context,
  }) {
    if (bytes.isEmpty) return;
    if (!digests.add(contentDigest(bytes))) return;
    staged.add(
      _StagedImage(
        DocumentImage(
          fileName: fileName,
          bytes: bytes,
          mediaType: AttachmentMediaType.png,
          page: page,
          width: width,
          height: height,
          source: source,
          rect: rect,
          order: order,
          caption: caption,
          context: context,
        ),
      ),
    );
  }

  /// Координаты PDFium (точки, начало внизу) → доли страницы (начало сверху).
  DocumentImageRect? _normalizedRect({
    required double left,
    required double bottom,
    required double right,
    required double top,
    required double pageWidth,
    required double pageHeight,
  }) {
    if (pageWidth <= 0 || pageHeight <= 0) return null;
    final double normalizedLeft = (left / pageWidth).clamp(0.0, 1.0);
    final double normalizedRight = (right / pageWidth).clamp(0.0, 1.0);
    final double normalizedTop = ((pageHeight - top) / pageHeight).clamp(
      0.0,
      1.0,
    );
    final double normalizedBottom = ((pageHeight - bottom) / pageHeight).clamp(
      0.0,
      1.0,
    );
    final double width = (normalizedRight - normalizedLeft).abs();
    final double height = (normalizedBottom - normalizedTop).abs();
    if (width <= 0 || height <= 0) return null;
    return DocumentImageRect(
      left: normalizedLeft,
      top: normalizedTop,
      width: width,
      height: height,
    );
  }
}

/// Изображение с привязкой к странице до назначения раздела.
class _StagedImage {
  const _StagedImage(this.image);

  final DocumentImage image;
}
