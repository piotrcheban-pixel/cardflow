import 'package:material_ui/material_ui.dart';

import 'nc_colors.dart';

/// Глубина Nocturne (REDESIGN-SPEC §3.3, ADR-035).
///
/// `elevation` у Material-компонентов = 0: глубину дают тени из токенов.
/// В тёмной теме тени чёрные, в Porcelain — мягче (прозрачность ×0,5) и теплее
/// (`shadowTint`). Внутренняя тень снизу монолита и rim light рисуются
/// компонентом (`NcMonolith`, этап 2), здесь — только внешние тени.
@immutable
class NcDepth {
  const NcDepth._({
    required this.shadowTint,
    required this.opacityScale,
    required this.depth0,
    required this.depth1,
    required this.depth2,
    required this.depth3,
  });

  /// Тёмная тема: чёрные тени полной прозрачности таблицы §3.3.
  static final NcDepth dark = _build(NcColors.black, 1.0);

  /// Porcelain: тёплая тень `#3A2E1A`, прозрачность ×0,5.
  static final NcDepth light = _build(NcColors.warmShadow, 0.5);

  /// Базовый цвет теней темы.
  final Color shadowTint;

  /// Множитель прозрачности теней (Porcelain — 0,5).
  final double opacityScale;

  /// `depth0` — без тени (рамка `hairline` у компонента).
  final List<BoxShadow> depth0;

  /// `depth1` — плитки колод, секции.
  final List<BoxShadow> depth1;

  /// `depth2` — hero-карточки, меню.
  final List<BoxShadow> depth2;

  /// `depth3` — монолит, парящий док, лист.
  final List<BoxShadow> depth3;

  /// Уровень глубины по номеру (0…3); неверный номер — `depth0`.
  static List<BoxShadow> level(int value, {required bool dark}) =>
      switch (value) {
        1 => dark ? NcDepth.dark.depth1 : NcDepth.light.depth1,
        2 => dark ? NcDepth.dark.depth2 : NcDepth.light.depth2,
        3 => dark ? NcDepth.dark.depth3 : NcDepth.light.depth3,
        _ => const <BoxShadow>[],
      };

  /// `glow(color)` — цветная тень **одного** главного CTA на экране
  /// (и подтверждённой оценки).
  List<BoxShadow> glow(Color color) => <BoxShadow>[
    BoxShadow(spreadRadius: 1, color: color.withValues(alpha: 0.40)),
    BoxShadow(
      offset: const Offset(0, 12),
      blurRadius: 32,
      color: color.withValues(alpha: 0.28),
    ),
  ];

  static NcDepth _build(Color tint, double scale) {
    List<BoxShadow> layer(double dy, double blur, double alpha) => <BoxShadow>[
      BoxShadow(
        offset: Offset(0, dy),
        blurRadius: blur,
        color: tint.withValues(alpha: alpha * scale),
      ),
    ];
    return NcDepth._(
      shadowTint: tint,
      opacityScale: scale,
      depth0: const <BoxShadow>[],
      depth1: <BoxShadow>[...layer(1, 2, 0.40), ...layer(4, 12, 0.24)],
      depth2: <BoxShadow>[...layer(8, 24, 0.45), ...layer(2, 6, 0.30)],
      depth3: <BoxShadow>[...layer(28, 64, 0.55), ...layer(8, 20, 0.35)],
    );
  }
}
