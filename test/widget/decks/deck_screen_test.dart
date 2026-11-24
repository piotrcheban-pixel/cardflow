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
import 'package:cardflow/ui/study/match_screen.dart';
import 'package:cardflow/ui/study/multiple_choice_screen.dart';
import 'package:cardflow/ui/study/true_false_screen.dart';
import 'package:cardflow/ui/study/typing_screen.dart';
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
      await tester.tap(find.widgetWithText(FilledButton, l10n.retry));
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

      // Находка F6: на пустой колоде кнопка выглядит неактивной, подпись
      // объясняет причину, а сообщение говорит про отсутствие карточек.
      expect(find.text(l10n.deckStartNeedsCards), findsOneWidget);
      expect(find.text(l10n.deckEmptySnack), findsOneWidget);
      expect(find.byType(ReviewSessionScreen), findsNothing);
    });

    testWidgets('кнопка «Добавить карточку» открывает форму', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDeck(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      // Аудит v4 (V10): «+» из AppBar удалён, действие одно — в строке списка.
      await tester.tap(
        find.byKey(const ValueKey<String>('deck-add-card-button')),
      );
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

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('review-mode-constructor')),
      );
      await tester.pumpAndSettle();
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

    // Итерация 7.15: в листе режимов появились «Тест» и «Ввод ответа» с
    // числом доступных карточек; без подходящих карточек пункт неактивен.
    testWidgets('лист режимов: «Тест» и «Ввод ответа» с числом карточек', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Биология',
            totalCards: 5,
            newCards: 5,
          ),
        ],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          for (var index = 0; index < 5; index++)
            makeCard(
              id: 'card-$index',
              deckId: 'deck-1',
              front: 'Вопрос $index?',
              back: <String>[
                'Митохондрия',
                'Рибосома',
                'Хлоропласт',
                'Лизосома',
                'Гольджи',
              ][index],
            ),
        ],
      );
      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reviewModeTest), findsOneWidget);
      expect(find.text(l10n.reviewModeTyping), findsOneWidget);
      expect(
        find.text(
          '${l10n.studyModeTestSubtitle} · ${l10n.studyModeAvailableCount(5)}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '${l10n.studyModeTypingSubtitle} · ${l10n.studyModeAvailableCount(5)}',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n.reviewModeTest));
      await tester.pumpAndSettle();
      expect(find.byType(MultipleChoiceScreen), findsOneWidget);
    });

    testWidgets('лист режимов: нет подходящих карточек — пункты неактивны', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Формулы',
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
            front: 'Формула?',
            back: r'$a^2 + b^2 = c^2$',
          ),
        ],
      );
      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      final ListTile testTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('review-mode-test')),
      );
      final ListTile typingTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('review-mode-typing')),
      );
      expect(testTile.enabled, isFalse);
      expect(typingTile.enabled, isFalse);
      final ListTile matchTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('review-mode-match')),
      );
      final ListTile trueFalseTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('review-mode-true-false')),
      );
      expect(matchTile.enabled, isFalse);
      expect(trueFalseTile.enabled, isFalse);
      expect(l10n.studyModeTestNotEnough(0), isNotEmpty);
      expect(
        find.textContaining(l10n.studyModeTestNotEnough(0)),
        findsOneWidget,
      );
      expect(
        find.textContaining(l10n.studyModeTypingNotEnough(0)),
        findsOneWidget,
      );
      expect(find.textContaining(l10n.studyModeMatchNotEnough), findsOneWidget);
      expect(
        find.textContaining(l10n.studyModeTrueFalseNotEnough),
        findsOneWidget,
      );
    });

    // 7.17, ADR-034: «Тест» — выбор варианта, поэтому формульные ответы
    // доступны, а «Ввод ответа» — нет (формулу нельзя напечатать).
    testWidgets('лист режимов: формулы доступны Тесту, но не Вводу ответа', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Формулы',
            totalCards: 4,
            newCards: 4,
          ),
        ],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          for (var index = 0; index < 4; index++)
            makeCard(
              id: 'formula-$index',
              deckId: 'deck-1',
              front: 'Формула $index?',
              back: <String>[
                r'$x_0 = a$',
                r'$x_1 = b$',
                r'$x_2 = c$',
                r'$x_3 = d$',
              ][index],
            ),
        ],
      );
      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '${l10n.studyModeTestSubtitle} · ${l10n.studyModeAvailableCount(4)}',
        ),
        findsOneWidget,
      );
      final ListTile testTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('review-mode-test')),
      );
      final ListTile typingTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('review-mode-typing')),
      );
      expect(testTile.enabled, isTrue);
      expect(typingTile.enabled, isFalse);
      expect(
        find.textContaining(l10n.studyModeTypingNotEnough(0)),
        findsOneWidget,
      );
    });

    testWidgets('лист режимов: «Ввод ответа» открывает экран ввода', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Биология',
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
            front: 'Органоид?',
            back: 'Митохондрия',
          ),
        ],
      );
      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reviewModeTyping));
      await tester.pumpAndSettle();
      expect(find.byType(TypingScreen), findsOneWidget);
    });

    testWidgets('лист режимов: «Подбор пар» открывает игру', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Биология',
            totalCards: 6,
            newCards: 6,
          ),
        ],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          for (var index = 0; index < 6; index++)
            makeCard(
              id: 'card-$index',
              deckId: 'deck-1',
              front: 'Вопрос $index',
              back: <String>[
                'Митохондрия',
                'Рибосома',
                'Хлоропласт',
                'Лизосома',
                'Гольджи',
                'Ядро',
              ][index],
            ),
        ],
      );
      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reviewModeMatch), findsOneWidget);
      expect(find.text(l10n.reviewModeTrueFalse), findsOneWidget);

      await tester.tap(find.text(l10n.reviewModeMatch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MatchScreen), findsOneWidget);
    });

    testWidgets('лист режимов: «Верно/Неверно» открывает режим', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Биология',
            totalCards: 2,
            newCards: 2,
          ),
        ],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          makeCard(
            id: 'a',
            deckId: 'deck-1',
            front: 'Вопрос a',
            back: 'Ответ a',
          ),
          makeCard(
            id: 'b',
            deckId: 'deck-1',
            front: 'Вопрос b',
            back: 'Ответ b',
          ),
        ],
      );
      await pumpDeck(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      final Finder trueFalseMode = find.text(l10n.reviewModeTrueFalse);
      // Лист режимов прокручивается внутри (D21): последние пункты не за сгибом.
      await tester.ensureVisible(trueFalseMode);
      await tester.pumpAndSettle();
      await tester.tap(trueFalseMode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(TrueFalseScreen), findsOneWidget);
    });

    // Итерация 7.11/7.12: причина пустой сессии — исчерпанный дневной лимит;
    // предупреждение даёт «Продолжить без лимита» и «Тренировку» (ADR-028).
    testWidgets(
      'дневной лимит исчерпан: предупреждение и «Продолжить без лимита»',
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

        expect(find.text(l10n.reviewDailyLimitTitle), findsWidgets);
        expect(find.text(l10n.deckDailyLimitNotice), findsWidgets);
        expect(find.byType(ReviewSessionScreen), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey<String>('review-limit-continue')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ReviewSessionScreen), findsOneWidget);
        expect(find.text('Вопрос'), findsOneWidget);
        expect(
          find.text(l10n.reviewDailyLimitTitle),
          findsNothing,
          reason: 'после подтверждения лимит не блокирует сессию',
        );
      },
    );

    testWidgets('дневной лимит исчерпан: предупреждение ведёт в тренировку', (
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

      await pumpDeck(
        tester,
        repository: repository,
        cards: cards,
        dailyUsage: FakeDailyUsageRepository(
          usage: const DailyReviewUsage(newCards: 20),
        ),
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
      await tester.tap(
        find.byKey(const ValueKey<String>('review-limit-practice')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PracticeSessionScreen), findsOneWidget);
      expect(find.text('Вопрос'), findsOneWidget);
    });

    // ADR-028 (итерация 7.12, owner-note): карточки, созданные сегодня, не
    // блокируются исчерпанным дневным лимитом — сессия стартует сразу.
    testWidgets(
      'только что созданные карточки доступны при исчерпанном лимите',
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
            makeCard(
              id: 'card-new',
              deckId: 'deck-1',
              front: 'Новая карточка',
              createdAt: DateTime.now(),
            ),
          ],
        );

        await pumpDeck(
          tester,
          repository: repository,
          cards: cards,
          dailyUsage: FakeDailyUsageRepository(
            usage: const DailyReviewUsage(newCards: 20),
          ),
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

        expect(find.text(l10n.reviewDailyLimitTitle), findsNothing);
        expect(find.byType(ReviewSessionScreen), findsOneWidget);
        expect(find.text('Новая карточка'), findsOneWidget);
      },
    );
  });
}
