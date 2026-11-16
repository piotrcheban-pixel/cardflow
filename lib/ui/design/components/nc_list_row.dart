import 'package:material_ui/material_ui.dart';

/// Строка 56–72 px внутри секции (REDESIGN-SPEC §8): `leading` 28 px,
/// заголовок/подзаголовок, `trailing` (шеврон/значение/переключатель).
/// Разделитель — `hairline` с отступом от leading.
class NcListRow extends StatelessWidget {
  /// Создаёт строку.
  const NcListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.showDivider = true,
    this.semanticLabel,
    this.minHeight = 56,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
  });

  /// Заголовок (ARB или `CardText`).
  final Widget title;

  /// Подзаголовок.
  final Widget? subtitle;

  /// Ведущий элемент (глиф 28, аватар).
  final Widget? leading;

  /// Хвостовой элемент (шеврон, значение, переключатель).
  final Widget? trailing;

  /// Тап по строке.
  final VoidCallback? onTap;

  /// Долгое нажатие.
  final VoidCallback? onLongPress;

  /// Правый клик (контекстное меню на ПК).
  final VoidCallback? onSecondaryTap;

  /// Рисовать разделитель снизу.
  final bool showDivider;

  /// Текст семантики.
  final String? semanticLabel;

  /// Минимальная высота.
  final double minHeight;

  /// Максимум строк заголовка.
  final int titleMaxLines;

  /// Максимум строк подзаголовка.
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
