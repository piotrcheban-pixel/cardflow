import 'package:material_ui/material_ui.dart';

/// Пустое состояние (REDESIGN-SPEC §8): 3D-иконка 120 → заголовок `titleL` →
/// текст `bodyM` `textSecondary` → 1–2 кнопки. Появление — каскад.
class NcEmptyState extends StatelessWidget {
  /// Создаёт пустое состояние.
  const NcEmptyState({
    super.key,
    required this.iconName,
    required this.title,
    required this.message,
    this.primaryAction,
    this.secondaryAction,
    this.compact = false,
    this.semanticLabel,
  });

  /// Имя 3D-иконки из инвентаря §5.3.
  final String iconName;

  /// Заголовок (ARB).
  final String title;

  /// Пояснение (ARB).
  final String message;

  /// Главное действие (обычно `NcButton`).
  final Widget? primaryAction;

  /// Второе действие.
  final Widget? secondaryAction;

  /// Компактный вариант (внутри секции).
  final bool compact;

  /// Текст семантики.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
