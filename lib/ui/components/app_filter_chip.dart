import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Единый чип фильтра (дизайн-система v3, ADR-045).
///
/// Один компонент для всех фильтров приложения (колоды, конструктор сессии).
/// Раньше «Все (13)» был одним `Text` внутри `Container(height: 38)` без
/// выравнивания: при жёсткой высоте текст прижимался к верхней кромке, и
/// подписи в ряду фильтров выглядели «съехавшими». Здесь зафиксированы:
///
/// * одинаковая высота [height] у всех чипов и одинаковая область нажатия
///   ([AppSizes.minTouchTarget] с вертикальным паддингом);
/// * текст и счётчик — одна строка по центру (`Row` + `Center`), счётчик
///   рисуется отдельным бейджем, поэтому не сдвигает подпись;
/// * состояния selected / unselected / hover / pressed / focused / disabled;
/// * длинная подпись переносится или обрезается по [maxWidth], а не ломает
///   высоту ряда.
class AppFilterChip extends StatelessWidget {
  /// Создаёт чип фильтра.
  const AppFilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.count,
    this.danger = false,
    this.icon,
    this.enabled = true,
    this.maxWidth,
    super.key,
  });

  /// Подпись фильтра (без счётчика).
  final String label;

  /// Значение счётчика; `null` — бейджа нет.
  final int? count;

  /// Выбран ли фильтр.
  final bool selected;

  /// Обработчик выбора.
  final VoidCallback onPressed;

  /// Фильтр «требует внимания» (например, «Срок наступил»).
  final bool danger;

  /// Иконка слева (необязательно).
  final IconData? icon;

  /// Доступен ли чип.
  final bool enabled;

  /// Максимальная ширина подписи (на узком экране).
  final double? maxWidth;

  /// Визуальная высота чипа.
  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color background = !enabled
        ? scheme.surfaceContainerLow.withValues(alpha: 0.6)
        : selected
        ? scheme.primary
        : scheme.surfaceContainerLow;
    final Color foreground = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
        : selected
        ? scheme.onPrimary
        : danger
        ? scheme.error
        : scheme.onSurfaceVariant;
    final Color border = !enabled
        ? scheme.outlineVariant
        : selected
        ? scheme.primary
        : danger
        ? scheme.error.withValues(alpha: 0.45)
        : scheme.outlineVariant;
    final TextStyle labelStyle =
        (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
          color: foreground,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          height: 1.2,
          letterSpacing: 0,
        );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      value: count?.toString(),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: AnimatedContainer(
              duration: AppMotion.duration(context, AppDurations.quick),
              curve: AppMotion.feedback,
              height: height,
              padding: EdgeInsets.only(
                left: icon == null ? AppSpacing.sm : AppSpacing.xs + 2,
                right: count == null ? AppSpacing.sm : AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadii.control),
                border: Border.all(color: border, width: AppSizes.borderWidth),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: AppSizes.iconSmall, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  // Flexible + ellipsis: на узком экране и при крупном шрифте
                  // (или тестовом Ahem) длинная подпись не выдавливает
                  // счётчик и не переполняет чип.
                  Flexible(
                    fit: FlexFit.loose,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxWidth ?? double.infinity,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      ),
                    ),
                  ),
                  if (count != null) ...<Widget>[
                    const SizedBox(width: 6),
                    _CountBadge(
                      count: count!,
                      selected: selected,
                      enabled: enabled,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Счётчик чипа: табличные цифры, не переносится и не смещает подпись.
class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.count,
    required this.selected,
    required this.enabled,
  });

  final int count;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color foreground = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
        : selected
        ? scheme.onPrimary
        : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? scheme.onPrimary.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        count.toString(),
        maxLines: 1,
        style: AppTypography.caption(context, color: foreground).copyWith(
          fontFeatures: AppTypography.tabularFigures,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}
