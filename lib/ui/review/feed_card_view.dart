import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/feed_swipe.dart';

/// Карточка ленты: свайпы-оценки, пружина, морфинг формы, 3D-flip (SPEC A7.3).
///
/// Жест: горизонтальное перетаскивание двигает карточку; отпускание решает
/// [feedSwipeRating] — оценка, вылет и `onRate`, либо возврат Expressive-
/// пружиной. Тап раскрывает/скрывает ответ (3D-flip, A4.4). Форма: 28 → 16 по
/// мере свайпа, pill при подтверждении (A4.3). Цвет — только роли темы.
class FeedCardView extends StatefulWidget {
  /// Создаёт карточку ленты.
  const FeedCardView({
    required this.front,
    required this.back,
    required this.revealed,
    required this.rated,
    required this.rating,
    required this.enabled,
    required this.resetToken,
    required this.onTap,
    required this.onRate,
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

  /// Оценена ли карточка.
  final bool rated;

  /// Оценка карточки, если она оценена.
  final Rating? rating;

  /// Доступны ли жесты (не идёт запись и карточка не оценена).
  final bool enabled;

  /// Счётчик сброса анимации после ошибки записи.
  final int resetToken;

  /// Тап по карточке (раскрыть/скрыть ответ).
  final VoidCallback onTap;

  /// Оценка свайпом.
  final ValueChanged<Rating> onRate;

  /// Полная карточка для разметки итерации 5; optional для прежних вызовов.
  final Card? card;

  /// Байты изображений по `media.id`.
  final Map<String, Uint8List> mediaBytes;

  /// Атрибуция и вид иллюстраций по `media.id` (7.14).
  final Map<String, MediaMetadata> mediaMetadata;

  /// Пружина переворота/возврата карточки (A6.6, ADR-019 §2).
  final SpringDescription? spring;

  @override
  State<FeedCardView> createState() => _FeedCardViewState();
}

class _FeedCardViewState extends State<FeedCardView>
    with TickerProviderStateMixin {
  late final AnimationController _swipe = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _flip = AnimationController.unbounded(
    vsync: this,
    value: widget.revealed ? 1 : 0,
  );
  double _width = 0;
  Rating? _commitRating;

  @override
  void didUpdateWidget(FeedCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _resetSwipe();
    }
    if (oldWidget.revealed != widget.revealed) {
      _flip.animateWith(
        SpringSimulation(
          widget.spring ?? AppMotion.expressiveSpring(),
          _flip.value,
          widget.revealed ? 1 : 0,
          0,
        ),
      );
    }
  }

  @override
  void dispose() {
    _swipe.dispose();
    _flip.dispose();
    super.dispose();
  }

  void _resetSwipe() {
    _swipe.stop();
    _swipe.value = 0;
    _commitRating = null;
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || widget.rated) return;
    _swipe.stop();
    if (_commitRating != null) {
      setState(() => _commitRating = null);
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || widget.rated) return;
    _swipe.value += details.delta.dx;
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || widget.rated) return;
    final double velocity = details.primaryVelocity ?? 0;
    final Rating? rating = feedSwipeRating(
      dx: _swipe.value,
      velocity: velocity,
      width: _width,
    );
    if (rating == null) {
      _swipe.animateWith(
        SpringSimulation(
          widget.spring ?? AppMotion.expressiveSpring(),
          _swipe.value,
          0,
          velocity,
        ),
      );
      return;
    }
    setState(() => _commitRating = rating);
    widget.onRate(rating);
    final double target = (_swipe.value >= 0 ? 1 : -1) * _width * 1.2;
    _swipe.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = math.min(constraints.maxWidth, 640);
        final double height = constraints.maxHeight;
        _width = width;
        return AnimatedBuilder(
          animation: _swipe,
          builder: (BuildContext context, Widget? child) {
            final double dx = _swipe.value;
            final bool committing = _commitRating != null;
            final double fraction = width <= 0
                ? 0
                : (dx.abs() / (width * feedLongSwipeFraction)).clamp(0.0, 1.0);
            final double radius = committing ? 999 : 28 - 12 * fraction;
            final Rating? preview =
                _commitRating ?? _directionRating(dx, width);
            final Color cardColor = _cardColor(
              Theme.of(context).colorScheme,
              preview,
              fraction,
            );
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: Transform.translate(
                  key: const ValueKey<String>('feed-swipe-transform'),
                  offset: Offset(dx, 0),
                  child: Transform.rotate(
                    angle: width <= 0 ? 0 : (dx / width) * 0.04,
                    child: Material(
                      color: cardColor,
                      elevation: 4,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(radius),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: committing || !widget.enabled
                            ? null
                            : widget.onTap,
                        onHorizontalDragStart: _onDragStart,
                        onHorizontalDragUpdate: _onDragUpdate,
                        onHorizontalDragEnd: _onDragEnd,
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: _FlipFace(
                                controller: _flip,
                                front: widget.front,
                                back: widget.back,
                                revealed: widget.revealed,
                                card: widget.card,
                                mediaBytes: widget.mediaBytes,
                                mediaMetadata: widget.mediaMetadata,
                              ),
                            ),
                            if (widget.rated)
                              const Positioned(
                                top: 12,
                                right: 12,
                                child: _RatedBadge(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Rating? _directionRating(double dx, double width) {
    if (width <= 0 || dx == 0) return null;
    if (dx > 0) {
      return dx >= width * feedLongSwipeFraction ? Rating.easy : Rating.good;
    }
    return -dx >= width * feedLongSwipeFraction ? Rating.hard : Rating.again;
  }

  Color _cardColor(ColorScheme scheme, Rating? rating, double fraction) {
    final Color base = scheme.surfaceContainerHigh;
    if (rating == null || fraction <= 0) return base;
    final Color tint = switch (rating) {
      Rating.again => scheme.errorContainer,
      Rating.hard => scheme.secondaryContainer,
      Rating.good => scheme.primary,
      Rating.easy => scheme.tertiaryContainer,
    };
    return Color.alphaBlend(tint.withValues(alpha: 0.12 * fraction), base);
  }
}

class _FlipFace extends StatelessWidget {
  const _FlipFace({
    required this.controller,
    required this.front,
    required this.back,
    required this.revealed,
    required this.card,
    required this.mediaBytes,
    required this.mediaMetadata,
  });

  final Animation<double> controller;
  final String front;
  final String back;
  final bool revealed;
  final Card? card;
  final Map<String, Uint8List> mediaBytes;
  final Map<String, MediaMetadata> mediaMetadata;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      label: revealed ? back : front,
      hint: AppLocalizations.of(context).feedSwipeHint,
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          final double value = controller.value.clamp(0.0, 1.0);
          final bool showBack = value >= 0.5;
          final Matrix4 transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(math.pi * value);
          // Обратная сторона уже повёрнута на π от наблюдателя. Без второго
          // поворота её текст рисуется зеркально; дополнительный rotationY(π)
          // разворачивает грань лицом к пользователю (итерация 7.9).
          if (showBack) transform.rotateY(math.pi);
          return Center(
            child: Transform(
              key: const ValueKey<String>('feed-card-flip-transform'),
              alignment: Alignment.center,
              transform: transform,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: card == null
                    ? Text(
                        showBack ? back : front,
                        key: const ValueKey<String>('feed-card-face'),
                        textAlign: TextAlign.center,
                        style: showBack
                            ? theme.textTheme.bodyLarge?.copyWith(height: 1.6)
                            : theme.textTheme.headlineMedium,
                      )
                    : CardContentView(
                        card: card!,
                        side: showBack ? back : front,
                        revealed: showBack,
                        faceKey: const ValueKey<String>('feed-card-face'),
                        mediaBytes: mediaBytes,
                        mediaMetadata: mediaMetadata,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RatedBadge extends StatelessWidget {
  const _RatedBadge();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('feed-rated-label'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.check_circle, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            l10n.feedRatedLabel,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
