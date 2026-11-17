@Tags(<String>['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/design.dart';

import '../helpers/nc_golden.dart';
import '../helpers/nc_harness.dart';

/// Golden навигации Nocturne (REDESIGN-SPEC §8, §9.1): док, рейл, сайдбар.
///
/// 8 вариантов на компонент: dark/light × обычный/high-contrast × textScale
/// 1,0/2,0. Эталоны снимаются на Windows (единственная доступная платформа,
/// L98); CI прогоняет тесты без тега `golden`.
void main() {
  setUpAll(loadNcFonts);

  List<NcNavItem> items() => <NcNavItem>[
    NcNavItem(
      key: const ValueKey<String>('nav-decks'),
      icon: Icons.style_outlined,
      selectedIcon: Icons.style,
      label: ncL10n.navDecks,
    ),
    NcNavItem(
      key: const ValueKey<String>('nav-statistics'),
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      label: ncL10n.navStatistics,
    ),
    NcNavItem(
      key: const ValueKey<String>('nav-settings'),
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: ncL10n.navSettings,
    ),
  ];

  ncGoldenGroup(
    'nav_dock',
    (NcGoldenVariant variant) =>
        NcNavDock(items: items(), selectedIndex: 1, onSelected: (int value) {}),
    size: (NcGoldenVariant variant) => const Size(390, 120),
  );

  ncGoldenGroup(
    'nav_rail',
    (NcGoldenVariant variant) =>
        NcNavRail(items: items(), selectedIndex: 1, onSelected: (int value) {}),
    size: (NcGoldenVariant variant) => const Size(120, 480),
  );

  ncGoldenGroup(
    'nav_sidebar',
    (NcGoldenVariant variant) => NcNavSidebar(
      items: items(),
      selectedIndex: 0,
      onSelected: (int value) {},
      appName: ncL10n.appTitle,
    ),
    size: (NcGoldenVariant variant) => const Size(300, 480),
  );
}
