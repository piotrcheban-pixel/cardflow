/// Извлечение встроенных изображений PDF через PDFium (итерация L76, ADR-037).
///
/// Обычный PDF хранит рисунки, схемы и фотографии как Image XObject, в том
/// числе внутри Form XObject. `pdfrx` умеет только текст и рендер страниц,
/// поэтому изображения извлекаются низкоуровневыми биндингами `pdfium_dart`
/// (тот же модуль PDFium, что грузит `pdfrx`: `pdfrx → pdfium_flutter →
/// pdfium_dart 0.4.1`). Отдельного нативного стека нет.
///
/// **Изолят.** PDFium не потокобезопасен, а `pdfrx` вызывает его в своём
/// фоновом воркер-изоляте. FFI-вызовы `pdfium_dart` из другого изолята падают
/// (`Cannot invoke native callback from a different isolate`), поэтому вся
/// работа выполняется в воркер-изоляте `pdfrx` через
/// `PdfrxEntryFunctions.instance.compute` — сериализованно с остальными
/// вызовами PDFium. Экспериментально подтверждено спайком итерации.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfrx/pdfrx.dart';

/// Минимальная сторона встроенного изображения, которую вообще извлекаем.
///
/// Не является фильтром «мусора»: небольшие формулы и фрагменты схем важны.
/// Окончательное решение принимает [DocumentImageFilter] с учётом текста
/// страницы (ADR-037).
const int kMinPdfImageSide = 32;

/// Максимум изображений из одного PDF (защита от «1000 иконок»).
const int kMaxPdfImages = 60;

/// Максимум пикселей растра одного изображения (W×H); больше — пропускаем.
const int kMaxPdfBitmapPixels = 16000000;

/// Максимальная сторона сохраняемого PNG: больше — уменьшаем без потери
/// пропорций (vision-модели всё равно ужимают изображение).
const int kMaxPdfImageOutputSide = 2600;

/// Отпечаток изображения на странице PDF.
///
/// Координаты — в точках PDF (начало в левом нижнем углу страницы), ширина и
/// высота — размеры страницы в точках. Парсер переводит их в доли страницы.
class PdfEmbeddedImage {
  /// Создаёт отпечаток.
  const PdfEmbeddedImage({
    required this.page,
    required this.order,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.pngBytes,
    required this.pageWidth,
    required this.pageHeight,
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
    this.inForm = false,
    this.bitsPerPixel = 0,
    this.colorspace = 0,
  });

  /// Номер страницы (с 1).
  final int page;

  /// Порядок отрисовки на странице (0 — первый объект).
  final int order;

  /// Ширина исходного изображения в пикселях (до масштабирования в PDF).
  final int pixelWidth;

  /// Высота исходного изображения в пикселях.
  final int pixelHeight;

  /// PNG-содержимое (BGRA → RGB, альфа наложена на белый фон).
  final Uint8List pngBytes;

  /// Ширина страницы в точках PDF.
  final double pageWidth;

  /// Высота страницы в точках PDF.
  final double pageHeight;

  /// Левая граница области на странице (точки PDF).
  final double left;

  /// Нижняя граница области на странице (точки PDF).
  final double bottom;

  /// Правая граница области на странице (точки PDF).
  final double right;

  /// Верхняя граница области на странице (точки PDF).
  final double top;

  /// Изображение лежало внутри Form XObject (вложенный ресурс).
  final bool inForm;

  /// Биты на пиксель исходного изображения (метаданные PDFium).
  final int bitsPerPixel;

  /// Цветовое пространство PDFium (`FPDF_COLORSPACE_*`).
  final int colorspace;

  /// Ширина области на странице в точках.
  double get displayWidth => right - left;

  /// Высота области на странице в точках.
  double get displayHeight => top - bottom;

  /// Доля площади страницы, занятая изображением (0..1).
  double get pageAreaFraction {
    if (pageWidth <= 0 || pageHeight <= 0) return 0;
    return (displayWidth * displayHeight) / (pageWidth * pageHeight);
  }

  /// Покрывает ли изображение почти всю страницу (скан).
  bool coversPage([double threshold = 0.85]) => pageAreaFraction >= threshold;

  @override
  String toString() =>
      'PdfEmbeddedImage(page: $page, order: $order, '
      '$pixelWidth×$pixelHeight, ${pngBytes.length} байт)';
}

