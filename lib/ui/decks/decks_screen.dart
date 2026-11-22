import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_layout.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/settings/provider_banner.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Действие контекстного меню колоды.
enum _DeckMenuAction { archive, rename, export, delete }

/// Экран «Мои колоды» (SPEC A6.2, ADR-038).
///
/// Шапка с реальными счётчиками, KPI-плитки, панель поиска/фильтров/сортировки,
/// сетка карточек колод. Полностью сохранены: поиск, фильтры, архив свайпом и
/// из меню с undo, переименование, экспорт/импорт ZIP, удаление с
/// подтверждением и создание колоды.
class DecksScreen extends ConsumerWidget {
  /// Создаёт экран.
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DeckQuery query = ref.watch(decksQueryProvider);
    final DecksSort sort = ref.watch(decksSortProvider);
    final DecksViewMode viewMode = ref.watch(decksViewModeProvider);
    final AsyncValue<List<DeckSummary>> summaries = ref.watch(
      deckSummariesProvider,
    );
    final AsyncValue<List<DeckSummary>> allSummaries = ref.watch(
      allDeckSummariesProvider,
    );
    final List<DeckSummary> decks = allSummaries.value ?? const <DeckSummary>[];

    final int totalCards = decks.fold<int>(
      0,
      (int sum, DeckSummary deck) => sum + deck.totalCards,
    );
    final int dueCards = decks.fold<int>(
      0,
      (int sum, DeckSummary deck) => sum + deck.dueCards,
    );
    final int studiedCards = decks.fold<int>(
      0,
      (int sum, DeckSummary deck) => sum + deck.totalCards - deck.newCards,
    );
    final bool loaded = summaries.hasValue;
    final Size window = MediaQuery.sizeOf(context);
    final bool compactHeight = window.height < 760;
    // Первый запуск: пустая база без фильтров — KPI и панель фильтров не нужны,
    // первым видно пустое состояние с действиями (находка D16).
    final bool firstLaunch =
        loaded &&
        (summaries.value ?? const <DeckSummary>[]).isEmpty &&
        decks.isEmpty &&
        query.normalizedSearch.isEmpty &&
        query.filter == DeckFilter.all;
    final bool showChrome = !firstLaunch;
    // Находка F7: «основной провайдер не настроен» виден уже на главной.
    final ProviderAccount? activeProvider = ref
        .watch(providerAccountsProvider)
        .value
        ?.active;
    final bool providerBroken =
        activeProvider != null && !activeProvider.isConfigured;

