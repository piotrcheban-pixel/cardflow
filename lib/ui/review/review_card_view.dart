import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart' as domain;
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Длительность переворота карточки (SPEC A7.2, аудит v4: 280–350 мс).
const Duration kReviewCardFlipDuration = Duration(milliseconds: 300);

/// Карточка сессии (SPEC A7.2; аудит v7 — G1/G3/G6/G7/G8/G9/G10/G11).
///
/// Композиция — «карточка = рабочая область», а не белое поле с текстом:
///
/// * сверху — надзаголовок стороны («Вопрос»/«Ответ»), выровненный с текстовой
///   колонкой;
/// * в центре — содержимое стороны (вопрос крупным кеглем; на обороте —
///   приглушённый вопрос, разделитель и ответ с изображениями);
/// * **внизу внутри карточки** — главное действие стороны: до раскрытия
///   «Показать ответ», после — панель из четырёх оценок. Поэтому кнопки не
///   «висят» отдельно от карточки, а состояние «вопрос» не содержит ни одной
///   оценки (G1) и ни одного недоступного действия (G5).
/// * ширина — от окна ([AppSizes.studyCardWidth], ≥60 % на 2K/FullHD), текстовая
///   колонка ограничена ~60 знаками (G7), поэтому на 4K строки не растягиваются;
/// * переворот — 300 мс с 3D-поворотом; панель оценок появляется fade+slide
///   (220 мс, G9) с учётом reduced motion.
///
/// Виджет без бизнес-логики: показывает строки и сообщает о тапе; раскрытие
/// ответа — состояние движка сессии.
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
    this.onRetryMedia,
    this.scrollController,
    this.questionFooter,
    this.answerFooter,
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

  /// Повтор чтения медиа карточки, если файл/байты не нашлись (7.19).
  final VoidCallback? onRetryMedia;

  /// Контроллер прокрутки содержимого карточки (клавиатура сессии).
  final ScrollController? scrollController;

  /// Действие лицевой стороны внутри карточки («Показать ответ»); `null` — нет.
  final Widget? questionFooter;

  /// Действие оборотной стороны внутри карточки (панель оценок); `null` — нет.
  final Widget? answerFooter;

  @override
  State<ReviewCardView> createState() => _ReviewCardViewState();
}

