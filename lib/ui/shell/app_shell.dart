/// Оболочка навигации приложения (SPEC A6.1, ADR-019 §3; REDESIGN-SPEC §9.1).
///
/// Телефон (< 600 px) — парящий док `NcNavDock`; планшет (600–1023) — рейл
/// `NcNavRail` 80 px; ПК (≥ 1024) — расширенный сайдбар `NcNavSidebar` 248 px.
/// Пункт «Сессия» скрыт: активной сессии вне полноэкранного маршрута нет,
/// а мёртвый пункт запрещён (SPEC 3.6, ADR-019 §3).
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/motion.dart';

/// Оболочка с тремя ветками: колоды, статистика, настройки.
class AppShell extends StatefulWidget {
  /// Создаёт оболочку вокруг [navigationShell].
  const AppShell({required this.navigationShell, super.key});

  /// Текущая ветка `StatefulShellRoute`.
  final StatefulNavigationShell navigationShell;

  /// Ширина, с которой переходим на рейл/сайдбар.
  static const double railBreakpoint = 600;

  /// Ширина, с которой рейл превращается в расширенный сайдбар.
  static const double wideBreakpoint = 1024;

  /// Ключи вкладок — контракт оболочки (§9.1).
  static const Key decksKey = ValueKey<String>('shell-nav-decks');
  static const Key statisticsKey = ValueKey<String>('shell-nav-statistics');
  static const Key settingsKey = ValueKey<String>('shell-nav-settings');

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Док утапливается на 8 px при прокрутке контента вниз (§9.1).
  bool _dockSunk = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification is! ScrollUpdateNotification) {
      return false;
    }
    final double? delta = notification.scrollDelta;
    if (delta == null || delta == 0) return false;
    final bool sunk = delta > 0;
    if (sunk != _dockSunk) setState(() => _dockSunk = sunk);
    return false;
  }

  void _handleSelected(int index) {
    if (_dockSunk) setState(() => _dockSunk = false);
    widget._goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<NcNavItem> items = <NcNavItem>[
      NcNavItem(
        key: AppShell.decksKey,
        icon: Icons.style_outlined,
        selectedIcon: Icons.style,
        label: l10n.navDecks,
      ),
      NcNavItem(
        key: AppShell.statisticsKey,
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: l10n.navStatistics,
      ),
      NcNavItem(
        key: AppShell.settingsKey,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: l10n.navSettings,
      ),
    ];
    final int selectedIndex = widget.navigationShell.currentIndex;
    final double width = MediaQuery.sizeOf(context).width;
    final Widget content = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: widget.navigationShell,
    );

    if (width >= AppShell.wideBreakpoint) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            NcNavSidebar(
              items: items,
              selectedIndex: selectedIndex,
              onSelected: _handleSelected,
              appName: l10n.appTitle,
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    if (width >= AppShell.railBreakpoint) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            NcNavRail(
              items: items,
              selectedIndex: selectedIndex,
              onSelected: _handleSelected,
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: content),
          PositionedDirectional(
            start: _ShellMetrics.dockMargin,
            end: _ShellMetrics.dockMargin,
            bottom: _ShellMetrics.dockMargin + safeBottom,
            child: AnimatedSlide(
              offset: _dockSunk ? const Offset(0, 0.125) : Offset.zero,
              duration: AppMotion.fast,
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _dockSunk ? 0.85 : 1,
                duration: AppMotion.fast,
                child: NcNavDock(
                  items: items,
                  selectedIndex: selectedIndex,
                  onSelected: _handleSelected,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Геометрия дока (16 px от краёв, REDESIGN-SPEC §9.1).
abstract final class _ShellMetrics {
  /// Отступ дока от краёв экрана.
  static const double dockMargin = 16;
}
