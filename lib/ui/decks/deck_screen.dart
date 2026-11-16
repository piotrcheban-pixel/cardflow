import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/domain/study/answer_type.dart';
import 'package:cardflow/domain/study/distractor_generator.dart';
import 'package:cardflow/domain/study/true_false_question.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';
import 'package:cardflow/ui/state/review_limits.dart';

/// Действие меню экрана колоды.
enum _DeckMenuAction { generate, rename, export, delete }

/// Выбранный режим в листе «Начать сессию».
enum _SessionModeAction {
  classic,
  feed,
  practice,
  test,
  typing,
  match,
  trueFalse,
  constructor,
}

/// Решение в предупреждении об исчерпанном дневном лимите (ADR-028).
enum _LimitChoice { continueWithoutLimits, practice }

/// Экран «Колода» (SPEC A6.3).
///
/// Заголовок с именем, счётчики (к повторению/новые/в процессе), карточка
/// «Начать сессию» (bottom sheet режима: классика или лента), список карточек
/// с переходом в редактирование, FAB «Добавить», меню переименовать/экспорт/
/// удалить, экспорт/импорт и состояния «не найдена»/ошибка.
class DeckScreen extends ConsumerWidget {
  /// Создаёт экран колоды [deckId].
  const DeckScreen({required this.deckId, super.key});

  /// Идентификатор открытой колоды.
  final String deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Deck?> deckAsync = ref.watch(deckProvider(deckId));
    final AsyncValue<List<Card>> cardsAsync = ref.watch(
      deckCardsProvider(deckId),
    );
    final AsyncValue<DeckSummary?> summaryAsync = ref.watch(
      deckSummaryProvider(deckId),
    );

    final Deck? deck = deckAsync.value;
    final bool hasError =
        deckAsync.hasError || cardsAsync.hasError || summaryAsync.hasError;

    return Scaffold(
      appBar: AppBar(
        title: deck == null ? null : Text(deck.name),
        actions: deck == null
            ? null
            : <Widget>[
                IconButton(
                  key: const ValueKey<String>('deck-generate-action'),
                  tooltip: l10n.deckGenerateTooltip,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: () =>
                      context.push(AppRoutes.deckGenerationPath(deck.id)),
                ),
                PopupMenuButton<_DeckMenuAction>(
                  key: const ValueKey<String>('deck-overflow-menu'),
                  tooltip: l10n.decksMenuTooltip,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (_DeckMenuAction action) =>
                      _handleMenuAction(context, ref, deck, action),
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<_DeckMenuAction>>[
                        PopupMenuItem<_DeckMenuAction>(
                          value: _DeckMenuAction.generate,
                          child: Text(l10n.deckGenerateTooltip),
                        ),
                        PopupMenuItem<_DeckMenuAction>(
                          value: _DeckMenuAction.rename,
                          child: Text(l10n.deckRename),
                        ),
                        PopupMenuItem<_DeckMenuAction>(
                          value: _DeckMenuAction.export,
                          child: Text(l10n.deckExport),
                        ),
                        PopupMenuItem<_DeckMenuAction>(
                          value: _DeckMenuAction.delete,
                          child: Text(l10n.delete),
                        ),
                      ],
                ),
              ],
      ),
      floatingActionButton: deck == null
          ? null
          : FloatingActionButton.small(
              key: const ValueKey<String>('deck-add-card'),
              tooltip: l10n.deckAddCardTooltip,
              onPressed: () => _openCardForm(context, deckId: deckId),
              child: const Icon(Icons.add),
            ),
      body: _buildBody(
        context,
        ref,
        l10n,
        deckAsync,
        cardsAsync,
        summaryAsync,
        hasError,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AsyncValue<Deck?> deckAsync,
    AsyncValue<List<Card>> cardsAsync,
    AsyncValue<DeckSummary?> summaryAsync,
    bool hasError,
  ) {
    if (hasError) {
      return _DeckErrorState(
        message: l10n.deckErrorTitle,
        onRetry: () {
          ref.invalidate(deckProvider(deckId));
          ref.invalidate(deckCardsProvider(deckId));
          ref.invalidate(deckSummaryProvider(deckId));
        },
      );
    }
    if (deckAsync.isLoading && !deckAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final Deck? deck = deckAsync.value;
    if (deck == null) {
      return Center(child: Text(l10n.deckNotFound));
    }
    if (cardsAsync.isLoading && !cardsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final DeckSummary? summary = summaryAsync.asData?.value;
    final List<Card> cards = cardsAsync.value ?? const <Card>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DeckCounters(summary: summary),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: M3ECard(
            key: const ValueKey<String>('deck-start-session'),
            headline: l10n.reviewStartSession,
            semanticLabel: l10n.reviewStartSession,
            onPressed: () =>
                _startSession(context, ref, deckId: deckId, cards: cards),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: cards.isEmpty
              ? _DeckCardsEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: cards.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (BuildContext context, int index) =>
                      _DeckCardTile(
                        card: cards[index],
                        onTap: () => _openCardForm(
                          context,
                          deckId: deckId,
                          cardId: cards[index].id,
                        ),
                      ),
                ),
        ),
      ],
    );
  }

