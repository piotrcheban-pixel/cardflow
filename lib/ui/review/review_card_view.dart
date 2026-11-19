import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart' as domain;
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

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
    this.card,
    this.mediaBytes = const <String, Uint8List>{},
    this.mediaMetadata = const <String, MediaMetadata>{},
    this.spring,
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

  /// Полная карточка для разметки итерации 5; optional для прежних вызовов.
  final domain.Card? card;

  /// Байты изображений по `media.id`.
  final Map<String, Uint8List> mediaBytes;

  /// Атрибуция и вид иллюстраций по `media.id` (7.14).
  final Map<String, MediaMetadata> mediaMetadata;

  /// Пружина переворота (A6.6: «Выразительная»/«Стандартная», ADR-019 §2).
  final SpringDescription? spring;

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
        widget.spring ?? AppMotion.expressiveSpring(),
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
    final ColorScheme scheme = theme.colorScheme;
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
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: widget.card == null
                  ? Text(
                      showBack ? widget.back : widget.front,
                      key: const ValueKey<String>('review-card-face'),
                      textAlign: TextAlign.center,
                      style: showBack
                          ? theme.textTheme.bodyLarge?.copyWith(height: 1.6)
                          : theme.textTheme.headlineMedium,
                    )
                  : CardContentView(
                      card: widget.card!,
                      side: showBack ? widget.back : widget.front,
                      revealed: showBack,
                      faceKey: const ValueKey<String>('review-card-face'),
                      mediaBytes: widget.mediaBytes,
                      mediaMetadata: widget.mediaMetadata,
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
              excludeSemantics: true,
              label: showBack ? widget.back : widget.front,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: AppSizes.borderWidth,
                  ),
                  boxShadow: AppShadows.card(theme.brightness),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 240,
                    maxWidth: AppSizes.studyCardMaxWidth,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: face,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
