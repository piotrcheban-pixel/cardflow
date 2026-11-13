import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  Widget buildApp(List<DeckSummary> summaries) {
    return ProviderScope(
      overrides: decksOverrides(
        deckRepository: FakeDeckRepository(summaries: summaries),
      ),
      child: const CardFlowApp(),
    );
  }

  group('CardFlowApp (корень: GoRouter + M3ETheme, ADR-007)', () {
    testWidgets('показывает экран «Колоды» под M3ETheme и ru-локалью', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(<DeckSummary>[
          makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 3),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(M3ETheme), findsOneWidget);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.decksTitle), findsOneWidget);
      expect(find.text('Испанский'), findsOneWidget);
      expect(
        Localizations.localeOf(tester.element(find.byType(Scaffold))),
        const Locale('ru'),
      );
    });

    testWidgets('тап по карточке колоды открывает экран колоды', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(<DeckSummary>[
          makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 1),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Испанский'));
      await tester.pumpAndSettle();

      expect(find.byType(DeckScreen), findsOneWidget);
    });

    testWidgets('стартовая локация роутера сразу открывает экран колоды', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(
              summaries: <DeckSummary>[
                makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 1),
              ],
            ),
          ),
          child: CardFlowApp(
            router: createAppRouter(
              initialLocation: AppRoutes.deckPath('deck-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DeckScreen), findsOneWidget);
      expect(find.text('Испанский'), findsOneWidget);
    });

    testWidgets(
      'production-роутер: колода → «Начать сессию» → классическая сессия (L2)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: decksOverrides(
              deckRepository: FakeDeckRepository(
                summaries: <DeckSummary>[
                  makeSummary(
                    id: 'deck-1',
                    name: 'Испанский',
                    totalCards: 1,
                    newCards: 1,
                  ),
                ],
              ),
              cardRepository: FakeCardRepository(
                cards: <Card>[
                  makeCard(
                    id: 'card-1',
                    deckId: 'deck-1',
                    front: 'Вопрос production-роутера',
                  ),
                ],
              ),
            ),
            child: const CardFlowApp(),
          ),
        );
        await tester.pumpAndSettle();
        final AppLocalizations l10n = l10nOf(tester);

        await tester.tap(find.text('Испанский'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.reviewStartSession));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.reviewModeClassic));
        await tester.pumpAndSettle();

        expect(find.byType(ReviewSessionScreen), findsOneWidget);
        expect(find.text('Вопрос production-роутера'), findsOneWidget);
      },
    );

    testWidgets('production-роутер: кнопка настроек на «Колодах» открывает '
        '«Настройки генерации» (ADR-013)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(
              summaries: <DeckSummary>[
                makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 1),
              ],
            ),
          ),
          child: const CardFlowApp(),
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byTooltip(l10n.settingsOpenTooltip));
      await tester.pumpAndSettle();

      expect(find.byType(GenerationSettingsScreen), findsOneWidget);
      expect(find.text(l10n.settingsTitle), findsOneWidget);
      // Настройки читаются через production-провайдеры с фейками
      // (без drift/secure storage в тесте).
      expect(find.text(l10n.settingsOpenAiCompatibleTitle), findsOneWidget);
    });
  });

  group('StartupErrorApp', () {
    testWidgets('показывает сообщение из ARB без сырых исключений', (
      tester,
    ) async {
      await tester.pumpWidget(const StartupErrorApp());
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold));
      final l10n = AppLocalizations.of(context);
      expect(find.text(l10n.databaseOpenError), findsOneWidget);
      expect(Localizations.localeOf(context), const Locale('ru'));
      expect(find.text(l10n.appTitle), findsNothing);
    });
  });
}
