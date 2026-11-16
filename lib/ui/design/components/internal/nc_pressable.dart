import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../motion.dart';
import '../../haptics.dart';
import '../../motion_scope.dart';
import '../../nc_theme.dart';
import '../../tokens/nc_radii.dart';
import '../internal/nc_spring_builder.dart';

/// Сжатие при нажатии: scale 0,96 на пружине `press` (§6.3-7).
///
/// Нажимаемые элементы показывают отклик формы, а не Material-ripple:
/// глубина и подсветка приходят из токенов.
class NcPressScale extends StatefulWidget {
  /// Оборачивает [child] пружинным масштабом.
  const NcPressScale({
    super.key,
    required this.pressed,
    required this.child,
    this.enabled = true,
    this.scale = AppMotion.pressScale,
  });

  /// Нажато ли сейчас.
  final bool pressed;

  /// Ребёнок.
  final Widget child;

  /// Разрешено ли сжатие.
  final bool enabled;

  /// Масштаб нажатого состояния (по умолчанию `AppMotion.pressScale`).
  final double scale;

  @override
  State<NcPressScale> createState() => _NcPressScaleState();
}

class _NcPressScaleState extends State<NcPressScale> {
  @override
  Widget build(BuildContext context) {
    final NcMotion motion = NcMotion.of(context);
    return NcSpringBuilder(
      value: widget.pressed && widget.enabled ? widget.scale : 1,
      spring: motion.pressSpring(),
      builder: (BuildContext context, double value) =>
          Transform.scale(scale: value, child: widget.child),
    );
  }
}

/// Кольцо фокуса: 2 px `aurum` со смещением 2 px (§10).
///
/// Рисуется поверх границ, не участвует в раскладке.
class NcFocusRing extends StatelessWidget {
  /// Оборачивает [child] кольцом при [focused].
  const NcFocusRing({
    super.key,
    required this.focused,
    required this.child,
    this.radius = NcRadii.pill,
    this.color,
    this.width = 2,
    this.inset = 2,
  });

  /// Показано ли кольцо.
  final bool focused;

  /// Ребёнок.
  final Widget child;

  /// Радиус кольца (обычно радиус компонента).
  final double radius;

  /// Цвет кольца; по умолчанию `aurum` темы.
  final Color? color;

  /// Толщина кольца.
  final double width;

  /// Смещение кольца наружу.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final Color ringColor = color ?? NcTheme.of(context).colors.aurum;
    return CustomPaint(
      painter: focused
          ? _NcFocusRingPainter(
              color: ringColor,
              radius: radius,
              width: width,
              inset: inset,
            )
          : null,
      child: child,
    );
  }
}

class _NcFocusRingPainter extends CustomPainter {
  const _NcFocusRingPainter({
    required this.color,
    required this.radius,
    required this.width,
    required this.inset,
  });

