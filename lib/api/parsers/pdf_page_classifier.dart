/// Классификация страниц PDF: текстовая, скан/рисунок или пустая (ADR-037).
///
/// Один PDF может содержать одновременно обычные текстовые страницы и сканы,
/// поэтому тип определяется **для каждой страницы отдельно**, а не только для
/// документа. Чистые функции домена парсеров, без Flutter и без FFI.
library;

/// Минимум символов текстового слоя, чтобы считать страницу текстовой.
///
/// Ниже порога страница считается сканом/рисунком: у сканов часто есть
/// «мусорный» слой из пары символов (номер страницы, водяной знак).
const int kPdfPageTextMinLength = 50;

/// Тип страницы PDF.
enum PdfPageKind {
  /// Страница с осмысленным текстовым слоем.
  textLayer,

  /// Страница без текста: скан или векторный рисунок (нужен рендер).
  scanned,

  /// Пустая страница: ни текста, ни изображений.
  blank,
}

/// Результат классификации одной страницы.
class PdfPageClassification {
  /// Создаёт результат.
  const PdfPageClassification({
    required this.page,
    required this.kind,
    required this.textLength,
    required this.imageCount,
  });

  /// Номер страницы (с 1).
  final int page;

  /// Тип страницы.
  final PdfPageKind kind;

  /// Длина текстового слоя после нормализации (в символах).
  final int textLength;

  /// Количество встроенных изображений на странице.
  final int imageCount;

  /// Есть ли у страницы полноценный текстовый слой.
  bool get hasTextLayer => kind == PdfPageKind.textLayer;

  /// Нужен ли рендер страницы (скан/рисунок без текста).
  bool get needsRendering => kind == PdfPageKind.scanned;

  @override
  String toString() =>
      'PdfPageClassification($page, ${kind.name}, '
      'text: $textLength, images: $imageCount)';
}

/// Классифицирует страницу по тексту и числу изображений.
///
/// [text] — извлечённый текстовый слой (после санитайзера), [imageCount] —
/// сколько Image XObject нашлось на странице.
PdfPageClassification classifyPdfPage({
  required int page,
  required String text,
  int imageCount = 0,
  int minTextLength = kPdfPageTextMinLength,
}) {
  final int textLength = text.trim().length;
  final PdfPageKind kind;
  if (textLength >= minTextLength) {
    kind = PdfPageKind.textLayer;
  } else if (imageCount > 0) {
    kind = PdfPageKind.scanned;
  } else {
    kind = PdfPageKind.blank;
  }
  return PdfPageClassification(
    page: page,
    kind: kind,
    textLength: textLength,
    imageCount: imageCount,
  );
}

/// Классифицирует все страницы документа.
List<PdfPageClassification> classifyPdfPages({
  required List<String> pageTexts,
  required List<int> imageCounts,
  int minTextLength = kPdfPageTextMinLength,
}) {
  return <PdfPageClassification>[
    for (var index = 0; index < pageTexts.length; index++)
      classifyPdfPage(
        page: index + 1,
        text: pageTexts[index],
        imageCount: index < imageCounts.length ? imageCounts[index] : 0,
        minTextLength: minTextLength,
      ),
  ];
}
