/// Детерминированная локальная заглушка карточки (итерация 7.14, шаг 3).
///
/// Когда картинку не удалось найти или скачать, карточка не остаётся пустой:
/// рисуется градиент с геометрическим паттерном и иконкой по виду иллюстрации.
/// Заглушка детерминирована от seed (хэша карточки): одна и та же карточка
/// всегда получает одни и те же байты. Палитры подобраны так, чтобы выглядеть
/// и в светлой, и в тёмной теме. Flutter не нужен — только `image`.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Пара цветов градиента заглушки (8 вариантов, mid-tone: читаемы в обеих темах).
const List<(int, int, int, int, int, int)> kPlaceholderPalettes =
    <(int, int, int, int, int, int)>[
      // indigo → teal
      (63, 81, 181, 0, 150, 136),
      // deep orange → amber
      (230, 74, 25, 255, 179, 0),
      // purple → pink
      (123, 31, 162, 216, 27, 96),
      // blue → cyan
      (25, 118, 210, 0, 172, 193),
      // green → lime
      (46, 125, 50, 156, 204, 101),
      // brown → sand
      (109, 76, 65, 215, 204, 200),
      // slate → blue grey
      (69, 90, 100, 144, 164, 174),
      // magenta → violet
      (194, 24, 91, 94, 53, 177),
    ];

/// Размер заглушки: 16:9 для фото/метафоры, 4:3 для схемы.
const int kPlaceholderWidth = 800;

/// Генератор заглушек без сети и Flutter.
class PlaceholderImageGenerator {
  /// Создаёт генератор.
  const PlaceholderImageGenerator();

  /// Рисует заглушку для карточки с [seed] и видом [kind].
  ///
  /// [query] — запрос модели, который не дал результата (для «найти заново»);
  /// [fallbackQuery] — запасной запрос модели.
  GeneratedCardImage generate({
    required String seed,
    GeneratedCardImageKind kind = GeneratedCardImageKind.photo,
    String? query,
    String? fallbackQuery,
  }) {
    final int hash = _fnv1a(seed);
    final int height = kind == GeneratedCardImageKind.diagram ? 600 : 450;
    final img.Image image = img.Image(
      width: kPlaceholderWidth,
      height: height,
      numChannels: 3,
    );
    final (int, int, int, int, int, int) palette =
        kPlaceholderPalettes[hash % kPlaceholderPalettes.length];
    _paintGradient(image, palette);
    _paintPattern(image, hash, palette);
    _paintKindIcon(image, kind, hash, palette);
    return GeneratedCardImage(
      bytes: Uint8List.fromList(img.encodePng(image, level: 6)),
      mediaType: AttachmentMediaType.png,
      query: query ?? '',
      kind: kind,
      fallbackQuery: fallbackQuery,
      provider: 'placeholder',
      isPlaceholder: true,
    );
  }

