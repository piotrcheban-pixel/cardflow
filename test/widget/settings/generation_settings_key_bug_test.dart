import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Итерация 7.5, диагностика D1 (owner note): ключ DeepSeek не сохранялся.
///
/// Пользователь вводит только ключ и нажимает «Сохранить». Ключ обязан попасть
/// в `ApiKeyStore` (secure storage) независимо от того, заполнены ли адрес и
/// модель сервера: это две независимые операции, и ранний выход по валидации
/// адреса не должен «съедать» ключ.
void main() {
  testWidgets(
    'ключ сохраняется, даже когда адрес и модель не заданы',
    (WidgetTester tester) async {
      final FakeApiKeyStore keys = FakeApiKeyStore();
      final FakeGenerationSettingsStore store = FakeGenerationSettingsStore();

      await tester.pumpWidget(
        appWithHome(
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(),
            generationSettingsStore: store,
            apiKeyStore: keys,
          ),
          home: const GenerationSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('settings-api-key')),
        'sk-deepseek-key',
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('settings-save')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(
        keys.keys[GenerationProvider.openaiCompatible],
        'sk-deepseek-key',
        reason:
            'ожидалось: ключ записан в защищённое хранилище (writeCalls=1), '
            'получено: writeCalls=${keys.writeCalls}',
      );
      // Значение ключа не должно попадать в текстовые виджеты (SPEC 3.4).
      expect(find.text('sk-deepseek-key'), findsNothing);
    },
  );
}
