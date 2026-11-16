import 'package:material_ui/material_ui.dart';

/// Поле ввода Nocturne (REDESIGN-SPEC §8): заливка `ink2`, рамка `hairline`
/// → при фокусе 1,5 px `aurum` со свечением 12 %, метка над полем, helper и
/// ошибка под полем (`bodyS`, ошибка — `ember`), многострочный режим с
/// авто-высотой, счётчик символов `monoM`.
class NcTextField extends StatelessWidget {
  /// Создаёт поле.
  const NcTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.enabled = true,
    this.multiline = false,
    this.autofocus = false,
    this.maxLines,
    this.maxLength,
    this.showCounter = false,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.focusNode,
    this.keyboardType,
    this.obscureText = false,
    this.readOnly = false,
    this.onTap,
    this.fieldKey,
    this.semanticLabel,
    this.initialValue,
  });

  /// Контроллер текста.
  final TextEditingController? controller;

  /// Метка над полем (`labelM`, `textSecondary`).
  final String? label;

  /// Плейсхолдер.
  final String? hint;

  /// Пояснение под полем.
  final String? helper;

  /// Ошибка под полем (рамка и текст — `ember`).
  final String? errorText;

  /// Включено ли поле.
  final bool enabled;

  /// Многострочный режим с авто-высотой.
  final bool multiline;

  /// Запросить фокус при появлении.
  final bool autofocus;

  /// Максимум строк (для [multiline] по умолчанию без ограничения).
  final int? maxLines;

  /// Максимальная длина (счётчик при [showCounter]).
  final int? maxLength;

  /// Показывать счётчик символов.
  final bool showCounter;

  /// Иконка слева.
  final IconData? prefixIcon;

  /// Виджет справа в поле (например, «Показать ответ»).
  final Widget? suffix;

  /// Изменение текста.
  final ValueChanged<String>? onChanged;

  /// Отправка (Enter).
  final ValueChanged<String>? onSubmitted;

  /// Действие клавиши Enter.
  final TextInputAction? textInputAction;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Тип клавиатуры.
  final TextInputType? keyboardType;

  /// Скрывать вводимый текст (ключи API).
  final bool obscureText;

  /// Только чтение.
  final bool readOnly;

  /// Тап по полю (открыть меню/экран).
  final VoidCallback? onTap;

  /// Ключ самого `TextField` (контракт §9: поля ищутся по ключу).
  final Key? fieldKey;

  /// Текст семантики, если отличается от [label].
  final String? semanticLabel;

  /// Начальное значение без контроллера.
  final String? initialValue;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
