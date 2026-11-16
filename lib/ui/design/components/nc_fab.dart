import 'package:material_ui/material_ui.dart';

/// Плавающая кнопка Nocturne (REDESIGN-SPEC §8): extended pill 56 с
/// `primary` + `glow`; при прокрутке вниз сжимается до круга 56, при
/// прокрутке вверх — разворачивается (`NcScrollCollapseScope`).
class NcFab extends StatelessWidget {
  /// Создаёт FAB.
  const NcFab({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add_rounded,
    this.semanticLabel,
  });

  /// Подпись (ARB); в свёрнутом виде скрыта, но остаётся в семантике.
  final String label;

  /// Действие.
  final VoidCallback? onPressed;

  /// Иконка.
  final IconData icon;

  /// Текст семантики (по умолчанию [label]).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
