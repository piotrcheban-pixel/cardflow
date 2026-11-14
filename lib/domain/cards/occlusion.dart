/// Форма маски Image Occlusion (SPEC A7.8, ADR-017).
enum OcclusionShape { rectangle, ellipse }

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

  Map<String, Object?> toJson() => <String, Object?>{};
}

/// Версионированный набор масок одного изображения.
class OcclusionDocument {
  const OcclusionDocument({this.masks = const <OcclusionMask>[]});

  static const int currentVersion = 1;

  final List<OcclusionMask> masks;

  static OcclusionDocument? tryParse(String? source) => null;

  String encode() => '{"version":1,"masks":[]}';
}
