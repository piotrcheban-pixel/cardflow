import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart' as domain;
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/feed_swipe.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Единая карточка сессии для всех режимов (V1).
///
/// Один виджет рисует и «Классику», и «Ленту»: оболочку (радиус, граница,
/// тень, hover-курсор), надзаголовок стороны, центрированное прокручиваемое
/// тело, нижнюю полосу действий, 3D-переворот. Режим «Лента» включает
/// параметром [enableSwipe]: горизонтальный жест двигает карточку, меняет её
/// форму/тон и по отпусканию отправляет оценку через [onRate].
///
/// Бизнес-логики здесь нет: тексты, стороны и действия приходят снаружи;
/// раскрытие ответа — состояние движка сессии.
class SessionCard extends StatefulWidget {
  /// Создаёт карточку.
  const SessionCard({
    required this.front,
    required this.back,
    required this.revealed,
    required this.onTap,
    this.card,
    this.mediaBytes = const <String, Uint8List>{},
    this.mediaMetadata = const <String, MediaMetadata>{},
    this.onRetryMedia,
    this.scrollController,
    this.questionFooter,
    this.answerFooter,
    this.questionHint,
    this.answerHint,
    this.cardKey,
    this.faceKey = const ValueKey<String>('session-card-face'),
    this.echoFaceKey,
    this.flipTransformKey,
    this.swipeTransformKey,
    this.ratingPanelKey,
    this.questionActionsKey,
    this.ratedOverlay,
    this.semanticLabel,
    this.semanticHint,
    this.enableSwipe = false,
    this.swipeEnabled = true,
    this.rated = false,
    this.rating,
    this.resetToken = 0,
    this.spring,
    this.onRate,
    this.flipDuration = const Duration(milliseconds: 300),
    super.key,
  });

  /// Текст вопроса.
  final String front;

  /// Текст ответа.
  final String back;

  /// Показан ли ответ.
  final bool revealed;

  /// Тап по карточке (раскрыть/скрыть ответ).
  final VoidCallback onTap;

  /// Полная карточка для разметки (типы, cloze, occlusion, медиа).
  final domain.Card? card;

  /// Байты изображений по `media.id`.
  final Map<String, Uint8List> mediaBytes;

  /// Атрибуция и вид иллюстраций по `media.id`.
  final Map<String, MediaMetadata> mediaMetadata;

  /// Повтор чтения медиа карточки, если файл/байты не нашлись.
  final VoidCallback? onRetryMedia;

  /// Внешний контроллер прокрутки тела (клавиатура сессии).
  final ScrollController? scrollController;

  /// Действие лицевой стороны внутри карточки («Показать ответ»).
  final Widget? questionFooter;

  /// Действие оборотной стороны внутри карточки (панель оценок).
  final Widget? answerFooter;

  /// Подсказка под вопросом (клавиши/жесты) — заполняет пустоту карточки
  /// осмысленной строкой и дробит её на короткие полосы (Вариант А).
  final Widget? questionHint;

  /// Подсказка под ответом (у «Ленты» — о свайпах/клавишах).
  final Widget? answerHint;

  /// Ключ самой карточки (для тестов и измерений).
  final Key? cardKey;

  /// Ключ отрисованного содержимого стороны.
  final ValueKey<String> faceKey;

  /// Ключ повтора вопроса на обороте (у «Ленты» — свой).
  final ValueKey<String>? echoFaceKey;

  /// Ключ Transform переворота (у «Ленты» — `feed-card-flip-transform`).
  final Key? flipTransformKey;

  /// Ключ Transform сдвига свайпа (у «Ленты» — `feed-swipe-transform`).
  final Key? swipeTransformKey;

  /// Ключ появляющейся панели оценок (у «Классики» — `review-rating-panel`).
  final Key? ratingPanelKey;

  /// Ключ блока главного действия лицевой стороны.
  final Key? questionActionsKey;

  /// Значок «оценено» в правом верхнем углу (у «Ленты»).
  final Widget? ratedOverlay;

