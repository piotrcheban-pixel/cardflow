import 'package:material_ui/material_ui.dart';

/// Ошибка загрузки (REDESIGN-SPEC §8): `shield_error` + текст ARB +
/// «Повторить» (`secondary`).
class NcErrorState extends StatelessWidget {
  /// Создаёт состояние ошибки.
  const NcErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title,
    this.retryLabel,
    this.iconName = 'shield_error',
    this.compact = false,
  });

  /// Текст ошибки (ARB).
  final String message;

  /// Повторить.
  final VoidCallback onRetry;

  /// Заголовок (ARB), необязателен.
  final String? title;

  /// Подпись кнопки (ARB «Повторить»).
  final String? retryLabel;

  /// Имя 3D-иконки.
  final String iconName;

  /// Компактный вариант.
  final bool compact;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
