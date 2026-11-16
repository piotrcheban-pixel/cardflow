import 'dart:async';

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/latex_markup.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/study/answer_type.dart';
import 'package:cardflow/domain/study/distractor_generator.dart';
import 'package:cardflow/domain/study/study_mode.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/review/review_chrome.dart';
import 'package:cardflow/ui/review/session_media.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/study/study_session_chrome.dart';
import 'package:cardflow/ui/study/study_session_controller.dart';

/// Снимок отвеченной карточки: вопрос остаётся на экране до «Далее».
class _AnsweredQuestion {
  const _AnsweredQuestion({
    required this.card,
    required this.options,
    required this.selectedIndex,
    required this.correct,
  });

  final Card card;
  final DistractorSet options;
  final int selectedIndex;
  final bool correct;
}

/// Режим «Тест» (SPEC A7.2-аналог, 7.15): вопрос и четыре варианта ответа.
///
/// Верный вариант подсвечивается зелёным, неверный — красным, правильный
/// показывается зелёным. Верный ответ автоматически ведёт дальше через 1,2 с
/// (кроме reduce motion), иначе — кнопка «Далее». FSRS пишется только для
/// due-карточек, остальные — тренировка (mode = `test`).
class MultipleChoiceScreen extends ConsumerStatefulWidget {
  /// Создаёт экран для колоды [deckId].
  const MultipleChoiceScreen({required this.deckId, super.key});

  /// Колода.
  final String deckId;

  @override
  ConsumerState<MultipleChoiceScreen> createState() =>
      _MultipleChoiceScreenState();
}

class _MultipleChoiceScreenState extends ConsumerState<MultipleChoiceScreen> {
  StudySessionController? _controller;
  Map<String, DistractorSet> _options = const <String, DistractorSet>{};
  SessionMedia _media = SessionMedia.empty;
  bool _loading = true;
  bool _loadFailed = false;
  bool _completionHapticPlayed = false;
  Timer? _autoAdvance;
  _AnsweredQuestion? _answered;