  final Color color;
  final double radius;
  final double width;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromLTWH(
      -inset,
      -inset,
      size.width + inset * 2,
      size.height + inset * 2,
    );
    final RoundedSuperellipseBorder shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius + inset),
    );
    canvas.drawPath(
      shape.getOuterPath(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_NcFocusRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.width != width ||
      oldDelegate.inset != inset;
}

/// Нажимаемая зона Nocturne: тап, долгое нажатие, фокус с клавиатуры
/// (Enter/Space), семантика кнопки и тактильный отклик.
///
/// Компоненты не дублируют это поведение: `NcButton`, `NcIconButton`,
/// `NcChip`, `NcListRow`, `NcCardTile`, строки меню и т.п. оборачивают своё
/// оформление в [NcTappable]. Отклик ограничен `NcHaptics` (§7).
class NcTappable extends StatefulWidget {
  /// Создаёт нажимаемую зону.
  const NcTappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.enabled = true,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.isButton = true,
    this.haptic = NcHapticKind.selectionClick,
    this.longPressHaptic = NcHapticKind.mediumImpact,
    this.scaleOnPress = true,
    this.pressedScale = AppMotion.pressScale,
    this.focusRadius = NcRadii.pill,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.behavior = HitTestBehavior.opaque,
    this.includeSemantics = true,
    this.mouseCursor,
  });

  /// Содержимое зоны.
  final Widget child;

  /// Тап.
  final VoidCallback? onTap;

  /// Долгое нажатие.
  final VoidCallback? onLongPress;

  /// Правый клик (контекстное меню на ПК).
  final VoidCallback? onSecondaryTap;

  /// Включена ли зона.
  final bool enabled;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  /// Значение семантики (например, выбранное значение).
  final String? semanticValue;

  /// Подсказка семантики.
  final String? semanticHint;

  /// Помечать ли узел как кнопку.
  final bool isButton;

  /// Отклик одиночного нажатия; `null` — без отклика.
  final NcHapticKind? haptic;

  /// Отклик долгого нажатия; `null` — без отклика.
  final NcHapticKind? longPressHaptic;

  /// Сжимать ли при нажатии.
  final bool scaleOnPress;

  /// Масштаб нажатия.
  final double pressedScale;

  /// Радиус кольца фокуса.
  final double focusRadius;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Запросить фокус при появлении.
  final bool autofocus;

  /// Изменение фокуса.
  final ValueChanged<bool>? onFocusChange;

  /// Поведение попадания.
  final HitTestBehavior behavior;

  /// Оборачивать ли в `Semantics`.
  final bool includeSemantics;

  /// Курсор мыши (по умолчанию `click` у включённой зоны).
  final MouseCursor? mouseCursor;

  @override
  State<NcTappable> createState() => _NcTappableState();
}

class _NcTappableState extends State<NcTappable> {
  bool _focused = false;
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled &&
      (widget.onTap != null ||
          widget.onLongPress != null ||
          widget.onSecondaryTap != null);

  void _activate() {
    if (!_interactive) return;
    final VoidCallback? onTap = widget.onTap;
    if (onTap == null) return;
    _fireHaptic(widget.haptic);
    onTap();
  }

  void _longPress() {
    if (!_interactive) return;
    final VoidCallback? onLongPress = widget.onLongPress;
    if (onLongPress == null) return;
    _fireHaptic(widget.longPressHaptic);
    onLongPress();
  }

  void _fireHaptic(NcHapticKind? kind) {
    if (kind == null) return;
    NcHaptics.of(context).rating(kind);
  }

  void _setPressed(bool value) {
    if (!_interactive || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
    widget.onFocusChange?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = widget.child;
    if (widget.scaleOnPress) {
      result = NcPressScale(
        pressed: _pressed,
        enabled: _interactive,
        scale: widget.pressedScale,
        child: result,
      );
    }
    result = NcFocusRing(
      focused: _focused && _interactive,
      radius: widget.focusRadius,
      child: result,
    );
    result = FocusableActionDetector(
      enabled: _interactive,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onShowFocusHighlight: _setFocused,
      mouseCursor: _interactive
          ? (widget.mouseCursor ?? SystemMouseCursors.click)
          : SystemMouseCursors.basic,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: _interactive ? _activate : null,
        onTapDown: _interactive ? (_) => _setPressed(true) : null,
        onTapUp: _interactive ? (_) => _setPressed(false) : null,
        onTapCancel: _interactive ? () => _setPressed(false) : null,
        onLongPress: _interactive && widget.onLongPress != null
            ? _longPress
            : null,
        onSecondaryTap: _interactive ? widget.onSecondaryTap : null,
        child: result,
      ),
    );
    if (widget.includeSemantics) {
      result = Semantics(
        button: widget.isButton,
        enabled: _interactive,
        label: widget.semanticLabel,
        value: widget.semanticValue,
        hint: widget.semanticHint,
        onTap: widget.onTap == null ? null : _activate,
        onLongPress: widget.onLongPress == null ? null : _longPress,
        child: result,
      );
    }
    return result;
  }
}
