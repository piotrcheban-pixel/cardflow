import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/study/answer_matcher.dart';
import 'package:cardflow/domain/study/answer_type.dart';
import 'package:cardflow/domain/study/study_mode.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/cards/content/latex_spans.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/review/session_media.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/study/study_session_chrome.dart';
import 'package:cardflow/ui/study/study_session_controller.dart';

/// Режим «Ввод ответа» (7.15): вспомнил и ввёл, как в Quizlet Write.
///
/// exact — зелёное, Good; almost — жёлтое «Почти!», Hard; wrong — красное с
/// посимвольным diff, Again. «Я был прав» после wrong/almost меняет оценку на
/// Good (undo + повторная запись), «Показать ответ» — сдался, Again.
class TypingScreen extends ConsumerStatefulWidget {
  /// Создаёт экран для колоды [deckId].
  const TypingScreen({required this.deckId, super.key});

  /// Колода.
  final String deckId;

  @override
  ConsumerState<TypingScreen> createState() => _TypingScreenState();
}

class _TypingScreenState extends ConsumerState<TypingScreen> {
  StudySessionController? _controller;
  SessionMedia _media = SessionMedia.empty;
  final TextEditingController _input = TextEditingController();
  bool _loading = true;
  bool _loadFailed = false;
  bool _completionHapticPlayed = false;
  bool _gaveUp = false;
  bool _iWasRight = false;
  AnswerMatch? _match;
  Card? _answeredCard;