class _ReviewCardViewState extends State<ReviewCardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kReviewCardFlipDuration,
    value: widget.revealed ? 1 : 0,
  );

  /// Кривая переворота: `easeInOutCubic` вместо линейного вращения
  /// (аудит v4, A1). Смена лица происходит ровно на 50 %.
  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );

  ScrollController? _internalScroll;

  ScrollController get _scroll =>
      widget.scrollController ?? (_internalScroll ??= ScrollController());

  @override
  void didUpdateWidget(ReviewCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealed == widget.revealed) return;
    if (widget.revealed) {
      _controller.forward(from: 0);
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _internalScroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 960;
        final double height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420;
        final bool narrow = width < 560;
        // Очень низкое окно (800×600 при 150 % = 533×400): кегли и поля
        // уменьшаются, чтобы вопрос читался целиком (G10), но не ниже
        // читаемого минимума.
        final bool tight = height < 320;
        final double factor = AppAdaptive.factorForContext(context);
        final double questionSize = tight
            ? (narrow ? 26 : 28)
            : (narrow ? 28 : AppTypography.reviewQuestionSize * factor);
        final double answerSize = tight
            ? 20
            : (narrow ? 22 : AppTypography.reviewAnswerSize * factor);
        // Поля 24–48 лог. px (требование композиции): 24 на FullHD, ~30 на 2K.
        final double padV = tight
            ? AppSpacing.sm
            : (AppSpacing.xl * factor).clamp(AppSpacing.xl, AppSpacing.huge);
        final double padH = narrow ? AppSpacing.lg : padV;
        // На узком экране панель оценок занимает больше высоты (сетка 2×2) —
        // сжимаем поля и приглушённый вопрос, чтобы ответ читался без прокрутки.
        final double bodyPadV = narrow ? AppSpacing.md : padV;
        // Текстовая колонка — 45–75 знаков (G7): на 2K/4K строки не
        // растягиваются на всю ширину карточки.
        final double columnWidth = math.max(
          200,
          math.min(
            width - padH * 2,
            AppSizes.studyTextColumnBase * (narrow ? 1 : factor),
          ),
        );
        final double columnInset = math.max(padH, (width - columnWidth) / 2);
        final Duration flipDuration = AppMotion.duration(
          context,
          kReviewCardFlipDuration,
        );
        if (_controller.duration != flipDuration) {
          _controller.duration = flipDuration;
        }
        return AnimatedBuilder(
          animation: _curved,
          builder: (BuildContext context, Widget? child) {
            final double value = _curved.value.clamp(0.0, 1.0);
            final bool showBack = value >= 0.5;
            final Matrix4 transform = Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(math.pi * value);
            final Widget face = showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _buildRevealed(
                      context,
                      theme,
                      questionSize: questionSize,
                      answerSize: answerSize,
                      padH: padH,
                      padV: padV,
                      bodyPadV: bodyPadV,
                      narrow: narrow,
                      columnWidth: columnWidth,
                      columnInset: columnInset,
                    ),
                  )
                : _buildQuestion(
                    context,
                    theme,
                    questionSize: questionSize,
                    padH: padH,
                    padV: padV,
                    bodyPadV: bodyPadV,
                    narrow: narrow,
                    columnWidth: columnWidth,
                    columnInset: columnInset,
                  );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Transform(
                alignment: Alignment.center,
                transform: transform,
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: AppRadii.cardRadius,
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: AppSizes.borderWidth,
                    ),
                    boxShadow: AppShadows.card(theme.brightness),
                  ),
                  child: face,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Лицевая сторона: надзаголовок, вопрос по центру, главное действие внизу.
  Widget _buildQuestion(
    BuildContext context,
    ThemeData theme, {
    required double questionSize,
    required double padH,
    required double padV,
    required double bodyPadV,
    required bool narrow,
    required double columnWidth,
    required double columnInset,
  }) {
    final Widget? footer = widget.questionFooter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(columnInset, padV, columnInset, 0),
          child: _SideLabel(
            label: AppLocalizations.of(context).reviewQuestionLabel,
          ),
        ),
        Expanded(
          // Семантика только текста стороны: кнопки под карточкой (действие,
          // оценки) остаются отдельными узлами дерева доступности.
          child: Semantics(
            label: widget.front,
            excludeSemantics: true,
            child: _CardBody(
              scroll: _scroll,
              padding: EdgeInsets.fromLTRB(padH, AppSpacing.md, padH, bodyPadV),
              columnWidth: columnWidth,
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
                  imageMaxHeight: math.max(160, availableHeight * 0.62),
                  imageMaxWidth: columnWidth,
                ),
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: EdgeInsets.fromLTRB(padH, 0, padH, padV),
            child: SizedBox(
              key: const ValueKey<String>('review-card-actions'),
              child: footer,
            ),
          ),
      ],
    );
  }

  /// Обратная сторона: приглушённый вопрос, ответ, изображения и оценки внизу.
  Widget _buildRevealed(
    BuildContext context,
    ThemeData theme, {
    required double questionSize,
    required double answerSize,
    required double padH,
    required double padV,
    required double bodyPadV,
    required bool narrow,
    required double columnWidth,
    required double columnInset,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget? footer = widget.answerFooter;
    // Повтор вопроса — второстепенный контекст (приглушённый), ответ — самый
    // крупный текст карточки (аудит v4, V4).
    final TextStyle mutedQuestion = theme.textTheme.titleSmall!.copyWith(
      // На узком экране повтор вопроса меньше: место нужно ответу и оценкам.
      fontSize: narrow ? 17 : math.max(18, questionSize * 0.48),
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    );
    final TextStyle answerStyle = theme.textTheme.bodyLarge!.copyWith(
      fontSize: answerSize,
      // Аудит v7 (G7): 1,55 выходило за норму 1,3–1,5.
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
    );
    final bool occlusion = widget.card?.occlusionJson != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
              padding: EdgeInsets.fromLTRB(padH, AppSpacing.xs, padH, bodyPadV),
              columnWidth: columnWidth,
              builder: (double availableHeight) => <Widget>[
                _content(
                  theme,
                  context,
                  side: widget.front,
                  revealed: true,
                  style: mutedQuestion,
                  // Холст occlusion-карточки рисуется на стороне вопроса с уже
                  // раскрытыми масками (revealed: true).
                  media: true,
                  imageMaxHeight: math.max(140, availableHeight * 0.42),
                  imageMaxWidth: columnWidth,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Row(
                    children: <Widget>[
                      const Expanded(child: Divider(height: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: _SideLabel(
                          label: l10n.reviewAnswerLabel,
                          accent: true,
                        ),
                      ),
                      const Expanded(child: Divider(height: 1)),
                    ],
                  ),
                ),
                _content(
                  theme,
                  context,
                  side: widget.back,
                  revealed: true,
                  style: answerStyle,
                  // Для occlusion холст уже нарисован выше — второй раз не
                  // рисуем; для cloze вопрос показан выше.
                  media: !occlusion,
                  includeClozeFront: false,
                  imageMaxHeight: math.max(180, availableHeight * 0.62),
                  imageMaxWidth: columnWidth,
                ),
              ],
            ),
          ),
        ),
        if (footer != null)
          // G9: появление панели оценок — fade + сдвиг 12 px из общей шкалы
          // (220 мс), а не мгновенная подмена цвета кнопок.
          _FadeSlideIn(
            key: const ValueKey<String>('review-rating-panel'),
            child: Padding(
              padding: EdgeInsets.fromLTRB(padH, 0, padH, padV),
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
  }) {
    final domain.Card? card = widget.card;
    if (card == null) {
      return Text(
        side,
        key: const ValueKey<String>('review-card-face'),
        textAlign: TextAlign.center,
        style: style,
      );
    }
    return CardContentView(
      card: card,
      side: side,
      revealed: revealed,
      faceKey: const ValueKey<String>('review-card-face'),
      questionStyle: style,
      answerStyle: style,
      mediaBytes: widget.mediaBytes,
      mediaMetadata: widget.mediaMetadata,
      onRetryMedia: widget.onRetryMedia,
      showMedia: media,
      includeClozeFront: includeClozeFront,
      imageMaxHeight: imageMaxHeight,
      imageMaxWidth: imageMaxWidth,
    );
  }
}

/// Однократное появление панели: fade 0→1 и сдвиг снизу 12 px.
///
/// Учитывает reduced motion ([AppMotion.reduce]): при системной настройке
/// «уменьшить движение» панель появляется сразу.
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

/// Тело карточки: короткое содержимое центрируется, длинное — прокручивается
/// внутри карточки с видимым индикатором (ничего не обрезается молча).
class _CardBody extends StatefulWidget {
  const _CardBody({
    required this.scroll,
    required this.padding,
    required this.columnWidth,
    required this.builder,
  });

  final ScrollController scroll;
  final EdgeInsets padding;

  /// Предел ширины текстовой колонки: содержимое центрируется, но строки не
  /// растягиваются на всю ширину карточки.
  final double columnWidth;

  final List<Widget> Function(double availableHeight) builder;

  @override
  State<_CardBody> createState() => _CardBodyState();
}

class _CardBodyState extends State<_CardBody> {
  /// Показывать ли постоянно индикатор прокрутки (контент не влезает).
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
              // Уведомление приходит во время layout — setState только после
              // кадра, иначе Flutter остановит сборку.
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
                    minHeight: availableHeight,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
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