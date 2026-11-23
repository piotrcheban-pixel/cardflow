import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/settings/about_links.dart';
import 'package:cardflow/ui/state/decks_ui_providers.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Пункт навигации боковой панели.
class _SidebarDestination {
  const _SidebarDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.branch,
    this.route,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Индекс ветки `StatefulShellRoute`; `null` — маршрут вне оболочки.
  final int? branch;

  /// Маршрут вне оболочки (генерация, конструктор).
  final String? route;

  bool get isBranch => branch != null;
}

/// Боковая навигация CardFlow (ADR-038): 240 px, логотип, поиск, пункты
/// разделов, сводка повторений. На широком экране постоянная, на узком —
/// содержимое выдвижного ящика (`Drawer`).
class AppSidebar extends ConsumerWidget {
  /// Создаёт панель.
  const AppSidebar({
    required this.currentBranch,
    required this.onSelectBranch,
    this.onSearch,
    this.onNavigate,
    this.onClose,
    super.key,
  });

  /// Текущий индекс ветки (колоды/статистика/настройки).
  final int currentBranch;

  /// Переключение ветки оболочки.
  final ValueChanged<int> onSelectBranch;

  /// Открытие поиска по колодам.
  final VoidCallback? onSearch;

  /// Любой переход (для закрытия ящика на узком экране).
  final VoidCallback? onNavigate;