    return Scaffold(
      body: AppPageScaffold(
        header: AppPageHeader(
          title: l10n.decksTitle,
          subtitle: Text(l10n.decksSubtitle(decks.length, dueCards)),
          overline: _DecksOverline(dueCards: loaded ? dueCards : null),
          actions: <Widget>[
            OutlinedButton.icon(
              key: const ValueKey<String>('decks-import'),
              onPressed: () => importDeckZip(context, ref),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.decksImportButton),
            ),
            FilledButton.icon(
              key: const ValueKey<String>('decks-new-deck'),
              onPressed: () => createDeckManually(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.decksNewDeck),
            ),
            IconButton(
              key: const ValueKey<String>('decks-generate-action'),
              tooltip: l10n.deckGenerateTooltip,
              icon: const Icon(Icons.auto_awesome_outlined, size: 20),
              onPressed: () => context.push(AppRoutes.generationPath),
            ),
          ],
        ),
        slivers: <Widget>[
          if (providerBroken) const PrimaryProviderBanner(),
          // Находка D16: на низком окне (800×600) четыре KPI-плитки съедали
          // экран, и пустое состояние/первая колода уходили под сгиб. На
          // низком окне KPI сжимаются в одну строку, а на первом запуске
          // (пустая база) метрики и панель фильтров не показываются вовсе —
          // первым видно пустое состояние с действиями.
          if (showChrome) ...<Widget>[
            if (compactHeight)
              _MetricsLine(
                totalCards: totalCards,
                dueCards: dueCards,
                studiedCards: studiedCards,
                decks: decks.length,
              )
            else
              _MetricsStrip(
                totalCards: totalCards,
                dueCards: dueCards,
                studiedCards: studiedCards,
                decks: decks.length,
              ),
            _DecksToolbar(
              query: query,
              sort: sort,
              viewMode: viewMode,
              counts: _FilterCounts.fromSummaries(decks),
            ),
          ],
          summaries.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.huge),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object error, StackTrace stackTrace) => AppErrorState(
              message: l10n.decksErrorTitle,
              retryLabel: l10n.retry,
              onRetry: () => ref.invalidate(deckSummariesProvider),
            ),
            data: (List<DeckSummary> loadedDecks) {
              if (loadedDecks.isEmpty) {
                final bool filtered =
                    query.normalizedSearch.isNotEmpty ||
                    query.filter != DeckFilter.all;
                if (filtered) {
                  // Находка D17: пустой результат поиска говорит про поиск,
                  // а не про «создайте колоду вручную».
                  final String search = query.normalizedSearch;
                  return AppEmptyState(
                    icon: Icons.search_off,
                    title: search.isNotEmpty
                        ? l10n.decksNoResultsForQuery(search)
                        : l10n.decksNoResults,
                    message: l10n.decksFilterEmptyHint,
                    actions: <Widget>[
                      FilledButton(
                        key: const ValueKey<String>('decks-reset-filters'),
                        onPressed: () {
                          ref.read(decksQueryProvider.notifier).clearSearch();
                          ref
                              .read(decksQueryProvider.notifier)
                              .setFilter(DeckFilter.all);
                        },
                        child: Text(l10n.decksSearchResetAction),
                      ),
                      OutlinedButton(
                        onPressed: () => createDeckManually(context, ref),
                        child: Text(l10n.decksCreateButton),
                      ),
                    ],
                  );
                }
                return _FirstLaunchEmptyState();
              }
              return _DeckCollection(
                summaries: _sortDecks(loadedDecks, sort),
                viewMode: viewMode,
                onOpen: (DeckSummary summary) =>
                    context.push('/decks/${summary.deck.id}'),
                onMenu: (DeckSummary summary) =>
                    _showContextMenu(context, ref, summary),
                onArchive: (DeckSummary summary) =>
                    _archiveDeck(context, ref, summary),
              );
            },
          ),
        ],
      ),
    );
  }

  static List<DeckSummary> _sortDecks(List<DeckSummary> decks, DecksSort sort) {
    final List<DeckSummary> sorted = List<DeckSummary>.of(decks);
    int studied(DeckSummary deck) => deck.totalCards - deck.newCards;
    switch (sort) {
      case DecksSort.due:
        sorted.sort((DeckSummary a, DeckSummary b) {
          final int byDue = b.dueCards.compareTo(a.dueCards);
          return byDue != 0 ? byDue : a.deck.name.compareTo(b.deck.name);
        });
      case DecksSort.progress:
        sorted.sort((DeckSummary a, DeckSummary b) {
          final double aProgress = a.totalCards == 0
              ? 0
              : studied(a) / a.totalCards;
          final double bProgress = b.totalCards == 0
              ? 0
              : studied(b) / b.totalCards;
          final int byProgress = bProgress.compareTo(aProgress);
          return byProgress != 0
              ? byProgress
              : a.deck.name.compareTo(b.deck.name);
        });
      case DecksSort.cards:
        sorted.sort((DeckSummary a, DeckSummary b) {
          final int byCards = b.totalCards.compareTo(a.totalCards);
          return byCards != 0 ? byCards : a.deck.name.compareTo(b.deck.name);
        });
      case DecksSort.name:
        sorted.sort(
          (DeckSummary a, DeckSummary b) =>
              a.deck.name.toLowerCase().compareTo(b.deck.name.toLowerCase()),
        );
    }
    return sorted;
  }

  Future<void> _archiveDeck(
    BuildContext context,
    WidgetRef ref,
    DeckSummary summary,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      await ref.read(deckRepositoryProvider).archiveDeck(summary.deck.id);
    } catch (_) {
      if (context.mounted) showAppMessage(context, l10n.genericError);
      return;
    }
    if (context.mounted) {
      showArchivedUndoSnackbar(context, ref, deckId: summary.deck.id);
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    DeckSummary summary,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final _DeckMenuAction? action = await showModalBottomSheet<_DeckMenuAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.deckRename),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_DeckMenuAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(l10n.deckExport),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_DeckMenuAction.export),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(l10n.deckActionArchive),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_DeckMenuAction.archive),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.delete),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_DeckMenuAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _DeckMenuAction.archive:
        await _archiveDeck(context, ref, summary);
      case _DeckMenuAction.rename:
        await renameDeck(context, ref, deck: summary.deck);
      case _DeckMenuAction.export:
        await exportDeckZip(context, ref, deck: summary.deck);
      case _DeckMenuAction.delete:
        await deleteDeckWithConfirmation(context, ref, deck: summary.deck);
    }
  }
}

