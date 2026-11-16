import 'package:material_ui/material_ui.dart';

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

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
