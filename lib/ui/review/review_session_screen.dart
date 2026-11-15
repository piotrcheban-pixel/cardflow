import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/review_card_view.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/state/review_limits.dart';

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
  const ReviewSessionScreen({this.deckId, this.plan, super.key});

  /// Идентификатор колоды.
  final String? deckId;

  /// План сессии конструктора; `null` — очередь из колоды.
  final SessionPlan? plan;

  @override
  ConsumerState<ReviewSessionScreen> createState() =>
      _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  ReviewSessionEngine? _engine;
  Timer? _budgetTimer;
  bool _timeExpired = false;
  bool _planMissing = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _limitReached = false;
  bool _completionHapticPlayed = false;
  Map<String, Uint8List> _mediaBytes = const <String, Uint8List>{};

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
    _budgetTimer?.cancel();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
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
      final mediaIds = <String>{for (final card in cards) ...card.mediaIds};
      final mediaBytes = mediaIds.isEmpty
          ? const <String, Uint8List>{}
          : await ref.read(cardMediaRepositoryProvider).readMedia(mediaIds);
      // Дневные лимиты A6.6 — остаток на локальный календарный день по
      // `review_logs`, а не свежий лимит на каждую сессию (ADR-019 §8, L45).
      // Расчёт тот же, что использует экран колоды (итерация 7.11): иначе
      // предварительная проверка и сессия расходятся, и пользователь видит
      // пустую сессию без причины.
      final RemainingReviewLimits limits = await readRemainingReviewLimits(ref);
      if (!mounted) return;
      // Пустая очередь при непустой колоде = исчерпан дневной лимит: экран
      // объясняет причину и предлагает тренировку (ADR-025).
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
              newLimit: limits.newCards,
              reviewLimit: limits.reviews,
            );
      final bool limitReached =
          !prebuilt && unlimitedQueue.isNotEmpty && limitedQueue.isEmpty;
      final engine = ReviewSessionEngine(
        cards: cards,
        scheduler: ref.read(schedulerProvider),
        reviewRepository: ref.read(reviewRepositoryProvider),
        clock: DateTime.now,
        prebuilt: prebuilt,
        newLimit: limits.newCards,
        reviewLimit: limits.reviews,
      )..addListener(_onEngineChanged);
      engine.start();
      setState(() {
        _engine = engine;
        _mediaBytes = mediaBytes;
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
        showAppMessage(context, AppLocalizations.of(context).reviewSaveError);
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
        showAppMessage(
          context,
          AppLocalizations.of(context).reviewUndoneMessage,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppMessage(context, AppLocalizations.of(context).reviewUndoError);
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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _reveal();
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

  Future<void> _confirmExit() async {
    final bool confirmed = await confirmReviewExit(context);
    if (confirmed && mounted) _leave();
  }

  /// Переход в тренировку из состояния «дневной лимит исчерпан».
  void _startPractice(String deckId) {
    context.pushReplacement(AppRoutes.practicePath(deckId));
  }

  void _leave() {
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ReviewSessionState? state = _engine?.state;
    final String? rawExcerpt = state?.current?.card.sourceExcerpt;
    final String? excerpt = (rawExcerpt == null || rawExcerpt.trim().isEmpty)
        ? null
        : rawExcerpt;
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
      // «всё повторено». В первом случае даём тренировку (ADR-025).
      final String? deckId = widget.deckId;
      return ReviewEmptyView(
        title: _limitReached ? l10n.reviewDailyLimitTitle : null,
        message: _limitReached ? l10n.reviewDailyLimitMessage : null,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: LinearProgressIndicator(
            value: state.total == 0 ? 0 : state.ratedCount / state.total,
            semanticsLabel: l10n.reviewProgressLabel,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: KeyedSubtree(
                key: const ValueKey<String>('review-card'),
                child: ReviewCardView(
                  key: ValueKey<String>(state.current!.card.id),
                  front: state.current!.card.front,
                  back: state.current!.card.back,
                  card: state.current!.card,
                  mediaBytes: _mediaBytes,
                  revealed: state.revealed,
                  spring: settings.motion == MotionPreference.standard
                      ? AppMotion.standardSpring()
                      : null,
                  onTap: _reveal,
                ),
              ),
            ),
          ),
        ),
        ReviewToolbar(
          preview: state.preview,
          enabled: !state.busy,
          onRating: (Rating rating) => unawaited(_rate(rating)),
        ),
      ],
    );
  }
}
