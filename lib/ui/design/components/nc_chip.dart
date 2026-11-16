import 'package:material_ui/material_ui.dart';

import '../../motion.dart';
import '../haptics.dart';
import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_radii.dart';
import 'nc_badge.dart';

/// Вид чипа Nocturne (REDESIGN-SPEC §8).
enum NcChipVariant {
  /// Фильтр: выбран — `aurumSoft` + текст `aurum` + галочка на `snap`.
  filter,

  /// Тег: `ink4`, `labelM`, `textSecondary`.
  tag,

  /// Статус: soft-цвет семантики + точка.
  status,
}

/// Чип Nocturne (§8): фильтр, тег, статус; выбранное состояние, удаление
/// (крестик) и тактильный отклик выбора.
class NcChip extends StatelessWidget {
  /// Создаёт чип.
  const NcChip({
    super.key,
    required this.label,
    this.variant = NcChipVariant.filter,
    this.selected = false,
    this.onSelected,
    this.onDeleted,
    this.deleteTooltip,
    this.leadingIcon,
    this.tone = NcBadgeTone.accent,
    this.showDot = false,
    this.selectedColor,
    this.enabled = true,
    this.semanticLabel,
  });

  /// Чип-фильтр.
  const NcChip.filter({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.leadingIcon,
    this.enabled = true,
    this.selectedColor,
    this.semanticLabel,
  }) : variant = NcChipVariant.filter,
       onDeleted = null,
       deleteTooltip = null,
       tone = NcBadgeTone.accent,
       showDot = false;

  /// Чип-тег.
  const NcChip.tag({
    super.key,
    required this.label,
    this.onDeleted,
    this.deleteTooltip,
    this.leadingIcon,
    this.enabled = true,
    this.semanticLabel,
  }) : variant = NcChipVariant.tag,
       selected = false,
       onSelected = null,
       tone = NcBadgeTone.neutral,
       showDot = false,
       selectedColor = null;

  /// Чип-статус.
  const NcChip.status({
    super.key,
    required this.label,
    this.tone = NcBadgeTone.jade,
    this.showDot = true,
    this.leadingIcon,
    this.semanticLabel,
  }) : variant = NcChipVariant.status,
       selected = false,
       onSelected = null,
       onDeleted = null,
       deleteTooltip = null,
       enabled = true,
       selectedColor = null;

  /// Текст (ARB).
  final String label;

  /// Вид чипа.
  final NcChipVariant variant;

  /// Выбран ли (для фильтра).
  final bool selected;

  /// Переключение фильтра.
  final VoidCallback? onSelected;

  /// Удаление (крестик у тега).
  final VoidCallback? onDeleted;

  /// Подпись крестика (ARB).
  final String? deleteTooltip;

  /// Иконка перед текстом.
  final IconData? leadingIcon;

  /// Тон статуса.
  final NcBadgeTone tone;

  /// Точка статуса.
  final bool showDot;

  /// Цвет выбранного фильтра (по умолчанию `aurum`).
  final Color? selectedColor;

  /// Включён ли чип.
  final bool enabled;

  /// Текст семантики.
  final String? semanticLabel;

  ({Color background, Color foreground}) _colors(NcTheme theme) {
    final Color accent = selectedColor ?? theme.colors.aurum;
    return switch (variant) {
      NcChipVariant.filter =>
        selected
            ? (
                background: Color.alphaBlend(
                  accent.withValues(alpha: 0.14),
                  theme.colors.ink2,
                ),
                foreground: accent,
              )
            : (
                background: theme.colors.ink4,
                foreground: theme.colors.textSecondary,
              ),
      NcChipVariant.tag => (
        background: theme.colors.ink4,
        foreground: theme.colors.textSecondary,
      ),
      NcChipVariant.status => (
        background: _toneSoft(theme, tone),
        foreground: _toneColor(theme, tone),
      ),
    };
  }

