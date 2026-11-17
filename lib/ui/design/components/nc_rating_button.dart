import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_radii.dart';
import 'internal/nc_pressable.dart';
import 'nc_key_hint.dart';

/// Кнопка оценки в доке (REDESIGN-SPEC §8, §9.6): высота 64, `r.m`, фон
/// `…Soft`-цвета оценки, рамка 1 px того же цвета 30 %; интервал сверху
/// (`monoM`), название (`labelL`), подсказка клавиши на ПК.
class NcRatingButton extends StatelessWidget {
  /// Создаёт кнопку оценки.
  const NcRatingButton({
    super.key,
    required this.label,
    required this.interval,
    required this.color,
    this.onPressed,
    this.keyHint,
    this.enabled = true,
    this.minHeight = 64,
    this.flex = 100,
  });

  /// Название оценки (ARB: «Не знаю»…).
  final String label;

  /// Подпись интервала (например, «3 д»); над названием.
  final String interval;

  /// Цвет оценки (`ember`/`amber`/`jade`/`glacier`).
  final Color color;

  /// Оценка; `null` — неактивна.
  final VoidCallback? onPressed;

  /// Подсказка клавиши (1…4) на ПК.
  final String? keyHint;

  /// Включена ли кнопка.
  final bool enabled;

  /// Минимальная высота (64; растёт при textScale 2,0).
  final double minHeight;

  /// Доля ширины в доке (neighbor-squish).
  final int flex;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool active = enabled && onPressed != null;
    final BorderRadiusGeometry radius = BorderRadius.circular(NcRadii.m);
    final Color foreground = active ? color : theme.colors.textDisabled;
    final Widget content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: active
              ? color.withValues(alpha: 0.14)
              : theme.colors.ink4.withValues(alpha: 0.4),
          shape: RoundedSuperellipseBorder(
            borderRadius: radius,
            side: BorderSide(
              color: active
                  ? color.withValues(alpha: 0.30)
                  : theme.colors.hairline,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    interval,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.typography.monoM.copyWith(
                      color: active
                          ? theme.colors.textSecondary
                          : theme.colors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.typography.labelL.copyWith(color: foreground),
                  ),
                ],
              ),
              if (keyHint != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: NcKeyHint(label: keyHint!, compact: true),
                ),
            ],
          ),
        ),
      ),
    );
    return NcTappable(
      enabled: active,
      onTap: onPressed,
      semanticLabel: '$label, $interval',
      focusRadius: NcRadii.m,
      child: content,
    );
  }
}
