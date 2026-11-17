import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/design.dart';

import '../../helpers/glass_budget.dart';
import '../../helpers/nc_harness.dart';

/// Навигация Nocturne (REDESIGN-SPEC §8, §9.1): док, рейл, сайдбар.
void main() {
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

  testWidgets('док: ключи пунктов, выбор, отклик, только активная подпись', (
    WidgetTester tester,
  ) async {
    final NcHapticRecorder recorder = NcHapticRecorder()..install();
    addTearDown(recorder.uninstall);
    final List<int> selected = <int>[];
    await pumpNc(
      tester,
      NcNavDock(items: items(), selectedIndex: 0, onSelected: selected.add),
      config: const NcTestConfig(size: Size(390, 120), hapticsEnabled: true),
      haptics: NcHaptics(enabled: true),
      settle: true,
    );

    expect(find.byKey(const ValueKey<String>('nav-decks')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('nav-statistics')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('nav-settings')), findsOneWidget);
    expect(find.text(ncL10n.navDecks), findsOneWidget);
    expect(find.text(ncL10n.navStatistics), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('nav-settings')));
    await tester.pump();
    expect(selected, <int>[2]);
    expect(recorder.count, greaterThanOrEqualTo(1));

    expectGlassBudget(tester, maxGroups: 2);
  });

  testWidgets('док: капсула активного пункта переезжает', (
    WidgetTester tester,
  ) async {
    Widget dock(int index) => NcNavDock(
      items: items(),
      selectedIndex: index,
      onSelected: (int value) {},
    );
    await pumpNc(
      tester,
      dock(0),
      config: const NcTestConfig(size: Size(390, 120)),
    );
    final Finder capsule = find.byKey(const ValueKey<String>('nc-nav-capsule'));
    expect(capsule, findsOneWidget);
    final Alignment start =
        tester.widget<Align>(capsule).alignment as Alignment;
    expect(start.x, lessThan(0));

    await tester.pumpWidget(
      ncApp(
        child: dock(2),
        config: const NcTestConfig(size: Size(390, 120)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final Alignment end = tester.widget<Align>(capsule).alignment as Alignment;
    expect(end.x, greaterThan(0.5));
  });

  testWidgets('рейл: пункты и подписи, выбор', (WidgetTester tester) async {
    final List<int> selected = <int>[];
    await pumpNc(
      tester,
      NcNavRail(items: items(), selectedIndex: 1, onSelected: selected.add),
      config: const NcTestConfig(size: Size(120, 500)),
    );

    expect(find.byKey(const ValueKey<String>('nav-decks')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('nc-nav-logo')), findsOneWidget);
    expect(find.text(ncL10n.navStatistics), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('nav-decks')));
    await tester.pump();
    expect(selected, <int>[0]);
    expectGlassBudget(tester, maxGroups: 2);
  });

  testWidgets('сайдбар: 248 px, название и все подписи', (
    WidgetTester tester,
  ) async {
    final List<int> selected = <int>[];
    await pumpNc(
      tester,
      NcNavSidebar(
        items: items(),
        selectedIndex: 0,
        onSelected: selected.add,
        appName: ncL10n.appTitle,
      ),
      config: const NcTestConfig(size: Size(400, 500)),
    );

    expect(tester.getSize(find.byType(NcNavSidebar)).width, 248);
    expect(find.text(ncL10n.appTitle), findsOneWidget);
    expect(find.text(ncL10n.navDecks), findsOneWidget);
    expect(find.text(ncL10n.navStatistics), findsOneWidget);
    expect(find.text(ncL10n.navSettings), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('nav-statistics')));
    await tester.pump();
    expect(selected, <int>[1]);
  });

  testWidgets('текст 2,0 без overflow: док', (WidgetTester tester) async {
    await pumpNcAtTextScale2(
      tester,
      NcNavDock(items: items(), selectedIndex: 0, onSelected: (int value) {}),
      config: const NcTestConfig(size: Size(360, 140)),
    );
  });

  testWidgets('текст 2,0 без overflow: рейл', (WidgetTester tester) async {
    await pumpNcAtTextScale2(
      tester,
      NcNavRail(items: items(), selectedIndex: 1, onSelected: (int value) {}),
      config: const NcTestConfig(size: Size(120, 640)),
    );
  });

  testWidgets('текст 2,0 без overflow: сайдбар', (WidgetTester tester) async {
    await pumpNcAtTextScale2(
      tester,
      NcNavSidebar(
        items: items(),
        selectedIndex: 2,
        onSelected: (int value) {},
        appName: ncL10n.appTitle,
      ),
      config: const NcTestConfig(size: Size(400, 640)),
    );
  });
}
