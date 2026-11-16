import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import '../../motion_scope.dart';

/// Анимирует `double` по физической пружине (REDESIGN-SPEC §6.1).
///
/// Каждая пружина создаётся через [SpringDescription.withDampingRatio]
/// (SPEC A4.4): абсолютный `damping` для stiffness 380 даёт ratio ≈ 0.02.
/// Виджет — единственная точка пружинных анимаций компонентов, поэтому
/// «Standard без overshoot» проверяется один раз на нём и дальше
/// гарантируется режимом [NcMotion] (§6.4).
class NcSpringBuilder extends StatefulWidget {
  /// Создаёт пружинную анимацию значения [value].
  const NcSpringBuilder({
    super.key,
    required this.value,
    required this.spring,
    required this.builder,
  });

  /// Целевое значение.
  final double value;

  /// Пружина (из `NcMotion`, не из литералов).
  final SpringDescription spring;

  /// Строитель кадра.
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<NcSpringBuilder> createState() => _NcSpringBuilderState();
}

class _NcSpringBuilderState extends State<NcSpringBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.value,
  );

  @override
  void didUpdateWidget(NcSpringBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.animateWith(
        SpringSimulation(
          widget.spring,
          _controller.value,
          widget.value,
          _controller.velocity,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) =>
        widget.builder(context, _controller.value),
  );
}
