import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Красная фаза итерации 2: форма создания/редактирования карточки
/// (SPEC A6.3, A8.4, ADR-009).
void main() {
  Future<FakeCardRepository> pumpDeckScreen(
    WidgetTester tester, {
    List<Card> deckCards = const <Card>[],
  }) async {
    final cards = FakeCardRepository(cards: deckCards);
    final decks = FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(
          id: 'deck-1',
          name: 'Испанский',
          totalCards: deckCards.length,
          newCards: deckCards.length,
        ),
      ],
    );
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(deckRepository: decks, cardRepository: cards),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1',
      ),
    );
    await tester.pumpAndSettle();
    return cards;
  }

  Future<void> openCreateForm(WidgetTester tester) async {
    final AppLocalizations l10n = l10nOf(tester);
    await tester.tap(find.byTooltip(l10n.deckAddCardTooltip));
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.byKey(ValueKey<String>(key));

  testWidgets('создание basic-карточки: черновик уходит в репозиторий', (
    WidgetTester tester,
  ) async {
    final cards = await pumpDeckScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);
    await openCreateForm(tester);
    expect(find.byType(CardFormScreen), findsOneWidget);

    await tester.enterText(field('card-form-front'), 'Столица Франции?');
    await tester.enterText(field('card-form-back'), 'Париж');
    await tester.enterText(field('card-form-tags'), ' #география, европа ');
    await tester.tap(field('card-form-save'));
    await tester.pumpAndSettle();

    expect(cards.createdDrafts, hasLength(1));
    final draft = cards.createdDrafts.single;
    expect(draft.front, 'Столица Франции?');
    expect(draft.back, 'Париж');
    expect(draft.tags, <String>['география', 'европа']);
    expect(draft.cardType, CardType.basic);
    expect(find.byType(CardFormScreen), findsNothing);
    expect(find.byType(DeckScreen), findsOneWidget);
    expect(find.text(l10n.cardCreatedMessage), findsOneWidget);
  });

  testWidgets('валидация: пустые front и back — ошибки из ARB, без записи', (
    WidgetTester tester,
  ) async {
    final cards = await pumpDeckScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);
    await openCreateForm(tester);

    await tester.tap(field('card-form-save'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.cardFormFrontEmptyError), findsOneWidget);
    expect(find.text(l10n.cardFormBackEmptyError), findsOneWidget);
    expect(cards.createdDrafts, isEmpty);
  });

  testWidgets('валидация: front >500 символов', (WidgetTester tester) async {
    final cards = await pumpDeckScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);
    await openCreateForm(tester);

    await tester.enterText(field('card-form-front'), 'а' * 501);
    await tester.enterText(field('card-form-back'), 'Ответ');
    await tester.tap(field('card-form-save'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.cardFormFrontTooLongError), findsOneWidget);
    expect(cards.createdDrafts, isEmpty);
  });

  testWidgets('валидация: больше трёх тегов', (WidgetTester tester) async {
    final cards = await pumpDeckScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);
    await openCreateForm(tester);

    await tester.enterText(field('card-form-front'), 'Вопрос');
    await tester.enterText(field('card-form-back'), 'Ответ');
    await tester.enterText(field('card-form-tags'), 'а, б, в, г');
    await tester.tap(field('card-form-save'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.cardFormTagsTooManyError), findsOneWidget);
    expect(cards.createdDrafts, isEmpty);
  });

  testWidgets('двусторонняя карточка: тип уходит в черновик', (
    WidgetTester tester,
  ) async {
    final cards = await pumpDeckScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);
    await openCreateForm(tester);

    await tester.tap(find.text(l10n.cardTypeBasicReversed));
    await tester.pumpAndSettle();
    expect(find.text(l10n.cardFormReversedHint), findsOneWidget);

    await tester.enterText(field('card-form-front'), 'Термин');
    await tester.enterText(field('card-form-back'), 'Определение');
    await tester.tap(field('card-form-save'));
    await tester.pumpAndSettle();

    expect(cards.createdDrafts.single.cardType, CardType.basicReversed);
    expect(find.text(l10n.cardCreatedMessage), findsOneWidget);
  });

  testWidgets('редактирование: поля заполнены, сохранение обновляет карточку', (
    WidgetTester tester,
  ) async {
    final initial = makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Старый вопрос',
      back: 'Старый ответ',
      tags: <String>['тег'],
    );
    final cards = await pumpDeckScreen(tester, deckCards: <Card>[initial]);
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.text('Старый вопрос'));
    await tester.pumpAndSettle();
    expect(find.byType(CardFormScreen), findsOneWidget);
    expect(find.text(l10n.cardFormTypeImmutable), findsOneWidget);

    await tester.enterText(field('card-form-front'), 'Новый вопрос');
    await tester.enterText(field('card-form-back'), 'Новый ответ');
    await tester.tap(field('card-form-save'));
    await tester.pumpAndSettle();

    expect(cards.updatedCards.single.id, 'card-1');
    expect(find.byType(DeckScreen), findsOneWidget);
    expect(find.text(l10n.cardUpdatedMessage), findsOneWidget);
    expect(find.text('Новый вопрос'), findsOneWidget);
  });

  testWidgets('удаление из формы: подтверждение и удаление', (
    WidgetTester tester,
  ) async {
    final initial = makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Удаляемый вопрос',
    );
    final cards = await pumpDeckScreen(tester, deckCards: <Card>[initial]);
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.text('Удаляемый вопрос'));
    await tester.pumpAndSettle();
    await tester.tap(field('card-form-delete'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.cardDeleteDialogTitle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('card-delete-confirm')));
    await tester.pumpAndSettle();

    expect(cards.deletedIds, <String>['card-1']);
    expect(find.byType(DeckScreen), findsOneWidget);
    expect(find.text(l10n.cardDeletedMessage), findsOneWidget);
  });

  testWidgets('не найдена при редактировании — ошибка загрузки из ARB', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);

    // Прямой переход на форму по id несуществующей карточки.
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(
            summaries: <DeckSummary>[
              makeSummary(id: 'deck-1', name: 'Испанский'),
            ],
          ),
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/cards/нет-такой/edit',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.cardFormLoadError), findsOneWidget);
  });
}
