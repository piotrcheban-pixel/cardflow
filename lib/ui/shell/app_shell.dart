/// Оболочка навигации приложения (SPEC A6.1, ADR-038).
///
/// Широкий экран (≥1024 px) — постоянная боковая панель 240 px и верхняя
/// панель 56 px вокруг ветки `StatefulShellRoute`. Узкий экран — та же панель
/// в выдвижном ящике (`Drawer`) и кнопка меню в верхней панели: так выглядит
/// эталонный макет Gemini/Stitch v2. Нижняя `NavigationBar` прежней оболочки
/// заменена осознанно (ADR-038), все маршруты и разделы сохранены.
///
/// Пункты «ИИ-генерация» и «Конструктор» живут вне ветвей (маршруты верхнего
/// уровня `/generate`, `/constructor`) и открываются поверх оболочки — это
/// существующая архитектура маршрутов, дублировать её второй копией нельзя.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/decks/deck_actions.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/shell/app_sidebar.dart';
import 'package:cardflow/ui/shell/app_top_header.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Оболочка с тремя ветками: колоды, статистика, настройки.
class AppShell extends ConsumerWidget {
  /// Создаёт оболочку вокруг [navigationShell].
  const AppShell({required this.navigationShell, super.key});

  /// Текущая ветка `StatefulShellRoute`.
  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  /// Глобальное действие «Новая карточка»: реальный выбор колоды (если их
  /// несколько) и переход в существующую форму карточки.
  Future<void> _createCard(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<DeckSummary> summaries;
    try {
      summaries = await ref.read(deckRepositoryProvider).watchSummaries().first;
    } on Object {
      if (context.mounted) showAppMessage(context, l10n.genericError);
      return;
    }
    if (!context.mounted) return;
    if (summaries.isEmpty) {
      showAppMessage(context, l10n.shellNewCardNoDecks);
      return;
    }
    if (summaries.length == 1) {
      context.push(AppRoutes.cardNewPath(summaries.single.deck.id));
      return;
    }
    final String? deckId = await showAppSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSheetHeader(
            title: l10n.shellNewCardSheetTitle,
            subtitle: l10n.shellNewCardSheetSubtitle,
            icon: Icons.note_add_outlined,
          ),
          for (final DeckSummary summary in summaries)
            ListTile(
              key: ValueKey<String>('shell-new-card-deck-${summary.deck.id}'),
              title: Text(summary.deck.name),
              subtitle: Text(l10n.deckCardCount(summary.totalCards)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(sheetContext).pop(summary.deck.id),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
    if (deckId != null && context.mounted) {
      context.push(AppRoutes.cardNewPath(deckId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool wide =
        MediaQuery.sizeOf(context).width >= AppSizes.sidebarBreakpoint;
    final String section = switch (navigationShell.currentIndex) {
      1 => l10n.navStatistics,
      2 => l10n.navSettings,
      _ => l10n.navDecks,
    };

    final Widget sidebar = AppSidebar(
      currentBranch: navigationShell.currentIndex,
      onSelectBranch: _goBranch,
      onSearch: () {
        ref.read(decksQueryProvider.notifier).clearSearch();
        ref.read(decksSearchVisibleProvider.notifier).open();
        _goBranch(0);
      },
    );

    if (wide) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: AppSizes.sidebarWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: scheme.outlineVariant,
                        width: AppSizes.borderWidth,
                      ),
                    ),
                  ),
                  child: sidebar,
                ),
              ),
              Expanded(
                child: Column(
                  children: <Widget>[
                    AppTopHeader(
                      section: section,
                      onNewCard: () => unawaited(_createCard(context, ref)),
                      onOpenSettings: () => _goBranch(2),
                    ),
                    Expanded(child: navigationShell),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      drawer: Drawer(
        width: 288,
        backgroundColor: scheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(AppRadii.panel),
          ),
        ),
        child: Builder(
          builder: (BuildContext drawerContext) => SafeArea(
            child: AppSidebar(
              currentBranch: navigationShell.currentIndex,
              onSelectBranch: _goBranch,
              onSearch: () {
                Navigator.of(drawerContext).pop();
                ref.read(decksQueryProvider.notifier).clearSearch();
                ref.read(decksSearchVisibleProvider.notifier).open();
                _goBranch(0);
              },
              onNavigate: () => Navigator.of(drawerContext).pop(),
              onClose: () => Navigator.of(drawerContext).pop(),
            ),
          ),
        ),
      ),
      body: Builder(
        builder: (BuildContext bodyContext) => SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              AppTopHeader(
                section: section,
                onNewCard: () => unawaited(_createCard(bodyContext, ref)),
                onOpenSettings: () => _goBranch(2),
                onOpenNav: () => Scaffold.of(bodyContext).openDrawer(),
              ),
              Expanded(child: navigationShell),
            ],
          ),
        ),
      ),
    );
  }
}
