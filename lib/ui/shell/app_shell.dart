/// Оболочка навигации приложения (SPEC A6.1, ADR-019 §3).
///
/// Телефон — `NavigationBar` снизу; планшет/ПК — `NavigationRail` слева.
/// Пункт «Сессия» скрыт: активной сессии вне полноэкранного маршрута нет,
/// а мёртвый пункт запрещён (SPEC 3.6, ADR-019 §3).
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';

/// Оболочка с тремя ветками: колоды, статистика, настройки.
class AppShell extends StatelessWidget {
  /// Создаёт оболочку вокруг [navigationShell].
  const AppShell({required this.navigationShell, super.key});

  /// Текущая ветка `StatefulShellRoute`.
  final StatefulNavigationShell navigationShell;

  /// Ширина, с которой переходим на `NavigationRail`.
  static const double railBreakpoint = 600;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<_ShellDestination> destinations = <_ShellDestination>[
      _ShellDestination(
        icon: Icons.style_outlined,
        selectedIcon: Icons.style,
        label: l10n.navDecks,
      ),
      _ShellDestination(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: l10n.navStatistics,
      ),
      _ShellDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: l10n.navSettings,
      ),
    ];
    final bool wide =
        MediaQuery.sizeOf(context).width >= AppShell.railBreakpoint;
    if (wide) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
              labelType: NavigationRailLabelType.all,
              destinations: <NavigationRailDestination>[
                for (final _ShellDestination destination in destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        destinations: <NavigationDestination>[
          for (final _ShellDestination destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

/// Описание пункта оболочки (иконки + подпись из ARB).
class _ShellDestination {
  const _ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
