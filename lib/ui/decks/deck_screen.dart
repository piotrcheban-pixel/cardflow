import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/cards/content/card_text.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/decks/deck_modes_sheet.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';
import 'package:cardflow/ui/state/review_limits.dart';

/// Действие меню экрана колоды.
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

  /// Действие контекстного меню строки карточки (аудит v7, V7-16).
  ///
  /// Меню — popup у кнопки «⋮» (как у меню колоды в шапке), а не bottom sheet
  /// внизу экрана: единый паттерн контекстных меню во всём приложении (G11).
  Future<void> _onCardMenuAction(
    BuildContext context,
    Card card,
    String action,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (!context.mounted) return;
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
        // Аудит 2.0 (P1-02): у экрана колоды всегда есть видимый выход. Если
        // стек пуст (переход после импорта через `go`), стрелка ведёт к списку
        // колод, а не исчезает.
        leading: IconButton(
          key: const ValueKey<String>('deck-back'),
          tooltip: l10n.decksTitle,
          icon: const Icon(Icons.arrow_back, size: AppSizes.navIcon),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.decksPath);
            }
          },
        ),
        title: deck == null ? null : Text(deck.name),
        actions: deck == null
            ? null
            : <Widget>[
                // Аудит v4 (V10/V19): «+» из AppBar убран — добавление
                // карточки живёт одной кнопкой в строке списка. Генерация —
                // одной иконкой; пункт меню-дубль удалён.
                IconButton(
                  key: const ValueKey<String>('deck-generate-action'),
                  tooltip: l10n.deckGenerateTooltip,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: () =>
                      context.push(AppRoutes.deckGenerationPath(deck.id)),
                ),
                IconButton(
                  key: const ValueKey<String>('deck-overflow-menu'),
                  tooltip: l10n.decksMenuTooltip,
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showDeckMenu(context, ref, deck),
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
      return _DeckLoading(width: AppSizes.detailsWidth(context));
    }
    final Deck? deck = deckAsync.value;
    if (deck == null) {
      return Center(child: Text(l10n.deckNotFound));
    }
    if (cardsAsync.isLoading && !cardsAsync.hasValue) {
      return _DeckLoading(width: AppSizes.detailsWidth(context));
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
              constraints: BoxConstraints(
                maxWidth: AppSizes.detailsWidth(context),
              ),
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
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) {
                        // Аудит v4: на 390 px заголовок «Карточки» сжимался до
                        // одного символа в строке — на узком экране заголовок
                        // и действия идут двумя строками.
                        final bool stacked = c.maxWidth < 560;
                        final Widget titleRow = Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                l10n.deckCardsTitle,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              l10n.deckCardCount(cards.length),
                              maxLines: 1,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        );
                        final List<Widget> actions = <Widget>[
                          // Находка F5: поиск и фильтр по состоянию внутри
                          // колоды, не занимая место у списка постоянно.
                          if (cards.isNotEmpty) ...<Widget>[
                            IconButton(
                              key: const ValueKey<String>(
                                'deck-cards-search-toggle',
                              ),
                              tooltip: l10n.deckSearchCardsHint,
                              icon: const Icon(Icons.search),
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
                                child: const Icon(Icons.filter_list),
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
                            icon: const Icon(Icons.add),
                            label: Text(l10n.deckAddCard),
                          ),
                        ];
                        if (!stacked) {
                          return Row(
                            children: <Widget>[
                              Expanded(child: titleRow),
                              const SizedBox(width: AppSpacing.xs),
                              ...actions,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            titleRow,
                            const SizedBox(height: AppSpacing.xs),
                            // TASK 04 (M-06): на 320 px и при кегле 130 %
                            // ряд «поиск + фильтр + Добавить карточку» не
                            // помещался (overflow 14–17 px). Wrap переносит
                            // действие на вторую строку без обрезки.
                            Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xxs,
                              children: actions,
                            ),
                          ],
                        );
                      },
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
                          // Аудит 2.0 (§6): поиск без кнопки очистки заставлял
                          // стирать запрос вручную.
                          suffixIcon: _cardSearch.text.isEmpty
                              ? null
                              : IconButton(
                                  key: const ValueKey<String>(
                                    'deck-card-search-clear',
                                  ),
                                  tooltip: l10n.deckSearchClear,
                                  icon: const Icon(
                                    Icons.close,
                                    size: AppSizes.iconSmall,
                                  ),
                                  onPressed: () {
                                    _cardSearch.clear();
                                    setState(() {});
                                  },
                                ),
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
                constraints: BoxConstraints(
                  maxWidth: AppSizes.detailsWidth(context),
                ),
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
                constraints: BoxConstraints(
                  maxWidth: AppSizes.detailsWidth(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: AppEmptyState(
                    icon: Icons.search_off,
                    title: l10n.deckCardsNoMatches,
                    message: l10n.decksFilterEmptyHint,
                    compact: true,
                    actions: <Widget>[
                      // Аудит 2.0 (§6): пустой результат даёт действие «сбросить»,
                      // а не только текст.
                      FilledButton.tonal(
                        key: const ValueKey<String>('deck-cards-reset'),
                        onPressed: () => setState(() {
                          _cardSearch.clear();
                          _cardFilter = _CardFilter.all;
                        }),
                        child: Text(l10n.decksSearchResetAction),
                      ),
                    ],
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
                  constraints: BoxConstraints(
                    maxWidth: AppSizes.detailsWidth(context),
                  ),
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
                      PopupMenuButton<String>(
                        key: ValueKey<String>(
                          'deck-card-menu-${visibleCards[index].id}',
                        ),
                        tooltip: l10n.deckCardMenuTooltip,
                        icon: const Icon(Icons.more_vert, size: 18),
                        onSelected: (String action) => unawaited(
                          _onCardMenuAction(
                            context,
                            visibleCards[index],
                            action,
                          ),
                        ),
                        itemBuilder: (BuildContext menuContext) =>
                            <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                key: const ValueKey<String>(
                                  'deck-card-menu-edit',
                                ),
                                value: 'edit',
                                child: Text(l10n.deckCardEdit),
                              ),
                              PopupMenuItem<String>(
                                key: const ValueKey<String>(
                                  'deck-card-menu-delete',
                                ),
                                value: 'delete',
                                child: Text(
                                  l10n.deckCardDelete,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
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
    // Аудит v4 (V3/V5): лист режимов — общий компонент; тот же лист открывает
    // кнопка «Учить» на карточке колоды, поэтому путь к действию один.
    final DeckSessionMode? selected = await showDeckModesSheet(
      context,
      availability: DeckModeAvailability.fromCards(cards),
    );
    if (selected == null || !context.mounted) return;
    switch (selected) {
      case DeckSessionMode.practice:
        await context.push(AppRoutes.practicePath(deckId));
      case DeckSessionMode.test:
        await context.push(AppRoutes.testPath(deckId));
      case DeckSessionMode.typing:
        await context.push(AppRoutes.typingPath(deckId));
      case DeckSessionMode.match:
        await context.push(AppRoutes.matchPath(deckId));
      case DeckSessionMode.trueFalse:
        await context.push(AppRoutes.trueFalsePath(deckId));
      case DeckSessionMode.constructor:
        await context.push(AppRoutes.constructorDeckPath(deckId));
      case DeckSessionMode.classic:
        await _openClassicMode(
          context,
          deckId: deckId,
          queueWithLimits: queueWithLimits,
          queueWithoutLimits: queueWithoutLimits,
          limitedByDay: limits != null,
        );
      case DeckSessionMode.feed:
        // Лента — свободный просмотр (ADR-044): ни дневные лимиты, ни очередь
        // FSRS не проверяются, потому что просмотр ничего не записывает.
        await context.push(AppRoutes.feedPath(deckId));
    }
  }

  /// Открывает классику; при исчерпанном лимите — предупреждение с
  /// «Продолжить без лимита» (ADR-028).
  Future<void> _openClassicMode(
    BuildContext context, {
    required String deckId,
    required bool queueWithLimits,
    required bool queueWithoutLimits,
    required bool limitedByDay,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (queueWithLimits) {
      await context.push(AppRoutes.studyPath(deckId));
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
    await context.push(AppRoutes.studyPath(deckId, ignoreDailyLimits: true));
  }

  /// Единое контекстное меню колоды (V8): тот же нижний лист, что в сетке.
  Future<void> _showDeckMenu(
    BuildContext context,
    WidgetRef ref,
    Deck deck,
  ) async {
    final DeckMenuAction? action = await showDeckContextMenu(
      context,
      deckName: deck.name,
      includeArchive: false,
    );
    if (action == null || !context.mounted) return;
    await _handleMenuAction(context, ref, deck, action);
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    Deck deck,
    DeckMenuAction action,
  ) async {
    switch (action) {
      case DeckMenuAction.rename:
        await renameDeck(context, ref, deck: deck);
      case DeckMenuAction.export:
        await exportDeckZip(context, ref, deck: deck);
      case DeckMenuAction.archive:
        // На экране открытой колоды архива нет (includeArchive: false).
        break;
      case DeckMenuAction.delete:
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
    final int due = summary?.dueCards ?? 0;
    final int newCards = summary?.newCards ?? 0;
    final int inProgress = summary?.inProgressCards ?? 0;
    final int total = summary?.totalCards ?? 0;
    // Аудит v4 (V44): пояснение-«костыль» убрано («В процессе» → «Начато»),
    // поэтому метрики самодостаточны и не требуют сноски.
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        AppStatusChip(
          label: l10n.deckDueCount(due),
          // Находка D18: на пустой колоде «К повторению: 0» — не тревога.
          tone: due > 0 ? AppStatusTone.info : AppStatusTone.neutral,
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
              // Аудит 2.0 (§6): «87 %» без чисел не отвечает на вопрос «сколько
              // изучено». Показываем «62 из 71 изучено» и процент рядом.
              Text(
                l10n.deckProgressCounts(studied, total),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
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

/// Скелетон экрана колоды: шапка, панель старта и строки карточек (F22).
class _DeckLoading extends StatelessWidget {
  const _DeckLoading({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AppSkeleton(width: 240, height: 34),
              const SizedBox(height: AppSpacing.md),
              const AppSkeleton(height: 96),
              const SizedBox(height: AppSpacing.md),
              const AppSkeleton(height: 72),
              const SizedBox(height: AppSpacing.lg),
              for (int index = 0; index < 5; index++) ...<Widget>[
                const AppSkeleton(height: 64),
                const SizedBox(height: AppSpacing.xs),
              ],
            ],
          ),
        ),
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
    final bool isCloze = card.cardType == CardType.cloze;
    final bool isOcclusion = card.occlusionJson != null;
    return AppPanel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      radius: AppRadii.input,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Аудит 2.0 (P2-09): на телефоне статус-чип и кебаб сужали текстовую
          // колонку до «Чему равен ток нейтрального пр…». На узком экране текст
          // занимает всю ширину, а состояние уходит в нижнюю строку.
          final bool narrow = constraints.maxWidth < 460;
          final Widget text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // P3-02: «Обычная» повторялась на каждой строке и ничего не
              // сообщала. Badge остаётся только у особых типов.
              if (isCloze || isOcclusion)
                Text(
                  isCloze ? l10n.cardTypeCloze : l10n.cardTypeOcclusion,
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
                maxLines: narrow ? 3 : 2,
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
          );
          final Widget state = AppStatusChip(
            label: _cardStateLabel(l10n, card.state),
            tone: card.state == CardState.newCard
                ? AppStatusTone.info
                : AppStatusTone.neutral,
            dense: true,
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                text,
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: <Widget>[
                    state,
                    const Spacer(),
                    Icon(Icons.chevron_right, color: scheme.outline),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: text),
              const SizedBox(width: AppSpacing.xs),
              state,
              Icon(Icons.chevron_right, color: scheme.outline),
            ],
          );
        },
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