  /// Семантическая подпись карточки; `null` — без внешней обёртки.
  final String? semanticLabel;

  /// Семантическая подсказка (жесты «Ленты»).
  final String? semanticHint;

  /// Включить свайп-оценки и форму ленты.
  final bool enableSwipe;

  /// Доступны ли жесты/тап (не идёт запись, карточка не оценена).
  final bool swipeEnabled;

  /// Карточка уже оценена (жесты и тап отключены).
  final bool rated;

  /// Текущая/подтверждённая оценка (тон свайпа).
  final Rating? rating;

  /// Счётчик сброса анимации после ошибки записи.
  final int resetToken;

  /// Пружина переворота/возврата карточки (A6.6).
  final SpringDescription? spring;

  /// Оценка свайпом.
  final ValueChanged<Rating>? onRate;

  /// Длительность переворота без пружины (280–350 мс).
  final Duration flipDuration;

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard>
    with TickerProviderStateMixin {
  late final AnimationController _flip = AnimationController.unbounded(
    vsync: this,
    value: widget.revealed ? 1 : 0,
  );
  late final AnimationController _swipe = AnimationController.unbounded(
    vsync: this,
  );
  ScrollController? _internalScroll;
  bool _hovered = false;
  double _width = 0;
  Rating? _commitRating;

  ScrollController get _scroll =>
      widget.scrollController ?? (_internalScroll ??= ScrollController());

  @override
  void didUpdateWidget(SessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _resetSwipe();
    }
    if (oldWidget.revealed != widget.revealed) {
      _animateFlip();
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _swipe.dispose();
    _internalScroll?.dispose();
    super.dispose();
  }

  void _animateFlip() {
    final double target = widget.revealed ? 1 : 0;
    if (AppMotion.reduce(context)) {
      _flip.value = target;
      return;
    }
    if (widget.enableSwipe) {
      _flip.animateWith(
        SpringSimulation(
          widget.spring ?? AppMotion.expressiveSpring(),
          _flip.value,
          target,
          0,
        ),
      );
      return;
    }
    _flip.animateTo(
      target,
      duration: AppMotion.duration(context, widget.flipDuration),
      curve: Curves.easeInOutCubic,
    );
  }

  void _resetSwipe() {
    _swipe.stop();
    _swipe.value = 0;
    _commitRating = null;
  }

  bool get _gesturesEnabled =>
      widget.enableSwipe && widget.swipeEnabled && !widget.rated;

  void _onDragStart(DragStartDetails details) {
    if (!_gesturesEnabled) return;
    _swipe.stop();
    if (_commitRating != null) {
      setState(() => _commitRating = null);
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_gesturesEnabled) return;
    _swipe.value += details.delta.dx;
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_gesturesEnabled) return;
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
    widget.onRate?.call(rating);
    final double target = (_swipe.value >= 0 ? 1 : -1) * _width * 1.2;
    if (AppMotion.reduce(context)) {
      _swipe.value = target;
      return;
    }
    _swipe.animateTo(
      target,
      duration: AppMotion.duration(context, AppDurations.medium),
      curve: Curves.easeOutCubic,
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
    final Color tint = switch (rating) {
      Rating.again => scheme.errorContainer,
      Rating.hard => scheme.surfaceContainer,
      Rating.good => scheme.secondaryContainer,
      Rating.easy => scheme.primaryFixed,
    };
    return Color.alphaBlend(tint.withValues(alpha: 0.18 * fraction), base);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double windowWidth = MediaQuery.sizeOf(context).width;
        final double width = widget.enableSwipe
            ? math.min(
                constraints.maxWidth,
                AppSizes.studyCardWidth(windowWidth),
              )
            : (constraints.hasBoundedWidth ? constraints.maxWidth : 960);
        final double availableHeight = widget.enableSwipe
            ? math.min(
                constraints.maxHeight,
                AppSizes.studyCardMinHeightFor(context),
              )
            : (constraints.hasBoundedHeight ? constraints.maxHeight : 420);
        final double cardHeight = math.min(
          availableHeight,
          AppSizes.studyCardMinHeightFor(context),
        );
        _width = width;
        final bool narrow = width < 560;
        final bool tight = cardHeight < 320;
        final bool cramped = cardHeight < 260;
        final double factor = AppAdaptive.factorForContext(context);
        final double questionSize = tight
            ? (narrow ? 26 : 28)
            : (narrow ? 28 : AppTypography.reviewQuestionSize * factor * 1.45);
        final double answerSize = tight
            ? 20
            : (narrow ? 22 : AppTypography.reviewAnswerSize * factor * 1.3);
        final double padV = tight
            ? AppSpacing.xs
            : (AppSpacing.xl * factor).clamp(AppSpacing.xl, AppSpacing.huge);
        final double padH = narrow ? AppSpacing.lg : padV;
        final double bodyPadV = narrow ? AppSpacing.md : padV;
        final double columnWidth = math.max(
          200,
          math.min(
            width - padH * 2,
            AppSizes.studyTextColumnBase * (narrow ? 1 : factor),
          ),
        );
        final double columnInset = math.max(padH, (width - columnWidth) / 2);
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_flip, _swipe]),
          builder: (BuildContext context, Widget? child) {
            final double flipValue = _flip.value.clamp(0.0, 1.0);
            final bool showBack = flipValue >= 0.5;
            final double dx = widget.enableSwipe ? _swipe.value : 0;
            final bool committing = _commitRating != null;
            final double fraction = !widget.enableSwipe || width <= 0
                ? 0
                : (dx.abs() / (width * feedLongSwipeFraction)).clamp(0.0, 1.0);
            final double radius = !widget.enableSwipe
                ? AppRadii.card
                : committing
                ? 999
                : AppRadii.card - 6 * fraction;
            final BorderRadius shape = BorderRadius.circular(radius);
            final Rating? preview = !widget.enableSwipe
                ? widget.rating
                : _commitRating ?? _directionRating(dx, width);
            final Color cardColor = widget.enableSwipe
                ? _cardColor(scheme, preview, fraction)
                : scheme.surfaceContainerLowest;
            final Widget face = showBack
                ? _buildRevealed(
                    context,
                    theme,
                    questionSize: questionSize,
                    answerSize: answerSize,
                    padH: padH,
                    padV: padV,
                    bodyPadV: bodyPadV,
                    narrow: narrow,
                    cramped: cramped,
                    tight: tight,
                    columnWidth: columnWidth,
                    columnInset: columnInset,
                  )
                : _buildQuestion(
                    context,
                    theme,
                    questionSize: questionSize,
                    padH: padH,
                    padV: padV,
                    bodyPadV: bodyPadV,
                    narrow: narrow,
                    cramped: cramped,
                    tight: tight,
                    columnWidth: columnWidth,
                    columnInset: columnInset,
                  );
            final Matrix4 transform = Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(math.pi * flipValue);
            // Обратная сторона уже повёрнута на π от наблюдателя: без второго
            // поворота её текст рисуется зеркально (итерация 7.9).
            if (showBack) transform.rotateY(math.pi);
            Widget flipped = Transform(
              key: widget.flipTransformKey,
              alignment: Alignment.center,
              transform: transform,
              child: face,
            );
            final String? semanticLabel = widget.semanticLabel;
            if (semanticLabel != null) {
              flipped = Semantics(
                button: true,
                label: semanticLabel,
                hint: widget.semanticHint,
                child: flipped,
              );
            }
            flipped = Stack(
              children: <Widget>[
                Positioned.fill(child: flipped),
                if (widget.ratedOverlay != null)
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: widget.ratedOverlay!,
                  ),
              ],
            );
            final Widget surface = MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) {
                if (!_hovered) setState(() => _hovered = true);
              },
              onExit: (_) {
                if (_hovered) setState(() => _hovered = false);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.enableSwipe
                    ? (committing || !widget.swipeEnabled || widget.rated
                          ? null
                          : widget.onTap)
                    : widget.onTap,
                onHorizontalDragStart: widget.enableSwipe ? _onDragStart : null,
                onHorizontalDragUpdate: widget.enableSwipe
                    ? _onDragUpdate
                    : null,
                onHorizontalDragEnd: widget.enableSwipe ? _onDragEnd : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: shape,
                    boxShadow: AppShadows.card(theme.brightness),
                  ),
                  child: Material(
                    color: cardColor,
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: shape,
                      side: BorderSide(
                        color: _hovered ? scheme.primary : scheme.outline,
                        width: AppSizes.borderWidth,
                      ),
                    ),
                    child: flipped,
                  ),
                ),
              ),
            );
            final Widget card = widget.enableSwipe
                ? Transform.translate(
                    key: widget.swipeTransformKey,
                    offset: Offset(dx, 0),
                    child: Transform.rotate(
                      angle: width <= 0 ? 0 : (dx / width) * 0.04,
                      child: surface,
                    ),
                  )
                : surface;
            return Center(
              // heightFactor: 1 — в свободных ограничениях («Классика»)
              // карточка отдаёт наружу свою высоту, а не растягивается на всю
              // рабочую область; в тесных («Лента») Center сам заполняет
              // страницу и центрирует карточку.
              heightFactor: 1,
              child: SizedBox(
                key: widget.cardKey,
                width: width,
                height: cardHeight,
                child: card,
              ),
            );
          },
        );
      },
    );
  }

  /// Лицевая сторона: надзаголовок, вопрос по центру, действие внизу.
  Widget _buildQuestion(
    BuildContext context,
    ThemeData theme, {
    required double questionSize,
    required double padH,
    required double padV,
    required double bodyPadV,
    required bool narrow,
    required bool cramped,
    required bool tight,
    required double columnWidth,
    required double columnInset,
  }) {
    final Widget? footer = widget.questionFooter;
    final bool occlusion = widget.card?.occlusionJson != null;
    final bool hasMedia =
        !occlusion && (widget.card?.questionMediaIds.isNotEmpty ?? false);
    final bool wideMedia = MediaQuery.sizeOf(context).width >= 1000;
    // Вариант А: текстовая карточка раскладывает вопрос и подсказку по всей
    // высоте тела (spaceEvenly), поэтому пустые полосы короткие; карточка с
    // изображением сохраняет центрирование и полную высоту картинки.
    final bool spaced =
        !cramped && !hasMedia && !occlusion && widget.questionHint != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!cramped)
          Padding(
            padding: EdgeInsets.fromLTRB(columnInset, padV, columnInset, 0),
            child: _SideLabel(
              label: AppLocalizations.of(context).reviewQuestionLabel,
            ),
          ),
        Expanded(
          child: Semantics(
            label: widget.front,
            excludeSemantics: true,
            child: _CardBody(
              scroll: _scroll,
              padding: EdgeInsets.fromLTRB(
                padH,
                hasMedia && wideMedia ? 0 : AppSpacing.md,
                padH,
                hasMedia && wideMedia ? 0 : bodyPadV,
              ),
              columnWidth: columnWidth,
              alignment: spaced
                  ? MainAxisAlignment.spaceEvenly
                  : MainAxisAlignment.center,
              builder: (double availableHeight) => <Widget>[
                _content(
                  theme,
                  context,
                  side: widget.front,
                  revealed: false,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: questionSize,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                  media: true,
                  imageMaxHeight: occlusion
                      ? math.max(160, availableHeight * 0.66)
                      : wideMedia
                      ? availableHeight
                      : math.max(200, availableHeight * 0.92),
                  imageMaxWidth: wideMedia ? columnWidth * 0.55 : columnWidth,
                  sideBySide: wideMedia && hasMedia,
                ),
                if (spaced) widget.questionHint!,
              ],
            ),
          ),
        ),
        if (footer != null)
          _CardFooterBand(
            band: !tight,
            padding: EdgeInsets.fromLTRB(
              padH,
              tight ? 0 : AppSpacing.md,
              padH,
              tight ? AppSpacing.xxs : padV,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      AppSizes.revealButtonMaxWidth *
                      AppAdaptive.factorForContext(context).clamp(1.0, 1.2),
                ),
                child: SizedBox(
                  key: widget.questionActionsKey,
                  width: double.infinity,
                  child: footer,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Обратная сторона: приглушённый вопрос, ответ, изображения и действия.
  Widget _buildRevealed(
    BuildContext context,
    ThemeData theme, {
    required double questionSize,
    required double answerSize,
    required double padH,
    required double padV,
    required double bodyPadV,
    required bool narrow,
    required bool cramped,
    required bool tight,
    required double columnWidth,
    required double columnInset,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget? footer = widget.answerFooter;
    final TextStyle mutedQuestion = theme.textTheme.titleSmall!.copyWith(
      fontSize: narrow ? 17 : math.max(18, questionSize * 0.48),
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    );
    final TextStyle answerStyle = theme.textTheme.bodyLarge!.copyWith(
      fontSize: answerSize,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
    );
    final bool occlusion = widget.card?.occlusionJson != null;
    final bool hasAnswerMedia =
        !occlusion && (widget.card?.answerMediaIds.isNotEmpty ?? false);
    final bool hasQuestionMedia =
        !occlusion && (widget.card?.questionMediaIds.isNotEmpty ?? false);
    final bool wideMedia =
        MediaQuery.sizeOf(context).width >= 1000 &&
        (hasAnswerMedia || hasQuestionMedia);
    // Вариант А: ответ, повтор вопроса и подсказка распределяются по высоте
    // тела, поэтому самая длинная пустая полоса короткая (≤30 %).
    final bool spaced =
        !tight && !cramped && !wideMedia && widget.answerHint != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!cramped)
          Padding(
            padding: EdgeInsets.fromLTRB(columnInset, padV, columnInset, 0),
            child: _SideLabel(label: l10n.reviewQuestionLabel),
          ),
        Expanded(
          child: Semantics(
            label: '${widget.front}\n${widget.back}',
            excludeSemantics: true,
            child: _CardBody(
              scroll: _scroll,
              padding: EdgeInsets.fromLTRB(
                padH,
                wideMedia ? 0 : AppSpacing.xs,
                padH,
                wideMedia ? 0 : bodyPadV,
              ),
              columnWidth: columnWidth,
              alignment: spaced
                  ? MainAxisAlignment.spaceEvenly
                  : MainAxisAlignment.center,
              builder: (double availableHeight) => <Widget>[
                if (!cramped) ...<Widget>[
                  _content(
                    theme,
                    context,
                    side: widget.front,
                    revealed: true,
                    style: mutedQuestion,
                    media: true,
                    imageMaxHeight: math.max(140, availableHeight * 0.42),
                    imageMaxWidth: columnWidth,
                    faceKey: widget.echoFaceKey ?? widget.faceKey,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(
                      top: AppSpacing.lg,
                      bottom: AppSpacing.sm,
                    ),
                    child: Divider(height: 1),
                  ),
                  _SideLabel(label: l10n.reviewAnswerLabel, accent: true),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (cramped)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _SideLabel(
                      label: l10n.reviewAnswerLabel,
                      accent: true,
                    ),
                  ),
                _content(
                  theme,
                  context,
                  side: widget.back,
                  revealed: true,
                  style: answerStyle,
                  media: !occlusion,
                  includeClozeFront: false,
                  imageMaxHeight: occlusion
                      ? math.max(160, availableHeight * 0.66)
                      : wideMedia
                      ? availableHeight
                      : math.max(220, availableHeight * 0.92),
                  imageMaxWidth: wideMedia ? columnWidth * 0.55 : columnWidth,
                  sideBySide: wideMedia && hasAnswerMedia,
                ),
                if (widget.answerHint != null)
                  spaced
                      ? widget.answerHint!
                      : Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: widget.answerHint!,
                        ),
              ],
            ),
          ),
        ),
        if (footer != null)
          _FadeSlideIn(
            key: widget.ratingPanelKey,
            child: _CardFooterBand(
              band: !tight,
              padding: EdgeInsets.fromLTRB(
                padH,
                tight ? 0 : AppSpacing.md,
                padH,
                tight ? AppSpacing.xxs : padV,
              ),
              child: footer,
            ),
          ),
      ],
    );
  }

  Widget _content(
    ThemeData theme,
    BuildContext context, {
    required String side,
    required bool revealed,
    required TextStyle? style,
    required bool media,
    required double imageMaxHeight,
    required double imageMaxWidth,
    bool includeClozeFront = true,
    bool sideBySide = false,
    ValueKey<String>? faceKey,
  }) {
    final domain.Card? card = widget.card;
    if (card == null) {
      return Text(
        side,
        key: faceKey ?? widget.faceKey,
        textAlign: TextAlign.center,
        style: style,
      );
    }
    return CardContentView(
      card: card,
      side: side,
      revealed: revealed,
      faceKey: faceKey ?? widget.faceKey,
      questionStyle: style,
      answerStyle: style,
      mediaBytes: widget.mediaBytes,
      mediaMetadata: widget.mediaMetadata,
      onRetryMedia: widget.onRetryMedia,
      showMedia: media,
      includeClozeFront: includeClozeFront,
      imageMaxHeight: imageMaxHeight,
      imageMaxWidth: imageMaxWidth,
      sideBySide: sideBySide,
    );
  }
}

