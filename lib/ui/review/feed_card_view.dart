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
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

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
    this.onRetryMedia,
    this.answerFooter,
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

  /// Повтор чтения медиа карточки, если файл/байты не нашлись (7.19).
  final VoidCallback? onRetryMedia;

  /// Полоса оценок внутри карточки (после ответа) — тот же компонент, что в
  /// «Классике» (V1/V3): панель не висит отдельным блоком под карточкой.
  final Widget? answerFooter;

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

  /// Прокрутка содержимого карточки: длинный вопрос не обрезается молча —
  /// при переполнении показывается индикатор (аудит v5, V5-3).
  final ScrollController _scroll = ScrollController();
  bool _canScroll = false;

  @override
  void didUpdateWidget(FeedCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _resetSwipe();
    }
    if (oldWidget.revealed != widget.revealed) {
      if (AppMotion.reduce(context)) {
        _flip.value = widget.revealed ? 1 : 0;
      } else {
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
  }

  @override
  void dispose() {
    _swipe.dispose();
    _flip.dispose();
    _scroll.dispose();
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
      if (AppMotion.reduce(context)) {
        _swipe.value = 0;
        return;
      }
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
    if (AppMotion.reduce(context)) {
      _swipe.value = target;
      return;
    }
    _swipe.animateTo(
      target,
      duration: AppMotion.duration(context, const Duration(milliseconds: 180)),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // F04/F06: карточка ленты — та же ширина и та же высотная политика,
        // что у «Классики» (72 % окна, не меньше 62 % рабочей области).
        final double windowWidth = MediaQuery.sizeOf(context).width;
        final double width = math.min(
          constraints.maxWidth,
          AppSizes.studyCardWidth(windowWidth),
        );
        final double height = math.min(
          constraints.maxHeight,
          AppSizes.studyCardMinHeightFor(context),
        );
        _width = width;
        return AnimatedBuilder(
          animation: _swipe,
          builder: (BuildContext context, Widget? child) {
            final double dx = _swipe.value;
            final bool committing = _commitRating != null;
            final double fraction = width <= 0
                ? 0
                : (dx.abs() / (width * feedLongSwipeFraction)).clamp(0.0, 1.0);
            final double radius = committing
                ? 999
                : AppRadii.card - 6 * fraction;
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
                    child: MouseRegion(
                      // F26: карточка кликабельна — курсор-указатель.
                      cursor: SystemMouseCursors.click,
                      child: Material(
                        color: cardColor,
                        elevation: 0,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(radius),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
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
                                child:
                                    NotificationListener<
                                      ScrollMetricsNotification
                                    >(
                                      onNotification:
                                          (
                                            ScrollMetricsNotification
                                            notification,
                                          ) {
                                            final bool canScroll =
                                                notification
                                                    .metrics
                                                    .maxScrollExtent >
                                                0.5;
                                            if (canScroll != _canScroll) {
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    if (mounted &&
                                                        canScroll !=
                                                            _canScroll) {
                                                      setState(
                                                        () => _canScroll =
                                                            canScroll,
                                                      );
                                                    }
                                                  });
                                            }
                                            return false;
                                          },
                                      child: Scrollbar(
                                        controller: _scroll,
                                        thumbVisibility: _canScroll,
                                        child: _FlipFace(
                                          controller: _flip,
                                          scroll: _scroll,
                                          front: widget.front,
                                          back: widget.back,
                                          revealed: widget.revealed,
                                          card: widget.card,
                                          mediaBytes: widget.mediaBytes,
                                          mediaMetadata: widget.mediaMetadata,
                                          onRetryMedia: widget.onRetryMedia,
                                          answerFooter: widget.answerFooter,
                                        ),
                                      ),
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
    final Color base = scheme.surfaceContainerLowest;
    if (rating == null || fraction <= 0) return base;
    // Тона свайпа — те же роли, что у кнопок оценок (ADR-038).
    final Color tint = switch (rating) {
      Rating.again => scheme.errorContainer,
      Rating.hard => scheme.surfaceContainer,
      Rating.good => scheme.secondaryContainer,
      Rating.easy => scheme.primaryFixed,
    };
    return Color.alphaBlend(tint.withValues(alpha: 0.18 * fraction), base);
  }
}

class _FlipFace extends StatelessWidget {
  const _FlipFace({
    required this.controller,
    required this.scroll,
    required this.front,
    required this.back,
    required this.revealed,
    required this.card,
    required this.mediaBytes,
    required this.mediaMetadata,
    this.onRetryMedia,
    this.answerFooter,
  });

  final Animation<double> controller;

  /// Контроллер прокрутки содержимого (индикатор в родителе).
  final ScrollController scroll;
  final String front;
  final String back;
  final bool revealed;
  final Card? card;
  final Map<String, Uint8List> mediaBytes;
  final Map<String, MediaMetadata> mediaMetadata;
  final VoidCallback? onRetryMedia;
  final Widget? answerFooter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double factor = AppAdaptive.factorForContext(context);
    final TextStyle questionStyle = theme.textTheme.headlineMedium!.copyWith(
      fontSize: AppTypography.reviewQuestionSize * factor * 1.45,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    );
    final TextStyle answerStyle = theme.textTheme.bodyLarge!.copyWith(
      fontSize: AppTypography.reviewAnswerSize * factor * 1.3,
      // V4: межстрочный ответа 1,45 — в норме 1,3–1,5 (было 1,55).
      height: 1.45,
    );
    return Semantics(
      button: true,
      label: revealed ? back : front,
      hint: l10n.feedSwipeHint,
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
              // Аудит v9 (G3/G8): свободная высота карточки распределяется
              // между элементами (spaceEvenly), а не собирается в одну сплошную
              // белую полосу посередине.
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  const EdgeInsets padding = EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                    vertical: AppSpacing.xl,
                  );
                  final Widget? footer = answerFooter;
                  final double footerReserve = showBack && footer != null
                      ? 132
                      : 0;
                  final double minContentHeight = math.max(
                    0,
                    constraints.maxHeight - padding.vertical - footerReserve,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scroll,
                          padding: padding,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: minContentHeight,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                // Аудит v4 (V22) + v5 (V5-11): оборот сохраняет вопрос-эхо,
                                // как в «Классике», — контекст не теряется после переворота.
                                if (showBack) ...<Widget>[
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      l10n.reviewQuestionLabel.toUpperCase(),
                                      style: AppTypography.overline(context),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  card == null
                                      ? Text(
                                          front,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontSize: math.max(
                                                  16,
                                                  18 * factor,
                                                ),
                                                height: 1.4,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        )
                                      : CardContentView(
                                          card: card!,
                                          side: front,
                                          revealed: true,
                                          faceKey: const ValueKey<String>(
                                            'feed-card-echo',
                                          ),
                                          questionStyle: theme
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontSize: math.max(
                                                  16,
                                                  18 * factor,
                                                ),
                                                height: 1.4,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                          answerStyle: theme
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontSize: math.max(
                                                  16,
                                                  18 * factor,
                                                ),
                                                height: 1.4,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                          mediaBytes: mediaBytes,
                                          mediaMetadata: mediaMetadata,
                                          onRetryMedia: onRetryMedia,
                                          showMedia: false,
                                        ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.md,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                ],
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    (showBack
                                            ? l10n.reviewAnswerLabel
                                            : l10n.reviewQuestionLabel)
                                        .toUpperCase(),
                                    style: AppTypography.overline(
                                      context,
                                      color: showBack
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                // Аудит v11 (G8): отдельный SizedBox был невидимым
                                // ребёнком spaceEvenly и склеивал два промежутка в
                                // одну полосу 32,7 % высоты. Расстояние между
                                // элементами задаёт сам spaceEvenly.
                                card == null
                                    ? Text(
                                        showBack ? back : front,
                                        key: const ValueKey<String>(
                                          'feed-card-face',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: showBack
                                            ? answerStyle
                                            : questionStyle,
                                      )
                                    : CardContentView(
                                        card: card!,
                                        side: showBack ? back : front,
                                        revealed: showBack,
                                        faceKey: const ValueKey<String>(
                                          'feed-card-face',
                                        ),
                                        questionStyle: questionStyle,
                                        answerStyle: answerStyle,
                                        mediaBytes: mediaBytes,
                                        mediaMetadata: mediaMetadata,
                                        onRetryMedia: onRetryMedia,
                                        imageMaxHeight: math.max(
                                          220,
                                          constraints.maxHeight * 0.72,
                                        ),
                                        imageMaxWidth: math.max(
                                          420,
                                          constraints.maxWidth * 0.62,
                                        ),
                                      ),
                                // F05: до ответа подсказок об оценках нет — лицо
                                // карточки содержит только вопрос. Подсказка стоит
                                // на обороте, где оценки уже доступны.
                                if (showBack)
                                  Text(
                                    l10n.feedRateHint,
                                    key: const ValueKey<String>(
                                      'feed-rate-hint',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (showBack && footer != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xxl,
                            AppSpacing.xs,
                            AppSpacing.xxl,
                            AppSpacing.lg,
                          ),
                          child: footer,
                        ),
                    ],
                  );
                },
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