/// Надзаголовок: реальный остаток повторений и метод планировщика.
class _DecksOverline extends StatelessWidget {
  const _DecksOverline({required this.dueCards});

  final int? dueCards;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final int? due = dueCards;
    // На узком экране точка-разделитель остаётся в одиночестве на строке.
    final bool showDot = due != null && MediaQuery.sizeOf(context).width >= 420;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (due != null)
          AppStatusChip(
            key: const ValueKey<String>('decks-due-chip'),
            label: l10n.shellDueToday(due),
            tone: due > 0 ? AppStatusTone.info : AppStatusTone.success,
            icon: due > 0 ? Icons.schedule : Icons.check_circle,
            dense: true,
          ),
        if (showDot)
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline,
              shape: BoxShape.circle,
            ),
          ),
        Text(
          l10n.decksOverline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.overline(context),
        ),
      ],
    );
  }
}

/// Полоса KPI-плиток.
class _MetricsStrip extends StatelessWidget {
  const _MetricsStrip({
    required this.totalCards,
    required this.dueCards,
    required this.studiedCards,
    required this.decks,
  });

  final int totalCards;
  final int dueCards;
  final int studiedCards;
  final int decks;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat number = NumberFormat.decimalPattern('ru');
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 620 ? 4 : 2;
        final double gap = AppSpacing.sm;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        final List<Widget> tiles = <Widget>[
          AppStatTile(
            key: const ValueKey<String>('decks-kpi-total'),
            label: l10n.decksMetricTotal,
            value: number.format(totalCards),
            icon: Icons.style_outlined,
            iconColor: scheme.primary,
          ),
          AppStatTile(
            key: const ValueKey<String>('decks-kpi-due'),
            label: l10n.decksMetricDue,
            value: number.format(dueCards),
            icon: Icons.schedule,
            iconColor: scheme.tertiary,
            helper: Text(l10n.shellDueLabel),
            helperColor: scheme.tertiary,
          ),
          AppStatTile(
            key: const ValueKey<String>('decks-kpi-studied'),
            label: l10n.decksMetricStudied,
            value: number.format(studiedCards),
            icon: Icons.task_alt,
            iconColor: scheme.secondary,
            helper: Text(l10n.decksProgressLabel),
          ),
          AppStatTile(
            key: const ValueKey<String>('decks-kpi-decks'),
            label: l10n.decksMetricDecks,
            value: number.format(decks),
            icon: Icons.view_agenda_outlined,
            iconColor: scheme.primary,
          ),
        ];
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Widget tile in tiles)
              SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

/// Счётчики для чипов фильтра.
class _FilterCounts {
  const _FilterCounts({
    required this.all,
    required this.withNew,
    required this.inProgress,
    required this.due,
  });

  factory _FilterCounts.fromSummaries(List<DeckSummary> decks) => _FilterCounts(
    all: decks.length,
    withNew: decks.where((DeckSummary deck) => deck.newCards > 0).length,
    inProgress: decks
        .where((DeckSummary deck) => deck.inProgressCards > 0)
        .length,
    due: decks.where((DeckSummary deck) => deck.dueCards > 0).length,
  );

  final int all;
  final int withNew;
  final int inProgress;
  final int due;
}

/// Панель поиска, фильтров, сортировки и режима отображения.
class _DecksToolbar extends ConsumerWidget {
  const _DecksToolbar({
    required this.query,
    required this.sort,
    required this.viewMode,
    required this.counts,
  });

  final DeckQuery query;
  final DecksSort sort;
  final DecksViewMode viewMode;
  final _FilterCounts counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool searchVisible = ref.watch(decksSearchVisibleProvider);
    final bool filtersVisible = ref.watch(decksFiltersVisibleProvider);
    final double width = MediaQuery.sizeOf(context).width;
    final bool wide = width >= 900;
    final bool compactControls = width < 520;