/// Запрос на извлечение (передаётся в воркер-изолят pdfrx).
class PdfImageExtractionRequest {
  /// Создаёт запрос.
  const PdfImageExtractionRequest({
    required this.bytes,
    this.maxImages = kMaxPdfImages,
    this.minSide = kMinPdfImageSide,
  });

  /// Байты PDF.
  final Uint8List bytes;

  /// Максимум изображений.
  final int maxImages;

  /// Минимальная сторона изображения в пикселях.
  final int minSide;
}

/// Результат извлечения (передаётся из воркер-изолята pdfrx).
class PdfImageExtractionResult {
  /// Создаёт результат.
  const PdfImageExtractionResult({
    required this.images,
    required this.pageCount,
    required this.pageWidths,
    required this.pageHeights,
  });

  /// Извлечённые изображения в порядке страниц.
  final List<PdfEmbeddedImage> images;

  /// Количество страниц документа.
  final int pageCount;

  /// Ширины страниц в точках PDF (по индексу страницы).
  final List<double> pageWidths;

  /// Высоты страниц в точках PDF (по индексу страницы).
  final List<double> pageHeights;

  /// Размер страницы [page] (с 1) в точках; `null` — нет такой страницы.
  ({double width, double height})? pageSize(int page) {
    final int index = page - 1;
    if (index < 0 || index >= pageWidths.length) return null;
    return (width: pageWidths[index], height: pageHeights[index]);
  }
}

/// Извлекает встроенные изображения PDF (Image XObject, включая Form XObject).
class PdfImageExtractor {
  /// Создаёт извлекатель.
  const PdfImageExtractor({
    this.maxImages = kMaxPdfImages,
    this.minSide = kMinPdfImageSide,
  });

  /// Максимум изображений из одного PDF.
  final int maxImages;

  /// Минимальная сторона изображения в пикселях.
  final int minSide;

  /// Возвращает изображения или `null`, если извлечение недоступно/упало.
  ///
  /// `null` — не ошибка файла: текст документа уже извлечён, изображения
  /// просто отсутствуют (частичный успех, ADR-037).
  Future<PdfImageExtractionResult?> extract(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    try {
      await pdfrxInitialize();
    } on Object {
      return null;
    }
    try {
      return await PdfrxEntryFunctions.instance
          .compute<PdfImageExtractionRequest, PdfImageExtractionResult>(
            extractPdfImagesInWorker,
            PdfImageExtractionRequest(
              bytes: bytes,
              maxImages: maxImages,
              minSide: minSide,
            ),
          );
    } on Object {
      return null;
    }
  }
}

/// Работа извлечения в воркер-изоляте PDFium (вызывается через `compute`).
///
/// Обязана быть функцией верхнего уровня: ссылка передаётся между изолятами.
PdfImageExtractionResult extractPdfImagesInWorker(
  PdfImageExtractionRequest request,
) {
  final pdfium.PDFium library = pdfium.getPdfium(
    modulePath: Pdfrx.pdfiumModulePath,
  );
  final Pointer<Uint8> data = calloc<Uint8>(request.bytes.length);
  data.asTypedList(request.bytes.length).setAll(0, request.bytes);
  final List<PdfEmbeddedImage> images = <PdfEmbeddedImage>[];
  final List<double> widths = <double>[];
  final List<double> heights = <double>[];
  try {
    final pdfium.FPDF_DOCUMENT document = library.FPDF_LoadMemDocument64(
      data.cast(),
      request.bytes.length,
      nullptr,
    );
    if (document.address == 0) {
      return const PdfImageExtractionResult(
        images: <PdfEmbeddedImage>[],
        pageCount: 0,
        pageWidths: <double>[],
        pageHeights: <double>[],
      );
    }
    try {
      final int pageCount = library.FPDF_GetPageCount(document);
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        if (images.length >= request.maxImages) break;
        final pdfium.FPDF_PAGE page = library.FPDF_LoadPage(
          document,
          pageIndex,
        );
        if (page.address == 0) {
          widths.add(0);
          heights.add(0);
          continue;
        }
        try {
          final double pageWidth = library.FPDF_GetPageWidth(page);
          final double pageHeight = library.FPDF_GetPageHeight(page);
          widths.add(pageWidth);
          heights.add(pageHeight);
          final int count = library.FPDFPage_CountObjects(page);
          var imageOrder = 0;
          for (var index = 0; index < count; index++) {
            if (images.length >= request.maxImages) break;
            final pdfium.FPDF_PAGEOBJECT object = library.FPDFPage_GetObject(
              page,
              index,
            );
            if (object.address == 0) continue;
            imageOrder = _collectPageObject(
              library: library,
              document: document,
              page: page,
              object: object,
              pageIndex: pageIndex,
              pageWidth: pageWidth,
              pageHeight: pageHeight,
              parentMatrix: const _Matrix.identity(),
              inForm: false,
              order: imageOrder,
              request: request,
              images: images,
            );
          }
        } on Object {
          widths.add(0);
          heights.add(0);
        } finally {
          library.FPDF_ClosePage(page);
        }
      }
    } finally {
      library.FPDF_CloseDocument(document);
    }
  } finally {
    calloc.free(data);
  }
  return PdfImageExtractionResult(
    images: List<PdfEmbeddedImage>.unmodifiable(images),
    pageCount: widths.length,
    pageWidths: List<double>.unmodifiable(widths),
    pageHeights: List<double>.unmodifiable(heights),
  );
}

