/// Выделение значимых визуальных областей на растре страницы PDF (ADR-037).
///
/// Скан нельзя отдать модели одной картинкой, если на странице несколько
/// самостоятельных схем и графиков (SPEC A8.3, итерация L76). Детектор ищет
/// связные области «чернил», отбрасывает строки текста (их обрабатывает
/// текстовый слой или vision-модель) и вырезает значимые области из **полного**
/// рендера страницы без масштабирования — качество не теряется.
///
/// Чистый Dart (`package:image`), без Flutter, без OCR-движка: распознавание
/// текста выполняет vision-модель на полном рендере страницы (ADR-023/027).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Значимая визуальная область страницы.
class PdfPageRegion {
  /// Создаёт область.
  const PdfPageRegion({
    required this.page,
    required this.order,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.pngBytes,
    required this.isWholePage,
  });

  /// Номер страницы (с 1).
  final int page;

  /// Порядок области на странице (0 — первая по площади/положению).
  final int order;

  /// Отступ слева в долях ширины страницы.
  final double left;

  /// Отступ сверху в долях высоты страницы.
  final double top;

  /// Ширина в долях ширины страницы.
  final double width;

  /// Высота в долях высоты страницы.
  final double height;

  /// Ширина вырезки в пикселях.
  final int pixelWidth;

  /// Высота вырезки в пикселях.
  final int pixelHeight;

  /// PNG-вырезка из полного рендера (без масштабирования).
  final Uint8List pngBytes;

  /// Область покрывает почти всю страницу (одна большая схема).
  final bool isWholePage;

  /// Площадь в долях площади страницы.
  double get areaFraction => width * height;

  @override
  String toString() =>
      'PdfPageRegion(page: $page, order: $order, '
      'l: ${left.toStringAsFixed(3)}, t: ${top.toStringAsFixed(3)}, '
      '${width.toStringAsFixed(3)}×${height.toStringAsFixed(3)}, '
      '${pngBytes.length} байт)';
}

/// Детектор визуальных областей страницы.
class PdfPageRegionDetector {
  /// Создаёт детектор.
  const PdfPageRegionDetector({
    this.maxRegions = 3,
    this.minRegionAreaFraction = 0.015,
    this.wholePageAreaFraction = 0.55,
    this.analysisWidth = 420,
    this.inkThreshold = 200,
    this.textLineMaxHeightFraction = 0.045,
    this.paddingFraction = 0.01,
    this.minComponentCells = 6,
    this.maxAspectRatio = 12,
  });

  /// Максимум областей с одной страницы.
  final int maxRegions;

  /// Минимальная площадь области (доля площади страницы).
  final double minRegionAreaFraction;

  /// С какой доли площади область считается «всей страницей».
  final double wholePageAreaFraction;

  /// Ширина сетки анализа в ячейках.
  final int analysisWidth;

  /// Порог «чернил» по яркости (0..255); темнее — содержимое.
  final int inkThreshold;

  /// Максимальная высота строки текста (доля высоты страницы).
  final double textLineMaxHeightFraction;

  /// Отступ вырезки (доля ширины/высоты страницы).
  final double paddingFraction;

  /// Минимум ячеек в связной области (меньше — шум/точка).
  final int minComponentCells;

  /// Максимальное отношение сторон области (тоньше — линия/разделитель).
  final double maxAspectRatio;

