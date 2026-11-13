import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/review/review_card_view.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Экран классической сессии повторения (SPEC A6.4, A7.2).
///
/// Каркас: линейный прогресс, undo, выход с диалогом, «Почему?» (неактивна без
/// `source_excerpt`), карточка с 3D-flip, панель 4 кнопок с прогнозом.
/// Данные пишутся в БД движком по одной оценке (транзакция, SPEC A5).
class ReviewSessionScreen extends ConsumerStatefulWidget {
  /// Создаёт экран сессии для колоды [deckId].
  const ReviewSessionScreen({required this.deckId, super.key});

  /// Идентификатор колоды.
  final String deckId;

  @override
  ConsumerState<ReviewSessionScreen> createState() =>
      _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  ReviewSessionEngine? _engine;
  bool _loading = true;
  bool _loadFailed = false;
  bool _completionHapticPlayed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final cards = await ref
          .read(cardRepositoryProvider)
          .cardsByDeck(widget.deckId);
      if (!mounted) return;
      final engine = ReviewSessionEngine(
        cards: cards,
        scheduler: ref.read(schedulerProvider),
        reviewRepository: ref.read(reviewRepositoryProvider),
        clock: DateTime.now,
      )..addListener(_onEngineChanged);
      engine.start();
      setState(() {
        _engine = engine;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  void _retry() {
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    _engine = null;
    unawaited(_load());
  }

  Future<void> _rate(Rating rating) async {
    final ReviewSessionEngine? engine = _engine;
    if (engine == null) return;
    try {
      final bool rated = await engine.rate(rating);
      if (!rated) return;
      _playHaptic(rating);
      if (engine.state.isCompleted && !_completionHapticPlayed) {
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
    if (engine == null || engine.state.revealed || engine.state.isCompleted) {
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    engine.reveal();
  }

  void _playHaptic(Rating rating) {
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool confirmed =
        (await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(l10n.reviewExitDialogTitle),
            content: Text(l10n.reviewExitDialogMessage),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>('review-exit-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.reviewExitContinue),
              ),
              FilledButton(
                key: const ValueKey<String>('review-exit-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.reviewExitConfirm),
              ),
            ],
          ),
        )) ??
        false;
    if (confirmed && mounted) _leave();
  }

  void _leave() {
    if (context.canPop()) context.pop();
  }

  void _showWhy(String excerpt) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.reviewWhySheetTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(child: Text(excerpt)),
            ],
          ),
        ),
      ),
    );
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
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.reviewTitle),
          actions: <Widget>[
            IconButton(
              key: const ValueKey<String>('review-undo'),
              tooltip: l10n.reviewUndoTooltip,
              icon: const Icon(Icons.undo),
              onPressed: state != null && state.undoCount > 0 && !state.busy
                  ? _undo
                  : null,
            ),
            IconButton(
              key: const ValueKey<String>('review-why'),
              tooltip: l10n.reviewWhyTooltip,
              icon: const Icon(Icons.info_outline),
              onPressed: excerpt == null ? null : () => _showWhy(excerpt),
            ),
            IconButton(
              key: const ValueKey<String>('review-close'),
              tooltip: l10n.reviewCloseTooltip,
              icon: const Icon(Icons.close),
              onPressed: _confirmExit,
            ),
          ],
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
    if (_loadFailed || state == null) return _buildLoadError(l10n);
    if (state.total == 0) return _buildEmpty(l10n);
    if (state.isCompleted) return _buildCompleted(l10n, state);
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
                  revealed: state.revealed,
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

  Widget _buildEmpty(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.done_all,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.reviewEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.reviewEmptyMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _leave, child: Text(l10n.reviewBack)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompleted(AppLocalizations l10n, ReviewSessionState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.celebration_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.reviewCompletedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.reviewCompletedMessage(state.ratedCount),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _leave, child: Text(l10n.reviewDone)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadError(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(l10n.reviewLoadError, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: _retry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
