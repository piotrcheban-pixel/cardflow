import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/session_card.dart';
import 'package:cardflow/ui/state/platform_info.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Карточка режима «Лента» (ADR-044, TASK 04).
///
/// Отдельный дизайн, а не уменьшенная «Классика»:
///
/// * одна крупная карточка на страницу, поля 12/16, мягкая тень — карточка
///   читается как лист;
/// * лицевая сторона — вопрос, надзаголовок и одно действие «Показать ответ»;
/// * **оборот показывает только ответ** — вопрос и его изображения не
///   дублируются (требование владельца, TASK 04 M-04);
/// * переворот — собственная Y-анимация 260–300 мс (`AppDurations.flip`),
///   учитывающая системное уменьшение движения; повторный тап возвращает
///   вопрос;
/// * длинный текст не прокручивается внутри страницы (это ломало вертикальные
///   свайпы): тело показывает градиент обрезки и действие «Открыть полностью»
///   **в нижней полосе**, а не поверх строк (M-05).
class FeedCardView extends StatefulWidget {
  /// Создаёт карточку ленты.
  const FeedCardView({
    required this.front,
    required this.back,
    required this.revealed,
    required this.onTap,
    this.card,
    this.mediaBytes = const <String, Uint8List>{},
    this.mediaMetadata = const <String, MediaMetadata>{},
    this.onRetryMedia,
    this.compact = false,
    super.key,
  });

  /// Текст вопроса.
  final String front;

  /// Текст ответа.
  final String back;

  /// Показан ли ответ.
  final bool revealed;

  /// Тап по карточке: раскрыть/скрыть ответ.
  final VoidCallback onTap;

  /// Полная карточка для разметки (cloze, LaTeX, occlusion, медиа).
  final Card? card;

  /// Байты изображений по `media.id`.
  final Map<String, Uint8List> mediaBytes;

  /// Атрибуция и вид иллюстраций по `media.id`.
  final Map<String, MediaMetadata> mediaMetadata;

  /// Повтор чтения медиа карточки после ошибки.
  final VoidCallback? onRetryMedia;

  /// Низкое окно: уменьшенные поля и кегль.
  final bool compact;

  @override
  State<FeedCardView> createState() => _FeedCardViewState();
}

