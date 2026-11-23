import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Аудит 1.0: находки D8/F6/F10/N8 на экране колоды.
void main() {
  Future<void> pumpDeckScreen(
    WidgetTester tester, {
    required List<Card> cards,
    FakeDailyUsageRepository? dailyUsage,
    FakeAppSettingsStore? appSettingsStore,
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(
            summaries: <DeckSummary>[
              makeSummary(
                id: 'deck-1',
                name: 'Физика',
                totalCards: cards.length,
                newCards: cards.length,
                dueCards: cards.length,
              ),
            ],
          ),
          cardRepository: FakeCardRepository(cards: cards),
          dailyUsageRepository: dailyUsage,
          appSettingsStore: appSettingsStore,
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('D8: cloze-карточка в списке без сырой разметки', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(
      tester,
      cards: <Card>[
        makeCard(
          id: 'card-1',
          deckId: 'deck-1',
          front: 'Теорема: {{c1::квадрат гипотенузы}}',
          back: 'Пояснение',
          cardType: CardType.cloze,
        ),
      ],
    );

    expect(find.textContaining('{{'), findsNothing);
    expect(find.textContaining('квадрат гипотенузы'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('cloze-gap-1')),
      findsOneWidget,
      reason: 'пропуск показан заглушкой, как в сессии',
    );
  });

  testWidgets('F10/V44: счётчики самодостаточны, сноски нет', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(
      tester,
      cards: <Card>[makeCard(id: 'card-1', deckId: 'deck-1', front: 'Вопрос')],
    );
    final AppLocalizations l10n = l10nOf(tester);
    // Аудит v4 (V44): метрика переименована в «Начато», пояснение-сноска
    // удалено — метрики понятны без «костыля».
    expect(
      find.byKey(const ValueKey<String>('deck-counters-note')),
      findsNothing,
    );
    expect(find.text(l10n.deckInProgressCount(0)), findsOneWidget);
  });

  testWidgets('N8: предупреждение о дневном лимите видно до выбора режима', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(
      tester,
      cards: <Card>[
        makeCard(
          id: 'card-1',
          deckId: 'deck-1',
          front: 'Старый вопрос',
          back: 'Ответ',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          due: DateTime.now().subtract(const Duration(days: 1)),
          state: CardState.review,
        ),
      ],
      dailyUsage: FakeDailyUsageRepository(
        usage: const DailyReviewUsage(newCards: 20, repeats: 200),
      ),
      appSettingsStore: FakeAppSettingsStore(
        settings: AppSettings.defaults.copyWith(
          dailyNewLimit: 20,
          dailyReviewLimit: 200,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('deck-daily-limit-notice')),
      findsOneWidget,
      reason: 'пользователь видит причину пустой очереди до старта',
    );
    expect(
      find.byKey(const ValueKey<String>('deck-limit-continue')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('deck-limit-practice')),
      findsOneWidget,
    );
  });
  testWidgets('D23: диалог лимита компактный, без дублирующего текста', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(
      tester,
      cards: <Card>[
        makeCard(
          id: 'card-1',
          deckId: 'deck-1',
          front: 'Старый вопрос',
          back: 'Ответ',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          due: DateTime.now().subtract(const Duration(days: 1)),
          state: CardState.review,
        ),
      ],
      dailyUsage: FakeDailyUsageRepository(
        usage: const DailyReviewUsage(newCards: 20, repeats: 200),
      ),
      appSettingsStore: FakeAppSettingsStore(
        settings: AppSettings.defaults.copyWith(
          dailyNewLimit: 20,
          dailyReviewLimit: 200,
        ),
      ),
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.text(l10n.reviewStartSession));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.reviewModeClassic));
    await tester.pumpAndSettle();

    final Size dialog = tester.getSize(
      find.byKey(const ValueKey<String>('app-dialog-surface')),
    );
    expect(dialog.width, lessThanOrEqualTo(520));
    expect(find.text(l10n.deckDailyLimitNotice), findsWidgets);
    expect(
      find.text(l10n.reviewDailyLimitContinueMessage),
      findsNothing,
      reason: 'дублирующий длинный текст заменён короткой формулировкой',
    );
  });
  testWidgets('F5: поиск по карточкам внутри колоды', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(
      tester,
      cards: <Card>[
        makeCard(id: 'card-1', deckId: 'deck-1', front: 'Первый вопрос'),
        makeCard(id: 'card-2', deckId: 'deck-1', front: 'Второй вопрос'),
      ],
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('deck-cards-search-toggle')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('deck-card-search')),
      'Первый',
    );
    await tester.pumpAndSettle();

    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text('Второй вопрос'), findsNothing);
  });

  testWidgets('F5: фильтр по состоянию — «К повторению»', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(
      tester,
      cards: <Card>[
        makeCard(
          id: 'card-1',
          deckId: 'deck-1',
          front: 'Созрела',
          state: CardState.review,
          due: DateTime.now().subtract(const Duration(days: 1)),
        ),
        makeCard(id: 'card-2', deckId: 'deck-1', front: 'Новая'),
      ],
    );
    await tester.tap(find.byKey(const ValueKey<String>('deck-cards-filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('deck-card-filter-due')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Созрела'), findsOneWidget);
    expect(find.text('Новая'), findsNothing);
  });

  testWidgets('F5: меню строки удаляет карточку с подтверждением', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(
      tester,
      cards: <Card>[
        makeCard(id: 'card-1', deckId: 'deck-1', front: 'Удаляемая'),
        makeCard(id: 'card-2', deckId: 'deck-1', front: 'Вторая'),
      ],
    );
    final Finder menu = find.byKey(
      const ValueKey<String>('deck-card-menu-card-1'),
    );
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('deck-card-menu-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('deck-card-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Удаляемая'), findsNothing);
    expect(find.text('Вторая'), findsOneWidget);
  });
}