    const Widget search = _DecksSearchField();
    final Widget controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PopupMenuButton<DecksSort>(
          key: const ValueKey<String>('decks-sort'),
          tooltip: l10n.decksSortTooltip,
          initialValue: sort,
          onSelected: (DecksSort value) =>
              ref.read(decksSortProvider.notifier).set(value),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<DecksSort>>[
            for (final DecksSort value in DecksSort.values)
              PopupMenuItem<DecksSort>(
                value: value,
                child: Text(_sortLabel(l10n, value)),
              ),
          ],
          child: Container(
            height: 34,
            width: compactControls ? 34 : null,
            padding: EdgeInsets.symmetric(
              horizontal: compactControls ? 0 : AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.sort,
                  size: AppSizes.iconSmall,
                  color: scheme.outline,
                ),
                if (!compactControls) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    _sortLabel(l10n, sort),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    size: AppSizes.iconSmall,
                    color: scheme.outline,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Container(
          height: 34,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ViewModeButton(
                key: const ValueKey<String>('decks-view-grid'),
                icon: Icons.grid_view,
                tooltip: l10n.decksViewGrid,
                selected: viewMode == DecksViewMode.grid,
                onPressed: () => ref
                    .read(decksViewModeProvider.notifier)
                    .set(DecksViewMode.grid),
              ),
              _ViewModeButton(
                key: const ValueKey<String>('decks-view-list'),
                icon: Icons.view_list,
                tooltip: l10n.decksViewList,
                selected: viewMode == DecksViewMode.list,
                onPressed: () => ref
                    .read(decksViewModeProvider.notifier)
                    .set(DecksViewMode.list),
              ),
            ],
          ),
        ),
      ],
    );

    final Widget searchRow = Row(
      children: <Widget>[
        if (!wide && !searchVisible) ...<Widget>[
          IconButton(
            tooltip: l10n.decksSearchTooltip,
            icon: const Icon(Icons.search, size: AppSizes.navIcon),
            onPressed: () =>
                ref.read(decksSearchVisibleProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: l10n.decksFilterTooltip,
            icon: const Icon(Icons.filter_list, size: AppSizes.navIcon),
            onPressed: () =>
                ref.read(decksFiltersVisibleProvider.notifier).toggle(),
          ),
          const Spacer(),
          controls,
        ] else if (!wide) ...<Widget>[
          Expanded(child: search),
          IconButton(
            tooltip: l10n.decksFilterTooltip,
            icon: const Icon(Icons.filter_list, size: AppSizes.navIcon),
            onPressed: () {
              ref.read(decksSearchVisibleProvider.notifier).close();
              ref.read(decksFiltersVisibleProvider.notifier).toggle();
            },
          ),
          controls,
        ] else ...<Widget>[
          Expanded(child: search),
          const SizedBox(width: AppSpacing.xs),
          controls,
        ],
      ],
    );

    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.xs + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          searchRow,
          if (filtersVisible) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (int index = 0; index < 4; index++) ...<Widget>[
                    if (index > 0) const SizedBox(width: AppSpacing.xs),
                    _FilterChip(
                      label: _filterLabel(l10n, counts, index),
                      selected: query.filter == DeckFilter.values[index],
                      danger: index == 3,
                      onPressed: () => ref
                          .read(decksQueryProvider.notifier)
                          .setFilter(DeckFilter.values[index]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _sortLabel(AppLocalizations l10n, DecksSort sort) =>
      switch (sort) {
        DecksSort.due => l10n.decksSortDue,
        DecksSort.progress => l10n.decksSortProgress,
        DecksSort.cards => l10n.decksSortCards,
        DecksSort.name => l10n.decksSortName,
      };

  static String _filterLabel(
    AppLocalizations l10n,
    _FilterCounts counts,
    int index,
  ) => switch (index) {
    0 => l10n.decksFilterAllCount(counts.all),
    1 => l10n.decksFilterNewCount(counts.withNew),
    2 => l10n.decksFilterInProgressCount(counts.inProgress),
    _ => l10n.decksFilterDueCount(counts.due),
  };
}

/// Кнопка режима отображения (сетка/список).
class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          // Находка A4: цель 44×44 (было 30×30), визуальный квадрат — внутри.
          width: AppSizes.minTouchTarget,
          height: AppSizes.minTouchTarget,
          alignment: Alignment.center,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.surfaceContainerLowest
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.08),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: AppSizes.iconSmall,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Чип фильтра.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final bool selected;
  final bool danger;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color background = selected
        ? scheme.primary
        : danger
        ? scheme.errorContainer.withValues(alpha: 0.5)
        : scheme.surfaceContainerLow;
    final Color foreground = selected
        ? scheme.onPrimary
        : danger
        ? scheme.error
        : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: SizedBox(
        height: AppSizes.minTouchTarget,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Поле поиска колод.
class _DecksSearchField extends ConsumerStatefulWidget {
  const _DecksSearchField();

  @override
  ConsumerState<_DecksSearchField> createState() => _DecksSearchFieldState();
}

class _DecksSearchFieldState extends ConsumerState<_DecksSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String search = ref.watch(decksQueryProvider).search;
    // Внешнее изменение запроса (кнопка поиска в панели, сброс) обновляет поле.
    if (_controller.text != search) {
      _controller.value = TextEditingValue(
        text: search,
        selection: TextSelection.collapsed(offset: search.length),
      );
    }
    final Widget field = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: Colors.transparent),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: AppSizes.icon, color: scheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: false,
              onChanged: (String value) =>
                  ref.read(decksQueryProvider.notifier).setSearch(value),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: l10n.decksSearchHint,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (search.isNotEmpty)
            IconButton(
              tooltip: l10n.decksSearchClearTooltip,
              icon: const Icon(Icons.close, size: AppSizes.iconSmall),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                _controller.clear();
                ref.read(decksQueryProvider.notifier).clearSearch();
              },
            ),
        ],
      ),
    );
    return field;
  }
}