/// Обходит объект страницы: изображение → растр, форма → рекурсия.
///
/// Возвращает следующий порядковый номер изображения на странице.
int _collectPageObject({
  required pdfium.PDFium library,
  required pdfium.FPDF_DOCUMENT document,
  required pdfium.FPDF_PAGE page,
  required pdfium.FPDF_PAGEOBJECT object,
  required int pageIndex,
  required double pageWidth,
  required double pageHeight,
  required _Matrix parentMatrix,
  required bool inForm,
  required int order,
  required PdfImageExtractionRequest request,
  required List<PdfEmbeddedImage> images,
}) {
  final int type = library.FPDFPageObj_GetType(object);
  if (type == pdfium.FPDF_PAGEOBJ_FORM) {
    final _Matrix? matrix = _objectMatrix(library, object);
    final _Matrix composed = matrix == null
        ? parentMatrix
        : parentMatrix.multiply(matrix);
    final int inner = library.FPDFFormObj_CountObjects(object);
    var next = order;
    for (var index = 0; index < inner; index++) {
      final pdfium.FPDF_PAGEOBJECT nested = library.FPDFFormObj_GetObject(
        object,
        index,
      );
      if (nested.address == 0) continue;
      next = _collectPageObject(
        library: library,
        document: document,
        page: page,
        object: nested,
        pageIndex: pageIndex,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        parentMatrix: composed,
        inForm: true,
        order: next,
        request: request,
        images: images,
      );
    }
    return next;
  }
  if (type != pdfium.FPDF_PAGEOBJ_IMAGE) return order;
  final PdfEmbeddedImage? image = _readImage(
    library: library,
    document: document,
    page: page,
    object: object,
    pageIndex: pageIndex,
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    parentMatrix: parentMatrix,
    inForm: inForm,
    order: order,
    request: request,
  );
  if (image == null) return order;
  images.add(image);
  return order + 1;
}

