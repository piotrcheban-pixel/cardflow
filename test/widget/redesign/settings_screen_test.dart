import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';

import '../../helpers/glass_budget.dart';
import '../../helpers/nc_harness.dart';
import '../../helpers/nc_screen_harness.dart';
import '../../helpers/redesign_screen_fixtures.dart';
import '../../helpers/settings_fakes.dart';

/// Настройки в оформлении Nocturne (REDESIGN-SPEC §9.16).
void main() {
  final AppLocalizations l10n = ncL10n;

  final List<String> sectionKeys = <String>[
    'settings-theme',
    'settings-dynamic-color',
    'settings-motion',
    'settings-dyslexia-font',
    'settings-text-scale',
    'settings-retention',
    'learning-step-add',
    'settings-new-limit',
    'settings-review-limit',
    'settings-haptics',
    'settings-high-contrast',
    'settings-open-generation',
    'settings-providers-empty',
    'settings-weekly-tokens',
    'settings-about-version',
    'settings-about-licenses',
    'settings-about-privacy',
  ];

  Future<void> pumpSettings(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    AppSettings? settings,
  }) => pumpNcScreen(
    tester,
    home: const SettingsScreen(),
    overrides: ncStage3Overrides(settings: settings),
    config: NcScreenConfig(size: size),
  );

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ключи settings-* на месте и новые элементы облика', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text(l10n.settingsScreenTitle), findsWidgets);
    expect(find.text(l10n.settingsAppearanceTitle), findsOneWidget);
    expect(find.text(l10n.settingsTextScalePreview), findsOneWidget);
    expect(find.text(l10n.settingsRetentionValue(90)), findsOneWidget);
    expect(find.byType(NcSection), findsWidgets);

    for (final String key in sectionKeys) {
      final Finder finder = find.byKey(ValueKey<String>(key));
      if (finder.evaluate().isEmpty) await reveal(tester, finder);
      expect(finder, findsOneWidget, reason: key);
    }
    expect(find.byType(NcSwitch), findsWidgets);
    expect(find.byType(NcSlider), findsNWidgets(2));
    expectGlassBudget(tester, maxGroups: 2);
  });

  testWidgets('тема, контраст и отклик сохраняются в app_settings', (
    WidgetTester tester,
  ) async {
    final FakeAppSettingsStore store = FakeAppSettingsStore();
    await pumpNcScreen(
      tester,
      home: const SettingsScreen(),
      overrides: ncStage3Overrides(appSettingsStore: store),
      config: const NcScreenConfig(size: Size(390, 844)),
    );

    await tester.tap(find.text(l10n.settingsThemeDark));
    await tester.pumpAndSettle();
    expect(store.settings.theme, AppThemePreference.dark);
    expect(
      tester
          .widget<NcSegmented<AppThemePreference>>(
            find.byKey(const ValueKey<String>('settings-theme')),
          )
          .value,
      AppThemePreference.dark,
    );

    await reveal(
      tester,
      find.byKey(const ValueKey<String>('settings-haptics')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-haptics')));
    await tester.pumpAndSettle();
    final NcSwitch hapticsSwitch = tester.widget<NcSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('settings-haptics')),
        matching: find.byType(NcSwitch),
      ),
    );
    expect(hapticsSwitch.value, isFalse);
  });

  testWidgets('лимиты: NcStepper с прежними ключами', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);
    await reveal(
      tester,
      find.byKey(const ValueKey<String>('settings-new-limit-plus')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-new-limit-plus')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-new-limit-value')),
      findsOneWidget,
    );
    expect(
      find.text('21'),
      findsOneWidget,
      reason: 'Значение лимита растёт на единицу',
    );
  });

  testWidgets('диалог шага обучения: NcDialog с прежними ключами', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);
    await reveal(
      tester,
      find.byKey(const ValueKey<String>('learning-step-add')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('learning-step-add')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('learning-step-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('learning-step-save')),
      findsOneWidget,
    );
    expect(find.text(l10n.settingsLearningStepDialogTitle), findsOneWidget);
  });

  testWidgets('textScale 2,0 на телефоне 360 × 740 без overflow', (
    WidgetTester tester,
  ) async {
    await pumpNcScreenAtTextScale2(
      tester,
      home: const SettingsScreen(),
      overrides: ncStage3Overrides(),
    );
    expect(find.text(l10n.settingsAppearanceTitle), findsOneWidget);
  });

  testWidgets('ширины 390/1440: секции и ключи на месте', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1440, 900),
    ]) {
      await pumpSettings(tester, size: size);
      expect(find.text(l10n.settingsAppearanceTitle), findsOneWidget);
      final Rect about = tester.getRect(
        find.byKey(const ValueKey<String>('settings-about-version')),
      );
      expect(about.right, lessThanOrEqualTo(size.width));
    }
  });
}
