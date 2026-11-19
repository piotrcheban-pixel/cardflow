import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';
import 'package:cardflow/ui/review/feed_progress_bar.dart';
import 'package:cardflow/ui/review/feed_session_engine.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/review/session_media.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Экран режима «Лента» (SPEC A7.3, ADR-016).
///
/// Полноэкранный вертикальный `PageView.builder`, Stories-прогресс, свайпы-
/// оценки с порогами, авто-продвижение 3/5/8 с с паузой, undo/«Почему?»/выход
/// из общего каркаса A6.4. Записи — через [FeedSessionEngine] и
/// `ReviewRepository` (одна транзакция на оценку).
class FeedSessionScreen extends ConsumerStatefulWidget {
  /// Создаёт экран ленты для колоды [deckId] (режим колоды, ADR-016).
  ///
  /// [plan] — очередь конструктора (SPEC A6.7, ADR-018); при наличии
  /// загруженной колоды не требуется.
  ///
  /// [ignoreDailyLimits] — подтверждённое «Продолжить без лимита» (ADR-028).
  const FeedSessionScreen({
    this.deckId,
    this.plan,
    this.ignoreDailyLimits = false,
    super.key,
  });

  /// Идентификатор колоды.
  final String? deckId;

  /// План сессии конструктора; `null` — очередь из колоды.
  final SessionPlan? plan;

  /// Игнорировать дневные лимиты (`?limits=ignore`, ADR-028).
  final bool ignoreDailyLimits;

  /// Варианты интервала авто-продвижения (SPEC A7.3).
  static const List<int> autoAdvanceSeconds = <int>[3, 5, 8];

  /// Интервал авто-продвижения по умолчанию.
  static const Duration defaultAutoAdvance = Duration(seconds: 5);

  @override
  ConsumerState<FeedSessionScreen> createState() => _FeedSessionScreenState();
}