  bool get _hapticsEnabled => ref.read(effectiveAppSettingsProvider).haptics;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    _input.dispose();
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
      final List<Card> typable = cards
          .where(AnswerTypes.isTypable)
          .toList(growable: false);
      final SessionMedia media = await loadSessionMedia(ref, typable);
      if (!mounted) return;
      final StudySessionController controller = StudySessionController(
        cards: typable,
        mode: StudyMode.typing,
        scheduler: ref.read(schedulerProvider),
        reviewRepository: ref.read(reviewRepositoryProvider),
        practiceRepository: ref.read(practiceRepositoryProvider),
        clock: DateTime.now,
      )..addListener(_onChanged);
      controller.start();
      setState(() {
        _controller = controller;
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
    _match = null;
    _answeredCard = null;
    _gaveUp = false;
    _iWasRight = false;
    _input.clear();
  }

  Future<void> _submit() async {
    final StudySessionController? controller = _controller;
    if (controller == null || controller.state.busy || _match != null) return;
    final StudySessionItem? item = controller.state.current;
    if (item == null) return;
    final String input = _input.text.trim();
    if (input.isEmpty) return;
    final AnswerMatch match = matchCardAnswer(item.card, input);
    setState(() {
      _match = match;
      _answeredCard = item.card;
      _gaveUp = false;
    });
    if (_hapticsEnabled) {
      unawaited(switch (match.result) {
        AnswerMatchResult.exact => HapticFeedback.lightImpact(),
        AnswerMatchResult.almost => HapticFeedback.selectionClick(),
        AnswerMatchResult.wrong => HapticFeedback.heavyImpact(),
      });
    }
    await _record(match);
  }

  Future<void> _showAnswer() async {
    final StudySessionController? controller = _controller;
    if (controller == null || controller.state.busy || _match != null) return;
    final StudySessionItem? item = controller.state.current;
    if (item == null) return;
    final AnswerMatch match = AnswerMatch(
      result: AnswerMatchResult.wrong,
      expected: item.card.back,
      normalizedInput: '',
    );
    setState(() {
      _match = match;
      _answeredCard = item.card;
      _gaveUp = true;
    });
    if (_hapticsEnabled) unawaited(HapticFeedback.heavyImpact());
    await _record(match);
  }

  Future<void> _record(AnswerMatch match) async {
    final StudySessionController? controller = _controller;
    if (controller == null) return;
    final Rating rating = switch (match.result) {
      AnswerMatchResult.exact => Rating.good,
      AnswerMatchResult.almost => Rating.hard,
      AnswerMatchResult.wrong => Rating.again,
    };
    try {
      await controller.answer(rating: rating, wasCorrect: match.isCorrect);
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(_resetAnswer);
      showAppMessage(context, AppLocalizations.of(context).reviewSaveError);
    }
  }

  /// «Я был прав»: меняет последнюю оценку на Good (undo + повторная запись).
  Future<void> _overrideCorrect() async {
    final StudySessionController? controller = _controller;
    final AnswerMatch? match = _match;
    if (controller == null ||
        match == null ||
        match.result == AnswerMatchResult.exact ||
        _gaveUp) {
      return;
    }
    try {
      final bool undone = await controller.undo();
      if (!undone) return;
      final bool answered = await controller.answer(
        rating: Rating.good,
        wasCorrect: true,
      );
      if (!answered || !mounted) return;
      setState(() {
        _iWasRight = true;
        _match = AnswerMatch(
          result: AnswerMatchResult.exact,
          expected: match.expected,
          normalizedInput: match.normalizedInput,
          diff: const <AnswerDiffOp>[],
        );
      });
      if (_hapticsEnabled) unawaited(HapticFeedback.lightImpact());
    } catch (_) {
      if (!mounted) return;
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
    // Итоги и пустая очередь: терять нечего — выходим без диалога (N7).
    final bool nothingToLose =
        (_controller?.state.isCompleted ?? true) ||
        (_controller?.state.total ?? 0) == 0;
    if (nothingToLose) {
      if (mounted && context.canPop()) context.pop();
      return;
    }
    final bool confirmed = await confirmReviewExit(
      context,
      kind: SessionExitKind.study,
    );
    if (confirmed && mounted && context.canPop()) context.pop();
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
    final StudySessionState? state = _controller?.state;
    final Card? current = _answeredCard ?? state?.current?.card;
    final String? excerpt = current?.sourceExcerpt;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: Scaffold(
        appBar: ReviewSessionAppBar(
          title: l10n.typingTitle,
          undoEnabled: state != null && state.undoCount > 0 && !state.busy,
          onUndo: _undo,
          whyExcerpt: excerpt,
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
    if (_loading) return const ReviewLoadingView();
    if (_loadFailed || state == null) {
      return ReviewLoadErrorView(onRetry: _retry);
    }
    if (state.total == 0) {
      return ReviewEmptyView(
        title: l10n.typingEmptyTitle,
        message: l10n.typingEmptyMessage,
        onBack: () {
          if (context.canPop()) context.pop();
        },
      );
    }
    if (state.isCompleted && _match == null) {
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
    final AnswerMatch? match = _match;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(padding: EdgeInsets.only(top: AppSpacing.xs)),
        // Аудит 2.0 (P2-02): номер вопроса не опережает показанный.
        StudyProgressBar(
          answered: state.answeredCount,
          total: state.total,
          currentIndex: _answeredCard != null ? state.answeredCount : null,
        ),
        Expanded(
          child: StudyWorkspace(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                StudyQuestionCard(
                  child: CardContentView(
                    key: ValueKey<String>('typing-question-${card.id}'),
                    card: card,
                    side: card.front,
                    revealed: false,
                    showAllFormulas: true,
                    faceKey: const ValueKey<String>('typing-question-face'),
                    mediaBytes: _media.bytes,
                    mediaMetadata: _media.metadata,
                    onRetryMedia: () => _retryMedia(card),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  key: const ValueKey<String>('typing-input'),
                  controller: _input,
                  autofocus: true,
                  enabled: match == null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => match == null ? _submit() : _next(),
                  decoration: InputDecoration(
                    labelText: l10n.typingInputLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (match == null)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey<String>('typing-check'),
                          onPressed: state.busy ? null : _submit,
                          child: Text(l10n.typingCheck),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey<String>('typing-show-answer'),
                          onPressed: state.busy ? null : _showAnswer,
                          child: Text(l10n.typingShowAnswer),
                        ),
                      ),
                    ],
                  )
                else ...<Widget>[
                  _TypingFeedback(match: match, gaveUp: _gaveUp),
                  const SizedBox(height: 12),
                  if (!_gaveUp &&
                      match.result != AnswerMatchResult.exact &&
                      !_iWasRight)
                    OutlinedButton(
                      key: const ValueKey<String>('typing-i-was-right'),
                      onPressed: state.busy ? null : _overrideCorrect,
                      child: Text(l10n.typingIWasRight),
                    ),
                  if (!_gaveUp &&
                      match.result != AnswerMatchResult.exact &&
                      !_iWasRight)
                    const SizedBox(height: 8),
                  FilledButton(
                    key: const ValueKey<String>('typing-next'),
                    onPressed: _next,
                    child: Text(l10n.typingNext),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Плашка результата ввода: цвет, текст и diff.
class _TypingFeedback extends StatelessWidget {
  const _TypingFeedback({required this.match, required this.gaveUp});

  final AnswerMatch match;
  final bool gaveUp;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final (
      Color background,
      Color foreground,
      String text,
    ) = switch (match.result) {
      AnswerMatchResult.exact => (
        AppColors.feedbackCorrectBackground(scheme),
        AppColors.feedbackCorrectForeground(scheme),
        l10n.typingCorrect,
      ),
      AnswerMatchResult.almost => (
        AppColors.feedbackAlmostBackground(scheme),
        AppColors.feedbackAlmostForeground(scheme),
        l10n.typingAlmost,
      ),
      AnswerMatchResult.wrong => (
        AppColors.feedbackWrongBackground(scheme),
        AppColors.feedbackWrongForeground(scheme),
        l10n.typingWrong,
      ),
    };
    final bool showExpected = gaveUp || match.result != AnswerMatchResult.exact;
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
            text,
            key: const ValueKey<String>('typing-feedback'),
            style: theme.textTheme.titleMedium?.copyWith(color: foreground),
          ),
          if (showExpected) ...<Widget>[
            const SizedBox(height: 6),
            CardText(
              key: const ValueKey<String>('typing-expected'),
              source: l10n.typingRightAnswer(match.expected),
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ],
          if (match.result != AnswerMatchResult.exact &&
              match.diff.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            AnswerDiffView(
              diff: match.diff,
              baseStyle: theme.textTheme.bodyLarge?.copyWith(color: foreground),
            ),
          ],
        ],
      ),
    );
  }
}

/// Посимвольный diff: лишнее зачёркнуто, недостающее подчёркнуто.
///
/// Фрагменты идут через тот же LaTeX-рендер, что и правильный ответ (7.17):
/// готовая формула во фрагменте показывается `Math`, а обрывок (разделитель
/// попал внутрь фрагмента) остаётся текстом, а не падает.
class AnswerDiffView extends StatelessWidget {
  const AnswerDiffView({required this.diff, this.baseStyle, super.key});

  final List<AnswerDiffOp> diff;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (final AnswerDiffOp op in diff) {
      final TextStyle? style = switch (op.kind) {
        AnswerDiffKind.equal => baseStyle,
        AnswerDiffKind.extra => baseStyle?.copyWith(
          decoration: TextDecoration.lineThrough,
          decorationColor: Colors.red,
          color: Colors.red,
        ),
        AnswerDiffKind.missing => baseStyle?.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: Colors.orange,
          fontWeight: FontWeight.bold,
        ),
      };
      spans.addAll(
        latexTextSpans(context, op.text, style: style, formulaStyle: style),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      key: const ValueKey<String>('typing-diff'),
    );
  }
}
