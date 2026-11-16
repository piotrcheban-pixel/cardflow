import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/study/study_mode.dart';
import 'package:cardflow/domain/study/true_false_question.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/review/session_media.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/study/study_session_chrome.dart';
import 'package:cardflow/ui/study/study_session_controller.dart';

/// Режим «Верно/Неверно» (7.16).
///
/// Показывает front и утверждение (правильный ответ или дистрактор 50/50).
/// Кнопки ✓/✗ и свайп вправо/влево. FSRS пишется только для due-карточек:
/// верно → Good, неверно → Again (ADR-032).
class TrueFalseScreen extends ConsumerStatefulWidget {
  /// Создаёт экран для колоды [deckId].
  const TrueFalseScreen({required this.deckId, super.key});

  /// Колода.
  final String deckId;

  @override
  ConsumerState<TrueFalseScreen> createState() => _TrueFalseScreenState();
}

class _TrueFalseScreenState extends ConsumerState<TrueFalseScreen> {
  StudySessionController? _controller;
  Map<String, TrueFalseQuestion> _questions =
      const <String, TrueFalseQuestion>{};
  SessionMedia _media = SessionMedia.empty;
  bool _loading = true;
  bool _loadFailed = false;
  bool _completionHapticPlayed = false;
  bool? _userSaysTrue;
  bool? _wasCorrect;
  Card? _answeredCard;
  Timer? _autoNext;

