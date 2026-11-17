import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/shell/app_shell.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';

/// Действие контекстного меню карточки колоды.
enum _DeckMenuAction { archive, rename, export, delete }

/// Экран «Колоды» (SPEC A6.2, REDESIGN-SPEC §9.2).
///
/// Шапка `NcTopBar` с large title и сводкой «К повторению: N · колод: M»
/// (UI-вычисление из `deckSummariesProvider`), поиск `NcSearchField`, чипы
/// фильтра, сетка плиток `NcCardTile` (1/2/3 колонки), бейдж «N к повторению»,
/// архив свайпом с хаптиком на пороге и undo-тостом, контекстное меню
/// `NcSheet`, Split-кнопка и `NcFab` создания, импорт ZIP. Обработчики и
/// провайдеры — прежние.
class DecksScreen extends ConsumerStatefulWidget {
  /// Создаёт экран.
  const DecksScreen({super.key});

  @override
  ConsumerState<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends ConsumerState<DecksScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DeckQuery query = ref.watch(decksQueryProvider);
    final bool searchVisible = ref.watch(decksSearchVisibleProvider);
    final bool filtersVisible = ref.watch(decksFiltersVisibleProvider);
    final AsyncValue<List<DeckSummary>> summaries = ref.watch(
      deckSummariesProvider,
    );
    final List<DeckSummary>? decks = summaries.asData?.value;
    final bool wide = MediaQuery.sizeOf(context).width >= 600;

    final Widget createSplit = NcSplitButton(
      key: const ValueKey<String>('decks-create-split'),
      label: l10n.decksCreateButton,
      icon: Icons.add_rounded,
      menuSemanticLabel: l10n.decksCreateMenuTooltip,
      items: <NcMenuItem<void>>[
        NcMenuItem<void>(
          label: l10n.decksCreateManual,
          icon: Icons.edit_outlined,
          onSelected: () => createDeckManually(context, ref),
        ),
        NcMenuItem<void>(
          key: const ValueKey<String>('decks-create-generate'),
          label: l10n.decksCreateGenerate,
          icon: Icons.auto_awesome,
          onSelected: () => context.push(AppRoutes.generationPath),
        ),
        NcMenuItem<void>(
          label: l10n.decksImportZip,
          icon: Icons.file_upload_outlined,
          onSelected: () => importDeckZip(context, ref),
        ),
      ],
      onPressed: () => createDeckManually(context, ref),
    );

