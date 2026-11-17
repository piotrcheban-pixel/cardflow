import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_depth.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'internal/nc_pressable.dart';

/// Монолит карточки сессии (REDESIGN-SPEC §8): `ink3`, `r.xl`, `depth3`,
/// rim light, внутренние поля 28/32, максимум 640. Слоты: лицо, метаданные,
/// бейджи.
class NcMonolith extends StatelessWidget {
  /// Создаёт монолит.
  const NcMonolith({
    super.key,
    required this.child,
    this.metadata,
    this.badges,
    this.maxWidth = NcSpace.maxSessionWidth,
    this.minHeight = 320,
    this.padding,
    this.onTap,
    this.semanticLabel,
  });

  /// Лицо карточки (вопрос/ответ).
  final Widget child;

  /// Тихая строка метаданных над лицом.
  final Widget? metadata;

  /// Бейджи под лицом.
  final Widget? badges;

  /// Максимальная ширина.
  final double maxWidth;

  /// Минимальная высота.
  final double minHeight;

  /// Внутренние поля (по умолчанию 32 × 28).
  final EdgeInsetsGeometry? padding;

  /// Тап (переворот).
  final VoidCallback? onTap;

  /// Текст семантики (лицо стороны).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final BorderRadiusGeometry radius = BorderRadius.circular(NcRadii.xl);
    final EdgeInsetsGeometry innerPadding =
        padding ??
        const EdgeInsets.symmetric(horizontal: NcSpace.s32, vertical: 28);
    final Widget content = Padding(
      padding: innerPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (metadata != null) ...<Widget>[
            metadata!,
            const SizedBox(height: NcSpace.s20),
          ],
          child,
          if (badges != null) ...<Widget>[
            const SizedBox(height: NcSpace.s20),
            badges!,
          ],
        ],
      ),
    );

    final Widget surface = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, minHeight: minHeight),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.ink3,
          shadows: NcDepth.level(3, dark: theme.isDark),
          shape: RoundedSuperellipseBorder(
            borderRadius: radius,
            side: BorderSide(color: theme.colors.hairline),
          ),
        ),
        child: ClipRSuperellipse(
          borderRadius: radius,
          child: Stack(
            children: <Widget>[
              content,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          NcColors.transparent,
                          theme.colors.rimLight,
                          NcColors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          NcColors.transparent,
                          NcColors.black.withValues(
                            alpha: theme.isDark ? 0.20 : 0.05,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTap == null) {
      if (semanticLabel == null) return surface;
      return Semantics(label: semanticLabel, container: true, child: surface);
    }
    return NcTappable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      focusRadius: NcRadii.xl,
      scaleOnPress: false,
      includeSemantics: true,
      child: surface,
    );
  }
}
