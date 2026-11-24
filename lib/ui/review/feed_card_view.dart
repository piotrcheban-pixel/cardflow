import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/components/app_buttons.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Карточка режима «Лента» (ADR-044).
///
/// Отдельный дизайн, а не уменьшенная «Классика»:
///
/// * одна крупная карточка на страницу, поля 16/24, мягкая тень и
///   expresивный радиус — карточка читается как лист, а не как панель;
/// * лицевая сторона — вопрос, надзаголовок и одно действие «Показать ответ»;
/// * оборот — приглушённый вопрос, ответ и спокойная подсказка о навигации;
/// * никаких кнопок оценки, номеров и прогнозов: просмотр не меняет FSRS;
/// * длинный текст не превращает карточку во вложенную прокрутку (это ломало
///   вертикальные свайпы): тело карточки не скроллится, а при переполнении
///   показывает действие «Открыть полностью» с читаемым листом.
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

class _FeedCardViewState extends State<FeedCardView> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double factor = AppAdaptive.factorForContext(context)
        .clamp(1.0, 1.45);
    final double windowWidth = MediaQuery.sizeOf(context).width;
    final double windowHeight = MediaQuery.sizeOf(context).height;
    final bool narrow = windowWidth < 560;
    final bool veryShort = windowHeight < 520 || widget.compact;
    final double padH = narrow ? AppSpacing.lg : AppSpacing.xxl;
    final double padV = veryShort ? AppSpacing.md : AppSpacing.xl;
    final double questionSize = veryShort
        ? (narrow ? 24 : 28)
        : (narrow ? 28 : math.min(46, 30 * factor + 4));
    final double answerSize = veryShort
        ? (narrow ? 19 : 22)
        : (narrow ? 22 : math.min(34, 23 * factor + 2));
    final bool wideMedia = windowWidth >= 1000;
    final Color borderColor = _hovered ? scheme.primary : scheme.outlineVariant;
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
              boxShadow: AppShadows.card(theme.brightness),
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
                      label: widget.revealed
                          ? l10n.reviewAnswerLabel
                          : l10n.reviewQuestionLabel,
                      revealed: widget.revealed,
                    ),
                  ),
                  Expanded(
                    child: _FeedOverflowBody(
                      compact: veryShort,
                      padH: padH,
                      padV: padV,
                      columnWidth: _textColumnWidth(
                        windowWidth: windowWidth,
                        padH: padH,
                        factor: factor,
                      ),
                      onReadFull: () => _openFullText(context),
                      builder: (double availableHeight) => _body(
                        theme,
                        l10n,
                        questionSize: questionSize,
                        answerSize: answerSize,
                        availableHeight: availableHeight,
                        wideMedia: wideMedia,
                        narrow: narrow,
                        columnWidth: _textColumnWidth(
                          windowWidth: windowWidth,
                          padH: padH,
                          factor: factor,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padH,
                      veryShort ? AppSpacing.xs : AppSpacing.sm,
                      padH,
                      veryShort ? AppSpacing.xs : padV,
                    ),
                    child: widget.revealed
                        ? _NavHint(l10n: l10n)
                        : Center(
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
                                  style: AppButtons.cardAction(context),
                                  onPressed: widget.onTap,
                                  child: Text(l10n.reviewRevealAction),
                                ),
                              ),
                            ),
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

  /// Текстовая колонка: 45–75 знаков, но не шире карточки.
  double _textColumnWidth({
    required double windowWidth,
    required double padH,
    required double factor,
  }) {
    final double cardWidth = AppSizes.studyCardWidth(windowWidth);
    return math.max(
      220,
      math.min(
        cardWidth - padH * 2,
        AppSizes.studyTextColumnBase * factor * 0.9,
      ),
    );
  }

  List<Widget> _body(
    ThemeData theme,
    AppLocalizations l10n, {
    required double questionSize,
    required double answerSize,
    required double availableHeight,
    required bool wideMedia,
    required bool narrow,
    required double columnWidth,
  }) {
    final Card? card = widget.card;
    if (card == null) {
      final TextStyle style = theme.textTheme.headlineMedium!.copyWith(
        fontSize: widget.revealed ? answerSize : questionSize,
        height: 1.4,
        fontWeight: widget.revealed ? FontWeight.w400 : FontWeight.w600,
        letterSpacing: -0.3,
        color: theme.colorScheme.onSurface,
      );
      return <Widget>[
        Text(
          widget.revealed ? widget.back : widget.front,
          key: const ValueKey<String>('feed-card-face'),
          textAlign: TextAlign.center,
          style: style,
        ),
      ];
    }
    final bool occlusion = card.occlusionJson != null;
    final double imageMaxHeight = math.max(160, availableHeight * 0.72);
    final TextStyle questionStyle = theme.textTheme.headlineMedium!.copyWith(
      fontSize: questionSize,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: theme.colorScheme.onSurface,
    );
    final TextStyle mutedQuestion = theme.textTheme.titleSmall!.copyWith(
      fontSize: narrow ? 16 : math.max(17, questionSize * 0.46),
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final TextStyle answerStyle = theme.textTheme.bodyLarge!.copyWith(
      fontSize: answerSize,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurface,
    );
    if (!widget.revealed) {
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
          imageMaxHeight: imageMaxHeight,
          imageMaxWidth: wideMedia ? columnWidth * 0.6 : columnWidth,
          sideBySide: wideMedia,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.feedBrowseHint,
          textAlign: TextAlign.center,
          style: AppTypography.caption(
            context,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }
    return <Widget>[
      CardContentView(
        card: card,
        side: widget.front,
        revealed: true,
        faceKey: const ValueKey<String>('feed-card-echo'),
        questionStyle: mutedQuestion,
        answerStyle: mutedQuestion,
        mediaBytes: widget.mediaBytes,
        mediaMetadata: widget.mediaMetadata,
        onRetryMedia: widget.onRetryMedia,
        imageMaxHeight: math.max(120, availableHeight * 0.4),
        imageMaxWidth: columnWidth,
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Divider(height: 1),
      ),
      CardContentView(
        card: card,
        side: widget.back,
        revealed: true,
        faceKey: const ValueKey<String>('feed-card-face'),
        questionStyle: questionStyle,
        answerStyle: answerStyle,
        mediaBytes: widget.mediaBytes,
        mediaMetadata: widget.mediaMetadata,
        onRetryMedia: widget.onRetryMedia,
        includeClozeFront: false,
        imageMaxHeight: occlusion ? imageMaxHeight : imageMaxHeight,
        imageMaxWidth: wideMedia ? columnWidth * 0.6 : columnWidth,
        sideBySide: wideMedia,
      ),
    ];
  }

  /// Полный текст карточки в отдельном листе: длинный вопрос/ответ не
  /// встраивается прокруткой в страницу ленты (это ломало свайпы), а
  /// открывается читаемым листом.
  void _openFullText(BuildContext context) {
    final Card? card = widget.card;
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (card == null) {
      showAppSheet<void>(
        context: context,
        builder: (BuildContext sheetContext) => Padding(
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.front,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        widget.back,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }
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
                  child: CardContentView(
                    card: card,
                    side: card.back,
                    revealed: true,
                    faceKey: const ValueKey<String>('feed-full-text'),
                    questionStyle: sheetTheme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    answerStyle: sheetTheme.textTheme.bodyLarge,
                    mediaBytes: widget.mediaBytes,
                    mediaMetadata: widget.mediaMetadata,
                    onRetryMedia: widget.onRetryMedia,
                    imageMaxHeight: 320,
                    imageMaxWidth: 520,
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
            l10n.feedNavHint,
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

/// Тело карточки без вложенной прокрутки.
///
/// Если содержимое выше доступной высоты, снизу появляется «Открыть
/// полностью»: сама карточка остаётся статичной, поэтому вертикальный свайп
/// и колесо мыши всегда управляют лентой, а не текстом внутри неё.
class _FeedOverflowBody extends StatefulWidget {
  const _FeedOverflowBody({
    required this.builder,
    required this.padH,
    required this.padV,
    required this.columnWidth,
    required this.onReadFull,
    required this.compact,
  });

  final List<Widget> Function(double availableHeight) builder;
  final double padH;
  final double padV;
  final double columnWidth;
  final VoidCallback onReadFull;
  final bool compact;

  @override
  State<_FeedOverflowBody> createState() => _FeedOverflowBodyState();
}

class _FeedOverflowBodyState extends State<_FeedOverflowBody> {
  final ScrollController _controller = ScrollController();
  bool _overflow = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableHeight = math.max(
          0,
          constraints.maxHeight - widget.padV * 2,
        );
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (ScrollMetricsNotification notification) {
            final bool overflow = notification.metrics.maxScrollExtent > 1;
            if (overflow != _overflow) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && overflow != _overflow) {
                  setState(() => _overflow = overflow);
                }
              });
            }
            return false;
          },
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _controller,
                  // Прокрутка только программная: жесты и колесо принадлежат
                  // ленте (иначе PageView и вложенный Scrollable конфликтуют —
                  // исходный дефект режима ленты).
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.padH,
                    vertical: widget.padV,
                  ),
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
                        children: widget.builder(availableHeight),
                      ),
                    ),
                  ),
                ),
              ),
              if (_overflow)
                Positioned(
                  left: widget.padH,
                  right: widget.padH,
                  bottom: widget.compact ? 4 : AppSpacing.xs,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: TextButton.icon(
                        key: const ValueKey<String>('feed-read-full'),
                        onPressed: widget.onReadFull,
                        icon: const Icon(
                          Icons.open_in_full,
                          size: AppSizes.iconSmall,
                        ),
                        label: Text(
                          AppLocalizations.of(context).feedReadFullText,
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
