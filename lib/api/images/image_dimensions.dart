/// Размеры изображения по заголовку файла (итерация 7.14).
///
/// Фильтр поиска картинок проверяет минимальную короткую сторону (400 px) и
/// соотношение сторон (1:3 … 3:1) до записи в `MediaStore`. Декодировать всё
/// изображение ради двух чисел дорого, поэтому формат читается из заголовков
/// JPEG/PNG/WebP. Неизвестный/битый файл → `null` (кандидат пропускается).
library;

/// Ширина и высота изображения.
class ImageDimensions {
  /// Создаёт размеры.
  const ImageDimensions(this.width, this.height);

  /// Ширина, px.
  final int width;

  /// Высота, px.
  final int height;

  /// Короткая сторона.
  int get shortSide => width < height ? width : height;

  /// Длинная сторона.
  int get longSide => width < height ? height : width;

  /// Соотношение длинной стороны к короткой (≥ 1).
  double get aspectRatio => longSide / (shortSide == 0 ? 1 : shortSide);

  /// Минимальная короткая сторона для иллюстрации карточки.
  static const int minShortSide = 400;

  /// Максимальное соотношение сторон (1:3 … 3:1).
  static const double maxAspectRatio = 3;

  /// Подходит ли изображение для карточки по размеру и пропорциям.
  bool get isUsable =>
      shortSide >= minShortSide && aspectRatio <= maxAspectRatio;

  /// Разбирает заголовок [bytes]; `null` — формат неизвестен или данные битые.
  static ImageDimensions? read(List<int> bytes) {
    final ImageDimensions? png = _png(bytes);
    if (png != null) return png;
    final ImageDimensions? jpeg = _jpeg(bytes);
    if (jpeg != null) return jpeg;
    return _webp(bytes);
  }

  @override
  String toString() => 'ImageDimensions(${width}x$height)';
}

/// PNG: сигнатура, затем IHDR с шириной/высотой (big-endian).
ImageDimensions? _png(List<int> bytes) {
  const List<int> signature = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];
  if (bytes.length < 24) return null;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return null;
  }
  if (bytes[12] != 0x49 ||
      bytes[13] != 0x48 ||
      bytes[14] != 0x44 ||
      bytes[15] != 0x52) {
    return null;
  }
  final int width = _u32be(bytes, 16);
  final int height = _u32be(bytes, 20);
  if (width <= 0 || height <= 0) return null;
  return ImageDimensions(width, height);
}

/// JPEG: ищем маркер SOFn (кроме DHT/DAC/DRI) и читаем высоту/ширину.
ImageDimensions? _jpeg(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var offset = 2;
  while (offset + 8 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    var marker = bytes[offset + 1];
    // Заполнители 0xFF могут повторяться.
    while (marker == 0xFF && offset + 2 < bytes.length) {
      offset++;
      marker = bytes[offset + 1];
    }
    // Маркеры без длины.
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) return null;
    if (offset + 4 > bytes.length) return null;
    final int length = _u16be(bytes, offset + 2);
    if (length < 2 || offset + 2 + length > bytes.length) return null;
    // SOF0–SOF15, кроме DHT(0xC4), JPG(0xC8), DAC(0xCC).
    final bool isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      if (offset + 9 > bytes.length) return null;
      final int height = _u16be(bytes, offset + 5);
      final int width = _u16be(bytes, offset + 7);
      if (width <= 0 || height <= 0) return null;
      return ImageDimensions(width, height);
    }
    offset += 2 + length;
  }
  return null;
}

/// WebP: RIFF-контейнер; размеры в VP8 (lossy), VP8L (lossless) или VP8X.
ImageDimensions? _webp(List<int> bytes) {
  if (bytes.length < 30) return null;
  if (bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46) {
    return null;
  }
  if (bytes[8] != 0x57 ||
      bytes[9] != 0x45 ||
      bytes[10] != 0x42 ||
      bytes[11] != 0x50) {
    return null;
  }
  final String chunk = String.fromCharCodes(bytes.sublist(12, 16));
  switch (chunk) {
    case 'VP8 ':
      // Кадровый заголовок: 3 байта тега + 3 байта синхронизации 0x9D012A.
      if (bytes.length < 30) return null;
      final int start = 20; // RIFF(12) + chunk size(4) + frame tag(4)
      if (bytes[start] != 0x9D ||
          bytes[start + 1] != 0x01 ||
          bytes[start + 2] != 0x2A) {
        return null;
      }
      final int width = (bytes[start + 3] | (bytes[start + 4] << 8)) & 0x3FFF;
      final int height = (bytes[start + 5] | (bytes[start + 6] << 8)) & 0x3FFF;
      if (width <= 0 || height <= 0) return null;
      return ImageDimensions(width, height);
    case 'VP8L':
      // Signature 0x2F, затем 14 бит ширины-1 и 14 бит высоты-1.
      if (bytes[20] != 0x2F) return null;
      final int bits =
          bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
      final int width = (bits & 0x3FFF) + 1;
      final int height = ((bits >> 14) & 0x3FFF) + 1;
      return ImageDimensions(width, height);
    case 'VP8X':
      // Canvas: 24 бита ширины-1 и 24 бита высоты-1 (little-endian).
      final int width = _u24le(bytes, 24) + 1;
      final int height = _u24le(bytes, 27) + 1;
      return ImageDimensions(width, height);
  }
  return null;
}

int _u16be(List<int> bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

int _u32be(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _u24le(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
