import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import 'nc_icon_button.dart';

/// Pill-поле поиска 44 px (REDESIGN-SPEC §8): иконка поиска, кнопка очистки,
/// появление/исчезновение — на `standard`.
class NcSearchField extends StatefulWidget {
  /// Создаёт поле поиска.
  const NcSearchField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.clearTooltip,
    this.clearKey,
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

  /// Ключ кнопки очистки (контракт экрана).
  final Key? clearKey;

  /// Текст семантики поля.
  final String? semanticLabel;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Включено ли поле.
  final bool enabled;

  @override
  State<NcSearchField> createState() => _NcSearchFieldState();
}

class _NcSearchFieldState extends State<NcSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(NcSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onTextChanged);
      _ownsController = widget.controller == null;
      _controller.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final double height = 20 + MediaQuery.textScalerOf(context).scale(16);
    final BorderRadius radius = BorderRadius.circular(height / 2);
    final bool hasText = _controller.text.isNotEmpty;
    final Widget field = Row(
      children: <Widget>[
        const SizedBox(width: 14),
        Icon(Icons.search_rounded, size: 18, color: theme.colors.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            textInputAction: TextInputAction.search,
            style: theme.typography.bodyM.copyWith(
              color: theme.colors.textPrimary,
            ),
            cursorColor: theme.colors.aurum,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              hintText: widget.hint,
              hintStyle: theme.typography.bodyM.copyWith(
                color: theme.colors.textTertiary,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        if (hasText && widget.clearTooltip != null)
          NcIconButton(
            key: widget.clearKey,
            icon: Icons.close_rounded,
            tooltip: widget.clearTooltip!,
            size: 32,
            onPressed: widget.enabled ? _clear : null,
          )
        else
          const SizedBox(width: 8),
      ],
    );
    Widget result = SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.ink2,
          shape: RoundedSuperellipseBorder(
            borderRadius: radius,
            side: BorderSide(
              color: hasText
                  ? theme.colors.hairlineStrong
                  : theme.colors.hairline,
            ),
          ),
        ),
        child: ClipRSuperellipse(borderRadius: radius, child: field),
      ),
    );
    if (widget.semanticLabel != null) {
      result = Semantics(label: widget.semanticLabel, child: result);
    }
    return result;
  }
}