/// Нижняя полоса карточки: действия отделены от содержимого спокойной
/// поверхностью и тонкой линией, а не висят в белом поле.
class _CardFooterBand extends StatelessWidget {
  const _CardFooterBand({
    required this.child,
    required this.padding,
    this.band = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Рисовать ли поверхность и разделитель (в очень низком окне — нет).
  final bool band;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: band
          ? BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant,
                  width: AppSizes.borderWidth,
                ),
              ),
            )
          : null,
      child: child,
    );
  }
}

/// Однократное появление панели: fade 0→1 и сдвиг снизу 12 px.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Duration duration = AppMotion.duration(context, AppDurations.medium);
    if (duration == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.enter,
      builder: (BuildContext context, double t, Widget? inner) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}

/// Подпись стороны карточки («Вопрос»/«Ответ»).
class _SideLabel extends StatelessWidget {
  const _SideLabel({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        label.toUpperCase(),
        style: AppTypography.overline(
          context,
          color: accent
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Тело карточки: короткое содержимое центрируется, длинное — прокручивается.
class _CardBody extends StatefulWidget {
  const _CardBody({
    required this.scroll,
    required this.padding,
    required this.columnWidth,
    required this.builder,
    this.alignment = MainAxisAlignment.center,
  });

  final ScrollController scroll;
  final EdgeInsets padding;
  final double columnWidth;
  final List<Widget> Function(double availableHeight) builder;

  /// Как распределять короткое содержимое по высоте тела.
  final MainAxisAlignment alignment;

  @override
  State<_CardBody> createState() => _CardBodyState();
}

class _CardBodyState extends State<_CardBody> {
  bool _canScroll = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableHeight = math.max(
          0,
          constraints.maxHeight - widget.padding.vertical,
        );
        final List<Widget> children = widget.builder(availableHeight);
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (ScrollMetricsNotification notification) {
            final bool canScroll = notification.metrics.maxScrollExtent > 0.5;
            if (canScroll != _canScroll) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && canScroll != _canScroll) {
                  setState(() => _canScroll = canScroll);
                }
              });
            }
            return false;
          },
          child: Scrollbar(
            controller: widget.scroll,
            thumbVisibility: _canScroll,
            child: SingleChildScrollView(
              controller: widget.scroll,
              padding: widget.padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.columnWidth,
                    minHeight: math.max(0, availableHeight),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: widget.alignment,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
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