class _FeedCardViewState extends State<FeedCardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController.unbounded(
    vsync: this,
    duration: AppDurations.flip,
    value: widget.revealed ? 1 : 0,
  );
  bool _hovered = false;
  bool _overflow = false;

  /// Какая сторона нарисована (TASK 04, часть 7): переключается один раз на
  /// середине переворота, а не пересобирает содержимое каждый кадр.
  bool _showBack = false;

  /// Идёт переворот: тяжёлая тень выключается (часть 7).
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _showBack = widget.revealed;
    _flip.addListener(_handleFlipTick);
    _flip.addStatusListener(_handleStatus);
  }

  void _handleFlipTick() {
    final bool showBack = _flip.value >= 0.5;
    if (showBack == _showBack) return;
    _showBack = showBack;
    if (mounted) setState(() {});
  }

  void _handleStatus(AnimationStatus status) {
    final bool animating = _flip.isAnimating;
    if (animating == _animating || !mounted) return;
    setState(() => _animating = animating);
  }

  @override
  void didUpdateWidget(FeedCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealed != widget.revealed) {
      final Duration duration = AppMotion.duration(context, AppDurations.flip);
      if (duration == Duration.zero) {
        _flip.value = widget.revealed ? 1 : 0;
        _showBack = widget.revealed;
      } else {
        _flip.animateTo(
          widget.revealed ? 1 : 0,
          duration: duration,
          curve: AppMotion.expressive,
        );
      }
    }
  }

  @override
  void dispose() {
    _flip.removeListener(_handleFlipTick);
    _flip.removeStatusListener(_handleStatus);
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double factor = AppAdaptive.factorForContext(context)
        .clamp(1.0, 1.45);
    final double windowWidth = MediaQuery.sizeOf(context).width;
    final double windowHeight = MediaQuery.sizeOf(context).height;
    final bool narrow = windowWidth < AppSizes.mobileBreakpoint;
    final bool veryShort = windowHeight < 520 || widget.compact;
    final double padH = narrow ? AppSpacing.lg : AppSpacing.xxl;
    final double padV = veryShort ? AppSpacing.md : AppSpacing.lg;
    final double cardWidth = AppSizes.studyCardWidth(windowWidth);
    final double textColumn = math.min(
      math.max(220, windowWidth - (narrow ? 24 : 48) - padH * 2),
      820,
    );
    final double questionSize = veryShort
        ? (narrow ? 24 : 28)
        : SessionCard.questionSizeFor(cardWidth, factor);
    final double answerSize = veryShort
        ? (narrow ? 19 : 22)
        : SessionCard.answerSizeFor(questionSize);
    // Та же раскладка «текст + картинка рядом», что в «Классике»: правило
    // `cardWidth >= 760` (TASK 04, часть 6) — иначе лента уменьшала фото.
    final bool wideMedia = cardWidth >= 760;
    final Color borderColor = _hovered ? scheme.primary : scheme.outlineVariant;
    // Сторона выбирается один раз на середине переворота; кадры двигают только
    // кэшированный растр (часть 7).
    final Widget face = _FeedFace(
      // Ключ стабилен, как и раньше: при смене стороны обновляется `builder`,
      // а прокрутка/переполнение сохраняют состояние (тесты и семантика).
      key: const ValueKey<String>('feed-face'),
      padH: padH,
      padV: padV,
      textColumn: textColumn,
      onOverflowChanged: (bool value) {
        if (value != _overflow && mounted) {
          setState(() => _overflow = value);
        }
      },
      builder: (double availableHeight) => _showBack
          ? _answerBody(
              theme,
              l10n,
              answerSize: answerSize,
              availableHeight: availableHeight,
              wideMedia: wideMedia,
              textColumn: textColumn,
              cardWidth: cardWidth,
            )
          : _questionBody(
              theme,
              l10n,
              questionSize: questionSize,
              answerSize: answerSize,
              availableHeight: availableHeight,
              wideMedia: wideMedia,
              textColumn: textColumn,
              cardWidth: cardWidth,
              narrow: narrow,
            ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? AppSpacing.sm : AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.panel),
              // Тень — только в покое: во время переворота BoxShadow не
              // пересчитывается каждый кадр (часть 7).
              boxShadow: _animating ? null : AppShadows.card(theme.brightness),
            ),
            child: Material(
              color: scheme.surfaceContainerLowest,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.panel),
                side: BorderSide(
                  color: borderColor,
                  width: AppSizes.borderWidth,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padH,
                      veryShort ? AppSpacing.xs : AppSpacing.md,
                      padH,
                      0,
                    ),
                    child: _FeedSideLabel(
                      key: const ValueKey<String>('feed-side-label'),
                      label: _showBack
                          ? l10n.reviewAnswerLabel
                          : l10n.reviewQuestionLabel,
                      revealed: _showBack,
                    ),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _flip,
                      child: RepaintBoundary(child: face),
                      builder: (BuildContext context, Widget? child) {
                        final double value = _flip.value.clamp(0.0, 1.0);
                        final Matrix4 transform = Matrix4.identity()
                          ..setEntry(3, 2, 0.0015)
                          ..rotateY(math.pi * value);
                        if (_showBack) transform.rotateY(math.pi);
                        return Transform(
                          key: const ValueKey<String>('feed-flip-transform'),
                          alignment: Alignment.center,
                          transform: transform,
                          child: child,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padH,
                      veryShort ? AppSpacing.xs : AppSpacing.sm,
                      padH,
                      veryShort ? AppSpacing.xs : padV,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (_overflow)
                          TextButton.icon(
                            key: const ValueKey<String>('feed-read-full'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                0,
                                AppSizes.minTouchTarget,
                              ),
                            ),
                            onPressed: () => _openFullText(context),
                            icon: const Icon(
                              Icons.open_in_full,
                              size: AppSizes.iconSmall,
                            ),
                            label: Text(l10n.feedReadFullText),
                          ),
                        if (widget.revealed)
                          _NavHint(l10n: l10n)
                        else
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    AppSizes.revealButtonMaxWidth *
                                    factor.clamp(1.0, 1.2),
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  key: const ValueKey<String>(
                                    'feed-card-reveal',
                                  ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(
                                      AppSizes.minTouchTarget,
                                    ),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(AppRadii.input),
                                      ),
                                    ),
                                  ),
                                  onPressed: widget.onTap,
                                  child: Text(l10n.reviewRevealAction),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _questionBody(
    ThemeData theme,
    AppLocalizations l10n, {
    required double questionSize,
    required double answerSize,
    required double availableHeight,
    required bool narrow,
    required bool wideMedia,
    required double textColumn,
    required double cardWidth,
  }) {
    // TASK 04, часть 6: тот же бюджет изображения, что в «Классике»
    // (`CardImageBudget.side`) — в ленте фото больше не уменьшено.
    final CardImageBudget imageBudget = CardImageBudget.side(
      availableHeight: availableHeight,
      columnWidth: textColumn,
      sideBySide: wideMedia,
    );
    final Card? card = widget.card;
    final TextStyle questionStyle = theme.textTheme.headlineMedium!.copyWith(
      fontSize: questionSize,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: theme.colorScheme.onSurface,
    );
    final TextStyle answerStyle = theme.textTheme.bodyLarge!.copyWith(
      fontSize: answerSize,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurface,
    );
    if (card == null) {
      return <Widget>[
        Text(
          widget.front,
          key: const ValueKey<String>('feed-card-face'),
          textAlign: TextAlign.center,
          style: questionStyle,
        ),
      ];
    }
    return <Widget>[
      CardContentView(
        card: card,
        side: widget.front,
        revealed: false,
        faceKey: const ValueKey<String>('feed-card-face'),
        questionStyle: questionStyle,
        answerStyle: answerStyle,
        mediaBytes: widget.mediaBytes,
        mediaMetadata: widget.mediaMetadata,
        onRetryMedia: widget.onRetryMedia,
        imageMaxHeight: imageBudget.maxHeight,
        imageMaxWidth: imageBudget.maxWidth,
        sideBySide: wideMedia,
        mediaAfterText: true,
      ),
      if (narrow) const SizedBox(height: AppSpacing.xs),
    ];
  }

  List<Widget> _answerBody(
    ThemeData theme,
    AppLocalizations l10n, {
    required double answerSize,
    required double availableHeight,
    required bool wideMedia,
    required double textColumn,
    required double cardWidth,
  }) {
    final CardImageBudget imageBudget = CardImageBudget.side(
      availableHeight: availableHeight,
      columnWidth: textColumn,
      sideBySide: wideMedia,
      isAnswer: true,
    );
    final Card? card = widget.card;
    final TextStyle answerStyle = theme.textTheme.bodyLarge!.copyWith(
      fontSize: answerSize,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurface,
    );
    if (card == null) {
      return <Widget>[
        Text(
          widget.back,
          key: const ValueKey<String>('feed-card-face'),
          textAlign: TextAlign.center,
          style: answerStyle,
        ),
      ];
    }
    return <Widget>[
      // Только ответ: вопроса и его изображений на обороте нет (M-04).
      CardContentView(
        card: card,
        side: widget.back,
        revealed: true,
        faceKey: const ValueKey<String>('feed-card-face'),
        questionStyle: answerStyle,
        answerStyle: answerStyle,
        mediaBytes: widget.mediaBytes,
        mediaMetadata: widget.mediaMetadata,
        onRetryMedia: widget.onRetryMedia,
        includeClozeFront: false,
        imageMaxHeight: imageBudget.maxHeight,
        imageMaxWidth: imageBudget.maxWidth,
        sideBySide: wideMedia,
        mediaAfterText: true,
      ),
    ];
  }

  /// Полный текст карточки в отдельном листе: длинный вопрос/ответ не
  /// встраивается прокруткой в страницу ленты (это ломало свайпы), а
  /// открывается читаемым листом.
  void _openFullText(BuildContext context) {
    final Card? card = widget.card;
    final AppLocalizations l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        final ThemeData sheetTheme = Theme.of(sheetContext);
        final ColorScheme scheme = sheetTheme.colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppSheetHeader(
                title: l10n.feedFullTextTitle,
                icon: Icons.menu_book_outlined,
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: card == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.front,
                              style: sheetTheme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              widget.back,
                              style: sheetTheme.textTheme.bodyLarge,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              widget.front,
                              style: sheetTheme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Divider(color: scheme.outlineVariant),
                            const SizedBox(height: AppSpacing.sm),
                            CardContentView(
                              card: card,
                              side: card.back,
                              revealed: true,
                              faceKey: const ValueKey<String>('feed-full-text'),
                              questionStyle: sheetTheme.textTheme.titleMedium,
                              answerStyle: sheetTheme.textTheme.bodyLarge,
                              mediaBytes: widget.mediaBytes,
                              mediaMetadata: widget.mediaMetadata,
                              onRetryMedia: widget.onRetryMedia,
                              imageMaxHeight: CardImageBudget.sheet.maxHeight,
                              imageMaxWidth: CardImageBudget.sheet.maxWidth,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Тело грани карточки с измерением переполнения.
///
/// Если содержимое выше доступной высоты, снизу появляется градиент, а в
/// нижней полосе — «Открыть полностью». Сам текст не перекрывается кнопкой
/// (M-05).
class _FeedFace extends StatefulWidget {
  const _FeedFace({
    required this.builder,
    required this.padH,
    required this.padV,
    required this.textColumn,
    required this.onOverflowChanged,
    super.key,
  });

  final List<Widget> Function(double availableHeight) builder;
  final double padH;
  final double padV;
  final double textColumn;
  final ValueChanged<bool> onOverflowChanged;

  @override
  State<_FeedFace> createState() => _FeedFaceState();
}

class _FeedFaceState extends State<_FeedFace> {
  final ScrollController _scroll = ScrollController();
  bool _overflow = false;

  /// Проверка переполнения уже запланирована на этот кадр.
  ///
  /// TASK 04, часть 7: `addPostFrameCallback` в `build` без этого флага
  /// добавлял колбэк **каждый кадр** анимации переворота — лишние layout-
  /// проверки и `setState` во время вращения были частью микро-фризов.
  bool _checkScheduled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Проверяет, помещается ли содержимое, после раскладки.
  ///
  /// `ScrollMetricsNotification` приходит не на первом кадре и не всегда —
  /// без явной проверки кнопка «Открыть полностью» не появлялась, и длинный
  /// ответ обрезался молча (TASK 04, M-05).
  void _checkOverflow() {
    if (!mounted || !_scroll.hasClients) return;
    final bool overflow = _scroll.position.maxScrollExtent > 1;
    if (overflow == _overflow) return;
    setState(() => _overflow = overflow);
    widget.onOverflowChanged(overflow);
  }

  void _scheduleOverflowCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      _checkOverflow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    _scheduleOverflowCheck();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableHeight = math.max(
          0,
          constraints.maxHeight - widget.padV * 2,
        );
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (ScrollMetricsNotification notification) {
            if (mounted) _checkOverflow();
            return false;
          },
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scroll,
                  // Прокрутка только программная: жесты и колесо принадлежат
                  // ленте (иначе PageView и вложенный Scrollable конфликтуют —
                  // исходный дефект режима ленты).
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.padH,
                    vertical: widget.padV,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.textColumn,
                        minHeight: availableHeight,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: widget.builder(availableHeight),
                      ),
                    ),
                  ),
                ),
              ),
              if (_overflow)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      key: const ValueKey<String>('feed-body-fade'),
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            scheme.surfaceContainerLowest.withValues(alpha: 0),
                            scheme.surfaceContainerLowest,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Надзаголовок стороны карточки («Вопрос»/«Ответ»).
class _FeedSideLabel extends StatelessWidget {
  const _FeedSideLabel({
    required this.label,
    required this.revealed,
    super.key,
  });

  final String label;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: revealed ? scheme.secondary : scheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label.toUpperCase(),
          style: AppTypography.overline(
            context,
            color: revealed ? scheme.secondary : scheme.primary,
          ),
        ),
      ],
    );
  }
}

/// Подсказка о навигации на обороте карточки.
class _NavHint extends StatelessWidget {
  const _NavHint({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.swap_vert,
          size: AppSizes.iconSmall,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xxs + 2),
        Flexible(
          child: Text(
            PlatformInfo.hasPhysicalKeyboard
                ? l10n.feedNavHint
                : l10n.feedAnswerNavHint,
            key: const ValueKey<String>('feed-nav-hint'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.caption(
              context,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
