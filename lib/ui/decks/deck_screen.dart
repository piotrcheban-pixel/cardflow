import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/latex_markup.dart';
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
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/decks/deck_gem.dart';
import 'package:cardflow/ui/design/design.dart';
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

/// Экран «Колода» (SPEC A6.3, REDESIGN-SPEC §9.3).
///
/// Шапка-hero с аватаром/названием (Hero из списка колод) и тремя
/// стат-пилюлями, Hero-CTA «Начать сессию», лист режимов сеткой плиток,
/// секция карточек `NcListRow` с `CardText`, парящий тулбар
/// «Добавить»/«Сгенерировать», диалог лимита, состояния empty/error/not found.
/// Обработчики и провайдеры — прежние.
class DeckScreen extends ConsumerStatefulWidget {
  /// Создаёт экран колоды [deckId].
  const DeckScreen({required this.deckId, super.key});

  /// Идентификатор открытой колоды.
  final String deckId;

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends ConsumerState<DeckScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _menuAnchor = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Deck?> deckAsync = ref.watch(deckProvider(widget.deckId));
    final AsyncValue<List<Card>> cardsAsync = ref.watch(
      deckCardsProvider(widget.deckId),
    );
    final AsyncValue<DeckSummary?> summaryAsync = ref.watch(
      deckSummaryProvider(widget.deckId),
    );

    final Deck? deck = deckAsync.value;
    final bool hasError =
        deckAsync.hasError || cardsAsync.hasError || summaryAsync.hasError;

