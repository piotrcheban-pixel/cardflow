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
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
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

/// Фильтр списка карточек внутри колоды (находка F5 аудита).
enum _CardFilter { all, due, newCards, learning }

/// Экран «Колода» (SPEC A6.3).
///
/// Заголовок с именем, счётчики (к повторению/новые/в процессе), карточка
/// «Начать сессию» (bottom sheet режима: классика или лента), список карточек
/// с переходом в редактирование, FAB «Добавить», меню переименовать/экспорт/
/// удалить, экспорт/импорт и состояния «не найдена»/ошибка.
///
/// Аудит 1.0 (F5): в колоде появились поиск, фильтр по состоянию и меню строки
/// (изменить/удалить) — раньше 71 карточку можно было только прокручивать.
class DeckScreen extends ConsumerStatefulWidget {
  /// Создаёт экран колоды [deckId].
  const DeckScreen({required this.deckId, super.key});

  /// Идентификатор открытой колоды.
  final String deckId;

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends ConsumerState<DeckScreen> {
  /// Поиск по карточкам колоды (F5).
  final TextEditingController _cardSearch = TextEditingController();

  /// Показано ли поле поиска (по умолчанию строка списка не занимает место).
  bool _cardSearchVisible = false;

  /// Фильтр по состоянию карточки (F5).
  _CardFilter _cardFilter = _CardFilter.all;

  @override
  void dispose() {
    _cardSearch.dispose();
    super.dispose();
  }

  /// Карточки, подходящие под текущий поиск и фильтр.
  List<Card> _visibleCards(List<Card> cards) {
    final String query = _cardSearch.text.trim().toLowerCase();
    final DateTime now = DateTime.now();
    return <Card>[
      for (final Card card in cards)
        if (_matchesFilter(card, now) &&
            (query.isEmpty ||
                card.front.toLowerCase().contains(query) ||
                card.back.toLowerCase().contains(query) ||
                card.tags.any(
                  (String tag) => tag.toLowerCase().contains(query),
                )))
          card,
    ];
  }

  bool _matchesFilter(Card card, DateTime now) {
    final bool isNew = card.state == CardState.newCard;
    return switch (_cardFilter) {
      _CardFilter.all => true,
      _CardFilter.due => !isNew && card.due != null && !card.due!.isAfter(now),
      _CardFilter.newCards => isNew,
      _CardFilter.learning => !isNew,
    };
  }

  /// Меню строки карточки: изменить или удалить (F5).
  Future<void> _showCardMenu(BuildContext context, Card card) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const ValueKey<String>('deck-card-menu-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.deckCardEdit),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            ListTile(
              key: const ValueKey<String>('deck-card-menu-delete'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(l10n.deckCardDelete),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      await _openCardForm(context, deckId: widget.deckId, cardId: card.id);
      return;
    }
    final bool confirmed =
        (await showAppDialog<bool>(
          context: context,
          title: l10n.deckCardDeleteTitle,
          subtitle: l10n.deckCardDeleteMessage,
          closeLabel: l10n.cancel,
          bodyBuilder: (BuildContext dialogContext) => const SizedBox.shrink(),
          actionsBuilder: (BuildContext dialogContext) => <Widget>[
            TextButton(
              key: const ValueKey<String>('deck-card-delete-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey<String>('deck-card-delete-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        )) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(cardRepositoryProvider).deleteCard(card.id);
      if (context.mounted) {
        showAppMessage(context, l10n.cardDeletedMessage);
      }
    } on Object {
      if (context.mounted) showAppMessage(context, l10n.genericError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String deckId = widget.deckId;
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
                  key: const ValueKey<String>('deck-add-card'),
                  tooltip: l10n.deckAddCard,
                  icon: const Icon(Icons.add),
                  onPressed: () => _openCardForm(context, deckId: deckId),
                ),
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
    final String deckId = widget.deckId;
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
    // Находка N8: предупреждение об исчерпанном дневном лимите видно на самом
    // экране колоды, а не только после выбора режима в листе.
    final RemainingReviewLimits? limits = ref
        .watch(deckRemainingLimitsProvider(deckId))
        .value;
    final bool limitExhausted = _limitBlocksQueue(cards, limits);
    final List<Card> visibleCards = _visibleCards(cards);
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 896),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _DeckCounters(summary: summary),
                    const SizedBox(height: AppSpacing.md),
                    _DeckProgress(summary: summary),
                    const SizedBox(height: AppSpacing.md),
                    if (limitExhausted) ...<Widget>[
                      _DailyLimitNotice(
                        onContinueWithoutLimits: () => context.push(
                          AppRoutes.studyPath(deckId, ignoreDailyLimits: true),
                        ),
                        onPractice: () =>
                            context.push(AppRoutes.practicePath(deckId)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _StartSessionPanel(
                      key: const ValueKey<String>('deck-start-session'),
                      title: l10n.reviewStartSession,
                      subtitle: cards.isEmpty
                          ? l10n.deckStartNeedsCards
                          : l10n.deckStudyModesTitle,
                      enabled: cards.isNotEmpty,
                      onPressed: cards.isEmpty
                          ? () => showAppMessage(context, l10n.deckEmptySnack)
                          : () => _startSession(
                              context,
                              ref,
                              deckId: deckId,
                              cards: cards,
                            ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l10n.deckCardsTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          l10n.deckCardCount(cards.length),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        // Находка F5: поиск и фильтр по состоянию внутри
                        // колоды, не занимая место у списка постоянно.
                        if (cards.isNotEmpty) ...<Widget>[
                          IconButton(
                            key: const ValueKey<String>(
                              'deck-cards-search-toggle',
                            ),
                            tooltip: l10n.deckSearchCardsHint,
                            icon: const Icon(Icons.search, size: 20),
                            onPressed: () => setState(() {
                              _cardSearchVisible = !_cardSearchVisible;
                              if (!_cardSearchVisible) _cardSearch.clear();
                            }),
                          ),
                          PopupMenuButton<_CardFilter>(
                            key: const ValueKey<String>('deck-cards-filter'),
                            tooltip: _cardFilterLabel(l10n, _cardFilter),
                            icon: Badge(
                              isLabelVisible: _cardFilter != _CardFilter.all,
                              child: const Icon(Icons.filter_list, size: 20),
                            ),
                            onSelected: (_CardFilter filter) =>
                                setState(() => _cardFilter = filter),
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<_CardFilter>>[
                                  for (final _CardFilter filter
                                      in _CardFilter.values)
                                    CheckedPopupMenuItem<_CardFilter>(
                                      key: ValueKey<String>(
                                        'deck-card-filter-${filter.name}',
                                      ),
                                      value: filter,
                                      checked: _cardFilter == filter,
                                      child: Text(
                                        _cardFilterLabel(l10n, filter),
                                      ),
                                    ),
                                ],
                          ),
                        ],
                        OutlinedButton.icon(
                          key: const ValueKey<String>('deck-add-card-button'),
                          onPressed: () =>
                              _openCardForm(context, deckId: deckId),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(l10n.deckAddCard),
                        ),
                      ],
                    ),
                    if (cards.isNotEmpty && _cardSearchVisible) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const ValueKey<String>('deck-card-search'),
                        controller: _cardSearch,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: l10n.deckSearchCardsHint,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (cards.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 896),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _DeckCardsEmpty(),
                ),
              ),
            ),
          )
        else if (visibleCards.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 896),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: AppEmptyState(
                    icon: Icons.search_off,
                    title: l10n.deckCardsNoMatches,
                    message: l10n.decksFilterEmptyHint,
                    compact: true,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xxl,
            ),
            sliver: SliverList.separated(
              itemCount: visibleCards.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (BuildContext context, int index) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 896),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _DeckCardTile(
                          card: visibleCards[index],
                          onTap: () => _openCardForm(
                            context,
                            deckId: deckId,
                            cardId: visibleCards[index].id,
                          ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey<String>(
                          'deck-card-menu-${visibleCards[index].id}',
                        ),
                        tooltip: l10n.deckCardMenuTooltip,
                        icon: const Icon(Icons.more_vert, size: 18),
                        onPressed: () =>
                            _showCardMenu(context, visibleCards[index]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Подпись фильтра карточек колоды.
  static String _cardFilterLabel(AppLocalizations l10n, _CardFilter filter) =>
      switch (filter) {
        _CardFilter.all => l10n.deckFilterAll,
        _CardFilter.due => l10n.deckFilterDue,
        _CardFilter.newCards => l10n.deckFilterNew,
        _CardFilter.learning => l10n.deckFilterLearning,
      };

  /// Исчерпан ли дневной лимит при непустой очереди (находка N8).
  static bool _limitBlocksQueue(
    List<Card> cards,
    RemainingReviewLimits? limits,
  ) {
    if (limits == null || cards.isEmpty) return false;
    final DateTime now = DateTime.now();
    final bool hasQueue = ReviewQueue.build(cards, now: now).isNotEmpty;
    if (!hasQueue) return false;
    final bool limitedQueue = ReviewQueue.build(
      cards,
      now: now,
      newLimit: limits.newCards,
      reviewLimit: limits.reviews,
    ).isNotEmpty;
    return !limitedQueue;
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
      // Находка F6: сообщение по адресу — карточек в колоде нет вовсе.
      showAppMessage(context, l10n.deckEmptySnack);
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
    // 7.15/7.17: сколько карточек подходит для «Теста» и «Ввода ответа».
    // «Тест» — выбор варианта: формульные ответы допустимы (ADR-034).
    final int typingCount = cards
        .where((Card card) => AnswerTypes.isTypable(card))
        .length;
    const DistractorGenerator distractorGenerator = DistractorGenerator();
    final int testCount = cards
        .where(
          (Card card) =>
              AnswerTypes.isChoice(card) &&
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
          child: ConstrainedBox(
            // Находка D21: лист не занимает всю высоту окна; длинный список
            // прокручивается внутри и не теряет последний пункт.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
            ),
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
                    subtitle: Text(l10n.reviewModeClassicSubtitle),
                    onTap: () => choose(_SessionModeAction.classic),
                  ),
                  ListTile(
                    key: const ValueKey<String>('review-mode-feed'),
                    leading: const Icon(Icons.view_agenda_outlined),
                    title: Text(l10n.reviewModeFeed),
                    subtitle: Text(l10n.reviewModeFeedSubtitle),
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
                          : l10n.studyModeTestNotEnough(testCount),
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
                          : l10n.studyModeTypingNotEnough(typingCount),
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
                          : '${l10n.studyModeMatchNotEnough} · '
                                '${l10n.studyModeAvailableCount(matchableCount)}',
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
                          : '${l10n.studyModeTrueFalseNotEnough} · '
                                '${l10n.studyModeAvailableCount(trueFalseCount)}',
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
    final _LimitChoice? choice = await showAppDialog<_LimitChoice>(
      context: context,
      // Находка D23: компактный диалог (480 px), одна формулировка вместо
      // дублирующих заголовка и текста.
      maxWidth: 480,
      title: l10n.reviewDailyLimitTitle,
      subtitle: l10n.deckDailyLimitNotice,
      closeLabel: l10n.cancel,
      bodyBuilder: (BuildContext dialogContext) => const SizedBox.shrink(),
      actionsBuilder: (BuildContext dialogContext) => <Widget>[
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

/// Счётчики колоды: к повторению / новые / в процессе / всего карточек.
class _DeckCounters extends StatelessWidget {
  const _DeckCounters({required this.summary});

  final DeckSummary? summary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int due = summary?.dueCards ?? 0;
    final int newCards = summary?.newCards ?? 0;
    final int inProgress = summary?.inProgressCards ?? 0;
    final int total = summary?.totalCards ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            AppStatusChip(
              label: l10n.deckDueCount(due),
              // Находка D18: на пустой колоде «К повторению: 0» — не тревога.
              tone: due > 0 ? AppStatusTone.danger : AppStatusTone.neutral,
              icon: Icons.schedule,
            ),
            AppStatusChip(
              label: l10n.deckNewCount(newCards),
              tone: AppStatusTone.info,
              icon: Icons.fiber_new,
            ),
            AppStatusChip(
              label: l10n.deckInProgressCount(inProgress),
              tone: AppStatusTone.neutral,
              icon: Icons.autorenew,
            ),
            AppStatusChip(
              label: l10n.deckCardCount(total),
              tone: AppStatusTone.neutral,
              icon: Icons.style_outlined,
            ),
          ],
        ),
        // Находка F10: «в процессе» пересекается с «к повторению» — без
        // пояснения суммы не сходились (61 + 9 + 60 при 71 карточке).
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.deckCountersNote,
          key: const ValueKey<String>('deck-counters-note'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Предупреждение об исчерпанном дневном лимите прямо на экране колоды (N8).
class _DailyLimitNotice extends StatelessWidget {
  const _DailyLimitNotice({
    required this.onContinueWithoutLimits,
    required this.onPractice,
  });

  final VoidCallback onContinueWithoutLimits;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return AppPanel(
      key: const ValueKey<String>('deck-daily-limit-notice'),
      padding: const EdgeInsets.all(AppSpacing.md),
      color: scheme.errorContainer,
      borderColor: scheme.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.timer_off_outlined, color: scheme.onErrorContainer),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.reviewDailyLimitTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.deckDailyLimitNotice,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              FilledButton(
                key: const ValueKey<String>('deck-limit-continue'),
                onPressed: onContinueWithoutLimits,
                child: Text(l10n.reviewDailyLimitContinueAction),
              ),
              OutlinedButton(
                key: const ValueKey<String>('deck-limit-practice'),
                onPressed: onPractice,
                child: Text(l10n.practiceStartAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Прогресс изучения колоды (доля карточек не в состоянии «новая»).
class _DeckProgress extends StatelessWidget {
  const _DeckProgress({required this.summary});

  final DeckSummary? summary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int total = summary?.totalCards ?? 0;
    final int studied = total - (summary?.newCards ?? 0);
    final double progress = total == 0 ? 0 : studied / total;
    final int percent = (progress * 100).round();
    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.deckProgressTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                l10n.statisticsRetentionValue(percent),
                style: AppTypography.numeric(
                  context,
                  color: progress >= 1 ? scheme.secondary : scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppProgressBar(
            value: progress,
            color: progress >= 1 ? scheme.secondary : scheme.primary,
            semanticsLabel: l10n.deckProgressTitle,
          ),
        ],
      ),
    );
  }
}

/// Панель «Начать сессию»: главное действие экрана колоды.
class _StartSessionPanel extends StatelessWidget {
  const _StartSessionPanel({
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  /// Доступна ли панель (на пустой колоде — нет, находка F6).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color foreground = enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.55);
    return AppPanel(
      onTap: onPressed,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          AppIconBadge(
            icon: Icons.play_circle_outline,
            color: enabled ? scheme.primary : scheme.outline,
            size: 44,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            enabled ? Icons.chevron_right : Icons.lock_outline,
            color: scheme.outline,
          ),
        ],
      ),
    );
  }
}

/// Пустое состояние списка карточек колоды.
class _DeckCardsEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: Icons.notes_outlined,
      title: l10n.deckCardsEmpty,
      message: l10n.deckCardsEmptyHint,
      compact: true,
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
    final ColorScheme scheme = theme.colorScheme;
    final String tags = card.tags.map((String tag) => '#$tag').join(', ');
    return AppPanel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      radius: AppRadii.input,
      child: Row(
        children: <Widget>[
          AppIconBadge(
            icon: Icons.notes_outlined,
            color: scheme.primary,
            size: 32,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  card.cardType == CardType.cloze
                      ? l10n.cardTypeCloze
                      : l10n.cardTypeBasic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                // Находка D8: в списке больше нет сырой cloze-разметки
                // «{{c1::…}}» — только отформатированный текст с пропуском.
                CardText(
                  source: card.front,
                  revealed: false,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                if (card.tags.isNotEmpty)
                  Text(
                    l10n.cardTagsLine(tags),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppStatusChip(
            label: _cardStateLabel(l10n, card.state),
            tone: card.state == CardState.newCard
                ? AppStatusTone.info
                : AppStatusTone.neutral,
            dense: true,
          ),
          Icon(Icons.chevron_right, color: scheme.outline),
        ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
          child: AppErrorState(
            message: message,
            retryLabel: l10n.retry,
            onRetry: onRetry,
          ),
        ),
      ),
    );
  }
}