class _FeedSessionScreenState extends ConsumerState<FeedSessionScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  FeedSessionEngine? _engine;
  Deck? _deck;
  Timer? _autoAdvanceTimer;
  Timer? _budgetTimer;
  Duration _autoAdvanceInterval = FeedSessionScreen.defaultAutoAdvance;
  bool _autoAdvancePaused = false;
  bool _timeExpired = false;
  bool _planMissing = false;
  int _deckCount = 1;
  bool _loading = true;
  bool _loadFailed = false;
  bool _completionHapticPlayed = false;
  bool _limitReached = false;
  bool _ignoreLimits = false;
  int _resetToken = 0;
  SessionMedia _media = SessionMedia.empty;

  bool get _hasSource => widget.plan != null || widget.deckId != null;

  /// Haptics включены в настройках (A6.6, ADR-019 §2).
  bool get _hapticsEnabled => ref.read(effectiveAppSettingsProvider).haptics;

  @override
  void initState() {
    super.initState();
    _ignoreLimits = widget.ignoreDailyLimits;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoAdvanceTimer?.cancel();
    _budgetTimer?.cancel();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final FeedSessionEngine? engine = _engine;
      if (engine != null) _scheduleAutoAdvance(engine.state);
      return;
    }
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
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
      AppSettings settings;
      try {
        settings = await ref.read(appSettingsProvider.future);
      } on Object {
        settings = AppSettings.defaults;
      }
      // Дневные лимиты A6.6 — остаток на локальный календарный день по
      // `review_logs`, а не свежий лимит на каждую сессию (ADR-019 §8, L45).
      // `?limits=ignore` (ADR-028) отключает лимиты после предупреждения.
      final RemainingReviewLimits? limits = _ignoreLimits
          ? null
          : RemainingReviewLimits.of(
              newLimit: settings.dailyNewLimit,
              reviewLimit: settings.dailyReviewLimit,
              usage: await ref
                  .read(dailyUsageRepositoryProvider)
                  .usageOnDay(DateTime.now()),
            );
      if (!mounted) return;
      final DateTime queueNow = DateTime.now().toUtc();
      final bool prebuilt = plan != null;
      final bool limitReached =
          !_ignoreLimits &&
          !prebuilt &&
          ReviewQueue.build(cards, now: queueNow).isNotEmpty &&
          ReviewQueue.build(
            cards,
            now: queueNow,
            newLimit: limits?.newCards,
            reviewLimit: limits?.reviews,
          ).isEmpty;
      final FeedSessionEngine engine = FeedSessionEngine(
        cards: cards,
        scheduler: ref.read(schedulerProvider),
        reviewRepository: ref.read(reviewRepositoryProvider),
        clock: DateTime.now,
        prebuilt: prebuilt,
        newLimit: limits?.newCards,
        reviewLimit: limits?.reviews,
      )..addListener(_onEngineChanged);
      engine.start();
      setState(() {
        _deck = deck;
        _deckCount = deckIds.length;
        _engine = engine;
        _media = media;
        _limitReached = limitReached;
        _loading = false;
        _autoAdvancePaused = false;
        _completionHapticPlayed = false;
        _resetToken = 0;
      });
      _startBudgetTimer(plan?.timeBudget);
      _syncPageAfterFrame();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Лимит минут (SPEC A6.7): по истечении сессия завершается, авто-продвижение
  /// и оценки останавливаются, непройденные карточки остаются на следующий раз.
  void _startBudgetTimer(Duration? budget) {
    _budgetTimer?.cancel();
    _budgetTimer = null;
    if (budget == null) return;
    _budgetTimer = Timer(budget, () {
      if (!mounted) return;
      _autoAdvanceTimer?.cancel();
      _autoAdvanceTimer = null;
      setState(() => _timeExpired = true);
    });
  }

  void _retry() {
    _autoAdvanceTimer?.cancel();
    _budgetTimer?.cancel();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    _engine = null;
    unawaited(_load());
  }

  void _onEngineChanged() {
    if (!mounted) return;
    setState(() {});
    final FeedSessionEngine? engine = _engine;
    if (engine == null) return;
    _syncPage(engine.state);
    _syncPageAfterFrame();
    _scheduleAutoAdvance(engine.state);
  }

  void _syncPage(FeedSessionState state) {
    if (!_pageController.hasClients) return;
    final int current = _pageController.page?.round() ?? 0;
    if (current == state.index) return;
    unawaited(
      _pageController.animateToPage(
        state.index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _syncPageAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final FeedSessionEngine? engine = _engine;
      if (engine != null) _syncPage(engine.state);
    });
  }

  void _scheduleAutoAdvance(FeedSessionState state) {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    if (_autoAdvancePaused || _timeExpired || state.busy || state.isCompleted) {
      return;
    }
    final FeedSessionItem? item = state.current;
    if (item == null || !item.revealed || item.rated) return;
    _autoAdvanceTimer = Timer(_autoAdvanceInterval, () {
      if (!mounted) return;
      _engine?.advance();
    });
  }

  void _togglePause() {
    final FeedSessionEngine? engine = _engine;
    if (engine == null) return;
    setState(() => _autoAdvancePaused = !_autoAdvancePaused);
    _scheduleAutoAdvance(engine.state);
  }

  void _setAutoAdvance(int seconds) {
    final FeedSessionEngine? engine = _engine;
    setState(() {
      _autoAdvanceInterval = Duration(seconds: seconds);
    });
    if (engine != null) _scheduleAutoAdvance(engine.state);
  }

  void _toggleReveal() {
    final FeedSessionEngine? engine = _engine;
    if (engine == null || _timeExpired) return;
    final FeedSessionItem? item = engine.state.current;
    if (item == null || item.rated || engine.state.busy) return;
    final bool revealing = !item.revealed;
    engine.toggleReveal();
    if (revealing && _hapticsEnabled) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  Future<void> _rate(Rating rating) async {
    final FeedSessionEngine? engine = _engine;
    if (engine == null || _timeExpired || engine.state.busy) return;
    try {
      final bool rated = await engine.rate(rating);
      if (!rated) {
        // Оценку не приняли (гонка busy/завершение): возвращаем карточку,
        // если она уже улетела за экран по свайпу.
        if (mounted) setState(() => _resetToken++);
        return;
      }
      if (!mounted) return;
      _playHaptic(rating);
      if (engine.state.isCompleted &&
          !_completionHapticPlayed &&
          _hapticsEnabled) {
        _completionHapticPlayed = true;
        unawaited(HapticFeedback.mediumImpact());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _resetToken++);
      showAppMessage(context, AppLocalizations.of(context).reviewSaveError);
    }
  }

  Future<void> _undo() async {
    final FeedSessionEngine? engine = _engine;
    if (engine == null) return;
    try {
      final bool undone = await engine.undo();
      if (!undone || !mounted) return;
      setState(() {
        _completionHapticPlayed = false;
        _resetToken++;
      });
      showAppMessage(context, AppLocalizations.of(context).reviewUndoneMessage);
    } catch (_) {
      if (!mounted) return;
      showAppMessage(context, AppLocalizations.of(context).reviewUndoError);
    }
  }

  void _playHaptic(Rating rating) {
    if (!_hapticsEnabled) return;
    switch (reviewHapticFor(rating)) {
      case ReviewHaptic.heavy:
        unawaited(HapticFeedback.heavyImpact());
      case ReviewHaptic.light:
        unawaited(HapticFeedback.lightImpact());
      case ReviewHaptic.selection:
        unawaited(HapticFeedback.selectionClick());
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _toggleReveal();
      return KeyEventResult.handled;
    }
    final Rating? rating = switch (key) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => Rating.again,
      LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => Rating.hard,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => Rating.good,
      LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => Rating.easy,
      _ => null,
    };
    if (rating == null) return KeyEventResult.ignored;
    unawaited(_rate(rating));
    return KeyEventResult.handled;
  }

  Future<void> _showWhy(String excerpt) async {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    await showReviewSourceExcerpt(context, excerpt);
    if (!mounted) return;
    final FeedSessionEngine? engine = _engine;
    if (engine != null) _scheduleAutoAdvance(engine.state);
  }

  Future<void> _confirmExit() async {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    final bool confirmed = await confirmReviewExit(context);
    if (!mounted) return;
    if (confirmed) {
      _leave();
    } else {
      final FeedSessionEngine? engine = _engine;
      if (engine != null) _scheduleAutoAdvance(engine.state);
    }
  }

  /// Переход в тренировку из состояния «дневной лимит исчерпан» (ADR-025).
  void _startPractice(String deckId) {
    context.pushReplacement(AppRoutes.practicePath(deckId));
  }

  /// Продолжает ленту без дневного лимита (ADR-028).
  void _continueWithoutLimits() {
    _ignoreLimits = true;
    _retry();
  }

  void _leave() {
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final FeedSessionState? state = _engine?.state;
    final String? rawExcerpt = state?.current?.card.sourceExcerpt;
    final String? excerpt = (rawExcerpt == null || rawExcerpt.trim().isEmpty)
        ? null
        : rawExcerpt;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: Scaffold(
        appBar: ReviewSessionAppBar(
          undoEnabled: state != null && state.undoCount > 0 && !state.busy,
          onUndo: _undo,
          whyExcerpt: excerpt,
          onWhyPressed: excerpt == null
              ? null
              : () => unawaited(_showWhy(excerpt)),
          onClose: _confirmExit,
        ),
        body: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: _buildBody(context, state),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FeedSessionState? state) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_planMissing) return ReviewPlanMissingView(onBack: _leave);
    if (_loadFailed || state == null) {
      return ReviewLoadErrorView(onRetry: _retry);
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (state.total == 0) {
      // Пустая лента при непустой колоде — исчерпанный дневной лимит
      // (ADR-028): объясняем причину и даём «Продолжить без лимита» или
      // тренировку.
      final String? deckId = widget.deckId;
      return ReviewEmptyView(
        title: _limitReached ? l10n.reviewDailyLimitTitle : null,
        message: _limitReached ? l10n.reviewDailyLimitMessage : null,
        onContinue: _limitReached && deckId != null
            ? _continueWithoutLimits
            : null,
        onPractice: _limitReached && deckId != null
            ? () => _startPractice(deckId)
            : null,
        onBack: _leave,
      );
    }
    if (_timeExpired) {
      return ReviewTimeUpView(ratedCount: state.ratedCount, onDone: _leave);
    }
    if (state.isCompleted) {
      return ReviewCompletedView(ratedCount: state.ratedCount, onDone: _leave);
    }
    final AppSettings settings = ref.watch(effectiveAppSettingsProvider);
    final List<bool> ratedFlags = <bool>[
      for (final FeedSessionItem item in state.items) item.rated,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 896),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: FeedProgressBar(
                rated: ratedFlags,
                currentIndex: state.index,
                animatePulse: settings.motion == MotionPreference.expressive,
              ),
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            key: const ValueKey<String>('feed-page-view'),
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: state.total,
            onPageChanged: (int index) => _engine?.visit(index),
            itemBuilder: (BuildContext context, int index) {
              final FeedSessionItem item = state.items[index];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FeedCardView(
                  key: ValueKey<String>('feed-card-${item.card.id}'),
                  front: item.card.front,
                  back: item.card.back,
                  card: item.card,
                  mediaBytes: _media.bytes,
                  mediaMetadata: _media.metadata,
                  revealed: item.revealed,
                  rated: item.rated,
                  rating: item.rating,
                  enabled: !state.busy && !item.rated && index == state.index,
                  resetToken: _resetToken,
                  spring: settings.motion == MotionPreference.standard
                      ? AppMotion.standardSpring()
                      : null,
                  onTap: _toggleReveal,
                  onRate: (Rating rating) => unawaited(_rate(rating)),
                ),
              );
            },
          ),
        ),
        _FeedBottomBar(
          deckName: _deck?.name,
          deckCount: _deckCount,
          position: state.index + 1,
          total: state.total,
          intervalSeconds: _autoAdvanceInterval.inSeconds,
          paused: _autoAdvancePaused,
          onIntervalChanged: _setAutoAdvance,
          onTogglePause: _togglePause,
          l10n: l10n,
        ),
      ],
    );
  }
}

