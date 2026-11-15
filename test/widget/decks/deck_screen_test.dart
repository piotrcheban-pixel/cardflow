import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/review/practice_session_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/session/session_constructor_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Красная фаза: экран «Колода» (SPEC A6.3, минимальный для итерации 1).
void main() {
  Future<void> pumpDeck(
    WidgetTester tester, {
    required FakeDeckRepository repository,
    FakeCardRepository? cards,
    FakeDeckTransferService? transfer,
    FakeFileGateway? gateway,
    FakeDailyUsageRepository? dailyUsage,
    FakeAppSettingsStore? appSettingsStore,
    String initialLocation = '/decks/deck-1',
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: repository,
          cardRepository: cards,
          transferService: transfer,
          fileGateway: gateway,
          dailyUsageRepository: dailyUsage,
          appSettingsStore: appSettingsStore,
        ),
        routes: decksRoutes(),
        initialLocation: initialLocation,
      ),
    );
  }

  Future<void> openOverflowMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  group('Колода: шапка и карточки', () {
    testWidgets('заголовок, счётчики и список карточек', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 6,
            newCards: 2,
            inProgressCards: 1,
            dueCards: 3,
          ),
        ],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          makeCard(
            id: 'card-1',
            deckId: 'deck-1',
            front: '¿Cómo estás?',
            tags: <String>['приветствие'],
            state: CardState.review,
          ),
          makeCard(id: 'card-2', deckId: 'deck-1', front: 'Глагол ser'),
        ],
      );

      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      expect(find.text('Испанский'), findsOneWidget);
      expect(find.text(l10n.deckDueCount(3)), findsOneWidget);
      expect(find.text(l10n.deckNewCount(2)), findsOneWidget);
      expect(find.text(l10n.deckInProgressCount(1)), findsOneWidget);
      expect(find.text('¿Cómo estás?'), findsOneWidget);
      expect(find.text('Глагол ser'), findsOneWidget);
      expect(
        find.text(l10n.cardTagsLine('#приветствие')),
        findsOneWidget,
        reason: 'Теги карточки показываются строкой из ARB',
      );
      expect(find.text(l10n.cardStateReview), findsOneWidget);
      expect(find.text(l10n.cardStateNew), findsOneWidget);
    });

    testWidgets('пустой список карточек: сообщение из ARB', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDeck(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      expect(find.text(l10n.deckCardsEmpty), findsOneWidget);
      expect(find.text(l10n.deckCardsEmptyHint), findsOneWidget);
    });

    testWidgets('колода не найдена', (WidgetTester tester) async {
      final FakeDeckRepository repository = FakeDeckRepository();

      await pumpDeck(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      expect(find.text(l10n.deckNotFound), findsOneWidget);
    });

    testWidgets('ошибка загрузки: строка из ARB и повтор', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      )..failDeck = true;

      await pumpDeck(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      expect(find.text(l10n.deckErrorTitle), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);

      repository.failDeck = false;
      await tester.tap(find.widgetWithText(TextButton, l10n.retry));
      await tester.pumpAndSettle();
      expect(find.text('Испанский'), findsOneWidget);
    });
  });

  group('Колода: меню действий', () {
    testWidgets('переименование из overflow-меню', (WidgetTester tester) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDeck(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await openOverflowMenu(tester);
      expect(find.text(l10n.deckRename), findsOneWidget);
      expect(find.text(l10n.deckExport), findsOneWidget);
      expect(find.text(l10n.delete), findsOneWidget);

      await tester.tap(find.text(l10n.deckRename));
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckRenameDialogTitle), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Испанский 2');
      await tester.tap(find.byKey(const ValueKey<String>('deck-name-submit')));
      await tester.pumpAndSettle();

      expect(repository.renamedIds, <String>['deck-1']);
      expect(repository.renamedNames, <String>['Испанский 2']);
      expect(find.text('Испанский 2'), findsOneWidget);
    });

    testWidgets('удаление с подтверждением возвращает к списку колод', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDeck(tester, repository: repository, initialLocation: '/');
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text('Испанский'));
      await tester.pumpAndSettle();
      expect(find.byType(DeckScreen), findsOneWidget);

      await openOverflowMenu(tester);
      await tester.tap(find.text(l10n.delete));
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckDeleteDialogTitle), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('delete-deck-confirm')),
      );
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['deck-1']);
      expect(find.byType(DecksScreen), findsOneWidget);
      expect(find.byType(DeckScreen), findsNothing);
    });

    testWidgets('экспорт: сервис, пикер сохранения и запись байтов', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );
      final FakeDeckTransferService transfer = FakeDeckTransferService();
      final FakeFileGateway gateway = FakeFileGateway();

      await pumpDeck(
        tester,
        repository: repository,
        transfer: transfer,
        gateway: gateway,
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await openOverflowMenu(tester);
      await tester.tap(find.text(l10n.deckExport));
      await tester.pumpAndSettle();

      expect(transfer.exportedDeckIds, <String>['deck-1']);
      expect(gateway.saveCalls, 1);
      expect(
        gateway.lastSuggestedFileName,
        endsWith('.zip'),
        reason: 'Диалогу сохранения предлагается имя с расширением .zip',
      );
      expect(
        gateway.lastSuggestedFileName,
        isNot(startsWith('.')),
        reason: 'Имя файла не должно быть пустым',
      );
      expect(
        gateway.lastSavedBytes,
        orderedEquals(transfer.exportBytes),
        reason: 'Шлюзу передаются ровно байты экспортированного архива',
      );
      expect(find.text(l10n.deckExportSuccess), findsOneWidget);
    });

    testWidgets('экспорт: отмена сохранения — тихий no-op', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );
      final FakeDeckTransferService transfer = FakeDeckTransferService();
      final FakeFileGateway gateway = FakeFileGateway()..saveResult = false;

      await pumpDeck(
        tester,
        repository: repository,
        transfer: transfer,
        gateway: gateway,
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await openOverflowMenu(tester);
      await tester.tap(find.text(l10n.deckExport));
      await tester.pumpAndSettle();

      expect(transfer.exportedDeckIds, <String>['deck-1']);
      expect(gateway.saveCalls, 1);
      expect(gateway.lastSavedBytes, isNull);
      expect(find.text(l10n.deckExportSuccess), findsNothing);
    });

    testWidgets('экспорт: ошибка архива маппится в строку ARB', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );
      final FakeDeckTransferService transfer = FakeDeckTransferService()
        ..exportError = const ArchiveException(
          ArchiveErrorCode.mediaMissing,
          details: 'сырой стектрейс',
        );

      await pumpDeck(tester, repository: repository, transfer: transfer);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await openOverflowMenu(tester);
      await tester.tap(find.text(l10n.deckExport));
      await tester.pumpAndSettle();

      expect(find.text(l10n.archiveErrorMediaMissing), findsOneWidget);
      expect(find.textContaining('сырой стектрейс'), findsNothing);
    });
  });

  group('Колода: сессия и карточки (итерация 2)', () {
    testWidgets('«Начать сессию»: выбор классического режима и переход', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 1,
            newCards: 1,
          ),
        ],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          makeCard(id: 'card-1', deckId: 'deck-1', front: 'Вопрос'),
        ],
      );

      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reviewSessionModeTitle), findsOneWidget);
      expect(find.text(l10n.reviewModeClassic), findsOneWidget);

      await tester.tap(find.text(l10n.reviewModeClassic));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewSessionScreen), findsOneWidget);
      expect(find.text('Вопрос'), findsOneWidget);
    });

    testWidgets('«Начать сессию» без карточек — сообщение, без перехода', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Пустая')],
      );

      await pumpDeck(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();

      expect(find.text(l10n.reviewStartEmptyMessage), findsOneWidget);
      expect(find.byType(ReviewSessionScreen), findsNothing);
    });

    testWidgets('FAB «Добавить» открывает форму новой карточки', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDeck(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byTooltip(l10n.deckAddCardTooltip));
      await tester.pumpAndSettle();

      expect(find.byType(CardFormScreen), findsOneWidget);
      expect(find.text(l10n.cardFormTitleNew), findsOneWidget);
    });

    testWidgets('тап по карточке открывает форму редактирования', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          makeCard(id: 'card-1', deckId: 'deck-1', front: 'Вопрос-один'),
        ],
      );

      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text('Вопрос-один'));
      await tester.pumpAndSettle();

      expect(find.byType(CardFormScreen), findsOneWidget);
      expect(find.text(l10n.cardFormTitleEdit), findsOneWidget);
    });

    testWidgets('лист режимов содержит «Конструктор» и открывает экран A6.7', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 1,
            newCards: 1,
          ),
        ],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          makeCard(id: 'card-1', deckId: 'deck-1', front: 'Вопрос'),
        ],
      );

      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      expect(find.text(l10n.constructorAction), findsOneWidget);

      await tester.tap(find.text(l10n.constructorAction));
      await tester.pumpAndSettle();

      expect(find.byType(SessionConstructorScreen), findsOneWidget);
      expect(find.text(l10n.constructorTitle), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey<String>('constructor-deck-deck-1')),
            )
            .selected,
        isTrue,
        reason: 'колода с экрана колоды предвыбрана',
      );
    });

    // Итерация 7.11 (owner-note): тренировка доступна из листа режимов и не
    // зависит от FSRS/дневного лимита.
    testWidgets('лист режимов: «Тренировка» открывает экран тренировки', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 1,
            newCards: 1,
          ),
        ],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          makeCard(
            id: 'card-1',
            deckId: 'deck-1',
            front: 'Вопрос',
            state: CardState.review,
            due: DateTime.now().add(const Duration(days: 3)),
          ),
        ],
      );
      // Дневной лимит новых исчерпан — тренировка всё равно доступна.
      final FakeDailyUsageRepository usage = FakeDailyUsageRepository(
        usage: const DailyReviewUsage(newCards: 20),
      );

      await pumpDeck(
        tester,
        repository: repository,
        cards: cards,
        dailyUsage: usage,
        appSettingsStore: FakeAppSettingsStore(
          settings: AppSettings.defaults.copyWith(dailyNewLimit: 20),
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reviewModePractice), findsOneWidget);

      await tester.tap(find.text(l10n.reviewModePractice));
      await tester.pumpAndSettle();

      expect(find.byType(PracticeSessionScreen), findsOneWidget);
      expect(find.text(l10n.practiceSubtitle), findsWidgets);
      expect(find.text('Вопрос'), findsOneWidget);
    });

    // Итерация 7.11: причина пустой сессии — исчерпанный дневной лимит, а не
    // «нет карточек»; при этом доступна тренировка.
    testWidgets(
      'дневной лимит исчерпан: сообщение о лимите вместо «нет карточек»',
      (WidgetTester tester) async {
        final FakeDeckRepository repository = FakeDeckRepository(
          summaries: <DeckSummary>[
            makeSummary(
              id: 'deck-1',
              name: 'Испанский',
              totalCards: 1,
              newCards: 1,
            ),
          ],
        );
        final FakeCardRepository cards = FakeCardRepository(
          cards: <Card>[
            makeCard(id: 'card-1', deckId: 'deck-1', front: 'Вопрос'),
          ],
        );
        final FakeDailyUsageRepository usage = FakeDailyUsageRepository(
          usage: const DailyReviewUsage(newCards: 20),
        );

        await pumpDeck(
          tester,
          repository: repository,
          cards: cards,
          dailyUsage: usage,
          appSettingsStore: FakeAppSettingsStore(
            settings: AppSettings.defaults.copyWith(dailyNewLimit: 20),
          ),
        );
        await tester.pumpAndSettle();
        final AppLocalizations l10n = l10nOf(tester);

        await tester.tap(find.text(l10n.reviewStartSession));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.reviewModeClassic));
        await tester.pumpAndSettle();

        expect(find.text(l10n.reviewStartEmptyLimitedMessage), findsOneWidget);
        expect(find.text(l10n.reviewStartEmptyMessage), findsNothing);
        expect(find.byType(ReviewSessionScreen), findsNothing);
      },
    );
  });
}
