import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/ui/generation/generation_screen.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Входы в генерацию (SPEC A6.2/A6.3): Split-меню «Колод» и меню колоды.
void main() {
  late FakeDeckRepository decks;
  late FakeGenerationRunner runner;

  setUp(() {
    decks = FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Моя колода', totalCards: 3),
      ],
    );
    runner = FakeGenerationRunner();
  });

  List<Override> overrides() {
    return <Override>[
      ...decksOverrides(deckRepository: decks),
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

  testWidgets('«Колоды» → Split-меню → «Сгенерировать карточки» → экран', (
    tester,
  ) async {
    await tester.pumpWidget(
      appWithRouter(overrides: overrides(), routes: routes()),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('decks-create-split')),
        matching: find.byIcon(M3EIcons.keyboard_arrow_down),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('decks-create-generate')),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.decksCreateGenerate));
    await tester.pumpAndSettle();

    expect(find.text(l10n.generationTitle), findsOneWidget);
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

    await tester.tap(find.byKey(const ValueKey<String>('deck-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('deck-generate-action')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.generationTitle), findsOneWidget);
    expect(find.text(l10n.generationTargetDeck('Моя колода')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-deck-name')),
      findsNothing,
    );
  });

  testWidgets('нет ключа → кнопка настроек открывает экран настроек', (
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
    final l10n = l10nOf(tester);

    expect(find.text(l10n.generationKeyMissing), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-open-settings')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsTitle), findsOneWidget);
    final Finder keyField = find.byKey(
      ValueKey<String>('settings-key-${GenerationProvider.openai.wireName}'),
    );
    await tester.scrollUntilVisible(
      keyField,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(keyField, findsOneWidget);
  });
}