  bool get _hapticsEnabled => ref.read(effectiveAppSettingsProvider).haptics;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _autoAdvance?.cancel();
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
      _answered = null;
    });
    try {
      final List<Card> cards = await ref
          .read(cardRepositoryProvider)
          .cardsByDeck(widget.deckId);
      const DistractorGenerator generator = DistractorGenerator();
      final Map<String, DistractorSet> options = <String, DistractorSet>{};
      final List<Card> queue = <Card>[];
      for (final Card card in cards) {
        if (!AnswerTypes.isChoice(card)) continue;
        final DistractorSet? set = generator.buildQuestion(card, cards);
        if (set == null) continue;
        options[card.id] = set;
        queue.add(card);
      }
      final SessionMedia media = await loadSessionMedia(ref, queue);
      if (!mounted) return;
      final StudySessionController controller = StudySessionController(
        cards: queue,
        mode: StudyMode.test,
        scheduler: ref.read(schedulerProvider),
        reviewRepository: ref.read(reviewRepositoryProvider),
        practiceRepository: ref.read(practiceRepositoryProvider),
        clock: DateTime.now,
      )..addListener(_onChanged);
      controller.start();
      setState(() {
        _controller = controller;
        _options = options;
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

  void _select(int index) {
    final StudySessionController? controller = _controller;
    if (controller == null || _answered != null || controller.state.busy) {
      return;
    }
    final StudySessionItem? item = controller.state.current;
    if (item == null) return;
    final DistractorSet? set = _options[item.card.id];
    if (set == null) return;
    final bool correct = index == set.correctIndex;
    if (_hapticsEnabled) {
      unawaited(
        correct ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact(),
      );
    }
    setState(() {
      _answered = _AnsweredQuestion(
        card: item.card,
        options: set,
        selectedIndex: index,
        correct: correct,
      );
    });
    unawaited(_record(correct));
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (correct && !reduceMotion) {
      _autoAdvance = Timer(const Duration(milliseconds: 1200), _next);
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
      setState(() => _answered = null);
      showAppMessage(context, AppLocalizations.of(context).reviewSaveError);
    }
  }

  void _next() {
    _autoAdvance?.cancel();
    _autoAdvance = null;
    if (!mounted) return;
    setState(() => _answered = null);
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
    _autoAdvance?.cancel();
    try {
      final bool undone = await controller.undo();
      if (undone && mounted) {
        _completionHapticPlayed = false;
        setState(() => _answered = null);
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_answered != null) {
        _next();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final int? index = switch (key) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => 0,
      LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => 1,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => 2,
      LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => 3,
      _ => null,
    };
    if (index == null) return KeyEventResult.ignored;
    _select(index);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StudySessionState? state = _controller?.state;
    final Card? current = _answered?.card ?? state?.current?.card;
    final String? excerpt = current?.sourceExcerpt;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: Scaffold(
        appBar: ReviewSessionAppBar(
          title: l10n.reviewModeTest,
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
    StudySessionState? state,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed || state == null) {
      return ReviewLoadErrorView(onRetry: _retry);
    }
    if (state.total == 0) {
      return ReviewEmptyView(
        title: l10n.testEmptyTitle,
        message: l10n.testEmptyMessage,
        onBack: () => context.canPop() ? context.pop() : null,
      );
    }
    if (state.isCompleted && _answered == null) {
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
                setState(() {});
              },
        onDone: () => context.canPop() ? context.pop() : null,
      );
    }
    final _AnsweredQuestion? answered = _answered;
    final Card card = answered?.card ?? state.current!.card;
    final DistractorSet set =
        answered?.options ?? _options[card.id] ?? _options.values.first;
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Center(
              child: CardContentView(
                key: ValueKey<String>('mc-question-${card.id}'),
                card: card,
                side: card.front,
                revealed: false,
                showAllFormulas: true,
                faceKey: const ValueKey<String>('mc-question-face'),
                mediaBytes: _media.bytes,
                mediaMetadata: _media.metadata,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            children: <Widget>[
              for (var index = 0; index < set.options.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _SpringOptionButton(
                    key: ValueKey<String>('study-option-$index'),
                    label: set.options[index],
                    semanticLabel: l10n.testOptionLabel(
                      index + 1,
                      plainTextOfLatex(set.options[index]),
                    ),
                    selected: answered?.selectedIndex == index,
                    state: _optionState(answered, set, index),
                    onPressed: answered == null && !state.busy
                        ? () => _select(index)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (answered != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton(
                key: const ValueKey<String>('test-next'),
                onPressed: _next,
                child: Text(l10n.testNext),
              ),
            ),
          ),
      ],
    );
  }

  _OptionVisual _optionState(
    _AnsweredQuestion? answered,
    DistractorSet set,
    int index,
  ) {
    if (answered == null) return _OptionVisual.neutral;
    if (index == set.correctIndex) return _OptionVisual.correct;
    if (index == answered.selectedIndex) return _OptionVisual.wrong;
    return _OptionVisual.neutral;
  }
}

/// Визуальное состояние варианта.
enum _OptionVisual { neutral, correct, wrong }

/// Вариант ответа с пружинной анимацией нажатия (SPEC A4.4).
class _SpringOptionButton extends StatefulWidget {
  const _SpringOptionButton({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.state,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final _OptionVisual state;
  final VoidCallback? onPressed;

  @override
  State<_SpringOptionButton> createState() => _SpringOptionButtonState();
}

class _SpringOptionButtonState extends State<_SpringOptionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _press() {
    _scale.value = 0.92;
    _scale.animateWith(
      SpringSimulation(AppMotion.standardSpring(), 0.92, 1, 0),
    );
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final (Color? background, Color? foreground) = switch (widget.state) {
      _OptionVisual.correct =>
        dark
            ? (const Color(0xFF1B5E20), const Color(0xFFC8E6C9))
            : (const Color(0xFFE8F5E9), const Color(0xFF1B5E20)),
      _OptionVisual.wrong =>
        dark
            ? (const Color(0xFFB71C1C), const Color(0xFFFFCDD2))
            : (const Color(0xFFFFEBEE), const Color(0xFFB71C1C)),
      _OptionVisual.neutral => (null, null),
    };
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: ScaleTransition(
          scale: _scale,
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: widget.onPressed == null ? null : _press,
              style: FilledButton.styleFrom(
                backgroundColor: background,
                foregroundColor: foreground,
                minimumSize: const Size.fromHeight(52),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: CardText(
                source: widget.label,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
