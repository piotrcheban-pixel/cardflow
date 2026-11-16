import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'internal/nc_pressable.dart';
import '../nc_theme.dart';

/// `−  N  +` для лимитов (REDESIGN-SPEC §8): круглые `tonal`-кнопки, значение
/// `monoL`, долгое нажатие — автоповтор. Ключи `settings-$id-minus/plus/value`
/// сохраняются ([minusKey], [valueKey], [plusKey]).
class NcStepper extends StatefulWidget {
  /// Создаёт степпер.
  const NcStepper({
    super.key,
    required this.value,
    this.onDecrement,
    this.onIncrement,
    this.minusKey,
    this.valueKey,
    this.plusKey,
    this.semanticLabel,
    this.minValue,
    this.maxValue,
  });

  /// Текущее значение.
  final int value;

  /// Уменьшить; `null` — кнопка «−» неактивна.
  final VoidCallback? onDecrement;

  /// Увеличить; `null` — кнопка «+» неактивна.
  final VoidCallback? onIncrement;

  /// Ключ кнопки «−».
  final Key? minusKey;

  /// Ключ значения.
  final Key? valueKey;

  /// Ключ кнопки «+».
  final Key? plusKey;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  /// Нижняя граница (для автоповтора).
  final int? minValue;

  /// Верхняя граница (для автоповтора).
  final int? maxValue;

  /// Задержка перед автоповтором.
  static const Duration repeatDelay = Duration(milliseconds: 400);

  /// Период автоповтора.
  static const Duration repeatPeriod = Duration(milliseconds: 120);

  @override
  State<NcStepper> createState() => _NcStepperState();
}

class _NcStepperState extends State<NcStepper> {
  Timer? _delay;
  Timer? _repeat;

  void _startRepeat(VoidCallback? action) {
    _stopRepeat();
    if (action == null) return;
    _delay = Timer(NcStepper.repeatDelay, () {
      _repeat = Timer.periodic(NcStepper.repeatPeriod, (_) => action());
    });
  }

  void _stopRepeat() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _StepperButton(
          key: widget.minusKey,
          icon: Icons.remove_rounded,
          semanticLabel: widget.semanticLabel,
          onPressed: widget.onDecrement,
          onLongPressStart: () => _startRepeat(widget.onDecrement),
          onLongPressEnd: _stopRepeat,
        ),
        SizedBox(
          width: 56,
          child: Center(
            child: Text(
              '${widget.value}',
              key: widget.valueKey,
              style: theme.typography.monoL.copyWith(
                color: widget.onIncrement == null && widget.onDecrement == null
                    ? theme.colors.textDisabled
                    : theme.colors.textPrimary,
              ),
            ),
          ),
        ),
        _StepperButton(
          key: widget.plusKey,
          icon: Icons.add_rounded,
          semanticLabel: widget.semanticLabel,
          onPressed: widget.onIncrement,
          onLongPressStart: () => _startRepeat(widget.onIncrement),
          onLongPressEnd: _stopRepeat,
        ),
      ],
    );
    if (widget.semanticLabel == null) return row;
    return Semantics(
      label: widget.semanticLabel,
      value: '${widget.value}',
      child: row,
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  final IconData icon;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool enabled = onPressed != null;
    final BorderRadius radius = BorderRadius.circular(18);
    return NcTappable(
      enabled: enabled,
      onTap: onPressed,
      onLongPressStart: enabled
          ? (LongPressStartDetails details) => onLongPressStart?.call()
          : null,
      onLongPressEnd: onLongPressEnd == null
          ? null
          : (LongPressEndDetails details) => onLongPressEnd!.call(),
      semanticLabel: semanticLabel,
      focusRadius: 18,
      scaleOnPress: false,
      includeSemantics: false,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: enabled ? theme.colors.ink4 : theme.colors.ink2,
          shape: RoundedSuperellipseBorder(
            borderRadius: radius,
            side: BorderSide(
              color: enabled
                  ? theme.colors.hairlineStrong
                  : theme.colors.hairline,
            ),
          ),
        ),
        child: SizedBox.square(
          dimension: 36,
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? theme.colors.textPrimary
                : theme.colors.textDisabled,
          ),
        ),
      ),
    );
  }
}
