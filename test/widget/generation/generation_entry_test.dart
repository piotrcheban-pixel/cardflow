import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/ui/generation/generation_screen.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Входы в генерацию (SPEC A6.2/A6.3): Split-меню «Колод» и меню колоды.
void main() {
  late FakeDeckRepository decks;
  late FakeGenerationRunner runner;
  late FakeProviderAccountsStore accountsStore;

  setUp(() {
    decks = FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Моя колода', totalCards: 3),
      ],
    );
    runner = FakeGenerationRunner();
    accountsStore = FakeProviderAccountsStore(
      ProviderAccounts.empty
          .withAccount(testProviderAccount(presetId: 'deepseek'))
          .withAccount(testProviderAccount(presetId: 'gemini')),
    );
  });

  List<Override> overrides() {
    return <Override>[
      ...decksOverrides(
        deckRepository: decks,
        providerAccountsStore: accountsStore,
        // У Gemini ключа нет: экран генерации показывает баннер с переходом
        // в настройки — им и проверяем сохранение выбора провайдера.
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': 'sk-ds'}),
      ),
      generationRunnerProvider.overrideWithValue(runner),
      generationCardStoreProvider.overrideWithValue(FakeGenerationCardStore()),
      documentGatewayProvider.overrideWithValue(FakeDocumentGateway()),
      fileParsingServiceProvider.overrideWithValue(FileParsingService()),
    ];
  }

  List<GoRoute> routes() {
    return <GoRoute>[
      ...decksRoutes(),
      GoRoute(
        path: '/generate',
        builder: (context, state) => const GenerationScreen(),
      ),
      GoRoute(
        path: '/decks/:id/generate',
        builder: (context, state) =>
            GenerationScreen(deckId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/settings/generation',
        builder: (context, state) => const GenerationSettingsScreen(),
      ),
    ];
  }

  testWidgets('«Колоды» → «ИИ-генерация» в панели → экран', (
    tester,
  ) async {
    // Аудит v4 (V17): ✨ из шапки «Колод» удалена — единственный глобальный
    // вход в генерацию — пункт «ИИ-генерация» постоянной навигации.
    await tester.pumpWidget(
      appWithAppRouter(overrides: overrides(), initialLocation: '/'),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);

    await tester.tap(find.byTooltip(l10n.navAi).first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.generationPageTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
      findsOneWidget,
    );
  });

  testWidgets('экран колоды → меню → генерация в существующую колоду', (
    tester,
  ) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: overrides(),
        routes: routes(),
        initialLocation: '/decks/deck-1',
      ),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('deck-generate-action')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.generationPageTitle), findsOneWidget);
    expect(find.text(l10n.generationTargetDeck('Моя колода')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-deck-name')),
      findsNothing,
    );
  });

  testWidgets('провайдеры не настроены → кнопка открывает экран провайдеров', (
    tester,
  ) async {
    accountsStore = FakeProviderAccountsStore();
    await tester.pumpWidget(
      appWithRouter(
        overrides: overrides(),
        routes: routes(),
        initialLocation: '/generate',
      ),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);

    expect(
      find.text(l10n.generationErrorProviderNotConfigured),
      findsOneWidget,
    );
    final Finder openSettings = find.byKey(
      const ValueKey<String>('generation-open-settings'),
    );
    await tester.ensureVisible(openSettings);
    await tester.pumpAndSettle();
    await tester.tap(openSettings);
    await tester.pumpAndSettle();
    expect(find.text(l10n.providersTitle), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('providers-add')), findsOneWidget);
  });

  testWidgets('выбранный провайдер сохраняется после возврата из настроек', (
    tester,
  ) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: overrides(),
        routes: routes(),
        initialLocation: '/generate',
      ),
    );
    await tester.pumpAndSettle();
    final Finder geminiChip = find.byKey(
      const ValueKey<String>('generation-provider-gemini'),
    );
    final Finder scrollable = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(geminiChip, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(geminiChip);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(geminiChip).selected, isTrue);

    final Finder settingsButton = find.byKey(
      const ValueKey<String>('generation-open-settings'),
    );
    await tester.scrollUntilVisible(
      settingsButton,
      -200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(GenerationSettingsScreen))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(geminiChip, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(geminiChip).selected, isTrue);
  });
}
