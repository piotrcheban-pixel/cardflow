import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/cloze_markup.dart';
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
    await tester.tap(find.byTooltip(l10n.deckAddCard));
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

    await tester.ensureVisible(find.text(l10n.cardTypeBasicReversed));
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

  group('аудит 1.0: сохранность правок и подсказки', () {
    Future<FakeCardRepository> openEdit(
      WidgetTester tester, {
      String front = 'Старый вопрос',
    }) async {
      final Card initial = makeCard(
        id: 'card-1',
        deckId: 'deck-1',
        front: front,
        back: 'Старый ответ',
      );
      final FakeCardRepository cards = await pumpDeckScreen(
        tester,
        deckCards: <Card>[initial],
      );
      await tester.tap(find.text(front));
      await tester.pumpAndSettle();
      expect(find.byType(CardFormScreen), findsOneWidget);
      return cards;
    }

    testWidgets(
      'N2: «назад» с правками открывает диалог, «Не сохранять» — выходит',
      (WidgetTester tester) async {
        final FakeCardRepository cards = await openEdit(tester);
        final AppLocalizations l10n = l10nOf(tester);

        await tester.enterText(field('card-form-front'), 'Изменённый вопрос');
        await tester.pump();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(find.text(l10n.cardFormUnsavedTitle), findsOneWidget);
        expect(
          cards.updatedCards,
          isEmpty,
          reason: 'ничего не сохранено молча',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('card-form-discard')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DeckScreen), findsOneWidget);
        expect(cards.updatedCards, isEmpty);
        expect(find.text('Старый вопрос'), findsOneWidget);
      },
    );

    testWidgets('N2: «Сохранить и выйти» сохраняет правки', (
      WidgetTester tester,
    ) async {
      final FakeCardRepository cards = await openEdit(tester);
      final AppLocalizations l10n = l10nOf(tester);

      await tester.enterText(field('card-form-front'), 'Новый вопрос');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('card-form-save-exit')),
      );
      await tester.pumpAndSettle();

      expect(cards.updatedCards, hasLength(1));
      expect(cards.updatedDrafts.single.front, 'Новый вопрос');
      expect(find.byType(DeckScreen), findsOneWidget);
      expect(find.text(l10n.cardUpdatedMessage), findsOneWidget);
    });

    testWidgets('N2: без правок «назад» выходит сразу', (
      WidgetTester tester,
    ) async {
      await openEdit(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CardFormScreen), findsNothing);
      expect(find.byType(DeckScreen), findsOneWidget);
    });

    testWidgets('N2: Esc в форме без правок выходит без диалога', (
      WidgetTester tester,
    ) async {
      await openEdit(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CardFormScreen), findsNothing);
    });

    testWidgets('F2: подсказка cloze и формат {{ответ}} работает', (
      WidgetTester tester,
    ) async {
      final FakeCardRepository cards = await pumpDeckScreen(tester);
      final AppLocalizations l10n = l10nOf(tester);
      await openCreateForm(tester);

      await tester.ensureVisible(find.text(l10n.cardTypeCloze));
      await tester.tap(find.text(l10n.cardTypeCloze));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('card-form-cloze-hint')),
        findsOneWidget,
      );
      expect(
        find.textContaining(clozeSyntaxExample),
        findsWidgets,
        reason: 'пример синтаксиса виден без чтения исходников',
      );

      await tester.enterText(
        field('card-form-front'),
        'Столица Франции — {{Париж}}.',
      );
      await tester.tap(field('card-form-save'));
      await tester.pumpAndSettle();

      expect(cards.createdDrafts, hasLength(1));
      expect(cards.createdDrafts.single.cardType, CardType.cloze);
      expect(cards.createdDrafts.single.front, contains('{{Париж}}'));
      expect(find.byType(CardFormScreen), findsNothing);
      expect(find.text(l10n.cardCreatedMessage), findsOneWidget);
    });

    testWidgets('F3: ошибки валидации видны и форма прокручивается к полю', (
      WidgetTester tester,
    ) async {
      await pumpDeckScreen(tester);
      final AppLocalizations l10n = l10nOf(tester);
      await openCreateForm(tester);

      // Уводим форму вниз: раньше ошибка оставалась выше области прокрутки.
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      await tester.tap(field('card-form-save'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('card-form-validation-summary')),
        findsOneWidget,
      );
      expect(find.text(l10n.cardFormValidationSummary), findsOneWidget);
      final Rect front = tester.getRect(field('card-form-front'));
      expect(
        front.top,
        greaterThan(56),
        reason: 'поле вопроса прокрутилось в видимую область',
      );
      expect(front.top, lessThan(400));
    });

    testWidgets('D12: подпись первого поля не срезана верхней границей', (
      WidgetTester tester,
    ) async {
      await pumpDeckScreen(tester);
      await openCreateForm(tester);

      final Rect front = tester.getRect(field('card-form-front'));
      expect(
        front.top,
        greaterThan(70),
        reason: 'между AppBar и полем есть отступ для плавающей подписи',
      );
    });
  });
  testWidgets('F4: живой предпросмотр показывает LaTeX и cloze до сохранения', (
    WidgetTester tester,
  ) async {
    await pumpDeckScreen(tester);
    await openCreateForm(tester);

    await tester.enterText(field('card-form-front'), r'Формула $E=mc^2$');
    await tester.enterText(field('card-form-back'), 'Энергия покоя');
    await tester.pumpAndSettle();

    final Finder preview = find.byKey(
      const ValueKey<String>('card-form-preview'),
    );
    expect(preview, findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.byType(Math)),
      findsOneWidget,
      reason: 'формула отрендерена, а не показана сырым текстом',
    );
    expect(
      find.descendant(of: preview, matching: find.textContaining('Энергия')),
      findsWidgets,
    );
  });
}
