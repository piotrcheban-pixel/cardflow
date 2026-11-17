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
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/generation_fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/settings_fakes.dart';

class _SuccessTransport implements GenerationTransport {
  int calls = 0;

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    return <String, Object?>{'ok': true};
  }
}

/// Экран «Настройки» (SPEC A6.6, ADR-019): каждый элемент сохраняется,
/// ошибки — из ARB, проверка ключа идёт через транспорт.
void main() {
  late FakeAppSettingsStore settings;
  late FakeApiKeyStore keys;
  late FakeExternalLinkLauncher launcher;
  late _SuccessTransport transport;

  setUp(() {
    settings = FakeAppSettingsStore();
    keys = FakeApiKeyStore(<String, String>{'deepseek': 'key-deepseek'});
    launcher = FakeExternalLinkLauncher();
    transport = _SuccessTransport();
  });

  List<Override> overrides({int tokens = 0}) =>
      decksOverrides(
        deckRepository: FakeDeckRepository(),
        appSettingsStore: settings,
        apiKeyStore: keys,
        providerAccountsStore: FakeProviderAccountsStore(
          ProviderAccounts.empty.withAccount(testProviderAccount()),
        ),
        statisticsRepository: FakeStatisticsRepository(tokens: tokens),
        externalLinkLauncher: launcher,
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
            transport: transport,
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, {int tokens = 0}) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides(tokens: tokens),
        home: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('тема, контраст, haptics сохраняются в app_settings', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(settings.settings.theme, AppThemePreference.dark);

    await reveal(
      tester,
      find.byKey(const ValueKey<String>('settings-haptics')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-haptics')));
    await tester.pumpAndSettle();
    expect(settings.settings.haptics, isFalse);

    await reveal(
      tester,
      find.byKey(const ValueKey<String>('settings-high-contrast')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-high-contrast')),
    );
    await tester.pumpAndSettle();
    expect(settings.settings.highContrast, isTrue);
  });

  testWidgets('ошибка записи: сообщение из ARB и откат значения', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    settings.failWrites = true;
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-dynamic-color')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.settingsSaveError), findsOneWidget);
    final NcSwitch tile = tester.widget<NcSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('settings-dynamic-color')),
        matching: find.byType(NcSwitch),
      ),
    );
    expect(tile.value, isFalse);
    expect(settings.settings.dynamicColor, isFalse);
  });

  testWidgets('лимиты, шаги обучения и размер шрифта', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    final Finder textScale = find.byKey(
      const ValueKey<String>('settings-text-scale'),
    );
    await reveal(tester, textScale);
    final Finder slider = find.descendant(
      of: textScale,
      matching: find.byType(Slider),
    );
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(settings.settings.textScale, greaterThan(1));

    await reveal(
      tester,
      find.byKey(const ValueKey<String>('settings-new-limit-plus')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-new-limit-plus')),
    );
    await tester.pumpAndSettle();
    expect(settings.settings.dailyNewLimit, 21);
    expect(find.text('21'), findsOneWidget);

    await reveal(
      tester,
      find.byKey(const ValueKey<String>('learning-step-add')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('learning-step-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('learning-step-input')),
      '5',
    );
    await tester.tap(find.byKey(const ValueKey<String>('learning-step-save')));
    await tester.pumpAndSettle();
    expect(
      settings.settings.learningSteps,
      contains(const Duration(minutes: 5)),
    );

    final NcChip added = tester.widget<NcChip>(
      find.byKey(const ValueKey<String>('learning-step-5')),
    );
    added.onDeleted!();
    await tester.pumpAndSettle();
    expect(
      settings.settings.learningSteps,
      isNot(contains(const Duration(minutes: 5))),
    );
  });

  testWidgets('API: сводка провайдеров, переход к настройке, токены', (
    WidgetTester tester,
  ) async {
    await pump(tester, tokens: 1234);
    final AppLocalizations l10n = l10nOf(tester);

    await reveal(
      tester,
      find.byKey(const ValueKey<String>('settings-weekly-tokens')),
    );
    expect(find.text(l10n.settingsApiTokensWeek(1234)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-provider-deepseek')),
      findsOneWidget,
      reason: 'В блоке API — сводка настроенных провайдеров (ADR-020)',
    );
    expect(find.text(l10n.providersActive), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-open-generation')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Model по умолчанию'),
      findsNothing,
      reason: 'Отдельной «модели по умолчанию» больше нет',
    );
  });

  testWidgets('API: провайдеры не настроены — подсказка вместо списка', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          appSettingsStore: settings,
          apiKeyStore: keys,
          providerAccountsStore: FakeProviderAccountsStore(),
          statisticsRepository: FakeStatisticsRepository(),
          externalLinkLauncher: launcher,
        ),
        home: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);
    await reveal(
      tester,
      find.byKey(const ValueKey<String>('settings-providers-empty')),
    );
    expect(find.text(l10n.providersEmptyTitle), findsOneWidget);
  });

  testWidgets('«О приложении»: версия, лицензии, политика приватности', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final AppLocalizations l10n = l10nOf(tester);

    await reveal(
      tester,
      find.byKey(const ValueKey<String>('settings-about-privacy')),
    );
    expect(find.text(l10n.settingsAboutVersion('1.0.0')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-about-privacy')),
    );
    await tester.pumpAndSettle();
    expect(launcher.lastUri, isNotNull);
    expect(launcher.lastUri!.path, endsWith('/docs/privacy.md'));

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-about-licenses')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
