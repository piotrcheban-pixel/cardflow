import 'package:material_ui/material_ui.dart';

import 'internal/nc_button_appearance.dart';
import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_radii.dart';

/// Варианты кнопки Nocturne (REDESIGN-SPEC §8).
enum NcButtonVariant {
  /// Градиент `aurumBright→aurumDeep`, текст `textOnAccent`, `glow` при
  /// `prominent: true` (один главный CTA на экран).
  primary,

  /// `ink4` + рамка `hairlineStrong`.
  secondary,

  /// Прозрачная, текст `textPrimary`.
  ghost,

  /// `emberSoft` + текст `ember` (удаление, ошибка).
  destructive,

  /// Градиент `iris→irisDeep` + блик (только «Сгенерировать»).
  ai,
}

/// Размер кнопки: высота 36 / 48 / 56 (§8).
enum NcButtonSize {
  /// 36 — малые действия в ряду.
  s,

  /// 48 — обычная кнопка.
  m,

  /// 56 — главное действие.
  l,
}

/// Кнопка Nocturne (REDESIGN-SPEC §8): 5 вариантов, 3 размера, pill,
/// состояние загрузки, фокус клавиатуры и `press`-сжатие.
class NcButton extends StatefulWidget {
  /// Создаёт кнопку.
  const NcButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = NcButtonVariant.primary,
    this.size = NcButtonSize.m,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.prominent = false,
    this.expand = false,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
    this.height,
  });

  /// Текст кнопки (из ARB).
  final String label;

  /// Действие; `null` — неактивная кнопка.
  final VoidCallback? onPressed;

  /// Вариант оформления.
  final NcButtonVariant variant;

  /// Размер.
  final NcButtonSize size;

  /// Иконка перед текстом.
  final IconData? icon;

  /// Иконка после текста.
  final IconData? trailingIcon;

  /// Состояние загрузки: текст заменяется тремя точками, ширина не меняется.
  final bool loading;

  /// Включить `glow` (только один главный CTA на экран).
  final bool prominent;

  /// Растянуть на всю доступную ширину.
  final bool expand;

  /// Запросить фокус при появлении.
  final bool autofocus;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Текст семантики, если отличается от [label].
  final String? semanticLabel;

  /// Высота (для доков сессии и hero-кнопок); по умолчанию по [size].
  final double? height;

  @override
  State<NcButton> createState() => _NcButtonState();
}

class _NcButtonState extends State<NcButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool enabled = widget.onPressed != null && !widget.loading;
    final NcButtonAppearance appearance = NcButtonAppearance.resolve(
      theme,
      widget.variant,
      enabled: enabled,
      prominent: widget.prominent,
      hovered: _hovered,
    );
    final double height =
        widget.height ?? NcButtonAppearance.height(widget.size);
    final double iconSize = NcButtonAppearance.iconSize(widget.size);

    final Widget label = Text(
      widget.label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style:
          (widget.size == NcButtonSize.s
                  ? theme.typography.labelM
                  : theme.typography.labelL)
              .copyWith(color: appearance.foreground),
    );
    final Widget content = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double labelMaxWidth = constraints.maxWidth;
        if (labelMaxWidth.isFinite) {
          if (widget.icon != null) labelMaxWidth -= iconSize + 8;
          if (widget.trailingIcon != null) labelMaxWidth -= iconSize + 8;
          if (labelMaxWidth < 0) labelMaxWidth = 0;
        }
        final Widget text = labelMaxWidth.isFinite
            ? ConstrainedBox(
                constraints: BoxConstraints(maxWidth: labelMaxWidth),
                child: label,
              )
            : label;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.icon != null) ...<Widget>[
              Icon(
                widget.icon,
                size: iconSize,
                color: appearance.iconColor ?? appearance.foreground,
              ),
              const SizedBox(width: 8),
            ],
            text,
            if (widget.trailingIcon != null) ...<Widget>[
              const SizedBox(width: 8),
              Icon(
                widget.trailingIcon,
                size: iconSize,
                color: appearance.iconColor ?? appearance.foreground,
              ),
            ],
          ],
        );
      },
    );
    final Widget body = widget.loading
        ? Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Opacity(opacity: 0, child: content),
              _NcLoadingDots(color: appearance.foreground),
            ],
          )
        : content;

    Widget button = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: NcButtonAppearance.horizontalPadding(widget.size),
      ),
      child: SizedBox(
        height: height,
        child: Center(widthFactor: 1, heightFactor: 1, child: body),
      ),
    );
    button = appearance.decorate(button, radius: NcRadii.pill);
    if (widget.variant == NcButtonVariant.ai) {
      button = _NcAiSheen(color: theme.colors.textOnAccent, child: button);
    }
    if (widget.expand) {
      button = SizedBox(width: double.infinity, child: button);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: NcTappable(
        onTap: enabled ? widget.onPressed : null,
        enabled: enabled,
        semanticLabel: widget.semanticLabel ?? widget.label,
        focusRadius: NcRadii.pill,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        child: button,
      ),
    );
  }
}

/// Три точки состояния загрузки вместо текста (§8).
class _NcLoadingDots extends StatelessWidget {
  const _NcLoadingDots({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (var index = 0; index < 3; index++) ...<Widget>[
        if (index > 0) const SizedBox(width: 5),
        DecoratedBox(
          decoration: ShapeDecoration(
            shape: const CircleBorder(),
            color: color,
          ),
          child: const SizedBox.square(dimension: 4),
        ),
      ],
    ],
  );
}

/// Медленный одноразовый блик кнопки «Сгенерировать» (§8: блик 3 с).
///
/// Анимация одноразовая (не повторяется), поэтому `pumpAndSettle` в тестах и
/// на экранах генерации завершается.
class _NcAiSheen extends StatelessWidget {
  const _NcAiSheen({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: -1, end: 2),
      duration: const Duration(seconds: 3),
      curve: Curves.linear,
      builder: (BuildContext context, double value, Widget? child) {
        return Stack(
          children: <Widget>[
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(NcRadii.pill),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(value - 1, -1),
                        end: Alignment(value, 1),
                        colors: <Color>[
                          color.withValues(alpha: 0),
                          color.withValues(alpha: 0.22),
                          color.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
