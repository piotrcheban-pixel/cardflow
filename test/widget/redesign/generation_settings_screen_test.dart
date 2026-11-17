import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/generation/api_key_verifier.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/anthropic_adapter.dart';
import 'package:cardflow/api/providers/gemini_adapter.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/glass_budget.dart';
import '../../helpers/nc_harness.dart';
import '../../helpers/nc_screen_harness.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/settings_fakes.dart';

class _OkTransport implements GenerationTransport {
  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async => <String, Object?>{'ok': true};
}

/// Провайдеры в оформлении Nocturne (REDESIGN-SPEC §9.17).
void main() {
  final AppLocalizations l10n = ncL10n;
  late FakeApiKeyStore keys;

  List<Override> overrides() {
    keys = FakeApiKeyStore(<String, String>{'deepseek': 'secret-value'});
    return decksOverrides(
      deckRepository: FakeDeckRepository(),
      providerAccountsStore: FakeProviderAccountsStore(
        ProviderAccounts.empty.withAccount(testProviderAccount()),
      ),
      apiKeyStore: keys,
      statisticsRepository: FakeStatisticsRepository(),
    )..add(
      apiKeyVerifierProvider.overrideWithValue(
        ApiKeyVerifier(
          adapters: <GenerationProviderAdapter>[
            const OpenAiAdapter(),
            const GeminiAdapter(),
            const AnthropicAdapter(),
            const OpenAiCompatibleAdapter(),
          ],
          apiKeyStore: keys,
          transport: _OkTransport(),
        ),
      ),
    );
  }

  Future<void> pumpProviders(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) => pumpNcScreen(
    tester,
    home: const GenerationSettingsScreen(),
    overrides: overrides(),
    config: NcScreenConfig(size: size),
  );

  testWidgets('ключи §9.17: карточка, бейджи, действия в Wrap', (
    WidgetTester tester,
  ) async {
    await pumpProviders(tester);

    expect(find.text(l10n.providersTitle), findsWidgets);
    expect(find.byKey(const ValueKey<String>('providers-add')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('provider-card-deepseek')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('provider-active-deepseek')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('provider-vision-deepseek')),
      findsOneWidget,
    );
    for (final String action in <String>['check', 'edit', 'delete']) {
      expect(
        find.byKey(ValueKey<String>('provider-$action-deepseek')),
        findsOneWidget,
        reason: action,
      );
    }
    expect(find.byType(NcBadge), findsWidgets);
    expect(find.byType(NcSurface), findsWidgets);
    expectGlassBudget(tester, maxGroups: 2);
  });

  testWidgets('проверка ключа: NcSpinner/бейдж результата', (
    WidgetTester tester,
  ) async {
    await pumpProviders(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('provider-check-deepseek')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('provider-check-result-deepseek')),
      findsOneWidget,
    );
    expect(find.text(l10n.providersCheckWorks), findsOneWidget);
  });

  testWidgets('меню добавления и диалог каталога с ключами', (
    WidgetTester tester,
  ) async {
    await pumpProviders(tester);
    await tester.tap(find.byKey(const ValueKey<String>('providers-add')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('providers-add-preset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('providers-add-custom')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('providers-add-preset')),
    );
    await tester.pumpAndSettle();
    for (final String key in <String>[
      'provider-preset-select',
      'provider-base-url',
      'provider-key',
      'provider-save',
      'provider-cancel',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
    expect(find.byType(NcDropdown<String>), findsWidgets);
  });

  testWidgets('значение ключа никогда не отображается', (
    WidgetTester tester,
  ) async {
    await pumpProviders(tester);
    expect(find.text('secret-value'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('provider-edit-deepseek')),
    );
    await tester.pumpAndSettle();
    expect(find.text('secret-value'), findsNothing);
    final TextField field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('provider-key')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.obscureText, isTrue);
    expect(field.controller?.text ?? '', isEmpty);
  });

  testWidgets('textScale 2,0 на телефоне 360 × 740 без overflow', (
    WidgetTester tester,
  ) async {
    await pumpNcScreenAtTextScale2(
      tester,
      home: const GenerationSettingsScreen(),
      overrides: overrides(),
    );
    expect(find.byType(NcSurface), findsWidgets);
  });

  testWidgets('ширины 390/1440: карточка и действия на месте', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1440, 900),
    ]) {
      await pumpProviders(tester, size: size);
      final Rect card = tester.getRect(
        find.byKey(const ValueKey<String>('provider-card-deepseek')),
      );
      expect(card.right, lessThanOrEqualTo(size.width));
    }
  });
}
