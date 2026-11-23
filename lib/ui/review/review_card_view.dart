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
  bool _hovered = false;

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
        // Совсем низкое окно (844×390 физических при 150 % = 562×260 лог.):
        // надзаголовок отнимает место у вопроса — прячем его (G10).
        final bool cramped = height < 260;
        final double factor = AppAdaptive.factorForContext(context);
        final double questionSize = tight
            ? (narrow ? 26 : 28)
            : (narrow ? 28 : AppTypography.reviewQuestionSize * factor * 1.12);
        final double answerSize = tight
            ? 20
            : (narrow ? 22 : AppTypography.reviewAnswerSize * factor * 1.1);
        // Поля 24–48 лог. px (требование композиции): 24 на FullHD, ~30 на 2K.
        final double padV = tight
            ? AppSpacing.xs
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
        // F01/V3: карточка занимает не меньше 62 % рабочей области под
        // шапкой (2K live — ~540, 4K — ~1298), а не высоту кеглей 430×factor.
        // Высота при этом остаётся «по содержимому»: длинный вопрос растёт
        // до доступной области, короткий заполняет минимум равными полями.
        final double minHeight = math.min(
          height,
          AppSizes.studyCardMinHeightFor(context),
        );
        // F01/V3: карточка — главный объект постоянного размера: не меньше
        // 62 % рабочей области, содержимое центрируется, длинное — прокручивается
        // внутри (F27). Высота не «прыгает» между вопросами разной длины.
        final double cardHeight = math.max(0, minHeight);
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
                      cramped: cramped,
                      tight: tight,
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
                    cramped: cramped,
                    tight: tight,
                    columnWidth: columnWidth,
                    columnInset: columnInset,
                  );
            final BorderRadius shape = BorderRadius.circular(AppRadii.card);
            return MouseRegion(
              // F26: кликабельная карточка показывает курсор-указатель и
              // hover-подсветку — «тап раскрывает ответ» обнаруживается.
              cursor: SystemMouseCursors.click,
              onEnter: (_) {
                if (!_hovered) setState(() => _hovered = true);
              },
              onExit: (_) {
                if (_hovered) setState(() => _hovered = false);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: AppMotion.duration(context, AppDurations.quick),
                  curve: AppMotion.feedback,
                  constraints: BoxConstraints(
                    // Ширина задана окном (≥60 % на 2K/FullHD, G3), высота —
                    // 62 % рабочей области: карточка не «прыгает» по высоте.
                    minWidth: width,
                    maxWidth: width,
                    minHeight: cardHeight,
                    maxHeight: cardHeight,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: shape,
                    border: Border.all(
                      color: _hovered ? scheme.primary : scheme.outlineVariant,
                      width: AppSizes.borderWidth,
                    ),
                    boxShadow: AppShadows.card(theme.brightness),
                  ),
                  child: ClipRRect(
                    borderRadius: shape,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: transform,
                      child: face,
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

  /// Лицевая сторона: надзаголовок, вопрос по центру, главное действие внизу.
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
    return Column(
      // Верхняя подпись, центрированное содержимое и нижняя полоса действий,
      // прижатая к кромке карточки (полоса — часть карточки, а не «кнопка в
      // белом поле»).
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
                  // У occlusion-карточки под картинкой живут кнопки масок:
                  // оставляем им место, чтобы не прокручивать (F27).
                  imageMaxHeight: math.max(
                    widget.card?.occlusionJson != null ? 160 : 200,
                    availableHeight *
                        (widget.card?.occlusionJson != null ? 0.66 : 0.92),
                  ),
                  imageMaxWidth: columnWidth,
                ),
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
                // F17: главное действие — кнопка осмысленной ширины (240–480),
                // выровненная по контенту, а не полоса на всю карточку.
                constraints: BoxConstraints(
                  maxWidth:
                      AppSizes.revealButtonMaxWidth *
                      AppAdaptive.factorForContext(context).clamp(1.0, 1.2),
                ),
                child: SizedBox(
                  key: const ValueKey<String>('review-card-actions'),
                  width: double.infinity,
                  child: footer,
                ),
              ),
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
    required bool cramped,
    required bool tight,
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
              padding: EdgeInsets.fromLTRB(padH, AppSpacing.xs, padH, bodyPadV),
              columnWidth: columnWidth,
              builder: (double availableHeight) => <Widget>[
                // В совсем низком окне повтор вопроса не нужен: главное — ответ
                // и оценки, иначе на экране остаётся только вопрос (G10).
                if (!cramped) ...<Widget>[
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
                  // Один и тот же каркас сторон во всех режимах: разделитель,
                  // подпись «ОТВЕТ» слева, затем ответ. Раньше в классике
                  // подпись стояла между двумя линиями по центру, в ленте —
                  // слева под линией (F06).
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
                  // Для occlusion холст уже нарисован выше — второй раз не
                  // рисуем; для cloze вопрос показан выше.
                  media: !occlusion,
                  includeClozeFront: false,
                  imageMaxHeight: math.max(
                    occlusion ? 160 : 220,
                    availableHeight * (occlusion ? 0.66 : 0.92),
                  ),
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

/// Нижняя полоса карточки: действия отделены от содержимого спокойной
/// поверхностью и тонкой линией, а не висят в белом поле.
///
/// Вопрос («Показать ответ») и ответ (оценки) используют одну полосу, поэтому
/// все режимы выглядят как один компонент (F06).
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
            child: Stack(
              children: <Widget>[
                SingleChildScrollView(
                  controller: widget.scroll,
                  padding: widget.padding,
                  child: Center(
                    child: ConstrainedBox(
                      // Короткое содержимое центрируется по высоте тела
                      // карточки; длинное — прокручивается (F27).
                      constraints: BoxConstraints(
                        maxWidth: widget.columnWidth,
                        minHeight: math.max(0, availableHeight),
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
                // F27: у нижней кромки — мягкое затухание, если контент не
                // влез: видно, что карточку можно прокрутить, без стрелки.
                if (_canScroll)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 40,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLowest
                                  .withValues(alpha: 0),
                              Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLowest,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
