import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/motion.dart';

/// Карточка классического режима: front/back с 3D-flip по тапу
/// (SPEC A7.2 — «3D-flip с Expressive-пружиной»).
///
/// Виджет без бизнес-логики: показывает строки и сообщает о тапе; раскрытие
/// ответа — состояние движка сессии. Пружина — [AppMotion.expressiveSpring]
/// (токены движения SPEC A4.4).
class ReviewCardView extends StatefulWidget {
  /// Создаёт карточку.
  const ReviewCardView({
    required this.front,
    required this.back,
    required this.revealed,
    required this.onTap,
    super.key,
  });

  /// Текст вопроса.
  final String front;

  /// Текст ответа.
  final String back;

  /// Показан ли ответ.
  final bool revealed;

  /// Тап по карточке (раскрыть ответ).
  final VoidCallback onTap;

  @override
  State<ReviewCardView> createState() => _ReviewCardViewState();
}

class _ReviewCardViewState extends State<ReviewCardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.revealed ? 1 : 0,
  );

  @override
  void didUpdateWidget(ReviewCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealed == widget.revealed) return;
    _controller.animateWith(
      SpringSimulation(
        AppMotion.expressiveSpring(),
        _controller.value,
        widget.revealed ? 1 : 0,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double value = _controller.value.clamp(0.0, 1.0);
        final bool showBack = value >= 0.5;
        final Matrix4 transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY(math.pi * value);
        final Widget face = Transform(
          alignment: Alignment.center,
          transform: showBack
              ? (Matrix4.identity()..rotateY(math.pi))
              : Matrix4.identity(),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text(
                showBack ? widget.back : widget.front,
                key: const ValueKey<String>('review-card-face'),
                textAlign: TextAlign.center,
                style: showBack
                    ? theme.textTheme.headlineSmall
                    : theme.textTheme.headlineMedium,
              ),
            ),
          ),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: Semantics(
              button: true,
              label: showBack ? widget.back : widget.front,
              child: Card(
                elevation: 3,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 240,
                    maxWidth: 640,
                  ),
                  child: Padding(padding: const EdgeInsets.all(8), child: face),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