/// Сетка/список карточек колод.
class _DeckCollection extends StatelessWidget {
  const _DeckCollection({
    required this.summaries,
    required this.viewMode,
    required this.onOpen,
    required this.onMenu,
    required this.onArchive,
  });

  final List<DeckSummary> summaries;
  final DecksViewMode viewMode;
  final ValueChanged<DeckSummary> onOpen;
  final ValueChanged<DeckSummary> onMenu;
  final ValueChanged<DeckSummary> onArchive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = switch (viewMode) {
          DecksViewMode.list => 1,
          DecksViewMode.grid =>
            constraints.maxWidth >= 1024
                ? 3
                : constraints.maxWidth >= 640
                ? 2
                : 1,
        };
        final double gap = AppSpacing.md;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final DeckSummary summary in summaries)
              SizedBox(
                width: width,
                child: Dismissible(
                  key: ValueKey<String>('deck-card-${summary.deck.id}'),
                  direction: DismissDirection.endToStart,
                  background: const _ArchiveSwipeBackground(),
                  onDismissed: (DismissDirection direction) =>
                      onArchive(summary),
                  child: _DeckTile(
                    summary: summary,
                    onOpen: () => onOpen(summary),
                    onMenu: () => onMenu(summary),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Фон свайпа «в архив».
class _ArchiveSwipeBackground extends StatelessWidget {
  const _ArchiveSwipeBackground();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppRadii.cardRadius,
      ),
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xl),
      child: Icon(Icons.archive_outlined, color: scheme.onErrorContainer),
    );
  }
}