class _FeedBottomBar extends StatelessWidget {
  const _FeedBottomBar({
    required this.deckName,
    required this.deckCount,
    required this.position,
    required this.total,
    required this.intervalSeconds,
    required this.paused,
    required this.onIntervalChanged,
    required this.onTogglePause,
    required this.l10n,
  });

  final String? deckName;
  final int deckCount;
  final int position;
  final int total;
  final int intervalSeconds;
  final bool paused;
  final ValueChanged<int> onIntervalChanged;
  final VoidCallback onTogglePause;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? label =
        deckName ??
        (deckCount > 1 ? l10n.sessionDeckCountLabel(deckCount) : null);
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (label != null)
                      Text(
                        label,
                        key: const ValueKey<String>('feed-deck-name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    Text(
                      l10n.feedCounter(position, total),
                      key: const ValueKey<String>('feed-counter'),
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<int>(
                key: const ValueKey<String>('feed-auto-advance'),
                tooltip: l10n.feedAutoAdvanceTooltip,
                onSelected: onIntervalChanged,
                itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
                  for (final int seconds
                      in FeedSessionScreen.autoAdvanceSeconds)
                    PopupMenuItem<int>(
                      value: seconds,
                      child: Text(l10n.feedSeconds(seconds)),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.timer_outlined,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(l10n.feedSeconds(intervalSeconds)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const ValueKey<String>('feed-pause'),
                onPressed: onTogglePause,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                label: Text(paused ? l10n.feedResume : l10n.feedPause),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