  static Color _toneColor(NcTheme theme, NcBadgeTone tone) => switch (tone) {
    NcBadgeTone.accent => theme.colors.aurum,
    NcBadgeTone.jade => theme.colors.jade,
    NcBadgeTone.ember => theme.colors.ember,
    NcBadgeTone.amber => theme.colors.amber,
    NcBadgeTone.iris => theme.colors.iris,
    NcBadgeTone.glacier => theme.colors.glacier,
    NcBadgeTone.neutral => theme.colors.textSecondary,
  };

  static Color _toneSoft(NcTheme theme, NcBadgeTone tone) => switch (tone) {
    NcBadgeTone.accent => theme.colors.aurumSoft,
    NcBadgeTone.jade => theme.colors.jadeSoft,
    NcBadgeTone.ember => theme.colors.emberSoft,
    NcBadgeTone.amber => theme.colors.amberSoft,
    NcBadgeTone.iris => theme.colors.irisSoft,
    NcBadgeTone.glacier => theme.colors.glacierSoft,
    NcBadgeTone.neutral => theme.colors.ink4,
  };

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final ({Color background, Color foreground}) colors = _colors(theme);
    final Color foreground = !enabled
        ? theme.colors.textDisabled
        : colors.foreground;
    final BorderRadius radius = BorderRadius.circular(NcRadii.pill);

    final Widget chipLabel = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: theme.typography.labelM.copyWith(color: foreground),
    );
    final Widget row = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (leadingIcon != null) ...<Widget>[
            Icon(leadingIcon, size: 15, color: foreground),
            const SizedBox(width: 6),
          ],
          if (variant == NcChipVariant.status && showDot) ...<Widget>[
            DecoratedBox(
              decoration: ShapeDecoration(
                color: foreground,
                shape: const CircleBorder(),
              ),
              child: const SizedBox.square(dimension: 6),
            ),
            const SizedBox(width: 6),
          ],
          if (variant == NcChipVariant.filter && selected) ...<Widget>[
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 160),
              curve: AppMotion.baseCurve,
              builder: (BuildContext context, double value, Widget? child) =>
                  Transform.scale(scale: value, child: child),
              child: Icon(Icons.check_rounded, size: 15, color: foreground),
            ),
            const SizedBox(width: 6),
          ],
          if (constraints.maxWidth.isFinite)
            Flexible(child: chipLabel)
          else
            chipLabel,
          if (onDeleted != null) ...<Widget>[
            const SizedBox(width: 4),
            Tooltip(
              message: deleteTooltip ?? '',
              child: NcTappable(
                onTap: onDeleted,
                semanticLabel: deleteTooltip,
                focusRadius: NcRadii.xs,
                haptic: null,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: theme.colors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final Widget chipContent = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: ShapeDecoration(
        color: enabled ? colors.background : theme.colors.ink2,
        shape: RoundedSuperellipseBorder(
          borderRadius: radius,
          side: BorderSide(
            color: variant == NcChipVariant.status
                ? colors.foreground.withValues(alpha: 0.30)
                : theme.colors.hairline,
          ),
        ),
      ),
      child: row,
    );

    final bool tappable =
        enabled && variant == NcChipVariant.filter && onSelected != null;
    if (!tappable) {
      return semanticLabel == null
          ? chipContent
          : Semantics(label: semanticLabel, child: chipContent);
    }
    return NcTappable(
      onTap: () {
        NcHaptics.of(context).selectionClick();
        onSelected?.call();
      },
      semanticLabel: semanticLabel ?? label,
      focusRadius: NcRadii.pill,
      haptic: null,
      child: chipContent,
    );
  }
}

/// Кривые для чипа (совпадают с токеном `snap`-анимации по времени).
abstract final class AppMotionCurves {
  /// Кривая появления галочки выбранного фильтра.
  static const Curve snap = Cubic(0.05, 0.7, 0.1, 1);
}