  /// Закрытие ящика; `null` — панель постоянная.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<_SidebarDestination> destinations = <_SidebarDestination>[
      _SidebarDestination(
        label: l10n.navDecks,
        icon: Icons.view_agenda_outlined,
        selectedIcon: Icons.view_agenda,
        branch: 0,
      ),
      _SidebarDestination(
        label: l10n.navAi,
        icon: Icons.auto_awesome_outlined,
        selectedIcon: Icons.auto_awesome,
        route: AppRoutes.generationPath,
      ),
      _SidebarDestination(
        label: l10n.navConstructor,
        icon: Icons.tune_outlined,
        selectedIcon: Icons.tune,
        route: AppRoutes.constructorPath,
      ),
      _SidebarDestination(
        label: l10n.navStatistics,
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        branch: 1,
      ),
      _SidebarDestination(
        label: l10n.navSettings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        branch: 2,
      ),
    ];
    final int due = ref.watch(totalDueCardsProvider).value ?? 0;
    // На низком окне (400 лог. px) пяти пунктам нужна каждая строка:
    // надзаголовок «Навигация» сворачивается, «Настройки» остаются видны.
    final bool compactHeight = MediaQuery.sizeOf(context).height < 480;

    return Material(
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Логотип и версия.
          SizedBox(
            height: AppSizes.headerHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  _BrandMark(scheme: scheme),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.appTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(
                      l10n.shellVersion(appVersion),
                      style: AppTypography.caption(
                        context,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      tooltip: l10n.shellCloseNavTooltip,
                      icon: const Icon(Icons.close, size: AppSizes.icon),
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
          ),
          Divider(height: AppSizes.borderWidth, color: scheme.outlineVariant),
          // Находка D10 + аудит v4 (V18/V36): честный пункт навигации без
          // рамки поля ввода и без обрезанной второй строки — только иконка и
          // короткая подпись, как у остальных пунктов.
          if (onSearch != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                0,
              ),
              child: Tooltip(
                message: l10n.shellSearchActionHint,
                child: InkWell(
                  key: const ValueKey<String>('shell-search-action'),
                  onTap: onSearch,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  child: SizedBox(
                    height: AppSizes.minTouchTarget,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs + 2,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.search,
                            size: AppSizes.icon,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Expanded(
                            child: Text(
                              l10n.shellSearchAction,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Надзаголовок и пункты.
          if (!compactHeight)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxs,
              ),
              child: Text(
                l10n.shellNavSection.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              children: <Widget>[
                for (final _SidebarDestination destination in destinations)
                  _SidebarItem(
                    destination: destination,
                    selected:
                        destination.isBranch &&
                        destination.branch == currentBranch,
                    onTap: () {
                      onNavigate?.call();
                      if (destination.route != null) {
                        context.push(destination.route!);
                        return;
                      }
                      onSelectBranch(destination.branch!);
                    },
                  ),
              ],
            ),
          ),
          Divider(height: AppSizes.borderWidth, color: scheme.outlineVariant),
          // Сводка повторений.
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: InkWell(
              onTap: () {
                onNavigate?.call();
                onSelectBranch(0);
              },
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: <Widget>[
                    AppIconBadge(
                      icon: Icons.schedule,
                      color: scheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        // Аудит v4 (V9): подпись «К повторению» убрана —
                        // число и так читается как остаток повторений.
                        l10n.shellDueToday(due),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Знак бренда: скруглённый квадрат с иконкой колоды.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.style_rounded,
        size: AppSizes.icon,
        color: scheme.onPrimary,
      ),
    );
  }
}

/// Пункт навигации с состоянием выбора.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _SidebarDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: AnimatedContainer(
            duration: AppDurations.quick,
            height: AppSizes.minTouchTarget,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2),
            decoration: BoxDecoration(
              color: selected ? scheme.surfaceContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: AppSizes.navIcon,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Компактная рейка навигации (640–1024 px): только иконки с tooltip.
///
/// Находка N6 аудита: на 800×600 прежняя оболочка прятала разделы в `Drawer`,
/// и путь «Статистика → Колоды» требовал двух действий и знания, что меню —
/// за бургером. Рейка держит все разделы видимыми, как на широком экране.
class AppNavRail extends StatelessWidget {
  /// Создаёт рейку.
  const AppNavRail({
    required this.currentBranch,
    required this.onSelectBranch,
    this.onSearch,
    super.key,
  });

  /// Текущая ветка оболочки.
  final int currentBranch;

  /// Переключение ветки оболочки.
  final ValueChanged<int> onSelectBranch;

  /// Открытие поиска по колодам.
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<_SidebarDestination> destinations = <_SidebarDestination>[
      _SidebarDestination(
        label: l10n.navDecks,
        icon: Icons.view_agenda_outlined,
        selectedIcon: Icons.view_agenda,
        branch: 0,
      ),
      _SidebarDestination(
        label: l10n.navAi,
        icon: Icons.auto_awesome_outlined,
        selectedIcon: Icons.auto_awesome,
        route: AppRoutes.generationPath,
      ),
      _SidebarDestination(
        label: l10n.navConstructor,
        icon: Icons.tune_outlined,
        selectedIcon: Icons.tune,
        route: AppRoutes.constructorPath,
      ),
      _SidebarDestination(
        label: l10n.navStatistics,
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        branch: 1,
      ),
      _SidebarDestination(
        label: l10n.navSettings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        branch: 2,
      ),
    ];
    final bool expanded = MediaQuery.sizeOf(context).width >= 900;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: SizedBox(
        width: expanded ? 92 : AppSizes.navRailWidth,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const SizedBox(height: AppSpacing.xs),
              if (onSearch != null)
                IconButton(
                  key: const ValueKey<String>('shell-rail-search'),
                  tooltip: l10n.shellSearchAction,
                  icon: const Icon(Icons.search, size: AppSizes.navIcon),
                  onPressed: onSearch,
                ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    for (final _SidebarDestination destination in destinations)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _RailItem(
                          destination: destination,
                          selected:
                              destination.isBranch &&
                              destination.branch == currentBranch,
                          // Аудит v2 (D2): на 900–1024 лог. px у рейки есть
                          // подписи — иконки без текста слишком загадочны.
                          expanded: expanded,
                          onTap: () {
                            final String? route = destination.route;
                            if (route != null) {
                              context.push(route);
                              return;
                            }
                            onSelectBranch(destination.branch!);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.expanded = false,
  });

  final _SidebarDestination destination;
  final bool selected;
  final VoidCallback onTap;

  /// Показывать подпись под иконкой (рейка шире 900 лог. px).
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      size: AppSizes.navIcon,
      color: selected ? scheme.primary : scheme.onSurfaceVariant,
    );
    return Center(
      child: Tooltip(
        message: destination.label,
        waitDuration: Duration.zero,
        child: Material(
          color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: InkWell(
            key: ValueKey<String>(
              'shell-rail-${destination.route ?? destination.branch}',
            ),
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: SizedBox(
              width: expanded ? 84 : AppSizes.minTouchTarget,
              height: expanded ? 56 : AppSizes.minTouchTarget,
              child: expanded
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        icon,
                        const SizedBox(height: 2),
                        Text(
                          destination.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : icon,
            ),
          ),
        ),
      ),
    );
  }
}