    final Widget topBar = NcTopBar(
      title: l10n.decksTitle,
      largeTitle: l10n.decksTitle,
      scrollController: _scrollController,
      actions: <Widget>[
        if (wide)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: createSplit,
          ),
        NcIconButton(
          key: const ValueKey<String>('decks-search-toggle'),
          icon: searchVisible ? Icons.search_off : Icons.search,
          tooltip: l10n.decksSearchTooltip,
          onPressed: () {
            if (searchVisible) {
              ref.read(decksQueryProvider.notifier).clearSearch();
              ref.read(decksSearchVisibleProvider.notifier).close();
            } else {
              ref.read(decksSearchVisibleProvider.notifier).toggle();
            }
          },
        ),
        _FilterAction(
          active: query.filter != DeckFilter.all,
          tooltip: l10n.decksFilterTooltip,
          onPressed: () =>
              ref.read(decksFiltersVisibleProvider.notifier).toggle(),
        ),
        NcIconButton(
          key: const ValueKey<String>('decks-settings-action'),
          icon: Icons.settings_outlined,
          tooltip: l10n.settingsOpenTooltip,
          onPressed: () => context.go(AppRoutes.settingsPath),
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NcScrollCollapseScope(
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  topBar,
                  if (decks != null && decks.isNotEmpty) ...<Widget>[
                    _DecksHeader(
                      summary: l10n.decksSummary(
                        decks.length,
                        decks.fold<int>(
                          0,
                          (int total, DeckSummary item) =>
                              total + item.dueCards,
                        ),
                      ),
                    ),
                    if (!wide)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: createSplit,
                        ),
                      ),
                  ],
                  AnimatedSize(
                    duration: AppMotion.fast,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: searchVisible
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: _DecksSearchField(),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  AnimatedSize(
                    duration: AppMotion.fast,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: filtersVisible
                        ? _DeckFilterChips(selected: query.filter)
                        : const SizedBox(width: double.infinity),
                  ),
                  Expanded(
                    child: _buildContent(context, ref, l10n, query, summaries),
                  ),
                ],
              ),
              PositionedDirectional(
                end: wide ? 24 : 16,
                bottom: wide ? 24 : NcNavDock.height + 32,
                child: NcFab(
                  label: l10n.decksCreateDeckFab,
                  onPressed: () => createDeckManually(context, ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    DeckQuery query,
    AsyncValue<List<DeckSummary>> summaries,
  ) {
    return summaries.when(
      loading: () => const _DecksSkeleton(),
      error: (Object error, StackTrace stackTrace) => NcErrorState(
        message: l10n.decksErrorTitle,
        retryLabel: l10n.retry,
        onRetry: () => ref.invalidate(deckSummariesProvider),
      ),
      data: (List<DeckSummary> deckSummaries) {
        if (deckSummaries.isEmpty) {
          final bool filtered =
              query.normalizedSearch.isNotEmpty ||
              query.filter != DeckFilter.all;
          if (filtered) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: NcEmptyState(
                  iconName: 'style',
                  showIcon: false,
                  title: l10n.decksNoResults,
                  message: l10n.decksNoResultsHint,
                ),
              ),
            );
          }
          return _DecksEmptyState(
            onCreate: () => createDeckManually(context, ref),
            onGenerate: () => context.push(AppRoutes.generationPath),
          );
        }
        return _DeckGrid(
          decks: deckSummaries,
          controller: _scrollController,
          onOpen: (DeckSummary summary) =>
              context.push('/decks/${summary.deck.id}'),
          onMenu: (DeckSummary summary) =>
              _showContextMenu(context, ref, summary),
          onArchive: (DeckSummary summary) =>
              _archiveDeck(context, ref, summary),
        );
      },
    );
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
    final _DeckMenuAction? action = await showNcSheet<_DeckMenuAction>(
      context,
      title: summary.deck.name,
      closeTooltip: l10n.commonClose,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NcListRow(
            title: Text(l10n.deckRename),
            leading: const Icon(Icons.edit_outlined),
            onTap: () => Navigator.of(sheetContext).pop(_DeckMenuAction.rename),
          ),
          NcListRow(
            title: Text(l10n.deckExport),
            leading: const Icon(Icons.ios_share),
            onTap: () => Navigator.of(sheetContext).pop(_DeckMenuAction.export),
          ),
          NcListRow(
            title: Text(l10n.deckActionArchive),
            leading: const Icon(Icons.archive_outlined),
            onTap: () =>
                Navigator.of(sheetContext).pop(_DeckMenuAction.archive),
          ),
          NcListRow(
            title: Text(l10n.delete),
            leading: const Icon(Icons.delete_outline),
            showDivider: false,
            onTap: () => Navigator.of(sheetContext).pop(_DeckMenuAction.delete),
          ),
        ],
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

/// Сводная строка шапки: «К повторению: N · колод: M» (UI-вычисление).
class _DecksHeader extends StatelessWidget {
  const _DecksHeader({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
      child: Text(
        summary,
        style: theme.typography.bodyM.copyWith(
          color: theme.colors.textSecondary,
        ),
      ),
    );
  }
}

/// Иконка фильтра с точкой `aurum`, если фильтр не «Все».
class _FilterAction extends StatelessWidget {
  const _FilterAction({
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        NcIconButton(
          key: const ValueKey<String>('decks-filter-toggle'),
          icon: Icons.filter_list,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        if (active)
          PositionedDirectional(
            top: 8,
            end: 8,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: theme.colors.aurum,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

/// Сетка плиток колод: 1 колонка (< 600), 2 (600–1023), 3 (≥ 1024).
class _DeckGrid extends StatelessWidget {
  const _DeckGrid({
    required this.decks,
    required this.controller,
    required this.onOpen,
    required this.onMenu,
    required this.onArchive,
  });

  final List<DeckSummary> decks;
  final ScrollController controller;
  final ValueChanged<DeckSummary> onOpen;
  final ValueChanged<DeckSummary> onMenu;
  final ValueChanged<DeckSummary> onArchive;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final int columns = width >= AppShell.wideBreakpoint
        ? 3
        : width >= AppShell.railBreakpoint
        ? 2
        : 1;
    final double textScale = MediaQuery.textScalerOf(context)
        .scale(1)
        .clamp(1.0, 1.8);
    final double extent = (columns == 1 ? 92 : 168) * textScale;
    return GridView.builder(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        width >= AppShell.wideBreakpoint ? 24 : 16,
        8,
        width >= AppShell.wideBreakpoint ? 24 : 16,
        160,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: extent,
      ),
      itemCount: decks.length,
      itemBuilder: (BuildContext context, int index) {
        final DeckSummary summary = decks[index];
        return NcStagger(
          index: index,
          child: Dismissible(
            key: ValueKey<String>('deck-card-${summary.deck.id}'),
            direction: DismissDirection.endToStart,
            background: const _ArchiveSwipeBackground(),
            onUpdate: (DismissUpdateDetails details) {
              if (details.reached && !details.previousReached) {
                NcHaptics.of(context).lightImpact();
              }
            },
            onDismissed: (DismissDirection direction) {
              onArchive(summary);
            },
            child: _DeckTile(
              summary: summary,
              onTap: () => onOpen(summary),
              onMenu: () => onMenu(summary),
            ),
          ),
        );
      },
    );
  }
}

/// Плитка колоды: 3D-аватар + название + «N карточек» + бейдж/галочка.
class _DeckTile extends StatefulWidget {
  const _DeckTile({
    required this.summary,
    required this.onTap,
    required this.onMenu,
  });

  final DeckSummary summary;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  State<_DeckTile> createState() => _DeckTileState();
}

class _DeckTileState extends State<_DeckTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final DeckSummary summary = widget.summary;
    final Widget avatar = Hero(
      tag: 'deck-avatar-${summary.deck.id}',
      child: NcIcon3D(
        name: deckGemName(summary.deck.id),
        size: 52,
        showShadow: false,
      ),
    );
    final Widget title = Hero(
      tag: 'deck-title-${summary.deck.id}',
      child: Text(
        summary.deck.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.typography.titleM.copyWith(
          color: theme.colors.textPrimary,
        ),
      ),
    );
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final Widget trailing = summary.dueCards > 0
        ? NcBadge(
            label: textScale > 1.3
                ? '${summary.dueCards}'
                : l10n.deckDueCount(summary.dueCards),
            semanticLabel: l10n.deckDueCount(summary.dueCards),
          )
        : Semantics(
            label: l10n.deckDueCount(0),
            child: Icon(
              Icons.check_rounded,
              size: 18,
              color: theme.colors.jade.withValues(alpha: 0.6),
            ),
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: <Widget>[
          NcCardTile(
            title: title,
            subtitle: Text(
              l10n.deckCardCount(summary.totalCards),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.bodyS.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
            leading: avatar,
            trailing: trailing,
            semanticLabel: summary.deck.name,
            onTap: widget.onTap,
            onLongPress: widget.onMenu,
            onSecondaryTap: widget.onMenu,
          ),
          if (_hovered)
            PositionedDirectional(
              top: 8,
              end: 8,
              child: NcIconButton(
                key: ValueKey<String>('deck-more-${summary.deck.id}'),
                icon: Icons.more_horiz,
                tooltip: l10n.decksMenuTooltip,
                size: 32,
                onPressed: widget.onMenu,
              ),
            ),
        ],
      ),
    );
  }
}

/// Фон свайпа «в архив» (архив — по направлению endToStart).
class _ArchiveSwipeBackground extends StatelessWidget {
  const _ArchiveSwipeBackground();

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Container(
      decoration: ShapeDecoration(
        color: theme.colors.ink4,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(NcRadii.l),
        ),
      ),
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.archive_outlined, color: theme.colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context).deckActionArchive,
            style: theme.typography.labelM.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Поле поиска колод (открывается иконкой search).
class _DecksSearchField extends ConsumerStatefulWidget {
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
    ref.watch(decksQueryProvider);
    return NcSearchField(
      key: const ValueKey<String>('decks-search-field'),
      controller: _controller,
      autofocus: true,
      hint: l10n.decksSearchHint,
      clearTooltip: l10n.decksSearchClearTooltip,
      clearKey: const ValueKey<String>('decks-search-clear'),
      semanticLabel: l10n.decksSearchHint,
      onChanged: (String value) {
        if (value.isEmpty) {
          ref.read(decksQueryProvider.notifier).clearSearch();
        } else {
          ref.read(decksQueryProvider.notifier).setSearch(value);
        }
      },
      focusNode: null,
    );
  }
}

/// Чипы фильтра: Все / Новые / В процессе / Просроченные.
class _DeckFilterChips extends ConsumerWidget {
  const _DeckFilterChips({required this.selected});

