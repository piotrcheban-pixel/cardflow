import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Красная фаза: экран «Колода» (SPEC A6.3, минимальный для итерации 1).
void main() {
  Future<void> pumpDeck(
    WidgetTester tester, {
    required FakeDeckRepository repository,
    FakeCardRepository? cards,
    FakeDeckTransferService? transfer,
    FakeFileGateway? gateway,
    String initialLocation = '/decks/deck-1',
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: repository,
          cardRepository: cards,
          transferService: transfer,
          fileGateway: gateway,
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
}
