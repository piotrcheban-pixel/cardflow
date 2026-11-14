import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/settings_fakes.dart';

/// A6.6/ADR-019: настройки применяются корнем приложения, а не только хранятся.
void main() {
  testWidgets('тема, шрифт дислексии и масштаб текста применяются', (
    WidgetTester tester,
  ) async {
    final FakeAppSettingsStore store = FakeAppSettingsStore(
      settings: AppSettings.defaults.copyWith(
        theme: AppThemePreference.dark,
        dyslexiaFont: true,
        textScale: 1.3,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          appSettingsStore: store,
        ),
        child: const CardFlowApp(),
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(DecksScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'OpenDyslexic');
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(13, 1e-9));
  });

  testWidgets('светлая тема по умолчанию и масштаб 1.0', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: decksOverrides(deckRepository: FakeDeckRepository()),
        child: const CardFlowApp(),
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(DecksScreen));
    expect(MediaQuery.textScalerOf(context).scale(10), 10);
    expect(
      Theme.of(context).textTheme.bodyMedium?.fontFamily,
      isNot('OpenDyslexic'),
    );
  });
}