  bool get _hapticsEnabled => ref.read(effectiveAppSettingsProvider).haptics;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _autoNext?.cancel();
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _resetAnswer();
    });
    try {
      final List<Card> cards = await ref
          .read(cardRepositoryProvider)
          .cardsByDeck(widget.deckId);
      final List<TrueFalseQuestion> questions = buildTrueFalseQuestions(
        cards: cards,
        seed: widget.deckId.hashCode,
      );
      final Map<String, TrueFalseQuestion> byCard = <String, TrueFalseQuestion>{
        for (final TrueFalseQuestion question in questions)
          question.card.id: question,
      };
      final List<Card> queue = <Card>[
        for (final Card card in cards)
          if (byCard.containsKey(card.id)) card,
      ];
      final SessionMedia media = await loadSessionMedia(ref, queue);
      if (!mounted) return;
      final StudySessionController controller = StudySessionController(
        cards: queue,
        mode: StudyMode.trueFalse,
        scheduler: ref.read(schedulerProvider),
        reviewRepository: ref.read(reviewRepositoryProvider),
        practiceRepository: ref.read(practiceRepositoryProvider),
        clock: DateTime.now,
      )..addListener(_onChanged);
      controller.start();
      setState(() {
        _controller = controller;
        _questions = byCard;
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

  void _retry() {
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    _controller = null;
    unawaited(_load());
  }

  void _resetAnswer() {
    _autoNext?.cancel();
    _autoNext = null;
    _userSaysTrue = null;
    _wasCorrect = null;
    _answeredCard = null;
  }

  void _answer(bool userSaysTrue) {
    final StudySessionController? controller = _controller;
    if (controller == null || controller.state.busy || _userSaysTrue != null) {
      return;
    }
    final StudySessionItem? item = controller.state.current;
    if (item == null) return;
    final TrueFalseQuestion? question = _questions[item.card.id];
    if (question == null) return;
    final bool correct = userSaysTrue == question.isTrue;
    setState(() {
      _userSaysTrue = userSaysTrue;
      _wasCorrect = correct;
      _answeredCard = item.card;
    });
    if (_hapticsEnabled) {
      unawaited(
        correct ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact(),
      );
    }
    unawaited(_record(correct));
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (correct && !reduceMotion) {
      _autoNext = Timer(const Duration(milliseconds: 900), _next);
    }
  }

  Future<void> _record(bool correct) async {
    final StudySessionController? controller = _controller;
    if (controller == null) return;
    try {
      await controller.answer(
        rating: correct ? Rating.good : Rating.again,
        wasCorrect: correct,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(_resetAnswer);
      showAppMessage(context, AppLocalizations.of(context).reviewSaveError);
    }
  }

  void _next() {
    if (!mounted) return;
    setState(_resetAnswer);
    final StudySessionController? controller = _controller;
    if (controller?.state.isCompleted ?? false) {
      if (!_completionHapticPlayed && _hapticsEnabled) {
        _completionHapticPlayed = true;
        unawaited(HapticFeedback.mediumImpact());
      }
    }
  }

  Future<void> _undo() async {
    final StudySessionController? controller = _controller;
    if (controller == null) return;
    try {
      final bool undone = await controller.undo();
      if (undone && mounted) {
        _completionHapticPlayed = false;
        setState(_resetAnswer);
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

  Future<void> _confirmExit() async {
    final bool confirmed = await confirmReviewExit(context);
    if (confirmed && mounted && context.canPop()) context.pop();
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0;
    final double dx = details.localPosition.dx;
    if (velocity.abs() < 250 && dx.abs() < 40) return;
    _answer(velocity > 0 || dx > 0);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StudySessionState? state = _controller?.state;
    final Card? current = _answeredCard ?? state?.current?.card;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: Scaffold(
        appBar: ReviewSessionAppBar(
          title: l10n.trueFalseTitle,
          undoEnabled: state != null && state.undoCount > 0 && !state.busy,
          onUndo: _undo,
          whyExcerpt: current?.sourceExcerpt,
          onClose: _confirmExit,
        ),
        body: _buildBody(context, l10n, state),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    StudySessionState? state,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed || state == null) {
      return ReviewLoadErrorView(onRetry: _retry);
    }
    if (state.total == 0) {
      return ReviewEmptyView(
        title: l10n.trueFalseEmptyTitle,
        message: l10n.trueFalseEmptyMessage,
        onBack: () {
          if (context.canPop()) context.pop();
        },
      );
    }
    if (state.isCompleted && _userSaysTrue == null) {
      return StudyResultsView(
        accuracy: state.accuracy,
        correct: state.correctCount,
        total: state.answeredCount,
        mistakes: _controller!.wrongCards,
        onRepeatMistakes: _controller!.wrongCards.isEmpty
            ? null
            : () {
                _controller!.repeatMistakes();
                _completionHapticPlayed = false;
                setState(_resetAnswer);
              },
        onDone: () {
          if (context.canPop()) context.pop();
        },
      );
    }
    final Card card = _answeredCard ?? state.current!.card;
    final TrueFalseQuestion question = _questions[card.id]!;
    final ThemeData theme = Theme.of(context);
    final bool? correct = _wasCorrect;
    final bool answered = correct != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: StudyProgressBar(
            answered: state.answeredCount,
            total: state.total,
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: answered ? null : _onHorizontalDragEnd,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: CardContentView(
                      key: ValueKey<String>('tf-question-${card.id}'),
                      card: card,
                      side: card.front,
                      revealed: false,
                      showAllFormulas: true,
                      faceKey: const ValueKey<String>('tf-question-face'),
                      mediaBytes: _media.bytes,
                      mediaMetadata: _media.metadata,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: CardText(
                      key: const ValueKey<String>('tf-statement'),
                      source: l10n.trueFalseStatement(question.shownAnswer),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.trueFalseSwipeHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (answered) ...<Widget>[
                    const SizedBox(height: 12),
                    _TrueFalseFeedback(correct: correct, question: question),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey<String>('tf-next'),
                      onPressed: _next,
                      child: Text(l10n.trueFalseNext),
                    ),
                  ] else ...<Widget>[
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const ValueKey<String>('tf-true'),
                            onPressed: state.busy ? null : () => _answer(true),
                            icon: const Icon(Icons.check),
                            label: Text(l10n.trueFalseTrueAction),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const ValueKey<String>('tf-false'),
                            onPressed: state.busy ? null : () => _answer(false),
                            icon: const Icon(Icons.close),
                            label: Text(l10n.trueFalseFalseAction),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Плашка результата «Верно/Неверно».
class _TrueFalseFeedback extends StatelessWidget {
  const _TrueFalseFeedback({required this.correct, required this.question});

  final bool correct;
  final TrueFalseQuestion question;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final (Color background, Color foreground) = correct
        ? dark
              ? (const Color(0xFF1B5E20), const Color(0xFFC8E6C9))
              : (const Color(0xFFE8F5E9), const Color(0xFF1B5E20))
        : dark
        ? (const Color(0xFFB71C1C), const Color(0xFFFFCDD2))
        : (const Color(0xFFFFEBEE), const Color(0xFFB71C1C));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            correct ? l10n.trueFalseCorrect : l10n.trueFalseWrong,
            key: const ValueKey<String>('tf-feedback'),
            style: theme.textTheme.titleMedium?.copyWith(color: foreground),
          ),
          if (!correct || !question.isTrue) ...<Widget>[
            const SizedBox(height: 6),
            CardText(
              key: const ValueKey<String>('tf-explanation'),
              source: l10n.trueFalseExplanation(question.card.back),
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ],
        ],
      ),
    );
  }
}
