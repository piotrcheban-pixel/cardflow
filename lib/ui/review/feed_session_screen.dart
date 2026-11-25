import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';
import 'package:cardflow/ui/review/feed_keyboard.dart';
import 'package:cardflow/ui/review/feed_progress_bar.dart';
import 'package:cardflow/ui/review/feed_session_engine.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/review/session_media.dart';
import 'package:cardflow/ui/review/session_notice.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Экран режима «Лента» — свободный просмотр карточек (ADR-044).
///
/// Это **не** классическая сессия в другой раскладке:
///
/// * одна карточка на страницу, вертикальный `PageView`: свайп вверх/вниз,
///   колесо мыши, тачпад и клавиши листают на соседнюю карточку;
/// * после перехода сразу видна следующая карточка — никакого «докрутите
///   колесо», пустых кадров и исчезающих карточек;
/// * никаких оценок, FSRS, дневных лимитов, авто-продвижения и undo: свайп —
///   навигация, а не ответ. Расписание повторений не меняется;
/// * тап по карточке раскрывает и скрывает ответ;
/// * длинный текст не прокручивается внутри страницы (это ломало вертикальные
///   свайпы): карточка показывает действие «Открыть полностью».
class FeedSessionScreen extends ConsumerStatefulWidget {
  /// Создаёт экран ленты для колоды [deckId].
  ///
  /// [plan] — очередь конструктора (SPEC A6.7, ADR-018): набор и порядок
  /// карточек уже выбраны пользователем.
  const FeedSessionScreen({this.deckId, this.plan, super.key});

  /// Идентификатор колоды.
  final String? deckId;

  /// План сессии конструктора; `null` — вся колода.
  final SessionPlan? plan;

  @override
  ConsumerState<FeedSessionScreen> createState() => _FeedSessionScreenState();
}

