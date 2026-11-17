import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Красная фаза: экран «Колоды» (SPEC A6.2).
///
/// Все тексты — из ARB; поиск/фильтр/архив/создание/переименование/удаление
/// проверяются через фейковый репозиторий (без БД).
void main() {
  Future<void> pumpDecks(
    WidgetTester tester, {
    required FakeDeckRepository repository,
    FakeCardRepository? cards,
    FakeDeckTransferService? transfer,
    FakeFileGateway? gateway,
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
      ),
    );
  }

  Finder createSplitButton() =>
      find.byKey(const ValueKey<String>('decks-create-split'));

  group('Колоды: состояния загрузки данных', () {
    testWidgets('loading: индикатор загрузки и заголовок из ARB', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      )..stallSummaries = true;

      await pumpDecks(tester, repository: repository);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.byType(NcSkeleton), findsNWidgets(4));
      expect(find.text(l10n.decksTitle), findsWidgets);
      expect(find.text(l10n.decksErrorTitle), findsNothing);
      expect(find.text(l10n.decksEmptyTitle), findsNothing);
    });

    testWidgets('empty: пустое состояние с кнопкой создания', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository();

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.decksEmptyTitle), findsOneWidget);
      expect(find.text(l10n.decksEmptyMessage), findsOneWidget);
      expect(
        find.widgetWithText(NcButton, l10n.decksCreateButton),
        findsOneWidget,
      );
      expect(find.text(l10n.decksCreateDeckFab), findsOneWidget);
    });

    testWidgets(
      'error: сообщение из ARB, без сырого текста; retry грузит данные',
      (WidgetTester tester) async {
        final FakeDeckRepository repository = FakeDeckRepository(
          summaries: <DeckSummary>[
            makeSummary(id: 'deck-1', name: 'Испанский'),
          ],
        )..failSummaries = true;

        await pumpDecks(tester, repository: repository);
        await tester.pumpAndSettle();

        final AppLocalizations l10n = l10nOf(tester);
        expect(find.text(l10n.decksErrorTitle), findsOneWidget);
        expect(
          find.textContaining('boom'),
          findsNothing,
          reason: 'Сырой текст исключения не должен показываться пользователю',
        );
        expect(
          find.text(l10n.retry),
          findsOneWidget,
          reason: 'Должна быть кнопка «Повторить»',
        );

        repository.failSummaries = false;
        await tester.tap(find.text(l10n.retry));
        await tester.pumpAndSettle();

        expect(find.text('Испанский'), findsOneWidget);
        expect(repository.watchSummariesCalls, greaterThanOrEqualTo(2));
      },
    );

    testWidgets('success: плитки колод с счётчиками (NcCardTile)', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 12,
            newCards: 3,
            inProgressCards: 2,
            dueCards: 4,
          ),
          makeSummary(id: 'deck-2', name: 'История'),
        ],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.byType(NcCardTile), findsNWidgets(2));
      expect(find.text('Испанский'), findsOneWidget);
      expect(find.text('История'), findsOneWidget);
      expect(find.text(l10n.deckCardCount(12)), findsOneWidget);
      expect(find.text(l10n.deckCardCount(0)), findsOneWidget);
      expect(find.text(l10n.deckDueCount(4)), findsOneWidget);
      expect(
        find.text(l10n.deckDueCount(0)),
        findsNothing,
        reason: 'Счётчик «к повторению» показывается только при наличии due',
      );
    });
  });

  group('Колоды: поиск и фильтр', () {
    testWidgets('поиск фильтрует колоды без учёта регистра и ё/е', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(id: 'deck-1', name: 'Ёжики'),
          makeSummary(id: 'deck-2', name: 'История'),
        ],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('decks-search-toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ежики');
      await tester.pumpAndSettle();

      expect(find.text('Ёжики'), findsOneWidget);
      expect(find.text('История'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('decks-search-clear')),
      );
      await tester.pumpAndSettle();
      expect(find.text('История'), findsOneWidget);
      expect(find.text('Ёжики'), findsOneWidget);
    });

    testWidgets('чипы фильтра: Все / Новые / В процессе / Просроченные', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(id: 'deck-1', name: 'Испанский', newCards: 5),
          makeSummary(id: 'deck-2', name: 'История', inProgressCards: 2),
          makeSummary(id: 'deck-3', name: 'География', dueCards: 3),
          makeSummary(id: 'deck-4', name: 'Повторение'),
        ],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      for (final String label in <String>[
        l10n.deckFilterAll,
        l10n.deckFilterNew,
        l10n.deckFilterInProgress,
        l10n.deckFilterDue,
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'Нет чипа «$label»');
      }

      await tester.tap(find.text(l10n.deckFilterDue));
      await tester.pumpAndSettle();
      expect(find.text('География'), findsOneWidget);
      expect(find.text('Испанский'), findsNothing);
      expect(find.text('История'), findsNothing);
      expect(find.text('Повторение'), findsNothing);

      await tester.tap(find.text(l10n.deckFilterNew));
      await tester.pumpAndSettle();
      expect(find.text('Испанский'), findsOneWidget);
      expect(find.text('География'), findsNothing);

      await tester.tap(find.text(l10n.deckFilterInProgress));
      await tester.pumpAndSettle();
      expect(find.text('История'), findsOneWidget);
      expect(find.text('Испанский'), findsNothing);

      await tester.tap(find.text(l10n.deckFilterAll));
      await tester.pumpAndSettle();
      expect(find.text('Испанский'), findsOneWidget);
      expect(find.text('История'), findsOneWidget);
      expect(find.text('География'), findsOneWidget);
      expect(find.text('Повторение'), findsOneWidget);
    });

    testWidgets('иконка фильтра скрывает и показывает чипы (кнопка живая)', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      expect(find.text(l10n.deckFilterAll), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('decks-filter-toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckFilterAll), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey<String>('decks-filter-toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckFilterAll), findsOneWidget);
    });
  });

  group('Колоды: архив свайпом и undo', () {
    testWidgets('свайп влево архивирует колоду, undo возвращает', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.drag(
        find.byKey(const ValueKey<String>('deck-card-deck-1')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();

      expect(repository.archivedIds, <String>['deck-1']);
      expect(find.text(l10n.deckArchivedMessage), findsOneWidget);
      expect(find.text(l10n.undo), findsOneWidget);
      expect(find.text('Испанский'), findsNothing);

      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();

      expect(repository.unarchivedIds, <String>['deck-1']);
      expect(find.text('Испанский'), findsOneWidget);
    });
  });

  group('Колоды: создание', () {
    testWidgets('вручную: валидация пустого имени и успешное создание', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository();

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(
        find.descendant(
          of: createSplitButton(),
          matching: find.text(l10n.decksCreateButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckCreateDialogTitle), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('deck-name-submit')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckNameEmptyError), findsOneWidget);
      expect(
        repository.createdNames,
        isEmpty,
        reason: 'Пустое имя не должно создавать колоду',
      );

      await tester.enterText(find.byType(TextField), '  Испанский  ');
      await tester.tap(find.byKey(const ValueKey<String>('deck-name-submit')));
      await tester.pumpAndSettle();

      expect(repository.createdNames, <String>['Испанский']);
      expect(find.text('Испанский'), findsOneWidget);
    });

    testWidgets('FAB «Создать колоду» открывает тот же диалог', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository();

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.decksCreateDeckFab));
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckCreateDialogTitle), findsOneWidget);
    });
  });

  group('Колоды: контекстное меню', () {
    Future<void> openContextMenu(WidgetTester tester) async {
      await tester.longPress(find.text('Испанский'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'долгое нажатие: Переименовать / Экспорт / Архивировать / Удалить',
      (WidgetTester tester) async {
        final FakeDeckRepository repository = FakeDeckRepository(
          summaries: <DeckSummary>[
            makeSummary(id: 'deck-1', name: 'Испанский'),
          ],
        );

        await pumpDecks(tester, repository: repository);
        await tester.pumpAndSettle();
        final AppLocalizations l10n = l10nOf(tester);

        await openContextMenu(tester);
        expect(find.text(l10n.deckRename), findsOneWidget);
        expect(find.text(l10n.deckExport), findsOneWidget);
        expect(
          find.text(l10n.deckActionArchive),
          findsOneWidget,
          reason:
              'Архив должен быть доступен не только свайпом (доступность, M11)',
        );
        expect(find.text(l10n.delete), findsOneWidget);
      },
    );

    testWidgets('архивирование из контекстного меню: undo возвращает колоду', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await openContextMenu(tester);
      await tester.tap(find.text(l10n.deckActionArchive));
      await tester.pumpAndSettle();

      expect(repository.archivedIds, <String>['deck-1']);
      expect(find.text('Испанский'), findsNothing);
      expect(find.text(l10n.deckArchivedMessage), findsOneWidget);
      expect(find.text(l10n.undo), findsOneWidget);

      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();

      expect(repository.unarchivedIds, <String>['deck-1']);
      expect(find.text('Испанский'), findsOneWidget);
    });

    testWidgets('переименование меняет имя колоды', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await openContextMenu(tester);
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

    testWidgets('удаление с подтверждением удаляет колоду', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await openContextMenu(tester);
      await tester.tap(find.text(l10n.delete));
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckDeleteDialogTitle), findsOneWidget);
      expect(
        find.text(l10n.deckDeleteDialogMessage('Испанский')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('delete-deck-confirm')),
      );
      await tester.pumpAndSettle();

      expect(repository.deletedIds, <String>['deck-1']);
      expect(find.text('Испанский'), findsNothing);
      expect(find.text(l10n.decksEmptyTitle), findsOneWidget);
    });

    testWidgets('отмена удаления не трогает колоду', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      await openContextMenu(tester);
      await tester.tap(find.text(l10n.delete));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('delete-deck-cancel')),
      );
      await tester.pumpAndSettle();

      expect(repository.deletedIds, isEmpty);
      expect(find.text('Испанский'), findsOneWidget);
    });
  });

  group('Колоды: навигация', () {
    testWidgets('тап по карточке открывает экран колоды', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );
      final FakeCardRepository cards = FakeCardRepository(
        cards: <Card>[
          makeCard(id: 'card-1', deckId: 'deck-1', front: '¿Cómo estás?'),
        ],
      );

      await pumpDecks(tester, repository: repository, cards: cards);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Испанский'));
      await tester.pumpAndSettle();

      expect(find.byType(DeckScreen), findsOneWidget);
      expect(find.byType(DecksScreen), findsNothing);
      expect(find.text('¿Cómo estás?'), findsOneWidget);
    });
  });
}
