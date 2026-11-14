import 'dart:convert';

/// Форма маски Image Occlusion (SPEC A7.8, ADR-017).
enum OcclusionShape {
  rectangle('rectangle'),
  ellipse('ellipse');

  const OcclusionShape(this.wireName);

  final String wireName;

  static OcclusionShape? tryParse(Object? value) {
    for (final shape in values) {
      if (shape.wireName == value) return shape;
    }
    return null;
  }
}

/// Прямоугольная или эллиптическая маска в нормализованных координатах.
class OcclusionMask {
  const OcclusionMask({
    required this.id,
    required this.shape,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String id;
  final OcclusionShape shape;
  final double x;
  final double y;
  final double width;
  final double height;

  bool get isValid {
    final values = <double>[x, y, width, height];
    return id.isNotEmpty &&
        id.trim() == id &&
        values.every((value) => value.isFinite) &&
        x >= 0 &&
        y >= 0 &&
        width > 0 &&
        height > 0 &&
        x + width <= 1 &&
        y + height <= 1;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'shape': shape.wireName,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  static OcclusionMask? _tryParse(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final shape = OcclusionShape.tryParse(value['shape']);
    final x = _double(value['x']);
    final y = _double(value['y']);
    final width = _double(value['width']);
    final height = _double(value['height']);
    if (id is! String ||
        shape == null ||
        x == null ||
        y == null ||
        width == null ||
        height == null) {
      return null;
    }
    final mask = OcclusionMask(
      id: id,
      shape: shape,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    return mask.isValid ? mask : null;
  }

  static double? _double(Object? value) {
    if (value is! num || value is bool) return null;
    return value.toDouble();
  }
}

/// Версионированный набор масок одного изображения.
class OcclusionDocument {
  const OcclusionDocument({this.masks = const <OcclusionMask>[]});

  static const int currentVersion = 1;

  final List<OcclusionMask> masks;

  static OcclusionDocument? tryParse(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['version'] != currentVersion) return null;
      final rawMasks = decoded['masks'];
      if (rawMasks is! List) return null;
      final masks = <OcclusionMask>[];
      final ids = <String>{};
      for (final raw in rawMasks) {
        final mask = OcclusionMask._tryParse(raw);
        if (mask == null || !ids.add(mask.id)) return null;
        masks.add(mask);
      }
      return OcclusionDocument(masks: List<OcclusionMask>.unmodifiable(masks));
    } on Object {
      return null;
    }
  }

  String encode() => jsonEncode(<String, Object?>{
    'version': currentVersion,
    'masks': <Map<String, Object?>>[for (final mask in masks) mask.toJson()],
  });
}
