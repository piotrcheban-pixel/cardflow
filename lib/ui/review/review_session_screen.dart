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
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_buttons.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/review_card_view.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/review/session_media.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/review/session_keyboard.dart';
import 'package:cardflow/ui/review/session_notice.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';
import 'package:cardflow/ui/state/review_limits.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Экран классической сессии повторения (SPEC A6.4, A7.2).
///
/// Каркас: линейный прогресс, undo, выход с диалогом, «Почему?» (неактивна без
/// `source_excerpt`), карточка с 3D-flip, панель 4 кнопок с прогнозом.
/// Данные пишутся в БД движком по одной оценке (транзакция, SPEC A5).
class ReviewSessionScreen extends ConsumerStatefulWidget {
  /// Создаёт экран сессии для колоды [deckId] (режим колоды, ADR-008).
  ///
  /// [plan] — очередь конструктора (SPEC A6.7, ADR-018); при наличии
  /// загруженной колоды не требуется.
  ///
  /// [ignoreDailyLimits] — пользователь подтвердил «Продолжить без лимита»
  /// (ADR-028, итерация 7.12): дневные лимиты не читаются и очередь не
  /// ограничивается.
  const ReviewSessionScreen({
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

  @override
  ConsumerState<ReviewSessionScreen> createState() =>
      _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen>
    with SessionNoticeMixin<ReviewSessionScreen> {
  ReviewSessionEngine? _engine;

  /// Прокрутка содержимого карточки клавиатурой (аудит v2, D1).
  final ScrollController _cardScroll = ScrollController();
  Timer? _budgetTimer;
  bool _timeExpired = false;
  bool _planMissing = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _limitReached = false;
  bool _ignoreLimits = false;
  bool _completionHapticPlayed = false;
  SessionMedia _media = SessionMedia.empty;

  bool get _hasSource => widget.plan != null || widget.deckId != null;

  /// Haptics включены в настройках (A6.6, ADR-019 §2).
  bool get _hapticsEnabled => ref.read(effectiveAppSettingsProvider).haptics;

  @override
  void initState() {
    super.initState();
    _ignoreLimits = widget.ignoreDailyLimits;
    unawaited(_load());
  }

  @override
  void dispose() {
    _budgetTimer?.cancel();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    _cardScroll.dispose();
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
      final SessionMedia media = await loadSessionMedia(ref, cards);
      // Дневные лимиты A6.6 — остаток на локальный календарный день по
      // `review_logs`, а не свежий лимит на каждую сессию (ADR-019 §8, L45).
      // Расчёт тот же, что использует экран колоды (итерация 7.11): иначе
      // предварительная проверка и сессия расходятся, и пользователь видит
      // пустую сессию без причины. `?limits=ignore` (ADR-028) отключает лимиты
      // по подтверждению пользователя.
      final RemainingReviewLimits? limits = _ignoreLimits
          ? null
          : await readRemainingReviewLimits(ref);
      if (!mounted) return;
      // Пустая очередь при непустой колоде = исчерпан дневной лимит: экран
      // объясняет причину и предлагает тренировку или продолжение без лимита
      // (ADR-025/ADR-028).
      final DateTime queueNow = DateTime.now().toUtc();
      final bool prebuilt = plan != null;
      final List<Card> unlimitedQueue = prebuilt
          ? cards
          : ReviewQueue.build(cards, now: queueNow);
      final List<Card> limitedQueue = prebuilt
          ? cards
          : ReviewQueue.build(
              cards,
              now: queueNow,
              newLimit: limits?.newCards,
              reviewLimit: limits?.reviews,
            );
      final bool limitReached =
          !_ignoreLimits &&
          !prebuilt &&
          unlimitedQueue.isNotEmpty &&
          limitedQueue.isEmpty;
      final engine = ReviewSessionEngine(
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
        _engine = engine;
        _media = media;
        _limitReached = limitReached;
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

  /// Лимит минут (SPEC A6.7): по истечении сессия завершается, оценки после
  /// не принимаются; непройденные карточки остаются на следующий раз.
  void _startBudgetTimer(Duration? budget) {
    _budgetTimer?.cancel();
    _budgetTimer = null;
    if (budget == null) return;
    _budgetTimer = Timer(budget, () {
      if (!mounted) return;
      setState(() => _timeExpired = true);
    });
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  void _retry() {
    _budgetTimer?.cancel();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    _engine = null;
    unawaited(_load());
  }

  Future<void> _rate(Rating rating) async {
    final ReviewSessionEngine? engine = _engine;
    if (engine == null || _timeExpired) return;
    // Оценка до раскрытия ответа запрещена и здесь: движок — последняя линия
    // защиты, даже если UI-условие когда-нибудь ослабят (находка F1 аудита).
    if (!engine.state.revealed) return;
    try {
      final bool rated = await engine.rate(rating);
      if (!rated) return;
      _playHaptic(rating);
      if (engine.state.isCompleted &&
          !_completionHapticPlayed &&
          _hapticsEnabled) {
        _completionHapticPlayed = true;
        unawaited(HapticFeedback.mediumImpact());
      }
    } catch (_) {
      if (mounted) {
        showSessionNotice(AppLocalizations.of(context).reviewSaveError);
      }
    }
  }

  Future<void> _undo() async {
    final ReviewSessionEngine? engine = _engine;
    if (engine == null) return;
    try {
      final bool undone = await engine.undo();
      if (undone && mounted) {
        _completionHapticPlayed = false;
        showSessionNotice(AppLocalizations.of(context).reviewUndoneMessage);
      }
    } catch (_) {
      if (mounted) {
        showSessionNotice(AppLocalizations.of(context).reviewUndoError);
      }
    }
  }

  /// Раскрывает ответ с haptic `selectionClick` (SPEC A4.4: раскрытие карточки).
  void _reveal() {
    final ReviewSessionEngine? engine = _engine;
    if (engine == null ||
        _timeExpired ||
        engine.state.revealed ||
        engine.state.isCompleted) {
      return;
    }
    if (_hapticsEnabled) unawaited(HapticFeedback.selectionClick());
    engine.reveal();
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
    final ReviewSessionState? state = _engine?.state;
    if (state == null) return KeyEventResult.ignored;
    return handleReviewSessionKey(
      event: event,
      revealed: state.revealed,
      canUndo: state.undoCount > 0 && !state.busy && !state.isCompleted,
      onReveal: _reveal,
      onRate: (Rating rating) => unawaited(_rate(rating)),
      onUndo: () => unawaited(_undo()),
      scroll: _cardScroll,
    );
  }

  Future<void> _confirmExit() async {
    final ReviewSessionState? state = _engine?.state;
    // Завершённая/пустая сессия и истёкший лимит: терять нечего, диалог —
    // лишний барьер (находка N7 аудита).
    if (state == null ||
        state.isCompleted ||
        state.total == 0 ||
        _timeExpired ||
        _planMissing ||
        _loadFailed) {
      _leave();
      return;
    }
    final bool confirmed = await confirmReviewExit(context);
    if (confirmed && mounted) _leave();
  }

  /// Переход в тренировку из состояния «дневной лимит исчерпан».
  void _startPractice(String deckId) {
    context.pushReplacement(AppRoutes.practicePath(deckId));
  }

  /// Продолжает изучение без дневного лимита (ADR-028): перечитывает колоду и
  /// строит очередь без ограничений.
  void _continueWithoutLimits() {
    _ignoreLimits = true;
    _retry();
  }

  void _leave() {
    if (context.canPop()) context.pop();
  }


  /// Повтор чтения медиа карточки после ошибки изображения (7.19).
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
    final ReviewSessionState? state = _engine?.state;
    final String? rawExcerpt = state?.current?.card.sourceExcerpt;
    final String? excerpt = (rawExcerpt == null || rawExcerpt.trim().isEmpty)
        ? null
        : rawExcerpt;
    final Deck? deck = widget.deckId == null
        ? null
        : ref.watch(deckProvider(widget.deckId!)).value;
    // Единая точка выхода (M2 ревью): системный back и кнопка AppBar не должны
    // обходить диалог SPEC A6.4.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: Scaffold(
        appBar: ReviewSessionAppBar(
          title: deck?.name ?? l10n.reviewTitle,
          undoEnabled: state != null && state.undoCount > 0 && !state.busy,
          onUndo: _undo,
          whyExcerpt: excerpt,
          onClose: _confirmExit,
        ),
        body: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: _buildBody(context, l10n, state),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    ReviewSessionState? state,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_planMissing) return ReviewPlanMissingView(onBack: _leave);
    if (_loadFailed || state == null) {
      return ReviewLoadErrorView(onRetry: _retry);
    }
    if (state.total == 0) {
      // Причина пустоты: исчерпанный дневной лимит (итерация 7.11) или
      // «всё повторено». В первом случае даём тренировку и продолжение без
      // лимита (ADR-025, ADR-028).
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
    final int displayIndex = (state.ratedCount + 1).clamp(1, state.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.studyCardMaxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: SessionProgressStrip(
                label: l10n.reviewCardCounter(displayIndex, state.total),
                value: state.total == 0 ? 0 : state.ratedCount / state.total,
                trailing: Text(
                  l10n.reviewRatedCount(state.ratedCount),
                  style: AppTypography.numeric(
                    context,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.studyCardMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey<String>('review-card'),
                        // Аудит v4 (A6): смена карточки — короткий fade + сдвиг
                        // 8 px (220 мс), а не мгновенная подмена.
                        child: AnimatedSwitcher(
                          duration: AppMotion.duration(
                            context,
                            AppDurations.medium,
                          ),
                          switchInCurve: AppMotion.enter,
                          switchOutCurve: AppMotion.enter,
                          transitionBuilder: (Widget child, Animation<double> a) {
                            return FadeTransition(
                              opacity: a,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.015),
                                  end: Offset.zero,
                                ).animate(a),
                                child: child,
                              ),
                            );
                          },
                          child: ReviewCardView(
                            key: ValueKey<String>(
                              'card-${state.current!.card.id}',
                            ),
                            scrollController: _cardScroll,
                            front: state.current!.card.front,
                            back: state.current!.card.back,
                            card: state.current!.card,
                            mediaBytes: _media.bytes,
                            mediaMetadata: _media.metadata,
                            onRetryMedia: () => _retryMedia(state.current!.card),
                            revealed: state.revealed,
                            onTap: _reveal,
                          ),
                        ),
                      ),
                    ),
                    if (!state.revealed) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        key: const ValueKey<String>('review-reveal'),
                        onPressed: _reveal,
                        style: AppButtons.large(context),
                        child: Text(l10n.reviewRevealAction),
                      ),
                      // Аудит v5 (V5-10): подсказка есть и до раскрытия —
                      // именно тогда она объясняет, что Space раскрывает ответ.
                      if (MediaQuery.sizeOf(context).height >= 500)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            l10n.reviewKeyboardHintsFront,
                            key: const ValueKey<String>(
                              'review-keyboard-hints-front',
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                    ] else if (MediaQuery.sizeOf(context).height >= 500)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          l10n.reviewKeyboardHints,
                          key: const ValueKey<String>('review-keyboard-hints'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (sessionNotice != null)
          SessionNotice(
            message: sessionNotice!,
            onDismiss: dismissSessionNotice,
            dismissTooltip: l10n.sessionNoticeDismiss,
          ),
        ReviewToolbar(
          compact: MediaQuery.sizeOf(context).height < 500,
          preview: state.preview,
          enabled: !state.busy && state.revealed,
          hint: state.revealed
              ? null
              : AppLocalizations.of(context).reviewRevealRequiredHint,
          onRating: (Rating rating) => unawaited(_rate(rating)),
        ),
      ],
    );
  }
}