/// Извлекает одно изображение; `null` — объект не подходит/ошибка чтения.
PdfEmbeddedImage? _readImage({
  required pdfium.PDFium library,
  required pdfium.FPDF_DOCUMENT document,
  required pdfium.FPDF_PAGE page,
  required pdfium.FPDF_PAGEOBJECT object,
  required int pageIndex,
  required double pageWidth,
  required double pageHeight,
  required _Matrix parentMatrix,
  required bool inForm,
  required int order,
  required PdfImageExtractionRequest request,
}) {
  final Pointer<pdfium.FPDF_IMAGEOBJ_METADATA> metadata =
      calloc<pdfium.FPDF_IMAGEOBJ_METADATA>();
  final Pointer<Float> left = calloc<Float>();
  final Pointer<Float> top = calloc<Float>();
  final Pointer<Float> right = calloc<Float>();
  final Pointer<Float> bottom = calloc<Float>();
  pdfium.FPDF_BITMAP bitmap = nullptr;
  try {
    final int metadataOk = library.FPDFImageObj_GetImageMetadata(
      object,
      page,
      metadata,
    );
    final int boundsOk = library.FPDFPageObj_GetBounds(
      object,
      left,
      top,
      right,
      bottom,
    );
    if (boundsOk == 0) return null;
    final int pixelWidth = metadataOk == 0 ? 0 : metadata.ref.width;
    final int pixelHeight = metadataOk == 0 ? 0 : metadata.ref.height;
    if (metadataOk != 0 &&
        (pixelWidth < request.minSide || pixelHeight < request.minSide)) {
      // Иконки и тонкие разделители пропускаем уже здесь; значимые мелкие
      // формулы сохранит фильтр с контекстом страницы.
      return null;
    }
    if (metadataOk != 0 && pixelWidth * pixelHeight > kMaxPdfBitmapPixels) {
      return null;
    }
    final _Rect pageRect = parentMatrix.transformRect(
      _Rect(
        left: left.value,
        bottom: bottom.value,
        right: right.value,
        top: top.value,
      ),
    );
    // Основной путь — рендер области страницы в исходном разрешении
    // изображения (не в размере на странице): качество не теряется.
    Uint8List? png;
    if (pixelWidth > 0 && pixelHeight > 0) {
      png = _renderRegionPng(
        library: library,
        page: page,
        rect: pageRect,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
      );
    }
    if (png == null) {
      // Резерв: растр PDFium в размере отображения (хуже по разрешению, но
      // корректно обрабатывает цветовые пространства и маски).
      bitmap = library.FPDFImageObj_GetRenderedBitmap(document, page, object);
      if (bitmap.address == 0) return null;
      png = _bitmapToPng(library, bitmap);
    }
    if (png == null) return null;
    return PdfEmbeddedImage(
      page: pageIndex + 1,
      order: order,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      pngBytes: png,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      left: pageRect.left,
      bottom: pageRect.bottom,
      right: pageRect.right,
      top: pageRect.top,
      inForm: inForm,
      bitsPerPixel: metadataOk == 0 ? 0 : metadata.ref.bits_per_pixel,
      colorspace: metadataOk == 0 ? 0 : metadata.ref.colorspace,
    );
  } on Object {
    return null;
  } finally {
    if (bitmap.address != 0) {
      library.FPDFBitmap_Destroy(bitmap);
    }
    calloc
      ..free(metadata)
      ..free(left)
      ..free(top)
      ..free(right)
      ..free(bottom);
  }
}

/// Рендерит область страницы в исходном разрешении изображения.
///
/// `FPDFImageObj_GetRenderedBitmap` отдаёт картинку в размере на странице
/// (например, скан 1224×1584 при 612×792 pt — как 612×792). Здесь PDFium
/// растеризует **область страницы** с масштабом «пиксели изображения / размер
/// на странице»: цветовые пространства, маски и прозрачность обрабатывает
/// сам PDFium, а качество не теряется.
Uint8List? _renderRegionPng({
  required pdfium.PDFium library,
  required pdfium.FPDF_PAGE page,
  required _Rect rect,
  required int pixelWidth,
  required int pixelHeight,
  required double pageWidth,
  required double pageHeight,
}) {
  final double displayWidth = rect.right - rect.left;
  final double displayHeight = rect.top - rect.bottom;
  if (displayWidth <= 0 || displayHeight <= 0) return null;
  var scale = math.min(pixelWidth / displayWidth, pixelHeight / displayHeight);
  if (!scale.isFinite || scale <= 0) return null;
  final double pageArea = pageWidth * pageHeight;
  if (pageArea <= 0) return null;
  // Защита от гигантских масштабов: ограничиваем общий растр страницы.
  final double maxScale = math.sqrt(kMaxPdfBitmapPixels / pageArea);
  if (scale > maxScale) scale = maxScale;
  final int fullWidth = math.max(1, (pageWidth * scale).ceil());
  final int fullHeight = math.max(1, (pageHeight * scale).ceil());
  final int x = math.max(0, (rect.left * scale).floor());
  final int y = math.max(0, ((pageHeight - rect.top) * scale).floor());
  final int width = math.max(1, (displayWidth * scale).round());
  final int height = math.max(1, (displayHeight * scale).round());
  if (width * height > kMaxPdfBitmapPixels) return null;
  final pdfium.FPDF_BITMAP bitmap = library.FPDFBitmap_Create(width, height, 1);
  if (bitmap.address == 0) return null;
  try {
    // Белый фон: прозрачность/маски накладываются на содержимое страницы.
    library.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
    library.FPDF_RenderPageBitmap(
      bitmap,
      page,
      -x,
      -y,
      fullWidth,
      fullHeight,
      0,
      0,
    );
    return _bitmapToPng(library, bitmap);
  } on Object {
    return null;
  } finally {
    library.FPDFBitmap_Destroy(bitmap);
  }
}