  /// Диагональный градиент из первой палитры во вторую.
  void _paintGradient(img.Image image, (int, int, int, int, int, int) palette) {
    final int width = image.width;
    final int height = image.height;
    final int maxSum = width + height - 2;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Два направления: диагональ + мягкая вертикальная составляющая.
        final double t = ((x + y) / maxSum * 0.7 + y / height * 0.3).clamp(
          0.0,
          1.0,
        );
        image.setPixelRgb(
          x,
          y,
          _mix(palette.$1, palette.$4, t),
          _mix(palette.$2, palette.$5, t),
          _mix(palette.$3, palette.$6, t),
        );
      }
    }
  }

  /// Геометрический паттерн: крупные круги и полосы, позиции от хэша.
  void _paintPattern(
    img.Image image,
    int hash,
    (int, int, int, int, int, int) palette,
  ) {
    final int width = image.width;
    final int height = image.height;
    final (int, int, int) light = _shade(palette, 0.55);
    final (int, int, int) dark = _shade(palette, -0.35);
    final int circleCount = 2 + (hash >> 5) % 2;
    for (var index = 0; index < circleCount; index++) {
      final int cx = 80 + ((hash >> (index * 7 + 3)) % (width - 160));
      final int cy = 60 + ((hash >> (index * 5 + 1)) % (height - 120));
      final int radius = 90 + ((hash >> (index * 3 + 2)) % 140);
      _fillCircle(image, cx, cy, radius, index.isEven ? light : dark);
    }
    // Две диагональные полосы для «движения» композиции.
    final int stripe = 14 + hash % 18;
    for (var y = 0; y < height; y++) {
      final int start = (y * 2 + hash % 120) % width;
      _fillRect(image, start, y, start + stripe, y, light, alpha: 0.35);
    }
  }

  /// Иконка вида иллюстрации: схема — оси и столбики, фото — солнце и горизонт,
  /// метафора — наложенные фигуры.
  void _paintKindIcon(
    img.Image image,
    GeneratedCardImageKind kind,
    int hash,
    (int, int, int, int, int, int) palette,
  ) {
    final int width = image.width;
    final int height = image.height;
    final (int, int, int) accent = _shade(palette, 0.85);
    final int cx = width ~/ 2;
    final int cy = height ~/ 2;
    switch (kind) {
      case GeneratedCardImageKind.diagram:
        // Оси.
        _fillRect(image, cx - 170, cy + 90, cx + 170, cy + 98, accent);
        _fillRect(image, cx - 178, cy - 100, cx - 170, cy + 98, accent);
        // Три столбика.
        _fillRect(image, cx - 120, cy + 8, cx - 70, cy + 90, accent);
        _fillRect(image, cx - 30, cy - 40, cx + 20, cy + 90, accent);
        _fillRect(image, cx + 60, cy - 90, cx + 110, cy + 90, accent);
      case GeneratedCardImageKind.photo:
        // Солнце и линия горизонта.
        _fillCircle(image, cx + 90, cy - 60, 42, accent);
        _fillRect(image, cx - 200, cy + 90, cx + 200, cy + 98, accent);
        // «Горы» — наложенные треугольники.
        _fillTriangle(
          image,
          cx - 200,
          cy + 90,
          cx - 40,
          cy - 80,
          cx + 120,
          cy + 90,
          accent,
        );
        _fillTriangle(
          image,
          cx - 40,
          cy + 90,
          cx + 100,
          cy - 30,
          cx + 240,
          cy + 90,
          accent,
          alpha: 0.6,
        );
      case GeneratedCardImageKind.illustration:
        // Наложенные фигуры: круг, квадрат, треугольник.
        _fillCircle(image, cx - 60, cy - 20, 90, accent, alpha: 0.55);
        _fillRect(
          image,
          cx - 10,
          cy - 80,
          cx + 150,
          cy + 80,
          accent,
          alpha: 0.45,
        );
        _fillTriangle(
          image,
          cx - 180,
          cy + 110,
          cx - 60,
          cy - 110,
          cx + 60,
          cy + 110,
          accent,
          alpha: 0.6,
        );
    }
    // Тонкая рамка, чтобы заглушка читалась как изображение.
    final (int, int, int) border = _shade(palette, 0.25);
    for (var i = 0; i < 6; i++) {
      _fillRect(image, i, i, width - 1 - i, i, border);
      _fillRect(
        image,
        i,
        height - 1 - i,
        width - 1 - i,
        height - 1 - i,
        border,
      );
      _fillRect(image, i, i, i, height - 1 - i, border);
      _fillRect(image, width - 1 - i, i, width - 1 - i, height - 1 - i, border);
    }
  }

  static int _mix(int from, int to, double t) =>
      (from + (to - from) * t).round().clamp(0, 255);

  /// Светлее/темнее пара цветов: [factor] > 0 — к белому, < 0 — к чёрному.
  static (int, int, int) _shade(
    (int, int, int, int, int, int) palette,
    double factor,
  ) {
    final int r = palette.$1;
    final int g = palette.$2;
    final int b = palette.$3;
    if (factor >= 0) {
      return (_mix(r, 255, factor), _mix(g, 255, factor), _mix(b, 255, factor));
    }
    final double k = -factor;
    return (_mix(r, 0, k), _mix(g, 0, k), _mix(b, 0, k));
  }

  /// Заливает прямоугольник [x1,y1]–[x2,y2] цветом с прозрачностью [alpha].
  void _fillRect(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    (int, int, int) color, {
    double alpha = 1,
  }) {
    final int left = x1 < x2 ? x1 : x2;
    final int right = x1 < x2 ? x2 : x1;
    final int top = y1 < y2 ? y1 : y2;
    final int bottom = y1 < y2 ? y2 : y1;
    for (var y = top.clamp(0, image.height - 1); y <= bottom; y++) {
      for (var x = left.clamp(0, image.width - 1); x <= right; x++) {
        _blendPixel(image, x, y, color, alpha);
      }
    }
  }

  /// Заливает круг [cx,cy] радиуса [radius].
  void _fillCircle(
    img.Image image,
    int cx,
    int cy,
    int radius,
    (int, int, int) color, {
    double alpha = 1,
  }) {
    final int r2 = radius * radius;
    for (var y = cy - radius; y <= cy + radius; y++) {
      if (y < 0 || y >= image.height) continue;
      for (var x = cx - radius; x <= cx + radius; x++) {
        if (x < 0 || x >= image.width) continue;
        final int dx = x - cx;
        final int dy = y - cy;
        if (dx * dx + dy * dy <= r2) {
          _blendPixel(image, x, y, color, alpha);
        }
      }
    }
  }

  /// Заливает треугольник (метод барицентрических координат).
  void _fillTriangle(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    int x3,
    int y3,
    (int, int, int) color, {
    double alpha = 1,
  }) {
    final int minX = [
      x1,
      x2,
      x3,
    ].reduce((a, b) => a < b ? a : b).clamp(0, image.width - 1);
    final int maxX = [
      x1,
      x2,
      x3,
    ].reduce((a, b) => a > b ? a : b).clamp(0, image.width - 1);
    final int minY = [
      y1,
      y2,
      y3,
    ].reduce((a, b) => a < b ? a : b).clamp(0, image.height - 1);
    final int maxY = [
      y1,
      y2,
      y3,
    ].reduce((a, b) => a > b ? a : b).clamp(0, image.height - 1);
    final int denominator = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3);
    if (denominator == 0) return;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final double a =
            ((y2 - y3) * (x - x3) + (x3 - x2) * (y - y3)) / denominator;
        final double b =
            ((y3 - y1) * (x - x3) + (x1 - x3) * (y - y3)) / denominator;
        final double c = 1 - a - b;
        if (a >= 0 && b >= 0 && c >= 0) {
          _blendPixel(image, x, y, color, alpha);
        }
      }
    }
  }

  /// Смешивает пиксель с цветом [color] по прозрачности [alpha].
  void _blendPixel(
    img.Image image,
    int x,
    int y,
    (int, int, int) color,
    double alpha,
  ) {
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) return;
    final img.Pixel pixel = image.getPixel(x, y);
    final int r = pixel.r.toInt();
    final int g = pixel.g.toInt();
    final int b = pixel.b.toInt();
    image.setPixelRgb(
      x,
      y,
      _mix(r, color.$1, alpha),
      _mix(g, color.$2, alpha),
      _mix(b, color.$3, alpha),
    );
  }

  /// FNV-1a 32 бита: стабильный хэш seed между запусками и платформами.
  static int _fnv1a(String seed) {
    var hash = 0x811c9dc5;
    for (final int unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
