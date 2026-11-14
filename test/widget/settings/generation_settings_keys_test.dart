import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Блок «Ключи API» на экране настроек генерации (A6.6/A6.8, SPEC 3.4).
void main() {
  late FakeApiKeyStore keyStore;
  late FakeGenerationSettingsStore settingsStore;

  setUp(() {
    keyStore = FakeApiKeyStore(<GenerationProvider, String>{
      GenerationProvider.openai: 'old-key',
    });
    settingsStore = FakeGenerationSettingsStore();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: <Override>[
          apiKeyStoreProvider.overrideWithValue(keyStore),
          generationSettingsStoreProvider.overrideWithValue(settingsStore),
        ],
        home: const GenerationSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('показывает статус ключа OpenAI и позволяет заменить', (
    tester,
  ) async {
    await pumpSettings(tester);
    final l10n = l10nOf(tester);
    final Finder keyField = find.byKey(
      const ValueKey<String>('settings-key-openai'),
    );
    await scrollTo(tester, keyField);
    expect(find.text(l10n.settingsKeyConfigured), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('settings-delete-key-openai')),
      findsOneWidget,
    );

    await tester.enterText(keyField, 'new-key');
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-save-key-openai')),
    );
    await tester.pumpAndSettle();

    expect(keyStore.keys[GenerationProvider.openai], 'new-key');
    expect(find.text(l10n.settingsKeySaved), findsWidgets);
  });

  testWidgets('пустой ключ — ошибка ARB, запись не выполняется', (
    tester,
  ) async {
    await pumpSettings(tester);
    final l10n = l10nOf(tester);
    final int writesBefore = keyStore.writeCalls;
    final Finder saveButton = find.byKey(
      const ValueKey<String>('settings-save-key-gemini'),
    );
    await scrollTo(tester, saveButton);

    await tester.tap(saveButton);
    await tester.pump();

    expect(find.text(l10n.settingsKeyEmptyError), findsOneWidget);
    expect(keyStore.writeCalls, writesBefore);
  });

  testWidgets('удаление ключа: статус меняется, ключ стирается', (
    tester,
  ) async {
    await pumpSettings(tester);
    final l10n = l10nOf(tester);
    final Finder deleteButton = find.byKey(
      const ValueKey<String>('settings-delete-key-openai'),
    );
    await scrollTo(tester, deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(keyStore.keys.containsKey(GenerationProvider.openai), isFalse);
    expect(find.text(l10n.settingsKeyDeleted), findsOneWidget);
    expect(find.text(l10n.settingsKeyMissing), findsWidgets);
  });
}
