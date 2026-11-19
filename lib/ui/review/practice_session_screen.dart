import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/practice_session_engine.dart';
import 'package:cardflow/ui/review/review_card_view.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/review/review_session_engine.dart'
    show ReviewHaptic, reviewHapticFor;
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/review/session_media.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Экран режима «Тренировка» (ADR-025, итерация 7.11).
///
/// Проходит любые карточки колоды независимо от FSRS: ни `due`, ни дневные
/// лимиты не учитываются, а оценки пишутся только в журнал с
/// `mode = 'practice'` — расписание повторения не меняется.
class PracticeSessionScreen extends ConsumerStatefulWidget {
  /// Создаёт экран тренировки для колоды [deckId].
  const PracticeSessionScreen({required this.deckId, super.key});

  /// Идентификатор колоды.
  final String deckId;

  @override
  ConsumerState<PracticeSessionScreen> createState() =>
      _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends ConsumerState<PracticeSessionScreen> {
  PracticeSessionEngine? _engine;
  bool _loading = true;
  bool _loadFailed = false;
  bool _completionHapticPlayed = false;
  SessionMedia _media = SessionMedia.empty;

  /// Haptics включены в настройках (A6.6, ADR-019 §2).
  bool get _hapticsEnabled => ref.read(effectiveAppSettingsProvider).haptics;

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
      final List<Card> cards = await ref
          .read(cardRepositoryProvider)
          .cardsByDeck(widget.deckId);
      final SessionMedia media = await loadSessionMedia(ref, cards);
      if (!mounted) return;
      final PracticeSessionEngine engine = PracticeSessionEngine(
        cards: cards,
        practiceRepository: ref.read(practiceRepositoryProvider),
        clock: DateTime.now,
      )..addListener(_onEngineChanged);
      engine.start();
      setState(() {
        _engine = engine;
        _media = media;
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
    final PracticeSessionEngine? engine = _engine;
    if (engine == null) return;
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
    final PracticeSessionEngine? engine = _engine;
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

  /// Раскрывает ответ с haptic `selectionClick` (SPEC A4.4).
  void _reveal() {
    final PracticeSessionEngine? engine = _engine;
    if (engine == null || engine.state.revealed || engine.state.isCompleted) {
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

  void _leave() {
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PracticeSessionState? state = _engine?.state;
    final String? rawExcerpt = state?.current?.sourceExcerpt;
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
          title: l10n.practiceTitle,
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
    PracticeSessionState? state,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed || state == null) {
      return ReviewLoadErrorView(onRetry: _retry);
    }
    if (state.total == 0) {
      return ReviewEmptyView(
        title: l10n.practiceEmptyTitle,
        message: l10n.practiceEmptyMessage,
        onBack: _leave,
      );
    }
    if (state.isCompleted) {
      return _PracticeCompletedView(
        ratedCount: state.ratedCount,
        onDone: _leave,
      );
    }
    final AppSettings settings = ref.watch(effectiveAppSettingsProvider);
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
              child: SessionProgressStrip(
                label: l10n.practiceRatedLabel(state.ratedCount, state.total),
                value: state.total == 0 ? 0 : state.ratedCount / state.total,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xxs + 2,
            AppSpacing.md,
            0,
          ),
          child: Text(
            l10n.practiceSubtitle,
            key: const ValueKey<String>('practice-subtitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.studyCardMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    KeyedSubtree(
                      key: const ValueKey<String>('practice-card'),
                      child: ReviewCardView(
                        key: ValueKey<String>(state.current!.id),
                        front: state.current!.front,
                        back: state.current!.back,
                        card: state.current!,
                        mediaBytes: _media.bytes,
                        mediaMetadata: _media.metadata,
                        revealed: state.revealed,
                        spring: settings.motion == MotionPreference.standard
                            ? AppMotion.standardSpring()
                            : null,
                        onTap: _reveal,
                      ),
                    ),
                    if (!state.revealed) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        key: const ValueKey<String>('practice-reveal'),
                        onPressed: _reveal,
                        child: Text(l10n.reviewRevealAction),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        ReviewToolbar(
          preview: null,
          enabled: !state.busy,
          onRating: (Rating rating) => unawaited(_rate(rating)),
        ),
      ],
    );
  }
}

/// Итог тренировки: сколько карточек пройдено.
class _PracticeCompletedView extends StatelessWidget {
  const _PracticeCompletedView({
    required this.ratedCount,
    required this.onDone,
  });

  final int ratedCount;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.sports_esports_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.practiceCompletedTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.practiceCompletedMessage(ratedCount),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onDone, child: Text(l10n.reviewDone)),
          ],
        ),
      ),
    );
  }
}
