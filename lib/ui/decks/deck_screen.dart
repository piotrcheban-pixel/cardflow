import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';

/// Действие меню экрана колоды.
enum _DeckMenuAction { rename, export, delete }

/// Экран «Колода» (SPEC A6.3).
///
/// Заголовок с именем, счётчики (к повторению/новые/в процессе), карточка
/// «Начать сессию» (bottom sheet режима; в итерации 2 доступен только
/// классический), список карточек с переходом в редактирование, FAB «Добавить»,
/// меню переименовать/экспорт/удалить, экспорт/импорт и состояния
/// «не найдена»/ошибка.
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
                PopupMenuButton<_DeckMenuAction>(
                  key: const ValueKey<String>('deck-overflow-menu'),
                  tooltip: l10n.decksMenuTooltip,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (_DeckMenuAction action) =>
                      _handleMenuAction(context, ref, deck, action),
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<_DeckMenuAction>>[
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
                _startSession(context, deckId: deckId, cards: cards),
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

  /// Bottom sheet режима сессии; в итерации 2 доступен только классический.
  ///
  /// Пустая очередь (все карточки не due и не новые) — сообщение вместо
  /// перехода на пустой экран.
  Future<void> _startSession(
    BuildContext context, {
    required String deckId,
    required List<Card> cards,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (ReviewQueue.build(cards, now: DateTime.now()).isEmpty) {
      showAppMessage(context, l10n.reviewStartEmptyMessage);
      return;
    }
    final bool? selected = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
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
              leading: const Icon(Icons.style_outlined),
              title: Text(l10n.reviewModeClassic),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (selected == true && context.mounted) {
      context.push(AppRoutes.studyPath(deckId));
    }
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    Deck deck,
    _DeckMenuAction action,
  ) async {
    switch (action) {
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