    final Widget topBar = NcTopBar(
      title: deck?.name,
      scrollController: _scrollController,
      leading: NcIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: l10n.reviewBack,
        variant: NcIconButtonVariant.glass,
        onPressed: () {
          if (context.canPop()) context.pop();
        },
      ),
      actions: deck == null
          ? const <Widget>[]
          : <Widget>[
              Builder(
                builder: (BuildContext context) => KeyedSubtree(
                  key: _menuAnchor,
                  child: NcIconButton(
                    key: const ValueKey<String>('deck-overflow-menu'),
                    icon: Icons.more_vert,
                    tooltip: l10n.decksMenuTooltip,
                    onPressed: () => _openOverflowMenu(context, l10n, deck),
                  ),
                ),
              ),
            ],
    );

    if (hasError) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              topBar,
              Expanded(
                child: NcErrorState(
                  message: l10n.deckErrorTitle,
                  retryLabel: l10n.retry,
                  onRetry: () {
                    ref.invalidate(deckProvider(widget.deckId));
                    ref.invalidate(deckCardsProvider(widget.deckId));
                    ref.invalidate(deckSummaryProvider(widget.deckId));
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (deckAsync.isLoading && !deckAsync.hasValue) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              topBar,
              const Expanded(child: _DeckSkeleton()),
            ],
          ),
        ),
      );
    }
    if (deck == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              topBar,
              Expanded(child: Center(child: Text(l10n.deckNotFound))),
            ],
          ),
        ),
      );
    }
    if (cardsAsync.isLoading && !cardsAsync.hasValue) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              topBar,
              const Expanded(child: _DeckSkeleton()),
            ],
          ),
        ),
      );
    }
    final DeckSummary? summary = summaryAsync.asData?.value;
    final List<Card> cards = cardsAsync.value ?? const <Card>[];
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: NcGlassGroup(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  topBar,
                  Expanded(
                    child: ListView(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(0, 0, 0, 120 + safeBottom),
                      children: <Widget>[
                        _DeckHero(
                          deck: deck,
                          summary: summary,
                          onStartSession: () => _startSession(
                            context,
                            ref,
                            deckId: widget.deckId,
                            cards: cards,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                          child: Text(
                            l10n.deckCardsSection(cards.length),
                            style: NcTheme.of(context).typography.overline
                                .copyWith(
                                  color: NcTheme.of(context)
                                      .colors
                                      .textTertiary,
                                ),
                          ),
                        ),
                        if (cards.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: _DeckCardsEmpty(
                              onAdd: () =>
                                  _openCardForm(context, deckId: widget.deckId),
                              onGenerate: () => context.push(
                                AppRoutes.deckGenerationPath(deck.id),
                              ),
                            ),
                          )
                        else
                          NcSection(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: <Widget>[
                              for (final Card card in cards)
                                _DeckCardRow(
                                  card: card,
                                  onTap: () => _openCardForm(
                                    context,
                                    deckId: widget.deckId,
                                    cardId: card.id,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 16 + safeBottom,
                child: Center(
                  child: _DeckToolbar(
                    onAdd: () => _openCardForm(context, deckId: widget.deckId),
                    onGenerate: () =>
                        context.push(AppRoutes.deckGenerationPath(deck.id)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOverflowMenu(
    BuildContext context,
    AppLocalizations l10n,
    Deck deck,
  ) async {
    final _DeckMenuAction? action = await showNcMenu<_DeckMenuAction>(
      context: context,
      anchorKey: _menuAnchor,
      items: <NcMenuItem<_DeckMenuAction>>[
        NcMenuItem<_DeckMenuAction>(
          value: _DeckMenuAction.generate,
          label: l10n.deckGenerateTooltip,
          icon: Icons.auto_awesome,
        ),
        NcMenuItem<_DeckMenuAction>(
          value: _DeckMenuAction.rename,
          label: l10n.deckRename,
          icon: Icons.edit_outlined,
        ),
        NcMenuItem<_DeckMenuAction>(
          value: _DeckMenuAction.export,
          label: l10n.deckExport,
          icon: Icons.ios_share,
        ),
        NcMenuItem<_DeckMenuAction>(
          value: _DeckMenuAction.delete,
          label: l10n.delete,
          icon: Icons.delete_outline,
          destructive: true,
          dividerBefore: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    await _handleMenuAction(context, ref, deck, action);
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
    final _SessionModeAction? selected = await showNcSheet<_SessionModeAction>(
      context,
      title: l10n.reviewModeSheetTitle,
      closeTooltip: l10n.commonClose,
      builder: (BuildContext sheetContext) {
        void choose(_SessionModeAction action) {
          Navigator.of(sheetContext).pop(action);
        }

        return _SessionModeGrid(
          testCount: testCount,
          typingCount: typingCount,
          matchableCount: matchableCount,
          trueFalseCount: trueFalseCount,
          onChoose: choose,
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
    final _LimitChoice? choice = await showNcDialog<_LimitChoice>(
      context,
      title: l10n.reviewDailyLimitTitle,
      message: l10n.reviewDailyLimitContinueMessage,
      icon3dName: 'hourglass_time',
      actions: <Widget>[
        NcButton(
          key: const ValueKey<String>('review-limit-cancel'),
          label: l10n.cancel,
          variant: NcButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        NcButton(
          key: const ValueKey<String>('review-limit-practice'),
          label: l10n.practiceStartAction,
          variant: NcButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(_LimitChoice.practice),
        ),
        NcButton(
          key: const ValueKey<String>('review-limit-continue'),
          label: l10n.reviewDailyLimitContinueAction,
          onPressed: () =>
              Navigator.of(context).pop(_LimitChoice.continueWithoutLimits),
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

/// Шапка-hero: 3D-аватар 88, название `headline`, три стат-пилюли.
class _DeckHero extends StatelessWidget {
  const _DeckHero({
    required this.deck,
    required this.summary,
    required this.onStartSession,
  });

  final Deck deck;
  final DeckSummary? summary;
  final VoidCallback onStartSession;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final int due = summary?.dueCards ?? 0;
    final int newCards = summary?.newCards ?? 0;
    final int inProgress = summary?.inProgressCards ?? 0;
    final bool narrowBadges = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: <Widget>[
          Hero(
            tag: 'deck-avatar-${deck.id}',
            child: NcIcon3D(
              name: deckGemName(deck.id),
              size: 88,
              showShadow: false,
            ),
          ),
          const SizedBox(height: NcSpace.s12),
          Hero(
            tag: 'deck-title-${deck.id}',
            child: Text(
              deck.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.headline.copyWith(
                color: theme.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: NcSpace.s12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              NcBadge(
                label: narrowBadges ? '$due' : l10n.deckDueCount(due),
                semanticLabel: l10n.deckDueCount(due),
                tone: NcBadgeTone.accent,
              ),
              NcBadge(
                label: narrowBadges ? '$newCards' : l10n.deckNewCount(newCards),
                semanticLabel: l10n.deckNewCount(newCards),
                tone: NcBadgeTone.glacier,
              ),
              NcBadge(
                label: narrowBadges
                    ? '$inProgress'
                    : l10n.deckInProgressCount(inProgress),
                semanticLabel: l10n.deckInProgressCount(inProgress),
                tone: NcBadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: NcSpace.s16),
          _StartSessionCard(
            subtitle: l10n.deckDueCount(due),
            onTap: onStartSession,
          ),
        ],
      ),
    );
  }
}

/// Hero-CTA «Начать сессию»: единственный glow на экране (§9.3).
class _StartSessionCard extends StatelessWidget {
  const _StartSessionCard({required this.subtitle, required this.onTap});

  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final double scale = MediaQuery.textScalerOf(context)
        .scale(1)
        .clamp(1.0, 1.8);
    return NcSurface(
      key: const ValueKey<String>('deck-start-session'),
      radius: NcRadii.xxl,
      level: 2,
      height: 120 * scale,
      padding: EdgeInsets.zero,
      semanticLabel: l10n.reviewStartSession,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  theme.colors.ink3,
                  theme.colors.aurumSoft.withValues(alpha: 0.35),
                ],
              ),
              shadows: theme.depth.glow(theme.colors.aurum),
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(NcRadii.xxl),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 16, 20),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        l10n.reviewStartSession,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.titleL.copyWith(
                          color: theme.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: NcSpace.s4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.bodyM.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const NcIcon3D(
                  name: 'mode_classic',
                  size: 72,
                  showShadow: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Лист режимов: сетка 2 × 4 на телефоне, 4 × 2 на ПК.
class _SessionModeGrid extends StatelessWidget {
  const _SessionModeGrid({
    required this.testCount,
    required this.typingCount,
    required this.matchableCount,
    required this.trueFalseCount,
    required this.onChoose,
  });

  final int testCount;
  final int typingCount;
  final int matchableCount;
  final int trueFalseCount;
  final ValueChanged<_SessionModeAction> onChoose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double width = MediaQuery.sizeOf(context).width;
    final int columns = width >= 1024 ? 4 : 2;
    final double scale = MediaQuery.textScalerOf(context)
        .scale(1)
        .clamp(1.0, 1.8);
    final List<_ModeSpec> modes = <_ModeSpec>[
      _ModeSpec(
        action: _SessionModeAction.classic,
        key: const ValueKey<String>('review-mode-classic'),
        icon: 'mode_classic',
        title: l10n.reviewModeClassic,
        subtitle: null,
        enabled: true,
      ),
      _ModeSpec(
        action: _SessionModeAction.feed,
        key: const ValueKey<String>('review-mode-feed'),
        icon: 'mode_feed',
        title: l10n.reviewModeFeed,
        subtitle: null,
        enabled: true,
      ),
      _ModeSpec(
        action: _SessionModeAction.test,
        key: const ValueKey<String>('review-mode-test'),
        icon: 'mode_test',
        title: l10n.reviewModeTest,
        subtitle: testCount > 0
            ? '${l10n.studyModeTestSubtitle} · '
                  '${l10n.studyModeAvailableCount(testCount)}'
            : l10n.studyModeNotEnough,
        enabled: testCount > 0,
      ),
      _ModeSpec(
        action: _SessionModeAction.typing,
        key: const ValueKey<String>('review-mode-typing'),
        icon: 'mode_typing',
        title: l10n.reviewModeTyping,
        subtitle: typingCount > 0
            ? '${l10n.studyModeTypingSubtitle} · '
                  '${l10n.studyModeAvailableCount(typingCount)}'
            : l10n.studyModeNotEnough,
        enabled: typingCount > 0,
      ),
      _ModeSpec(
        action: _SessionModeAction.match,
        key: const ValueKey<String>('review-mode-match'),
        icon: 'mode_match',
        title: l10n.reviewModeMatch,
        subtitle: matchableCount >= 6
            ? '${l10n.studyModeMatchSubtitle} · '
                  '${l10n.studyModeAvailableCount(matchableCount)}'
            : l10n.studyModeMatchNotEnough,
        enabled: matchableCount >= 6,
      ),
      _ModeSpec(
        action: _SessionModeAction.trueFalse,
        key: const ValueKey<String>('review-mode-true-false'),
        icon: 'mode_true_false',
        title: l10n.reviewModeTrueFalse,
        subtitle: trueFalseCount > 0
            ? '${l10n.studyModeTrueFalseSubtitle} · '
                  '${l10n.studyModeAvailableCount(trueFalseCount)}'
            : l10n.studyModeTrueFalseNotEnough,
        enabled: trueFalseCount > 0,
      ),
      _ModeSpec(
        action: _SessionModeAction.practice,
        key: const ValueKey<String>('review-mode-practice'),
        icon: 'mode_practice',
        title: l10n.reviewModePractice,
        subtitle: l10n.practiceSubtitle,
        enabled: true,
      ),
      _ModeSpec(
        action: _SessionModeAction.constructor,
        key: const ValueKey<String>('review-mode-constructor'),
        icon: 'mode_constructor',
        title: l10n.constructorAction,
        subtitle: null,
        enabled: true,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 132 * scale,
      ),
      itemCount: modes.length,
      itemBuilder: (BuildContext context, int index) =>
          _ModeTile(spec: modes[index], onTap: onChoose, columns: columns),
    );
  }
}

/// Описание плитки режима.
class _ModeSpec {
  const _ModeSpec({
    required this.action,
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
  });

  final _SessionModeAction action;
  final Key key;
  final String icon;
  final String title;
  final String? subtitle;
  final bool enabled;
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.spec,
    required this.onTap,
    required this.columns,
  });

  final _ModeSpec spec;
  final ValueChanged<_SessionModeAction> onTap;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final String? subtitle = spec.subtitle;
    return Opacity(
      opacity: spec.enabled ? 1 : 0.4,
      child: NcSurface(
        key: spec.key,
        radius: NcRadii.l,
        level: 1,
        padding: const EdgeInsets.all(NcSpace.s8),
        semanticLabel: spec.title,
        onTap: spec.enabled ? () => onTap(spec.action) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: NcIcon3D(name: spec.icon, size: 56, showShadow: false),
            ),
            const Spacer(),
            Text(
              spec.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.titleS.copyWith(
                color: spec.enabled
                    ? theme.colors.textPrimary
                    : theme.colors.textDisabled,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.bodyS.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Пустое состояние карточек колоды.
class _DeckCardsEmpty extends StatelessWidget {
  const _DeckCardsEmpty({required this.onAdd, required this.onGenerate});

  final VoidCallback onAdd;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NcEmptyState(
      iconName: 'empty_cards',
      title: l10n.deckCardsEmpty,
      message: l10n.deckCardsEmptyHint,
      primaryAction: NcButton(
        label: l10n.deckAddCardTooltip,
        icon: Icons.add_rounded,
        onPressed: onAdd,
      ),
      secondaryAction: NcButton(
        label: l10n.decksCreateGenerate,
        variant: NcButtonVariant.ai,
        icon: Icons.auto_awesome,
        onPressed: onGenerate,
      ),
    );
  }
}

/// Одна карточка в списке колоды: глиф типа, лицевая сторона через `CardText`,
/// ответ `textSecondary`, точка состояния и миниатюра.
class _DeckCardRow extends StatelessWidget {
  const _DeckCardRow({required this.card, required this.onTap});

  final Card card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final String stateLabel = switch (card.state) {
      CardState.newCard => l10n.cardStateNew,
      CardState.learning => l10n.cardStateLearning,
      CardState.review => l10n.cardStateReview,
      CardState.relearning => l10n.cardStateRelearning,
    };
    final Color stateColor = card.suspended
        ? theme.colors.textDisabled
        : switch (card.state) {
            CardState.newCard => theme.colors.glacier,
            CardState.learning => theme.colors.amber,
            CardState.review => theme.colors.jade,
            CardState.relearning => theme.colors.amber,
          };
    return NcListRow(
      onTap: onTap,
      semanticLabel: card.front,
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colors.ink4,
          shape: BoxShape.circle,
        ),
        child: _CardTypeGlyph(card: card),
      ),
      title: CardText(
        source: card.front,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.typography.titleS.copyWith(
          color: theme.colors.textPrimary,
        ),
      ),
      subtitle: CardText(
        source: card.back,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.typography.bodyS.copyWith(
          color: theme.colors.textSecondary,
        ),
      ),
      trailing: Semantics(
        label: stateLabel,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Глиф типа карточки: Basic — две полоски, Cloze — `[…]`, LaTeX — `∑`,
/// Occlusion — рамка с маской.
const String _clozeGlyph = '[…]';
const String _latexGlyph = '∑';

class _CardTypeGlyph extends StatelessWidget {
  const _CardTypeGlyph({required this.card});

  final Card card;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Color color = theme.colors.textSecondary;
    if (card.cardType == CardType.cloze) {
      return Text(
        _clozeGlyph,
        style: theme.typography.monoM.copyWith(color: color, fontSize: 10),
      );
    }
    if (card.occlusionJson != null) {
      return Icon(Icons.crop_free, size: 14, color: color);
    }
    if (LatexMarkup.parse(card.front).hasFormulas ||
        LatexMarkup.parse(card.back).hasFormulas) {
      return Text(
        _latexGlyph,
        style: theme.typography.monoM.copyWith(color: color, fontSize: 14),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(width: 12, height: 2, color: color),
        const SizedBox(height: 3),
        Container(width: 8, height: 2, color: color),
      ],
    );
  }
}

/// Парящий тулбар колоды: «Добавить» (primary-круг 48) и «Сгенерировать».
class _DeckToolbar extends StatelessWidget {
  const _DeckToolbar({required this.onAdd, required this.onGenerate});

  final VoidCallback onAdd;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    return NcGlass(
      tier: NcGlassTier.regular,
      radius: NcRadii.pill,
      grouped: true,
      showNoise: false,
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcSurface(
            key: const ValueKey<String>('deck-add-card'),
            width: 48,
            height: 48,
            radius: NcRadii.pill,
            level: 0,
            border: false,
            hoverLift: false,
            padding: EdgeInsets.zero,
            color: theme.colors.aurum,
            semanticLabel: l10n.deckAddCardTooltip,
            onTap: onAdd,
            child: Icon(Icons.add_rounded, color: theme.colors.textOnAccent),
          ),
          const SizedBox(width: 8),
          NcIconButton(
            key: const ValueKey<String>('deck-generate-action'),
            icon: Icons.auto_awesome,
            tooltip: l10n.deckGenerateTooltip,
            iconColor: theme.colors.iris,
            onPressed: onGenerate,
          ),
        ],
      ),
    );
  }
}

/// Загрузка экрана колоды: skeleton-строки.
class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Center(child: NcSkeleton(width: 88, height: 88)),
          const SizedBox(height: 16),
          const Center(child: NcSkeleton(width: 180, height: 28)),
          const SizedBox(height: 24),
          const NcSkeleton(height: 120, radius: NcRadii.xxl),
          const SizedBox(height: 24),
          for (var index = 0; index < 4; index++) ...<Widget>[
            const NcSkeleton(height: 64, radius: NcRadii.l),
            if (index < 3) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
