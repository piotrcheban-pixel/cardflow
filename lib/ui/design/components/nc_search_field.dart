import 'package:material_ui/material_ui.dart';

/// Pill-поле поиска 44 px (REDESIGN-SPEC §8): иконка поиска, кнопка очистки,
/// появление/исчезновение — на `standard`.
class NcSearchField extends StatelessWidget {
  /// Создаёт поле поиска.
  const NcSearchField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.clearTooltip,
    this.semanticLabel,
    this.focusNode,
    this.enabled = true,
  });

  /// Контроллер текста.
  final TextEditingController? controller;

  /// Плейсхолдер (ARB).
  final String? hint;

  /// Изменение запроса.
  final ValueChanged<String>? onChanged;

  /// Отправка запроса.
  final ValueChanged<String>? onSubmitted;

  /// Запросить фокус при появлении.
  final bool autofocus;

  /// Подпись кнопки очистки (ARB).
  final String? clearTooltip;

  /// Текст семантики поля.
  final String? semanticLabel;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Включено ли поле.
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