  final DeckFilter selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    Widget chip(String label, DeckFilter filter) {
      return NcChip.filter(
        label: label,
        selected: selected == filter,
        onSelected: () =>
            ref.read(decksQueryProvider.notifier).setFilter(filter),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: <Widget>[
          chip(l10n.deckFilterAll, DeckFilter.all),
          const SizedBox(width: 8),
          chip(l10n.deckFilterNew, DeckFilter.withNewCards),
          const SizedBox(width: 8),
          chip(l10n.deckFilterInProgress, DeckFilter.inProgress),
          const SizedBox(width: 8),
          chip(l10n.deckFilterDue, DeckFilter.due),
        ],
      ),
    );
  }
}

/// Загрузка списка: четыре skeleton-плитки (§9.2).
class _DecksSkeleton extends StatelessWidget {
  const _DecksSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: <Widget>[
        for (var index = 0; index < 4; index++) ...<Widget>[
          const NcSkeleton(height: 88, radius: NcRadii.l),
          if (index < 3) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Пустое состояние списка колод.
class _DecksEmptyState extends StatelessWidget {
  const _DecksEmptyState({required this.onCreate, required this.onGenerate});

  final VoidCallback onCreate;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: NcEmptyState(
          iconName: 'empty_decks',
          title: l10n.decksEmptyTitle,
          message: l10n.decksEmptyMessage,
          primaryAction: NcButton(
            label: l10n.decksCreateButton,
            icon: Icons.add_rounded,
            onPressed: onCreate,
          ),
          secondaryAction: NcButton(
            label: l10n.decksCreateGenerate,
            variant: NcButtonVariant.ai,
            icon: Icons.auto_awesome,
            onPressed: onGenerate,
          ),
        ),
      ),
    );
  }
}

/// Имя 3D-аватара колоды: `deck_gem_1..8` по стабильному хешу id (§5.4).
String deckGemName(String deckId) {
  var hash = 0x811C9DC5;
  for (final int unit in deckId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return 'deck_gem_${hash % 8 + 1}';
}