class _FeedSessionScreenState extends ConsumerState<FeedSessionScreen>
    with SessionNoticeMixin<FeedSessionScreen> {
  final PageController _pageController = PageController();
  FeedSessionEngine? _engine;
  Deck? _deck;
  int _deckCount = 1;
  bool _loading = true;
  bool _loadFailed = false;
  bool _planMissing = false;
  bool _timeExpired = false;
  bool _animating = false;

  /// Индекс страницы, которую видит пользователь (`total` — итог ленты).
  int _visibleIndex = 0;

  /// Пользователь долистал до итоговой страницы после последней карточки.
  bool _endReached = false;
  double _wheelAccumulator = 0;
  Timer? _wheelReset;
  Timer? _budgetTimer;
  SessionMedia _media = SessionMedia.empty;

  bool get _hasSource => widget.plan != null || widget.deckId != null;

  /// Haptics включены в настройках (A6.6, ADR-019 §2).
  bool get _hapticsEnabled => ref.read(effectiveAppSettingsProvider).haptics;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _wheelReset?.cancel();
    _budgetTimer?.cancel();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_hasSource) {
      setState(() {
        _loading = false;
        _loadFailed = false;
        _planMissing = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
      _planMissing = false;
      _timeExpired = false;
    });
    try {
      final SessionPlan? plan = widget.plan;
      final List<Card> cards = plan != null
          ? plan.cards
          : await ref.read(cardRepositoryProvider).cardsByDeck(widget.deckId!);
      final List<String> deckIds = plan != null
          ? <String>{for (final Card card in cards) card.deckId}
                .toList(growable: false)
          : <String>[widget.deckId!];
      final Deck? deck = deckIds.length == 1
          ? await ref.read(deckRepositoryProvider).deckById(deckIds.single)
          : null;
      final SessionMedia media = await loadSessionMedia(ref, cards);
      if (!mounted) return;
      final FeedSessionEngine engine = FeedSessionEngine(
        cards: cards,
        prebuilt: plan != null,
      )..addListener(_onEngineChanged);
      engine.start();
      setState(() {
        _deck = deck;
        _deckCount = deckIds.length;
        _engine = engine;
        _media = media;
        _loading = false;
      });
      _startBudgetTimer(plan?.timeBudget);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Лимит минут конструктора (SPEC A6.7): по истечении просмотр
  /// останавливается, карточки не оцениваются и расписание не меняется.
  void _startBudgetTimer(Duration? budget) {
    _budgetTimer?.cancel();
    _budgetTimer = null;
    if (budget == null) return;
    _budgetTimer = Timer(budget, () {
      if (!mounted) return;
      setState(() => _timeExpired = true);
    });
  }

  void _retry() {
    _budgetTimer?.cancel();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    _engine = null;
    unawaited(_load());
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _goTo(int index) async {
    final FeedSessionEngine? engine = _engine;
    if (engine == null ||
        _animating ||
        !_pageController.hasClients ||
        _timeExpired ||
        index < 0 ||
        index > engine.state.total ||
        index == _visibleIndex) {
      return;
    }
    _animating = true;
    try {
      if (AppMotion.reduce(context)) {
        _pageController.jumpToPage(index);
      } else {
        await _pageController.animateToPage(
          index,
          // Полноэкранный переход ленты — 240 мс: быстрее, чем 300 мс
          // прежней анимации, и без пружины (лента листается часто).
          duration: AppMotion.duration(context, AppDurations.medium),
          curve: AppMotion.enter,
        );
      }
    } finally {
      _animating = false;
    }
  }

  /// Завершение вертикального перехода страницы ленты.
  ///
  /// TASK 04 (M-13): после последней карточки есть отдельная итоговая
  /// страница — свайп вверх больше не «ничего не делает», а показывает
  /// результат просмотра и кнопку выхода.
  void _onPageChanged(int index) {
    _visibleIndex = index;
    final FeedSessionEngine? engine = _engine;
    final int total = engine?.state.total ?? 0;
    if (index >= total) {
      if (!_endReached) setState(() => _endReached = true);
      return;
    }
    if (_endReached) setState(() => _endReached = false);
    engine?.visit(index);
  }

  /// Колесо мыши и тачпад: одно движение — одна карточка.
  ///
  /// Обработчик стоит на самой странице (глубже `Scrollable` PageView) и
  /// забирает событие через `pointerSignalResolver`, поэтому колесо не
  /// проваливается во вложенный скролл и не требует «докрутить» страницу.
  /// Мелкие дельты тачпада накапливаются до порога; сброс — 220 мс.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolved,
    ) {
      if (resolved is! PointerScrollEvent) return;
      final FeedSessionEngine? engine = _engine;
      if (engine == null || _timeExpired) return;
      final double dy = resolved.scrollDelta.dy;
      if (dy == 0) return;
      // Одно и то же направление суммируется, смена — сбрасывает накопление.
      if (_wheelAccumulator != 0 && _wheelAccumulator.sign != dy.sign) {
        _wheelAccumulator = 0;
      }
      _wheelAccumulator += dy;
      _wheelReset?.cancel();
      _wheelReset = Timer(const Duration(milliseconds: 220), () {
        _wheelAccumulator = 0;
      });
      if (_wheelAccumulator.abs() < 40) return;
      final int direction = _wheelAccumulator > 0 ? 1 : -1;
      _wheelAccumulator = 0;
      unawaited(_goTo(engine.state.index + direction));
    });
  }

  void _toggleReveal() {
    final FeedSessionEngine? engine = _engine;
    if (engine == null || _timeExpired || _endReached) return;
    _toggleRevealAt(engine.state.index);
  }

  /// Раскрывает ответ конкретной карточки (тап по видимой странице).
  void _toggleRevealAt(int index) {
    final FeedSessionEngine? engine = _engine;
    if (engine == null || _timeExpired || _endReached) return;
    final List<FeedSessionItem> items = engine.state.items;
    if (index < 0 || index >= items.length) return;
    final bool willReveal = !items[index].revealed;
    engine.toggleRevealAt(index);
    if (willReveal && _hapticsEnabled) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final FeedSessionEngine? engine = _engine;
    if (engine == null) return KeyEventResult.ignored;
    return handleFeedSessionKey(
      event: event,
      onNext: () => unawaited(_goTo(engine.state.index + 1)),
      onPrevious: () => unawaited(_goTo(engine.state.index - 1)),
      onReveal: _toggleReveal,
      onFirst: () => unawaited(_goTo(0)),
      onLast: () => unawaited(_goTo(engine.state.total - 1)),
      onClose: () => unawaited(_confirmExit()),
    );
  }

  Future<void> _confirmExit() async {
    final FeedSessionEngine? engine = _engine;
    if (engine == null || engine.state.total == 0 || _timeExpired) {
      _leave();
      return;
    }
    final bool confirmed = await confirmReviewExit(
      context,
      kind: SessionExitKind.feed,
    );
    if (confirmed && mounted) _leave();
  }

  void _leave() {
    if (context.canPop()) context.pop();
  }

  Future<void> _retryMedia(Card card) async {
    final SessionMedia updated = await reloadSessionMedia(ref, <Card>[
      card,
    ], _media);
    if (!mounted) return;
    setState(() => _media = updated);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FeedSessionState? state = _engine?.state;
    final bool terminal =
        _planMissing ||
        _timeExpired ||
        (!_loading && !_loadFailed && (state?.total ?? 0) == 0);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Focus(
            autofocus: true,
            onKeyEvent: _handleKey,
            child: _buildBody(context, l10n, state, terminal: terminal),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    FeedSessionState? state, {
    required bool terminal,
  }) {
    if (_loading) return const ReviewLoadingView();
    if (_planMissing) return ReviewPlanMissingView(onBack: _leave);
    if (_loadFailed || state == null) {
      return ReviewLoadErrorView(onRetry: _retry);
    }
    if (state.total == 0) {
      return ReviewEmptyView(
        title: l10n.feedEmptyTitle,
        message: l10n.feedEmptyMessage,
        onBack: _leave,
      );
    }
    if (_timeExpired) {
      return _FeedTimeUpView(viewed: state.index + 1, onDone: _leave);
    }
    final double windowWidth = MediaQuery.sizeOf(context).width;
    final double windowHeight = MediaQuery.sizeOf(context).height;
    final bool compact = windowHeight < 560;
    // Карточка ленты живёт в той же контентной колонке, что классика:
    // 72 % окна на десктопе (иначе на 2K текст тонет в белом поле) и почти
    // вся ширина на телефоне. Прогресс и рейка навигации выровнены по ней.
    final double cardWidth = math.min(
      AppSizes.studyCardWidth(windowWidth),
      windowWidth - AppSpacing.sm * 2,
    );
    final double gutter = math.max(0, (windowWidth - cardWidth) / 2);
    // Высота листа: на телефоне карточка занимает всю полезную область, на
    // десктопе — 78 % рабочей высоты (полноэкранный «пустой холст» на 2K
    // выглядит как неиспользованное пространство, а не как карточка).
    final double pageHeight = math.max(
      320,
      windowHeight - AppSizes.headerHeightFor(context) - (compact ? 34 : 58),
    );
    final double cardHeight = windowWidth >= 900
        ? math.min(pageHeight, pageHeight * 0.78)
        : pageHeight;
    final String deckLabel =
        _deck?.name ??
        (_deckCount > 1
            ? l10n.sessionDeckCountLabel(_deckCount)
            : l10n.reviewModeFeed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _FeedHeader(
          title: deckLabel,
          showClose: !terminal,
          // TASK 04: на телефоне чип «Лента» отнимал у названия колоды место;
          // режим и так очевиден по композиции.
          showModeChip: windowWidth >= AppSizes.mobileBreakpoint,
          onClose: _confirmExit,
        ),
        Center(
          child: SizedBox(
            width: cardWidth,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.xs : AppSpacing.md,
                compact ? 0 : AppSpacing.xs,
                compact ? AppSpacing.xs : AppSpacing.md,
                compact ? 0 : AppSpacing.xs,
              ),
              child: FeedProgressBar(
                total: state.total,
                currentIndex: _endReached
                    ? state.total - 1
                    : math.min(state.index, state.total - 1),
                onSeek: (int index) => unawaited(_goTo(index)),
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: <Widget>[
              PageView.builder(
                key: const ValueKey<String>('feed-page-view'),
                controller: _pageController,
                scrollDirection: Axis.vertical,
                // TASK 04: после последней карточки — итоговая страница, чтобы
                // свайп вверх не упирался в границу без объяснения.
                itemCount: state.total + 1,
                // Страница всегда целиком: никаких частичных положений после
                // свайпа и никакой инерционной прокрутки через несколько карточек.
                physics: const PageScrollPhysics(),
                allowImplicitScrolling: false,
                onPageChanged: _onPageChanged,
                itemBuilder: (BuildContext context, int index) {
                  if (index >= state.total) {
                    return _FeedEndView(
                      total: state.total,
                      cardWidth: cardWidth,
                      onDone: _leave,
                    );
                  }
                  final FeedSessionItem item = state.items[index];
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: _onPointerSignal,
                    child: Center(
                      child: SizedBox(
                        width: cardWidth,
                        height: cardHeight,
                        child: FeedCardView(
                          key: ValueKey<String>('feed-card-${item.card.id}'),
                          front: item.card.front,
                          back: item.card.back,
                          card: item.card,
                          mediaBytes: _media.bytes,
                          mediaMetadata: _media.metadata,
                          onRetryMedia: () => _retryMedia(item.card),
                          revealed: item.revealed,
                          compact: compact,
                          onTap: () => _toggleRevealAt(index),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (windowWidth >= 1000 && state.total > 1 && gutter >= 120)
                Positioned(
                  right: math.max(AppSpacing.sm, gutter - 56),
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _FeedNavRail(
                      canPrevious: state.canGoPrevious,
                      canNext: state.canGoNext,
                      onPrevious: () => unawaited(_goTo(state.index - 1)),
                      onNext: () => unawaited(_goTo(state.index + 1)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (sessionNotice != null)
          SessionNotice(
            message: sessionNotice!,
            onDismiss: dismissSessionNotice,
            dismissTooltip: l10n.sessionNoticeDismiss,
          ),
      ],
    );
  }
}

/// Шапка ленты: выход, название колоды и бейдж режима просмотра.
class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.title,
    required this.showClose,
    required this.showModeChip,
    required this.onClose,
  });

  final String title;
  final bool showClose;

  /// Показывать ли чип «Лента»; на телефоне он скрыт (TASK 04, M-14).
  final bool showModeChip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SizedBox(
      height: AppSizes.headerHeightFor(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          children: <Widget>[
            if (showClose)
              IconButton(
                key: const ValueKey<String>('review-close'),
                tooltip: l10n.reviewCloseTooltip,
                icon: const Icon(Icons.arrow_back, size: AppSizes.navIcon),
                onPressed: onClose,
              )
            else
              const SizedBox(width: AppSpacing.sm),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (showModeChip)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  // Аудит 2.0 (P3-08): режим называется «Лента» везде — чип
                  // «Просмотр» расходился с названием в листе режимов.
                  l10n.feedBrowseBadgeV2,
                  key: const ValueKey<String>('feed-browse-badge'),
                  style: AppTypography.caption(context, color: scheme.primary),
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

/// Вертикальная рейка навигации для мыши (десктоп).
class _FeedNavRail extends StatelessWidget {
  const _FeedNavRail({
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onNext,
  });

  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          key: const ValueKey<String>('feed-previous'),
          tooltip: l10n.feedPreviousTooltip,
          onPressed: canPrevious ? onPrevious : null,
          style: IconButton.styleFrom(
            backgroundColor: scheme.surfaceContainerLowest,
            disabledForegroundColor: scheme.outlineVariant,
            side: BorderSide(color: scheme.outlineVariant),
          ),
          icon: const Icon(Icons.keyboard_arrow_up, size: AppSizes.iconLarge),
        ),
        const SizedBox(height: AppSpacing.xs),
        IconButton(
          key: const ValueKey<String>('feed-next'),
          tooltip: l10n.feedNextTooltip,
          onPressed: canNext ? onNext : null,
          style: IconButton.styleFrom(
            backgroundColor: scheme.surfaceContainerLowest,
            disabledForegroundColor: scheme.outlineVariant,
            side: BorderSide(color: scheme.outlineVariant),
          ),
          icon: const Icon(Icons.keyboard_arrow_down, size: AppSizes.iconLarge),
        ),
      ],
    );
  }
}

/// Итог просмотра: пользователь долистал ленту до конца (TASK 04).
class _FeedEndView extends StatelessWidget {
  const _FeedEndView({
    required this.total,
    required this.cardWidth,
    required this.onDone,
  });

  final int total;
  final double cardWidth;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cardWidth),
          child: AppEmptyState(
            key: const ValueKey<String>('feed-end'),
            hero: true,
            icon: Icons.done_all,
            metric: Text(total.toString()),
            title: l10n.feedEndTitle,
            message: l10n.feedEndMessage(total),
            actions: <Widget>[
              FilledButton(
                key: const ValueKey<String>('feed-end-done'),
                onPressed: onDone,
                child: Text(l10n.reviewDone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Итог просмотра по лимиту минут конструктора (ADR-018).
class _FeedTimeUpView extends StatelessWidget {
  const _FeedTimeUpView({required this.viewed, required this.onDone});

  final int viewed;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppSizes.studyCardWidth(MediaQuery.sizeOf(context).width),
          ),
          child: AppEmptyState(
            hero: true,
            icon: Icons.timer_off_outlined,
            metric: Text(viewed.toString()),
            title: l10n.reviewTimeUpTitle,
            message: l10n.feedTimeUpMessage(viewed),
            actions: <Widget>[
              FilledButton(
                key: const ValueKey<String>('feed-timeup-done'),
                onPressed: onDone,
                child: Text(l10n.reviewDone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
