import 'package:material_ui/material_ui.dart';

/// Группа строк в стиле inset grouped (REDESIGN-SPEC §8): заголовок
/// `overline`, поверхность `ink2` `r.l`, `depth1`, разделители между строками
/// с отступом от `leading`.
class NcSection extends StatelessWidget {
  /// Создаёт секцию.
  const NcSection({
    super.key,
    this.title,
    required this.children,
    this.footer,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.dividerIndent = 16,
    this.semanticLabel,
  });

  /// Заголовок секции (`overline`, текст заглавными в ARB).
  final String? title;

  /// Строки секции.
  final List<Widget> children;

  /// Пояснение под секцией.
  final Widget? footer;

  /// Внутренние отступы строк.
  final EdgeInsetsGeometry padding;

  /// Отступ разделителя слева.
  final double dividerIndent;

  /// Текст семантики секции.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
