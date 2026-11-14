import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';

/// Действие контекстного меню карточки колоды.
enum _DeckMenuAction { archive, rename, export, delete }

/// Экран «Колоды» (SPEC A6.2).
///
/// Поиск, чипы фильтра, карточки колод на `M3ECard`, архив свайпом или из
/// контекстного меню (доступность, M11) с undo-снекбаром, контекстное меню
/// (архивировать/переименовать/экспорт/удалить), Split-кнопка и Extended FAB
/// создания, импорт ZIP. Строки — из ARB.
class DecksScreen extends ConsumerWidget {
  /// Создаёт экран.
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DeckQuery query = ref.watch(decksQueryProvider);
    final bool searchVisible = ref.watch(decksSearchVisibleProvider);
    final bool filtersVisible = ref.watch(decksFiltersVisibleProvider);
    final AsyncValue<List<DeckSummary>> summaries = ref.watch(
      deckSummariesProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.decksTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.decksSearchTooltip,
            icon: Icon(searchVisible ? Icons.search_off : Icons.search),
            onPressed: () {
              if (searchVisible) {
                ref.read(decksQueryProvider.notifier).clearSearch();
                ref.read(decksSearchVisibleProvider.notifier).close();
              } else {
                ref.read(decksSearchVisibleProvider.notifier).toggle();
              }
            },
          ),
          IconButton(
            tooltip: l10n.decksFilterTooltip,
            icon: const Icon(Icons.filter_list),
            onPressed: () =>
                ref.read(decksFiltersVisibleProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: l10n.settingsOpenTooltip,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.generationSettingsPath),
          ),
        ],
      ),
      floatingActionButton: M3EExtendedFab(
        label: l10n.decksCreateDeckFab,
        icon: const Icon(Icons.add),
        onPressed: () => createDeckManually(context, ref),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (searchVisible) const _DecksSearchField(),
          if (filtersVisible) _DeckFilterChips(selected: query.filter),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: M3ESplitButton<String>(
                key: const ValueKey<String>('decks-create-split'),
                label: l10n.decksCreateButton,
                leadingIcon: Icons.add,
                trailingTooltip: l10n.decksCreateMenuTooltip,
                items: <M3ESplitButtonItem<String>>[
                  M3ESplitButtonItem<String>(
                    value: 'manual',
                    child: l10n.decksCreateManual,
                  ),
                  M3ESplitButtonItem<String>(
                    value: 'generate',
                    child: Text(
                      l10n.decksCreateGenerate,
                      key: const ValueKey<String>('decks-create-generate'),
                    ),
                  ),
                  M3ESplitButtonItem<String>(
                    value: 'import',
                    child: l10n.decksImportZip,
                  ),
                ],
                onPressed: () => createDeckManually(context, ref),
                onSelected: (String value) async {
                  switch (value) {
                    case 'manual':
                      await createDeckManually(context, ref);
                    case 'generate':
                      await context.push(AppRoutes.generationPath);
                    case 'import':
                      await importDeckZip(context, ref);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildContent(context, ref, l10n, query, summaries)),
        ],
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => _DecksErrorState(
        message: l10n.decksErrorTitle,
        onRetry: () => ref.invalidate(deckSummariesProvider),
      ),
      data: (List<DeckSummary> deckSummaries) {
        if (deckSummaries.isEmpty) {
          final bool filtered =
              query.normalizedSearch.isNotEmpty ||
              query.filter != DeckFilter.all;
          if (filtered) {
            return Center(child: Text(l10n.decksNoResults));
          }
          return _DecksEmptyState(
            onCreate: () => createDeckManually(context, ref),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: deckSummaries.length,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(height: 12),
          itemBuilder: (BuildContext context, int index) {
            final DeckSummary summary = deckSummaries[index];
            return Dismissible(
              key: ValueKey<String>('deck-card-${summary.deck.id}'),
              direction: DismissDirection.endToStart,
              background: _ArchiveSwipeBackground(),
              onDismissed: (DismissDirection direction) =>
                  _archiveDeck(context, ref, summary),
              child: M3ECard(
                headline: summary.deck.name,
                subhead: l10n.deckCardCount(summary.totalCards),
                supportingText: summary.dueCards > 0
                    ? l10n.deckDueCount(summary.dueCards)
                    : null,
                semanticLabel: summary.deck.name,
                onPressed: () => context.push('/decks/${summary.deck.id}'),
                onLongPress: () => _showContextMenu(context, ref, summary),
              ),
            );
          },
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

/// Фон свайпа «в архив» (архив — по направлению endToStart).
class _ArchiveSwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: 24),
      child: Icon(Icons.archive_outlined, color: scheme.onErrorContainer),
    );
  }
}

/// Поле поиска колод (открывается иконкой search).
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
    final String search = ref.watch(decksQueryProvider).search;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _controller,
        autofocus: true,
        onChanged: (String value) =>
            ref.read(decksQueryProvider.notifier).setSearch(value),
        decoration: InputDecoration(
          hintText: l10n.decksSearchHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: search.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.decksSearchClearTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controller.clear();
                    ref.read(decksQueryProvider.notifier).clearSearch();
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
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
      return M3EChip(
        label: label,
        type: M3EChipType.filter,
        selected: selected == filter,
        onPressed: () =>
            ref.read(decksQueryProvider.notifier).setFilter(filter),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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

/// Пустое состояние списка колод.
class _DecksEmptyState extends StatelessWidget {
  const _DecksEmptyState({required this.onCreate});

  final VoidCallback onCreate;

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
              Icons.style_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.decksEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(l10n.decksEmptyMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onCreate,
              child: Text(l10n.decksCreateButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// Состояние ошибки загрузки списка колод.
class _DecksErrorState extends StatelessWidget {
  const _DecksErrorState({required this.message, required this.onRetry});

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
