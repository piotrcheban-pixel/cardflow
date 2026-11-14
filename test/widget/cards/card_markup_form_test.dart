import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<FakeCardRepository> pumpForm(WidgetTester tester) async {
    final cards = FakeCardRepository();
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: cards,
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/cards/new',
      ),
    );
    await tester.pumpAndSettle();
    return cards;
  }

  testWidgets('форма предлагает cloze и сохраняет разметку с пустым back', (
    tester,
  ) async {
    final cards = await pumpForm(tester);

    expect(find.text('С пропусками'), findsOneWidget);
    await tester.ensureVisible(find.text('С пропусками'));
    await tester.tap(find.text('С пропусками'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('card-form-front')),
      'Столица {{c1::Париж}}',
    );
    await tester.tap(find.byKey(const ValueKey('card-form-save')));
    await tester.pumpAndSettle();

    expect(cards.createdDrafts.single.cardType, CardType.cloze);
    expect(cards.createdDrafts.single.back, isEmpty);
  });

  testWidgets('форма содержит рабочий вход выбора occlusion-изображения', (
    tester,
  ) async {
    await pumpForm(tester);

    expect(
      find.byKey(const ValueKey('card-form-pick-image')),
      findsOneWidget,
      reason: 'без выбора изображения редактор масок недоступен пользователю',
    );
  });

  testWidgets('cloze без пропуска показывает отдельную ошибку и не сохраняется', (
    tester,
  ) async {
    final cards = await pumpForm(tester);
    await tester.ensureVisible(find.text('С пропусками'));
    await tester.tap(find.text('С пропусками'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('card-form-front')),
      'Обычный текст',
    );
    await tester.tap(find.byKey(const ValueKey('card-form-save')));
    await tester.pump();

    expect(find.text('Добавьте пропуск в формате {{c1::ответ}}'), findsOneWidget);
    expect(cards.createdDrafts, isEmpty);
  });
}