  /// Открывает форму создания/редактирования и показывает итог снекбаром.
  Future<void> _openCardForm(
    BuildContext context, {
    required String deckId,
    String? cardId,
  }) async {
    final CardFormResult? result = await context.push<CardFormResult>(
      cardId == null
          ? AppRoutes.cardNewPath(deckId)
          : AppRoutes.cardEditPath(deckId, cardId),
    );
    if (result == null || !context.mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    showAppMessage(context, switch (result) {
      CardFormResult.created => l10n.cardCreatedMessage,
      CardFormResult.updated => l10n.cardUpdatedMessage,
      CardFormResult.deleted => l10n.cardDeletedMessage,
    });
  }

  /// Bottom sheet режима сессии: классика, лента, тренировка или конструктор
  /// (SPEC A6.3, ADR-025).
  ///
  /// Пустая колода — сообщение вместо перехода. Очередь классики/ленты
  /// проверяется с тем же остатком дневных лимитов, что и сама сессия
  /// (A6.6, ADR-019 §8): если лимит на сегодня исчерпан, пользователь видит
  /// предупреждение и может продолжить без лимита или пройти карточки
  /// тренировкой (ADR-028, итерация 7.12).
  Future<void> _startSession(
    BuildContext context,
    WidgetRef ref, {
    required String deckId,
    required List<Card> cards,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (cards.isEmpty) {
      showAppMessage(context, l10n.reviewStartEmptyMessage);
      return;
    }
    RemainingReviewLimits? limits;
    try {
      limits = await readRemainingReviewLimits(ref);
    } on Object {
      // Настройки/журнал недоступны — проверяем без лимитов, как раньше.
      limits = null;
    }
    if (!context.mounted) return;
    final DateTime now = DateTime.now();
    final bool queueWithoutLimits = ReviewQueue.build(
      cards,
      now: now,
    ).isNotEmpty;
    final bool queueWithLimits = ReviewQueue.build(
      cards,
      now: now,
      newLimit: limits?.newCards,
      reviewLimit: limits?.reviews,
    ).isNotEmpty;
    // 7.15: сколько карточек подходит для «Теста» и «Ввода ответа».
    final int typingCount = cards
        .where((Card card) => AnswerTypes.isTypable(card))
        .length;
    const DistractorGenerator distractorGenerator = DistractorGenerator();
    final int testCount = cards
        .where(
          (Card card) =>
              AnswerTypes.isTypable(card) &&
              distractorGenerator.buildQuestion(card, cards) != null,
        )
        .length;
    final int matchableCount = cards
        .where(
          (Card card) =>
              card.cardType != CardType.cloze &&
              card.front.trim().isNotEmpty &&
              card.back.trim().isNotEmpty,
        )
        .length;
    final int trueFalseCount = cards
        .where((Card card) => hasTrueFalseAlternative(card, cards))
        .length;
    final _SessionModeAction?
    selected = await showModalBottomSheet<_SessionModeAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        void choose(_SessionModeAction action) {
          Navigator.of(sheetContext).pop(action);
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.reviewSessionModeTitle,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                ),
                ListTile(
                  key: const ValueKey<String>('review-mode-classic'),
                  leading: const Icon(Icons.style_outlined),
                  title: Text(l10n.reviewModeClassic),
                  onTap: () => choose(_SessionModeAction.classic),
                ),
                ListTile(
                  key: const ValueKey<String>('review-mode-feed'),
                  leading: const Icon(Icons.view_agenda_outlined),
                  title: Text(l10n.reviewModeFeed),
                  onTap: () => choose(_SessionModeAction.feed),
                ),
                ListTile(
                  key: const ValueKey<String>('review-mode-practice'),
                  leading: const Icon(Icons.sports_esports_outlined),
                  title: Text(l10n.reviewModePractice),
                  subtitle: Text(l10n.practiceSubtitle),
                  onTap: () => choose(_SessionModeAction.practice),
                ),
                ListTile(
                  key: const ValueKey<String>('review-mode-test'),
                  enabled: testCount > 0,
                  leading: const Icon(Icons.quiz_outlined),
                  title: Text(l10n.reviewModeTest),
                  subtitle: Text(
                    testCount > 0
                        ? '${l10n.studyModeTestSubtitle} · '
                              '${l10n.studyModeAvailableCount(testCount)}'
                        : l10n.studyModeNotEnough,
                  ),
                  onTap: testCount > 0
                      ? () => choose(_SessionModeAction.test)
                      : null,
                ),
                ListTile(
                  key: const ValueKey<String>('review-mode-typing'),
                  enabled: typingCount > 0,
                  leading: const Icon(Icons.keyboard_outlined),
                  title: Text(l10n.reviewModeTyping),
                  subtitle: Text(
                    typingCount > 0
                        ? '${l10n.studyModeTypingSubtitle} · '
                              '${l10n.studyModeAvailableCount(typingCount)}'
                        : l10n.studyModeNotEnough,
                  ),
                  onTap: typingCount > 0
                      ? () => choose(_SessionModeAction.typing)
                      : null,
                ),
                ListTile(
                  key: const ValueKey<String>('review-mode-match'),
                  enabled: matchableCount >= 6,
                  leading: const Icon(Icons.grid_view_outlined),
                  title: Text(l10n.reviewModeMatch),
                  subtitle: Text(
                    matchableCount >= 6
                        ? '${l10n.studyModeMatchSubtitle} · '
                              '${l10n.studyModeAvailableCount(matchableCount)}'
                        : l10n.studyModeMatchNotEnough,
                  ),
                  onTap: matchableCount >= 6
                      ? () => choose(_SessionModeAction.match)
                      : null,
                ),
                ListTile(
                  key: const ValueKey<String>('review-mode-true-false'),
                  enabled: trueFalseCount > 0,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(l10n.reviewModeTrueFalse),
                  subtitle: Text(
                    trueFalseCount > 0
                        ? '${l10n.studyModeTrueFalseSubtitle} · '
                              '${l10n.studyModeAvailableCount(trueFalseCount)}'
                        : l10n.studyModeTrueFalseNotEnough,
                  ),
                  onTap: trueFalseCount > 0
                      ? () => choose(_SessionModeAction.trueFalse)
                      : null,
                ),
                ListTile(
                  key: const ValueKey<String>('review-mode-constructor'),
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.constructorAction),
                  onTap: () => choose(_SessionModeAction.constructor),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    switch (selected) {
      case _SessionModeAction.practice:
        await context.push(AppRoutes.practicePath(deckId));
      case _SessionModeAction.test:
        await context.push(AppRoutes.testPath(deckId));
      case _SessionModeAction.typing:
        await context.push(AppRoutes.typingPath(deckId));
      case _SessionModeAction.match:
        await context.push(AppRoutes.matchPath(deckId));
      case _SessionModeAction.trueFalse:
        await context.push(AppRoutes.trueFalsePath(deckId));
      case _SessionModeAction.constructor:
        await context.push(AppRoutes.constructorDeckPath(deckId));
      case _SessionModeAction.classic:
        await _openReviewMode(
          context,
          deckId: deckId,
          feed: false,
          queueWithLimits: queueWithLimits,
          queueWithoutLimits: queueWithoutLimits,
          limitedByDay: limits != null,
        );
      case _SessionModeAction.feed:
        await _openReviewMode(
          context,
          deckId: deckId,
          feed: true,
          queueWithLimits: queueWithLimits,
          queueWithoutLimits: queueWithoutLimits,
          limitedByDay: limits != null,
        );
    }
  }

  /// Открывает классику/ленту; при исчерпанном лимите — предупреждение с
  /// «Продолжить без лимита» (ADR-028).
  Future<void> _openReviewMode(
    BuildContext context, {
    required String deckId,
    required bool feed,
    required bool queueWithLimits,
    required bool queueWithoutLimits,
    required bool limitedByDay,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (queueWithLimits) {
      await context.push(
        feed ? AppRoutes.feedPath(deckId) : AppRoutes.studyPath(deckId),
      );
      return;
    }
    if (!queueWithoutLimits || !limitedByDay) {
      showAppMessage(context, l10n.reviewStartEmptyMessage);
      return;
    }
    final _LimitChoice? choice = await showDialog<_LimitChoice>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.reviewDailyLimitTitle),
        content: Text(l10n.reviewDailyLimitContinueMessage),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('review-limit-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey<String>('review-limit-practice'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LimitChoice.practice),
            child: Text(l10n.practiceStartAction),
          ),
          FilledButton(
            key: const ValueKey<String>('review-limit-continue'),
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(_LimitChoice.continueWithoutLimits),
            child: Text(l10n.reviewDailyLimitContinueAction),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == _LimitChoice.practice) {
      await context.push(AppRoutes.practicePath(deckId));
      return;
    }
    await context.push(
      feed
          ? AppRoutes.feedPath(deckId, ignoreDailyLimits: true)
          : AppRoutes.studyPath(deckId, ignoreDailyLimits: true),
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    Deck deck,
    _DeckMenuAction action,
  ) async {
    switch (action) {
      case _DeckMenuAction.generate:
        await context.push(AppRoutes.deckGenerationPath(deck.id));
      case _DeckMenuAction.rename:
        await renameDeck(context, ref, deck: deck);
      case _DeckMenuAction.export:
        await exportDeckZip(context, ref, deck: deck);
      case _DeckMenuAction.delete:
        final bool deleted = await deleteDeckWithConfirmation(
          context,
          ref,
          deck: deck,
        );
        if (deleted && context.mounted && context.canPop()) {
          context.pop();
        }
    }
  }
}

/// Счётчики шапки экрана колоды: к повторению / новые / в процессе.
class _DeckCounters extends StatelessWidget {
  const _DeckCounters({required this.summary});

  final DeckSummary? summary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int due = summary?.dueCards ?? 0;
    final int newCards = summary?.newCards ?? 0;
    final int inProgress = summary?.inProgressCards ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: <Widget>[
          _CounterLabel(icon: Icons.schedule, label: l10n.deckDueCount(due)),
          _CounterLabel(
            icon: Icons.fiber_new,
            label: l10n.deckNewCount(newCards),
          ),
          _CounterLabel(
            icon: Icons.autorenew,
            label: l10n.deckInProgressCount(inProgress),
          ),
        ],
      ),
    );
  }
}

class _CounterLabel extends StatelessWidget {
  const _CounterLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Пустое состояние списка карточек колоды.
class _DeckCardsEmpty extends StatelessWidget {
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
              Icons.notes_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.deckCardsEmpty,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(l10n.deckCardsEmptyHint, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Одна карточка в списке колоды: front, теги, состояние; тап — редактирование.
class _DeckCardTile extends StatelessWidget {
  const _DeckCardTile({required this.card, required this.onTap});

  final Card card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String tags = card.tags.map((String tag) => '#$tag').join(', ');
    return ListTile(
      onTap: onTap,
      title: Text(card.front),
      subtitle: card.tags.isEmpty
          ? null
          : Text(
              l10n.cardTagsLine(tags),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Text(
        _cardStateLabel(l10n, card.state),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _cardStateLabel(AppLocalizations l10n, CardState state) {
    return switch (state) {
      CardState.newCard => l10n.cardStateNew,
      CardState.learning => l10n.cardStateLearning,
      CardState.review => l10n.cardStateReview,
      CardState.relearning => l10n.cardStateRelearning,
    };
  }
}

/// Состояние ошибки загрузки экрана колоды.
class _DeckErrorState extends StatelessWidget {
  const _DeckErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
