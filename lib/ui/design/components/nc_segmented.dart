import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../haptics.dart';
import 'internal/nc_pressable.dart';
import 'internal/nc_spring_builder.dart';
import '../motion_scope.dart';
import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_radii.dart';

/// Сегмент `NcSegmented` (REDESIGN-SPEC §8).
@immutable
class NcSegment<T> {
  /// Создаёт сегмент.
  const NcSegment({
    required this.value,
    required this.label,
    this.leading,
    this.enabled = true,
    this.key,
    this.semanticLabel,
  });

  /// Значение сегмента.
  final T value;

  /// Текст сегмента (ARB).
  final String label;

  /// Иконка/превью перед текстом.
  final Widget? leading;

  /// Доступен ли сегмент.
  final bool enabled;

  /// Ключ сегмента (контракт §9).
  final Key? key;

  /// Текст семантики, если отличается от [label].
  final String? semanticLabel;
}

/// Pill-трек `ink2` с «бегунком» `ink4` + rim light, скользящим на пружине
/// `snap` (REDESIGN-SPEC §8). До 4 сегментов; при узкой ширине — горизонтальная
/// прокрутка.
class NcSegmented<T> extends StatelessWidget {
  /// Создаёт сегментированный переключатель.
  const NcSegmented({
    super.key,
    required this.segments,
    required this.value,
    this.onChanged,
    this.semanticLabel,
  });

  /// Сегменты (2–4).
  final List<NcSegment<T>> segments;

  /// Выбранное значение.
  final T value;

  /// Выбор; `null` — неактивен весь контрол.
  final ValueChanged<T>? onChanged;

  /// Текст семантики контрола.
  final String? semanticLabel;

  /// Минимальная ширина сегмента при прокрутке.
  static const double minSegmentWidth = 104;

  /// Высота контрола.
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    if (segments.isEmpty) return const SizedBox.shrink();
    final int selectedIndex = math.max(
      0,
      segments.indexWhere((NcSegment<T> segment) => segment.value == value),
    );
    final Widget control = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 520;
        final double innerWidth = math.max(0, maxWidth - 8);
        final double segmentWidth = math.max(
          innerWidth / segments.length,
          minSegmentWidth,
        );
        final double total = segmentWidth * segments.length;
        final bool scrollable = total > innerWidth + 0.5;

        final Widget indicator = NcSpringBuilder(
          value: selectedIndex.toDouble(),
          spring: NcMotion.of(context).snapSpring(),
          builder: (BuildContext context, double progress) {
            final double x = ((progress + 0.5) * 2 / segments.length) - 1;
            return Align(
              alignment: Alignment(x, 0),
              child: SizedBox(
                width: segmentWidth,
                height: height - 8,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: theme.colors.ink4,
                    shadows: theme.depth.depth1,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(NcRadii.pill),
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(NcRadii.pill),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          theme.colors.rimLight,
                          NcColors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );

        final Widget row = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final NcSegment<T> segment in segments)
              SizedBox(
                key: segment.key,
                width: segmentWidth,
                height: height - 8,
                child: NcTappable(
                  enabled: segment.enabled && onChanged != null,
                  onTap: segment.enabled && onChanged != null
                      ? () {
                          NcHaptics.of(context).selectionClick();
                          onChanged!(segment.value);
                        }
                      : null,
                  semanticLabel: segment.semanticLabel ?? segment.label,
                  focusRadius: NcRadii.pill,
                  scaleOnPress: false,
                  haptic: null,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (segment.leading != null) ...<Widget>[
                          segment.leading!,
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            segment.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: theme.typography.labelM.copyWith(
                              color: !segment.enabled
                                  ? theme.colors.textDisabled
                                  : segment.value == value
                                  ? theme.colors.textPrimary
                                  : theme.colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );

        final Widget inner = SizedBox(
          width: total,
          height: height - 8,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: indicator),
              row,
            ],
          ),
        );

        return Container(
          height: height,
          padding: const EdgeInsets.all(4),
          decoration: ShapeDecoration(
            color: theme.colors.ink2,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(NcRadii.pill),
            ),
          ),
          child: scrollable
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: inner,
                )
              : inner,
        );
      },
    );
    if (semanticLabel == null) return control;
    return Semantics(label: semanticLabel, container: true, child: control);
  }
}