/// Карточка колоды.
class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.summary,
    required this.onOpen,
    required this.onMenu,
  });

  final DeckSummary summary;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int studied = summary.totalCards - summary.newCards;
    final double progress = summary.totalCards == 0
        ? 0
        : studied / summary.totalCards;
    final bool hasWork = summary.dueCards > 0 || summary.newCards > 0;
    final String date = MaterialLocalizations.of(context)
        .formatShortDate(summary.deck.updatedAt.toLocal());

    return AppPanel(
      key: ValueKey<String>('deck-tile-${summary.deck.id}'),
      onTap: onOpen,
      onLongPress: onMenu,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _DeckMonogram(name: summary.deck.name),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.deckOverline.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.overline(context),
                    ),
                    Text(
                      summary.deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey<String>('deck-menu-${summary.deck.id}'),
                tooltip: l10n.deckMoreActions,
                icon: const Icon(Icons.more_horiz, size: AppSizes.icon),
                onPressed: onMenu,
                style: IconButton.styleFrom(
                  foregroundColor: scheme.outline,
                  // Находка A4: цель не меньше 44×44, а не 32 px.
                  minimumSize: const Size(
                    AppSizes.minTouchTarget,
                    AppSizes.minTouchTarget,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (summary.totalCards == 0)
                // Находка D18: одно сообщение нейтрального тона вместо чипа
                // «В колоде пока нет карточек» + текста «Нет карточек».
                AppStatusChip(
                  label: l10n.deckCardsEmpty,
                  tone: AppStatusTone.neutral,
                  dense: true,
                )
              else if (summary.dueCards > 0)
                AppStatusChip(
                  label: l10n.deckDueCount(summary.dueCards),
                  tone: AppStatusTone.danger,
                  dense: true,
                )
              else if (summary.newCards > 0)
                AppStatusChip(
                  label: l10n.deckNewCount(summary.newCards),
                  tone: AppStatusTone.info,
                  dense: true,
                )
              else if (summary.totalCards > 0)
                AppStatusChip(
                  label: l10n.deckAllReviewed,
                  tone: AppStatusTone.success,
                  icon: Icons.check_circle,
                  dense: true,
                ),
              if (summary.totalCards > 0)
                Text(
                  l10n.deckCardCount(summary.totalCards),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.decksProgressLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                l10n.statisticsRetentionValue((progress * 100).round()),
                style: AppTypography.numeric(
                  context,
                  color: progress >= 1 ? scheme.secondary : scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs + 2),
          AppProgressBar(
            value: progress,
            color: progress >= 1 ? scheme.secondary : scheme.primary,
            semanticsLabel: l10n.decksProgressLabel,
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: AppSizes.borderWidth, color: scheme.surfaceContainer),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.schedule,
                  size: AppSizes.iconSmall,
                  color: scheme.outline,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    l10n.deckUpdated(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (hasWork)
                  FilledButton.icon(
                    key: ValueKey<String>('deck-study-${summary.deck.id}'),
                    onPressed: onOpen,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(l10n.deckStudyAction),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    key: ValueKey<String>('deck-study-${summary.deck.id}'),
                    onPressed: onOpen,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: Text(l10n.deckReviewAction),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Монограмма колоды: детерминированный цвет из имени (без фиктивных данных).
class _DeckMonogram extends StatelessWidget {
  const _DeckMonogram({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int hash = name.codeUnits.fold<int>(0, (int a, int b) => a + b);
    final List<Color> palette = <Color>[
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
    ];
    final Color color = palette[hash % palette.length];
    final String letter = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
      ),
    );
  }
}

/// Компактная строка KPI для низких окон (находка D16).
///
/// Четыре плитки высотой ~100 px на 800×600 съедали экран; в одну строку те же
/// числа занимают ~40 px, а информация остаётся доступной.
class _MetricsLine extends StatelessWidget {
  const _MetricsLine({
    required this.totalCards,
    required this.dueCards,
    required this.studiedCards,
    required this.decks,
  });

  final int totalCards;
  final int dueCards;
  final int studiedCards;
  final int decks;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _MetricValue(
          key: const ValueKey<String>('decks-kpi-total'),
          label: l10n.decksMetricTotal,
          value: totalCards,
        ),
        _MetricValue(
          key: const ValueKey<String>('decks-kpi-due'),
          label: l10n.decksMetricDue,
          value: dueCards,
        ),
        _MetricValue(
          key: const ValueKey<String>('decks-kpi-studied'),
          label: l10n.decksMetricStudied,
          value: studiedCards,
        ),
        _MetricValue(
          key: const ValueKey<String>('decks-kpi-decks'),
          label: l10n.decksMetricDecks,
          value: decks,
        ),
      ],
    );
  }
}

class _MetricValue extends StatelessWidget {
  const _MetricValue({required this.label, required this.value, super.key});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          NumberFormat.decimalPattern('ru').format(value),
          style: AppTypography.numeric(context, color: scheme.onSurface),
        ),
        const SizedBox(width: AppSpacing.xxs + 2),
        Text(label, style: AppTypography.overline(context)),
      ],
    );
  }
}

/// Пустое состояние первого запуска (находка D16).
///
/// Функциональный виджет, а не литерал в дереве: действия «Создать» и
/// «Сгенерировать» должны работать, а не быть заглушкой.
class _FirstLaunchEmptyState extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: Icons.style_outlined,
      title: l10n.decksEmptyTitle,
      message: l10n.decksEmptyMessage,
      actions: <Widget>[
        FilledButton(
          key: const ValueKey<String>('decks-empty-create'),
          onPressed: () => createDeckManually(context, ref),
          child: Text(l10n.decksCreateButton),
        ),
        OutlinedButton(
          onPressed: () => context.push(AppRoutes.generationPath),
          child: Text(l10n.decksCreateGenerate),
        ),
      ],
    );
  }
}
