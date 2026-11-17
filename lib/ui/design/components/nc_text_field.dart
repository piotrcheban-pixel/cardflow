import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';

/// Поле ввода Nocturne (REDESIGN-SPEC §8): заливка `ink2`, рамка `hairline`
/// → при фокусе 1,5 px `aurum` со свечением 12 %, метка над полем, helper и
/// ошибка под полем (`bodyS`, ошибка — `ember`), многострочный режим с
/// авто-высотой, счётчик символов `monoM`.
class NcTextField extends StatefulWidget {
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
  State<NcTextField> createState() => _NcTextFieldState();
}

class _NcTextFieldState extends State<NcTextField> {
  late final TextEditingController _controller =
      widget.controller ??
      TextEditingController(text: widget.initialValue ?? '');
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late bool _ownsController = widget.controller == null;
  late bool _ownsFocusNode = widget.focusNode == null;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    if (widget.showCounter) _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(NcTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_onFocusChanged);
      if (_ownsFocusNode) _focusNode.dispose();
      _ownsFocusNode = widget.focusNode == null;
    }
    if (oldWidget.controller != widget.controller) {
      _ownsController = widget.controller == null;
    }
    if (oldWidget.showCounter != widget.showCounter) {
      if (widget.showCounter) {
        _controller.addListener(_onTextChanged);
      } else {
        _controller.removeListener(_onTextChanged);
      }
    }
  }

  void _onFocusChanged() {
    if (_focused == _focusNode.hasFocus) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    if (_ownsFocusNode) _focusNode.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final String counterText = '${_controller.text.length}/${widget.maxLength}';
    final bool hasError = widget.errorText != null;
    final Color borderColor = hasError
        ? theme.colors.ember
        : _focused
        ? theme.colors.aurum
        : theme.colors.hairline;
    final List<BoxShadow> glow = _focused && !hasError
        ? <BoxShadow>[
            BoxShadow(
              color: theme.colors.aurum.withValues(alpha: 0.12),
              blurRadius: 12,
            ),
          ]
        : const <BoxShadow>[];
    final BorderRadius radius = BorderRadius.circular(NcRadii.s);
    final Widget field = TextField(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction:
          widget.textInputAction ??
          (widget.multiline ? TextInputAction.newline : null),
      maxLines: widget.maxLines ?? (widget.multiline ? null : 1),
      minLines: 1,
      maxLength: widget.maxLength,
      inputFormatters: widget.maxLength == null
          ? null
          : <TextInputFormatter>[
              LengthLimitingTextInputFormatter(widget.maxLength),
            ],
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: theme.typography.bodyL.copyWith(
        color: widget.enabled
            ? theme.colors.textPrimary
            : theme.colors.textDisabled,
      ),
      cursorColor: theme.colors.aurum,
      decoration: InputDecoration(
        counterText: '',
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        hintText: widget.hint,
        hintStyle: theme.typography.bodyM.copyWith(
          color: theme.colors.textTertiary,
        ),
        prefixIcon: widget.prefixIcon == null
            ? null
            : Icon(
                widget.prefixIcon,
                size: 18,
                color: _focused
                    ? theme.colors.aurum
                    : theme.colors.textTertiary,
              ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        suffixIcon: widget.suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NcSpace.s16,
          vertical: NcSpace.s12,
        ),
      ),
    );

    final Widget container = DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colors.ink2,
        shadows: glow,
        shape: RoundedSuperellipseBorder(
          borderRadius: radius,
          side: BorderSide(
            color: borderColor,
            width: _focused || hasError ? 1.5 : 1,
          ),
        ),
      ),
      child: ClipRSuperellipse(borderRadius: radius, child: field),
    );

    final List<Widget> column = <Widget>[];
    if (widget.label != null) {
      column.add(
        Padding(
          padding: const EdgeInsets.only(bottom: NcSpace.s4),
          child: Text(
            widget.label!,
            style: theme.typography.labelM.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
        ),
      );
    }
    column.add(container);
    if (hasError) {
      column.add(
        Padding(
          padding: const EdgeInsets.only(top: NcSpace.s4),
          child: Text(
            widget.errorText!,
            style: theme.typography.bodyS.copyWith(color: theme.colors.ember),
          ),
        ),
      );
    } else if (widget.helper != null) {
      column.add(
        Padding(
          padding: const EdgeInsets.only(top: NcSpace.s4),
          child: Text(
            widget.helper!,
            style: theme.typography.bodyS.copyWith(
              color: theme.colors.textTertiary,
            ),
          ),
        ),
      );
    }
    if (widget.showCounter) {
      column.add(
        Padding(
          padding: const EdgeInsets.only(top: NcSpace.s4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              counterText,
              style: theme.typography.monoM.copyWith(
                color: hasError
                    ? theme.colors.ember
                    : theme.colors.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: column,
    );
    final String? semanticLabel = widget.semanticLabel ?? widget.label;
    if (semanticLabel == null) return content;
    return Semantics(label: semanticLabel, child: content);
  }
}
