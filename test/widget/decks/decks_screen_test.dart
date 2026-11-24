import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
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

  // V11: «создать» на пустой базе — одна кнопка (в пустом состоянии),
  // на непустой — кнопка шапки. Helper поддерживает оба входа.
  Finder createButton() => find.byWidgetPredicate(
    (Widget widget) =>
        widget.key == const ValueKey<String>('decks-new-deck') ||
        widget.key == const ValueKey<String>('decks-empty-create'),
  );

  /// Прокручивает страницу к колоде [name] (карточки ниже первого экрана).
  Future<void> scrollToDeck(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(
      find.text(name),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  group('Колоды: состояния загрузки данных', () {
    testWidgets('loading: скелетон загрузки и заголовок из ARB', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      )..stallSummaries = true;

      await pumpDecks(tester, repository: repository);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final AppLocalizations l10n = l10nOf(tester);
      // F22: вместо голого спиннера — скелетон геометрии списка.
      expect(find.byType(AppSkeleton), findsWidgets);
      expect(find.text(l10n.decksTitle), findsOneWidget);
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
        find.widgetWithText(FilledButton, l10n.decksCreateButton),
        findsOneWidget,
      );
      // V11: единственный вход «создать» — в пустом состоянии, шапка его
      // не дублирует.
      expect(
        find.byKey(const ValueKey<String>('decks-empty-create')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('decks-new-deck')),
        findsNothing,
      );
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
          find.widgetWithText(FilledButton, l10n.retry),
          findsOneWidget,
          reason: 'Должна быть кнопка «Повторить»',
        );

        repository.failSummaries = false;
        final Finder retryButton = find.widgetWithText(
          FilledButton,
          l10n.retry,
        );
        await tester.ensureVisible(retryButton);
        await tester.pumpAndSettle();
        await tester.tap(retryButton);
        await tester.pumpAndSettle();

        await scrollToDeck(tester, 'Испанский');
        expect(find.text('Испанский'), findsOneWidget);
        expect(repository.watchSummariesCalls, greaterThanOrEqualTo(2));
      },
    );

    testWidgets('success: карточки колод с счётчиками', (
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
      expect(
        find.byKey(const ValueKey<String>('deck-tile-deck-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('deck-tile-deck-2')),
        findsOneWidget,
      );
      expect(find.text('Испанский'), findsOneWidget);
      expect(find.text('История'), findsOneWidget);
      expect(find.text(l10n.deckCardCount(12)), findsOneWidget);
      // Находка D18: у пустой колоды одно нейтральное сообщение вместо
      // дубля «В колоде пока нет карточек» + «Нет карточек».
      expect(find.text(l10n.deckCardsEmpty), findsOneWidget);
      expect(find.text(l10n.deckCardCount(0)), findsNothing);
      expect(find.text(l10n.deckDueCount(4)), findsOneWidget);
      expect(
        find.text(l10n.deckDueCount(0)),
        findsNothing,
        reason: 'Счётчик «к повторению» показывается только при наличии due',
      );
    });
  });

  group('Колоды: KPI и адаптивность', () {
    testWidgets('KPI считаются по реальным сводкам', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 12,
            newCards: 3,
            dueCards: 4,
          ),
          makeSummary(
            id: 'deck-2',
            name: 'История',
            totalCards: 8,
            newCards: 1,
            dueCards: 0,
          ),
        ],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();

      Finder tileValue(String key, String value) => find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.text(value),
      );
      expect(tileValue('decks-kpi-total', '20'), findsOneWidget);
      expect(tileValue('decks-kpi-due', '4'), findsOneWidget);
      // Изучено = (12-3) + (8-1) = 16.
      expect(tileValue('decks-kpi-studied', '16'), findsOneWidget);
      expect(tileValue('decks-kpi-decks', '2'), findsOneWidget);
    });

    testWidgets('подзаголовок склоняет числа (1 колода / 1 карточка)', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 1,
            dueCards: 1,
          ),
        ],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();

      expect(find.text('1 колода в работе'), findsOneWidget);
    });

    testWidgets('узкий экран 360×800: без переполнений, карточка читается', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 12,
            dueCards: 4,
            newCards: 3,
          ),
        ],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await scrollToDeck(tester, 'Испанский');
      expect(find.text('Испанский'), findsOneWidget);
      expect(tester.takeException(), isNull);
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

      await tester.tap(find.byTooltip(l10n.decksSearchTooltip));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ежики');
      await tester.pumpAndSettle();

      expect(find.text('Ёжики'), findsOneWidget);
      expect(find.text('История'), findsNothing);

      await tester.tap(find.byTooltip(l10n.decksSearchClearTooltip));
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
        l10n.decksFilterAllCount(4),
        l10n.decksFilterNewCount(1),
        l10n.decksFilterInProgressCount(1),
        l10n.decksFilterDueCount(1),
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'Нет чипа «$label»');
      }

      await tester.tap(find.text(l10n.decksFilterDueCount(1)));
      await tester.pumpAndSettle();
      expect(find.text('География'), findsOneWidget);
      expect(find.text('Испанский'), findsNothing);
      expect(find.text('История'), findsNothing);
      expect(find.text('Повторение'), findsNothing);

      await tester.tap(find.text(l10n.decksFilterNewCount(1)));
      await tester.pumpAndSettle();
      expect(find.text('Испанский'), findsOneWidget);
      expect(find.text('География'), findsNothing);

      await tester.tap(find.text(l10n.decksFilterInProgressCount(1)));
      await tester.pumpAndSettle();
      expect(find.text('История'), findsOneWidget);
      expect(find.text('Испанский'), findsNothing);

      await tester.tap(find.text(l10n.decksFilterAllCount(4)));
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

      expect(find.text(l10n.decksFilterAllCount(1)), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.decksFilterTooltip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.decksFilterAllCount(1)), findsNothing);
      await tester.tap(find.byTooltip(l10n.decksFilterTooltip));
      await tester.pumpAndSettle();
      expect(find.text(l10n.decksFilterAllCount(1)), findsOneWidget);
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

      await scrollToDeck(tester, 'Испанский');

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

      await tester.tap(createButton());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('deck-name-submit')),
        findsOneWidget,
      );

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

    testWidgets('кнопка шапки «Новая колода» открывает тот же диалог', (
      WidgetTester tester,
    ) async {
      // На первом запуске (пустая база) кнопки шапки нет — V11; проверяем
      // шапку на непустой базе.
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
      );

      await pumpDecks(tester, repository: repository);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('decks-new-deck')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('deck-name-submit')),
        findsOneWidget,
      );
    });
  });

  group('Колоды: контекстное меню', () {
    Future<void> openContextMenu(WidgetTester tester) async {
      await scrollToDeck(tester, 'Испанский');
      // Аудит v4 (ACTIONS #20): долгое нажатие убрано — меню открывается
      // единственной кнопкой ⋮ карточки.
      await tester.tap(find.byKey(const ValueKey<String>('deck-menu-deck-1')));
      await tester.pumpAndSettle();
    }

    testWidgets('меню ⋮: Переименовать / Экспорт / Архивировать / Удалить', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
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
    });

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

      await scrollToDeck(tester, 'Испанский');
      await tester.tap(find.text('Испанский'));
      await tester.pumpAndSettle();

      expect(find.byType(DeckScreen), findsOneWidget);
      expect(find.byType(DecksScreen), findsNothing);
      expect(find.text('¿Cómo estás?'), findsOneWidget);
    });
  });
}
