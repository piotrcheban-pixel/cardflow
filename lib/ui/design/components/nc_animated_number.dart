import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';

/// Анимированное число (REDESIGN-SPEC §8, §6.3-5): считает 0→N за 900 мс
/// ease-out, цифры табличные. Для точности, удержания, «+N».
class NcAnimatedNumber extends StatefulWidget {
  /// Создаёт анимированное число.
  const NcAnimatedNumber({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.format,
    this.semanticLabel,
    this.from = 0,
    this.textAlign,
  });

  /// Целевое значение.
  final num value;

  /// Стиль (например, `displayXL`).
  final TextStyle? style;

  /// Длительность счёта.
  final Duration duration;

  /// Форматирование (например, «90 %»).
  final String Function(num value)? format;

  /// Текст семантики (итоговое значение, чтобы скринридер не читал кадры).
  final String? semanticLabel;

  /// Начальное значение.
  final num from;

  /// Выравнивание.
  final TextAlign? textAlign;

  @override
  State<NcAnimatedNumber> createState() => _NcAnimatedNumberState();
}

class _NcAnimatedNumberState extends State<NcAnimatedNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late Animation<double> _animation = Tween<double>(
    begin: widget.from.toDouble(),
    end: widget.value.toDouble(),
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    if (widget.duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(NcAnimatedNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.duration != widget.duration ||
        oldWidget.from != widget.from) {
      final double current = _animation.value;
      _controller.duration = widget.duration;
      _animation = Tween<double>(begin: current, end: widget.value.toDouble())
          .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      if (widget.duration == Duration.zero) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(num value) =>
      widget.format?.call(value) ?? value.round().toString();

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final TextStyle base = (widget.style ?? theme.typography.displayXL)
        .copyWith(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );
    final Widget number = AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, Widget? child) => Text(
        _format(_animation.value),
        style: base,
        textAlign: widget.textAlign,
      ),
    );
    final String semanticValue = widget.semanticLabel ?? _format(widget.value);
    return Semantics(
      label: semanticValue,
      child: ExcludeSemantics(child: number),
    );
  }
}
