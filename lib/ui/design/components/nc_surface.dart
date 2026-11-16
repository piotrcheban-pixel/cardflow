import 'package:material_ui/material_ui.dart';

import 'internal/nc_spring_builder.dart';
import '../motion_scope.dart';
import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_depth.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'internal/nc_pressable.dart';

/// Плотная поверхность Nocturne (REDESIGN-SPEC §8): основа плиток, секций,
/// строк. Глубину даёт `NcDepth` (elevation Material = 0), hover на ПК
/// приподнимает элемент на 2 px.
enum NcSurfaceTone {
  /// `ink2` — плитки колод, строки, поверхности контента.
  tile,

  /// `ink3` — монолит карточки сессии, диалог.
  monolith,

  /// Без заливки: только рамка/тень (зона прикрепления, hero).
  bare,
}

/// Плотная поверхность: `ink2`/`ink3`, `depth0–3`, радиус из токенов,
/// hover-подъём на ПК. Основа плиток (REDESIGN-SPEC §8).
class NcSurface extends StatefulWidget {
  /// Создаёт поверхность.
  const NcSurface({
    super.key,
    required this.child,
    this.tone = NcSurfaceTone.tile,
    this.level = 1,
    this.radius = NcRadii.m,
    this.color,
    this.padding,
    this.border = true,
    this.hoverLift = true,
    this.width,
    this.height,
    this.onTap,
    this.semanticLabel,
  });

  /// Содержимое.
  final Widget child;

  /// Заливка поверхности.
  final NcSurfaceTone tone;

  /// Уровень глубины 0…3 (`NcDepth`).
  final int level;

  /// Радиус скругления (из `NcRadii`).
  final double radius;

  /// Переопределение заливки (например, `amberSoft` у баннера).
  final Color? color;

  /// Внутренние отступы.
  final EdgeInsetsGeometry? padding;

  /// Рисовать ли рамку `hairline` (уровень 0 без рамки пуст).
  final bool border;

  /// Приподнимать ли на hover (ПК) на 2 px.
  final bool hoverLift;

  /// Ширина (иначе по содержимому).
  final double? width;

  /// Высота (иначе по содержимому).
  final double? height;

  /// Тап по поверхности (делает её кнопкой).
  final VoidCallback? onTap;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  @override
  State<NcSurface> createState() => _NcSurfaceState();
}

class _NcSurfaceState extends State<NcSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    final bool interactive = widget.onTap != null;
    final Color fill =
        widget.color ??
        switch (widget.tone) {
          NcSurfaceTone.tile => colors.ink2,
          NcSurfaceTone.monolith => colors.ink3,
          NcSurfaceTone.bare => NcColors.transparent,
        };
    final List<BoxShadow> shadows = NcDepth.level(
      widget.level,
      dark: theme.isDark,
    );
    final RoundedSuperellipseBorder shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(widget.radius),
      side: widget.border
          ? BorderSide(color: colors.hairline)
          : BorderSide.none,
    );

    Widget content = Padding(
      padding: widget.padding ?? const EdgeInsets.all(NcSpace.s16),
      child: widget.child,
    );
    if (widget.width != null || widget.height != null) {
      content = SizedBox(
        width: widget.width,
        height: widget.height,
        child: content,
      );
    }

    Widget surface = DecoratedBox(
      decoration: ShapeDecoration(shape: shape, color: fill, shadows: shadows),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(widget.radius),
        child: content,
      ),
    );

    if (interactive) {
      surface = NcTappable(
        onTap: widget.onTap,
        semanticLabel: widget.semanticLabel,
        focusRadius: widget.radius,
        pressedScale: 0.98,
        child: surface,
      );
    } else if (widget.semanticLabel != null) {
      surface = Semantics(
        label: widget.semanticLabel,
        container: true,
        child: surface,
      );
    }

    if (!widget.hoverLift) return surface;
    final double lift = _hovered ? -2 : 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: NcSpringBuilder(
        value: lift,
        spring: NcMotion.of(context).standardSpring(),
        builder: (BuildContext context, double value) =>
            Transform.translate(offset: Offset(0, value), child: surface),
      ),
    );
  }
}