  /// Находит значимые области на PNG-рендере страницы [page].
  ///
  /// Пустой список — на странице нет визуальных объектов (только текст или
  /// пусто). Ошибка декодирования PNG не бросается: пустой список.
  List<PdfPageRegion> detect(Uint8List pagePng, {required int page}) {
    // Принимаем любой декодируемый раст: рендер приходит PNG, встроенный скан
    // после PDFium — тоже PNG, но устойчивость к JPEG не мешает.
    final img.Image? picture = img.decodeImage(pagePng);
    if (picture == null || picture.width < 8 || picture.height < 8) {
      return const <PdfPageRegion>[];
    }
    final int cell = math.max(1, (picture.width / analysisWidth).ceil());
    final int gridWidth = (picture.width / cell).ceil();
    final int gridHeight = (picture.height / cell).ceil();
    final List<bool> ink = _inkGrid(
      picture,
      cellSize: cell,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
    final List<bool> dilated = _dilate(
      ink,
      width: gridWidth,
      height: gridHeight,
    );
    final List<_Box> components = _components(
      dilated,
      width: gridWidth,
      height: gridHeight,
    );
    final List<_Box> merged = _merge(
      components,
      margin: 1,
      limit: gridWidth + gridHeight,
    );
    final int textMaxHeight = math.max(
      2,
      (textLineMaxHeightFraction * gridHeight).round(),
    );
    final double gridArea = gridWidth * gridHeight.toDouble();
    final List<_Box> visual = <_Box>[];
    for (final _Box box in merged) {
      if (box.width <= 0 || box.height <= 0) continue;
      final bool textLike = box.height <= textMaxHeight;
      if (textLike) continue;
      if (box.area / gridArea < minRegionAreaFraction) continue;
      final double aspect =
          math.max(box.width, box.height) / math.min(box.width, box.height);
      if (aspect > maxAspectRatio) continue;
      visual.add(box);
    }
    if (visual.isEmpty) return const <PdfPageRegion>[];
    visual.sort((_Box a, _Box b) => b.area.compareTo(a.area));
    final bool wholePage =
        visual.length == 1 &&
        visual.single.area / gridArea >= wholePageAreaFraction;
    final List<_Box> selected = visual
        .take(wholePage ? 1 : maxRegions)
        .toList();
    // Читальный порядок: сверху вниз, затем слева направо.
    selected.sort((_Box a, _Box b) {
      final int byTop = a.top.compareTo(b.top);
      return byTop != 0 ? byTop : a.left.compareTo(b.left);
    });
    final List<PdfPageRegion> regions = <PdfPageRegion>[];
    for (var index = 0; index < selected.length; index++) {
      final _Box box = selected[index];
      final _Crop? crop = _crop(
        picture,
        box,
        cellSize: cell,
        padX: (paddingFraction * picture.width).round(),
        padY: (paddingFraction * picture.height).round(),
      );
      if (crop == null) continue;
      regions.add(
        PdfPageRegion(
          page: page,
          order: index,
          left: box.left / gridWidth,
          top: box.top / gridHeight,
          width: box.width / gridWidth,
          height: box.height / gridHeight,
          pixelWidth: crop.width,
          pixelHeight: crop.height,
          pngBytes: crop.png,
          isWholePage: wholePage,
        ),
      );
    }
    return List<PdfPageRegion>.unmodifiable(regions);
  }

  /// Сетка «чернил»: ячейка помечена, если в ней есть тёмный пиксель.
  List<bool> _inkGrid(
    img.Image picture, {
    required int cellSize,
    required int gridWidth,
    required int gridHeight,
  }) {
    final Uint8List rgba = picture.getBytes(order: img.ChannelOrder.rgba);
    final int width = picture.width;
    final int height = picture.height;
    final List<bool> ink = List<bool>.filled(gridWidth * gridHeight, false);
    for (var y = 0; y < height; y++) {
      final int row = y * width * 4;
      final int gridRow = (y ~/ cellSize) * gridWidth;
      for (var x = 0; x < width; x++) {
        final int index = row + x * 4;
        final int r = rgba[index];
        final int g = rgba[index + 1];
        final int b = rgba[index + 2];
        final int a = rgba[index + 3];
        // Прозрачный пиксель — фон (страница уже наложена на белый).
        if (a < 16) continue;
        final int luminance = (r * 299 + g * 587 + b * 114) ~/ 1000;
        if (luminance < inkThreshold) {
          final int cellIndex = gridRow + (x ~/ cellSize);
          if (cellIndex >= 0 && cellIndex < ink.length) ink[cellIndex] = true;
        }
      }
    }
    return ink;
  }

  /// Дилатация 3×3: склеивает штрихи схемы в одну область.
  List<bool> _dilate(
    List<bool> ink, {
    required int width,
    required int height,
  }) {
    final List<bool> result = List<bool>.filled(ink.length, false);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!ink[y * width + x]) continue;
        for (var dy = -1; dy <= 1; dy++) {
          final int ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final int nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            result[ny * width + nx] = true;
          }
        }
      }
    }
    return result;
  }

  /// Связные компоненты (4-соседство) по сетке.
  List<_Box> _components(
    List<bool> grid, {
    required int width,
    required int height,
  }) {
    final List<bool> visited = List<bool>.filled(grid.length, false);
    final List<_Box> boxes = <_Box>[];
    final List<int> stack = <int>[];
    for (var start = 0; start < grid.length; start++) {
      if (!grid[start] || visited[start]) continue;
      visited[start] = true;
      stack
        ..clear()
        ..add(start);
      var minX = width;
      var maxX = -1;
      var minY = height;
      var maxY = -1;
      var cells = 0;
      while (stack.isNotEmpty) {
        final int index = stack.removeLast();
        final int x = index % width;
        final int y = index ~/ width;
        cells++;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
        final List<int> neighbours = <int>[
          if (x > 0) index - 1,
          if (x + 1 < width) index + 1,
          if (y > 0) index - width,
          if (y + 1 < height) index + width,
        ];
        for (final int neighbour in neighbours) {
          if (grid[neighbour] && !visited[neighbour]) {
            visited[neighbour] = true;
            stack.add(neighbour);
          }
        }
      }
      if (cells < minComponentCells) continue;
      boxes.add(
        _Box(left: minX, top: minY, right: maxX, bottom: maxY, cells: cells),
      );
    }
    return boxes;
  }

  /// Склеивает пересекающиеся/близкие прямоугольники.
  List<_Box> _merge(
    List<_Box> boxes, {
    required int margin,
    required int limit,
  }) {
    List<_Box> current = List<_Box>.of(boxes);
    var rounds = 0;
    while (rounds++ < limit) {
      var merged = false;
      final List<_Box> result = <_Box>[];
      for (final _Box box in current) {
        var placed = false;
        for (var index = 0; index < result.length; index++) {
          if (result[index].touches(box, margin)) {
            result[index] = result[index].union(box);
            merged = true;
            placed = true;
            break;
          }
        }
        if (!placed) result.add(box);
      }
      current = result;
      if (!merged) break;
    }
    return current;
  }

  /// Вырезает область из полного растра с отступом (без масштабирования).
  _Crop? _crop(
    img.Image picture,
    _Box box, {
    required int cellSize,
    required int padX,
    required int padY,
  }) {
    final int left = math.max(0, box.left * cellSize - padX);
    final int top = math.max(0, box.top * cellSize - padY);
    final int right = math.min(
      picture.width,
      (box.right + 1) * cellSize + padX,
    );
    final int bottom = math.min(
      picture.height,
      (box.bottom + 1) * cellSize + padY,
    );
    final int width = right - left;
    final int height = bottom - top;
    if (width < 8 || height < 8) return null;
    final img.Image cropped = img.copyCrop(
      picture,
      x: left,
      y: top,
      width: width,
      height: height,
    );
    return _Crop(
      png: Uint8List.fromList(img.encodePng(cropped)),
      width: width,
      height: height,
    );
  }
}

/// Результат вырезки области.
class _Crop {
  const _Crop({required this.png, required this.width, required this.height});

  final Uint8List png;
  final int width;
  final int height;
}

/// Прямоугольник в координатах сетки анализа.
class _Box {
  const _Box({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.cells,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
  final int cells;

  int get width => right - left + 1;

  int get height => bottom - top + 1;

  int get area => width * height;

  /// Пересекаются ли прямоугольники с отступом [margin].
  bool touches(_Box other, int margin) {
    return left - margin <= other.right + margin &&
        right + margin >= other.left - margin &&
        top - margin <= other.bottom + margin &&
        bottom + margin >= other.top - margin;
  }

  /// Объединение прямоугольников.
  _Box union(_Box other) {
    return _Box(
      left: math.min(left, other.left),
      top: math.min(top, other.top),
      right: math.max(right, other.right),
      bottom: math.max(bottom, other.bottom),
      cells: cells + other.cells,
    );
  }

  @override
  String toString() => '_Box($left,$top)-($right,$bottom)';
}
