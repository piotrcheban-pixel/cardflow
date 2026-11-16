import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_glass.dart';
import '../tokens/nc_radii.dart';

/// Толщина стекла Nocturne (REDESIGN-SPEC §4.1).
enum NcGlassTier {
  /// `glass.thin` — верхняя панель, капсула действий, тосты.
  thin,

  /// `glass.regular` — док навигации, док оценок, тулбар.
  regular,

  /// `glass.thick` — листы, диалоги, меню.
  thick,
}

/// Примитив стекла (REDESIGN-SPEC §4.1): размытие с насыщением, тинт, зерно,
/// rim light и рамка. При повышенном контрасте и выключенном стекле —
/// сплошная `ink3` с рамкой (§4.4).
class NcGlass extends StatelessWidget {
  /// Создаёт стеклянную поверхность.
  const NcGlass({
    super.key,
    required this.child,
    this.tier = NcGlassTier.regular,
    this.radius = NcRadii.xl,
    this.padding,
    this.grouped = false,
    this.showNoise = true,
    this.showRimLight = true,
    this.width,
    this.height,
    this.semanticLabel,
  });

  /// Содержимое.
  final Widget child;

  /// Толщина материала.
  final NcGlassTier tier;

  /// Радиус скругления (из `NcRadii`).
  final double radius;

  /// Внутренние отступы.
  final EdgeInsetsGeometry? padding;

  /// Использовать `BackdropFilter.grouped` (нужен [NcGlassGroup] выше).
  final bool grouped;

  /// Рисовать ли зерно 2–3 %.
  final bool showNoise;

  /// Рисовать ли верхний блик.
  final bool showRimLight;

  /// Ширина.
  final double? width;

  /// Высота.
  final double? height;

  /// Текст семантики (если стекло — отдельный смысловой слой).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    final NcGlassMaterial material = switch (tier) {
      NcGlassTier.thin => theme.glass.thin,
      NcGlassTier.regular => theme.glass.regular,
      NcGlassTier.thick => theme.glass.thick,
    };
    final bool solid = material.isSolid || !theme.glassEnabled;
    final NcGlassMaterial effective = solid
        ? NcGlassMaterials.solid(colors)
        : material;
    final BorderRadius borderRadius = BorderRadius.circular(radius);

    Widget content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    if (showNoise && effective.noiseOpacity > 0) {
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _NcGlassGrainPainter(
                  opacity: effective.noiseOpacity,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (showRimLight && effective.rimLightOpacity > 0) {
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          content,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 24,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      colors.rimLight.withValues(
                        alpha: effective.rimLightOpacity,
                      ),
                      NcColors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget glass = DecoratedBox(
      decoration: ShapeDecoration(
        color: solid ? colors.ink3 : effective.tint,
        shape: RoundedSuperellipseBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: effective.borderColor),
        ),
      ),
      child: content,
    );
    if (!solid) {
      final bool hasGroup = grouped && BackdropGroup.of(context) != null;
      glass = hasGroup
          ? BackdropFilter.grouped(filter: effective.filter, child: glass)
          : BackdropFilter(filter: effective.filter, child: glass);
    }
    if (width != null || height != null) {
      glass = SizedBox(width: width, height: height, child: glass);
    }
    glass = ClipRSuperellipse(borderRadius: borderRadius, child: glass);
    if (semanticLabel != null) {
      glass = Semantics(label: semanticLabel, container: true, child: glass);
    }
    return glass;
  }
}

/// Общая группа `BackdropGroup` для нескольких `NcGlass(grouped: true)`
/// (§4.1): один проход размытия вместо N.
class NcGlassGroup extends StatelessWidget {
  /// Оборачивает несколько стеклянных элементов одной группой.
  const NcGlassGroup({super.key, required this.child});

  /// Стеклянные элементы.
  final Widget child;

  @override
  Widget build(BuildContext context) => BackdropGroup(child: child);
}

/// Зерно стекла: детерминированная россыпь точек вместо тайла PNG.
///
/// Отступление от §4.1 (там «шейдер `grain.frag` или тайловый PNG»): у
/// компонента нет асинхронной загрузки ассета, golden-снимки детерминированы,
/// а зерно не тянет `ImageProvider` в каждый кадр. Записано в журнале
/// `journal/redesign-2/README.md`.
class _NcGlassGrainPainter extends CustomPainter {
  const _NcGlassGrainPainter({required this.opacity, required this.color});

  final double opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final math.Random random = math.Random(0x4E43);
    final Paint paint = Paint()..color = color.withValues(alpha: opacity);
    const double step = 9;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        final double dx = x + random.nextDouble() * step;
        final double dy = y + random.nextDouble() * step;
        if (dx >= size.width || dy >= size.height) continue;
        canvas.drawCircle(Offset(dx, dy), 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_NcGlassGrainPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.color != color;
}