/// Читает растр PDFium в PNG: BGRA → RGB, альфа на белом фоне.
Uint8List? _bitmapToPng(pdfium.PDFium library, pdfium.FPDF_BITMAP bitmap) {
  final int width = library.FPDFBitmap_GetWidth(bitmap);
  final int height = library.FPDFBitmap_GetHeight(bitmap);
  if (width <= 0 || height <= 0) return null;
  if (width * height > kMaxPdfBitmapPixels) return null;
  final int stride = library.FPDFBitmap_GetStride(bitmap);
  final int format = library.FPDFBitmap_GetFormat(bitmap);
  final Pointer<Void> buffer = library.FPDFBitmap_GetBuffer(bitmap);
  if (buffer.address == 0 || stride <= 0) return null;
  final Uint8List pixels = buffer.cast<Uint8>().asTypedList(stride * height);
  final bool alpha =
      format == pdfium.FPDFBitmap_BGRA ||
      format == pdfium.FPDFBitmap_BGRA_Premul;
  final bool premultiplied = format == pdfium.FPDFBitmap_BGRA_Premul;
  final Uint8List rgb = Uint8List(width * height * 3);
  var out = 0;
  for (var y = 0; y < height; y++) {
    final int row = y * stride;
    for (var x = 0; x < width; x++) {
      final int offset = row + x * 4;
      int b = pixels[offset];
      int g = pixels[offset + 1];
      int r = pixels[offset + 2];
      final int a = pixels[offset + 3];
      if (alpha && a < 255) {
        if (premultiplied) {
          // Предумноженная альфа: доводим до белого фона.
          r = r + (255 - a);
          g = g + (255 - a);
          b = b + (255 - a);
        } else {
          r = (r * a + 255 * (255 - a)) ~/ 255;
          g = (g * a + 255 * (255 - a)) ~/ 255;
          b = (b * a + 255 * (255 - a)) ~/ 255;
        }
      }
      rgb[out++] = r > 255 ? 255 : r;
      rgb[out++] = g > 255 ? 255 : g;
      rgb[out++] = b > 255 ? 255 : b;
    }
  }
  img.Image picture = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  final int longest = math.max(width, height);
  if (longest > kMaxPdfImageOutputSide) {
    final double scale = kMaxPdfImageOutputSide / longest;
    picture = img.copyResize(
      picture,
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
      interpolation: img.Interpolation.linear,
    );
  }
  return Uint8List.fromList(img.encodePng(picture));
}

/// Матрица преобразования PDF (a, b, c, d, e, f).
class _Matrix {
  /// Создаёт матрицу.
  const _Matrix(this.a, this.b, this.c, this.d, this.e, this.f);

  /// Единичная матрица.
  const _Matrix.identity() : a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  /// Умножение: результат применяет [other], затем текущую матрицу.
  _Matrix multiply(_Matrix other) {
    return _Matrix(
      a * other.a + c * other.b,
      b * other.a + d * other.b,
      a * other.c + c * other.d,
      b * other.c + d * other.d,
      a * other.e + c * other.f + e,
      b * other.e + d * other.f + f,
    );
  }

  ({double x, double y}) apply(double x, double y) =>
      (x: a * x + c * y + e, y: b * x + d * y + f);

  /// Преобразует прямоугольник и возвращает его в точках PDF.
  _Rect transformRect(_Rect rect) {
    final Iterable<({double x, double y})> corners = <({double x, double y})>[
      apply(rect.left, rect.bottom),
      apply(rect.right, rect.bottom),
      apply(rect.left, rect.top),
      apply(rect.right, rect.top),
    ];
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final corner in corners) {
      minX = math.min(minX, corner.x);
      maxX = math.max(maxX, corner.x);
      minY = math.min(minY, corner.y);
      maxY = math.max(maxY, corner.y);
    }
    return _Rect(left: minX, bottom: minY, right: maxX, top: maxY);
  }
}

/// Прямоугольник в точках PDF.
class _Rect {
  const _Rect({
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
  });

  final double left;
  final double bottom;
  final double right;
  final double top;
}

/// Матрица объекта страницы (позиция формы в системе родителя).
_Matrix? _objectMatrix(pdfium.PDFium library, pdfium.FPDF_PAGEOBJECT object) {
  final Pointer<pdfium.FS_MATRIX> matrix = calloc<pdfium.FS_MATRIX>();
  try {
    if (library.FPDFPageObj_GetMatrix(object, matrix) == 0) return null;
    final pdfium.FS_MATRIX value = matrix.ref;
    return _Matrix(value.a, value.b, value.c, value.d, value.e, value.f);
  } on Object {
    return null;
  } finally {
    calloc.free(matrix);
  }
}
